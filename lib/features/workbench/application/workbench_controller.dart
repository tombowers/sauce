import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/models/commit_entry.dart';
import '../../../core/models/branch_entry.dart';
import '../../../core/models/repo_snapshot.dart';
import '../../../core/models/working_tree_entry.dart';
import '../../../core/services/git_cli_service.dart';
import '../../../core/services/local_state_store.dart';

class WorkbenchController extends ChangeNotifier {
  WorkbenchController({GitCliService? gitService})
    : _gitService = gitService ?? GitCliService() {
    repoPath = Directory.current.path;
  }

  static const _recentReposKey = 'recent_repo_paths';
  static const _showRemoteBranchesKey = 'show_remote_branches';
  static const _activeRepoPathKey = 'active_repo_path';
  static const _commandLogKey = 'console.command_log';
  static const _selectedCommitByRepoKey = 'selected_commit_by_repo';
  static const _selectedViewKey = 'workbench.selected_view';
  static const _workingTreeFilterKey = 'workbench.working_tree.filter';
  static const _workingTreeLayoutKey = 'workbench.working_tree.layout';
  static const _selectedWorkingTreePathByRepoKey =
      'selected_working_tree_path_by_repo';
  final GitCliService _gitService;
  LocalStateStore? _localStore;
  final Map<String, String> _selectedCommitByRepoPath = <String, String>{};
  final Map<String, String> _selectedWorkingTreePathByRepoPath =
      <String, String>{};
  final Set<String> selectedWorkingTreeBatchPaths = <String>{};
  String? _workingTreeSelectionAnchorPath;

  RepoSnapshot? snapshot;
  String repoPath = '';
  String? errorMessage;
  String? activeDiff;
  bool isLoading = false;
  bool isRunningCommand = false;
  bool isLoadingDiff = false;
  bool showRemoteBranches = false;
  int selectedCommitIndex = 0;
  WorkbenchPrimaryView selectedView = WorkbenchPrimaryView.history;
  WorkingTreeViewFilter workingTreeFilter = WorkingTreeViewFilter.unstaged;
  WorkingTreeLayout workingTreeLayout = WorkingTreeLayout.flat;
  final List<String> commandLog = <String>[
    'Connect a local repository to begin.',
  ];
  final List<String> recentRepoPaths = <String>[];

  Future<void> initialize() async {
    final store = await _store();
    final storedRepos = store.readStringList(_recentReposKey);
    recentRepoPaths
      ..clear()
      ..addAll(storedRepos);

    final persistedActiveRepo = store.readString(
      _activeRepoPathKey,
      fallback: '',
    );
    final restoredRepoPath = persistedActiveRepo.isNotEmpty
        ? persistedActiveRepo
        : (storedRepos.isNotEmpty ? storedRepos.first : repoPath);
    if (restoredRepoPath.isNotEmpty) {
      repoPath = restoredRepoPath;
    }
    showRemoteBranches = store.readBool(
      _showRemoteBranchesKey,
      fallback: false,
    );
    selectedView = _readPrimaryView(store);
    workingTreeFilter = _readWorkingTreeFilter(store);
    workingTreeLayout = _readWorkingTreeLayout(store);
    commandLog
      ..clear()
      ..addAll(store.readStringList(_commandLogKey));
    if (commandLog.isEmpty) {
      commandLog.add('Connect a local repository to begin.');
    }
    _selectedCommitByRepoPath
      ..clear()
      ..addAll(_loadSelectedCommitByRepoPath(store));
    _selectedWorkingTreePathByRepoPath
      ..clear()
      ..addAll(_loadStringMap(store, _selectedWorkingTreePathByRepoKey));

    notifyListeners();

    if (persistedActiveRepo.isNotEmpty) {
      await connectToRepository(persistedActiveRepo);
    }
  }

  CommitEntry? get selectedCommit {
    final commits = snapshot?.commits;
    if (commits == null || commits.isEmpty) {
      return null;
    }
    final index = selectedCommitIndex.clamp(0, commits.length - 1);
    return commits[index];
  }

  bool get hasRepository => snapshot != null;

  List<BranchEntry> get localBranches =>
      snapshot?.branches.where((branch) => !branch.isRemote).toList() ??
      const [];

  List<BranchEntry> get remoteBranches =>
      snapshot?.branches.where((branch) => branch.isRemote).toList() ??
      const [];

  List<WorkingTreeEntry> get filteredWorkingTreeEntries {
    final workingTree = snapshot?.workingTree;
    if (workingTree == null) {
      return const [];
    }
    return workingTree.entriesForFilter(workingTreeFilter);
  }

  List<WorkingTreeEntry> get visibleWorkingTreeEntries {
    final workingTree = snapshot?.workingTree;
    if (workingTree == null) {
      return const [];
    }
    if (workingTreeFilter == WorkingTreeViewFilter.unstaged) {
      return [
        ...workingTree.entriesForFilter(WorkingTreeViewFilter.unstaged),
        ...workingTree.entriesForFilter(WorkingTreeViewFilter.staged),
      ];
    }
    return filteredWorkingTreeEntries;
  }

  WorkingTreeEntry? get selectedWorkingTreeEntry {
    final repo = snapshot;
    if (repo == null) {
      return null;
    }
    final selectedPath = _selectedWorkingTreePathByRepoPath[repo.path];
    final entries = visibleWorkingTreeEntries;
    if (entries.isEmpty) {
      return null;
    }
    if (selectedPath == null || selectedPath.isEmpty) {
      return entries.first;
    }
    return entries.firstWhere(
      (entry) => entry.path == selectedPath,
      orElse: () => entries.first,
    );
  }

  Future<void> connectToRepository(String rawPath) async {
    final trimmedPath = rawPath.trim();
    if (trimmedPath.isEmpty) {
      errorMessage = 'Enter a local repository path.';
      notifyListeners();
      return;
    }

    repoPath = trimmedPath;
    errorMessage = null;
    isLoading = true;
    notifyListeners();

    try {
      final nextSnapshot = await _gitService.loadSnapshot(
        trimmedPath,
        showRemoteBranches: showRemoteBranches,
      );
      snapshot = nextSnapshot;
      repoPath = nextSnapshot.path;
      _syncPrimaryViewForSnapshot(nextSnapshot);
      selectedCommitIndex = _resolveSelectedCommitIndex(nextSnapshot);
      _pruneWorkingTreeBatchSelection(nextSnapshot);
      _ensureWorkingTreeSelection(nextSnapshot);
      _rememberRepo(nextSnapshot.path);
      unawaited(_persistActiveRepoPath(nextSnapshot.path));
      _persistSelectedCommitForCurrentRepo();
      await _loadDiffForCurrentSelection(notify: false);
    } on GitCliException catch (error) {
      errorMessage = error.message;
    } catch (_) {
      errorMessage = 'Unable to inspect that repository.';
      activeDiff = null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (!hasRepository) {
      return;
    }
    await connectToRepository(snapshot!.path);
  }

  Future<void> runQuickCommand(List<String> args) async {
    if (!hasRepository || isRunningCommand) {
      return;
    }

    await _runGitCommand(args);
    await refresh();
  }

  Future<void> runConsoleCommand(String input) async {
    if (!hasRepository || isRunningCommand) {
      return;
    }

    final tokens = _tokenize(input);
    if (tokens.isEmpty) {
      return;
    }

    final args = tokens.first == 'git' ? tokens.skip(1).toList() : tokens;
    if (args.isEmpty) {
      errorMessage = 'Type a git command, for example: status --short';
      notifyListeners();
      return;
    }

    await _runGitCommand(args);
    await refresh();
  }

  void selectCommit(int index) {
    selectedCommitIndex = index;
    if (selectedView != WorkbenchPrimaryView.history) {
      selectedView = WorkbenchPrimaryView.history;
      unawaited(_persistSelectedView());
    }
    _persistSelectedCommitForCurrentRepo();
    notifyListeners();
  }

  Future<void> selectUncommittedChanges() async {
    final repo = snapshot;
    if (repo != null) {
      if (repo.workingTree.dirtyCount == 0) {
        if (selectedView != WorkbenchPrimaryView.history) {
          selectedView = WorkbenchPrimaryView.history;
          await _persistSelectedView();
        }
        notifyListeners();
        return;
      }
      _ensureWorkingTreeSelection(repo);
    }
    if (selectedView != WorkbenchPrimaryView.changes) {
      selectedView = WorkbenchPrimaryView.changes;
      await _persistSelectedView();
    }
    notifyListeners();
    await _loadDiffForCurrentSelection();
  }

  void dismissError() {
    errorMessage = null;
    notifyListeners();
  }

  Future<void> removeRecentRepository(String path) async {
    final removed = recentRepoPaths.remove(path);
    if (!removed) {
      return;
    }
    await _persistRecentRepos();
    notifyListeners();
  }

  Future<void> setShowRemoteBranches(bool value) async {
    if (showRemoteBranches == value) {
      return;
    }
    showRemoteBranches = value;
    final store = await _store();
    await store.writeBool(_showRemoteBranchesKey, value);
    notifyListeners();
    if (hasRepository) {
      await refresh();
    }
  }

  Future<void> switchToBranch(BranchEntry branch) async {
    if (!hasRepository || isRunningCommand) {
      return;
    }
    if (!branch.isRemote) {
      if (branch.isCurrent) {
        return;
      }
      await _runUserGitAction(['switch', branch.name]);
      return;
    }

    final existingLocal = localBranches.where(
      (localBranch) => localBranch.shortName == branch.shortName,
    );
    if (existingLocal.isNotEmpty) {
      await switchToBranch(existingLocal.first);
      return;
    }

    await _runUserGitAction([
      'switch',
      '--track',
      '-c',
      branch.shortName,
      branch.name,
    ]);
  }

  Future<void> setPrimaryView(WorkbenchPrimaryView view) async {
    if (selectedView == view) {
      return;
    }
    selectedView = view;
    if (view == WorkbenchPrimaryView.changes) {
      final repo = snapshot;
      if (repo != null) {
        _ensureWorkingTreeSelection(repo);
      }
    }
    await _persistSelectedView();
    notifyListeners();
    if (view == WorkbenchPrimaryView.changes) {
      await _loadDiffForCurrentSelection();
    }
  }

  Future<void> setWorkingTreeFilter(WorkingTreeViewFilter filter) async {
    if (workingTreeFilter == filter) {
      return;
    }
    workingTreeFilter = filter;
    final repo = snapshot;
    if (repo != null) {
      _ensureWorkingTreeSelection(repo);
    }
    final store = await _store();
    await store.writeString(_workingTreeFilterKey, filter.name);
    notifyListeners();
    await _loadDiffForCurrentSelection();
  }

  Future<void> setWorkingTreeLayout(WorkingTreeLayout layout) async {
    if (workingTreeLayout == layout) {
      return;
    }
    workingTreeLayout = layout;
    final store = await _store();
    await store.writeString(_workingTreeLayoutKey, layout.name);
    notifyListeners();
  }

  Future<void> selectWorkingTreeEntry(String path) async {
    final repo = snapshot;
    if (repo == null) {
      return;
    }
    selectedView = WorkbenchPrimaryView.changes;
    _selectedWorkingTreePathByRepoPath[repo.path] = path;
    _workingTreeSelectionAnchorPath = path;
    unawaited(_persistSelectedView());
    unawaited(_persistSelectedWorkingTreePathMap());
    notifyListeners();
    await _loadDiffForCurrentSelection();
  }

  Future<void> activateWorkingTreeEntry({
    required String path,
    required List<String> visiblePaths,
    required bool isControlPressed,
    required bool isShiftPressed,
  }) async {
    final repo = snapshot;
    if (repo == null) {
      return;
    }

    selectedView = WorkbenchPrimaryView.changes;
    _selectedWorkingTreePathByRepoPath[repo.path] = path;

    if (isShiftPressed && visiblePaths.isNotEmpty) {
      final anchor = _workingTreeSelectionAnchorPath ?? path;
      final anchorIndex = visiblePaths.indexOf(anchor);
      final targetIndex = visiblePaths.indexOf(path);
      if (anchorIndex != -1 && targetIndex != -1) {
        if (!isControlPressed) {
          selectedWorkingTreeBatchPaths.clear();
        }
        final start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
        final end = anchorIndex < targetIndex ? targetIndex : anchorIndex;
        selectedWorkingTreeBatchPaths.addAll(
          visiblePaths.sublist(start, end + 1),
        );
      }
    } else if (isControlPressed) {
      _workingTreeSelectionAnchorPath = path;
      if (!selectedWorkingTreeBatchPaths.add(path)) {
        selectedWorkingTreeBatchPaths.remove(path);
      }
    } else {
      _workingTreeSelectionAnchorPath = path;
      selectedWorkingTreeBatchPaths.clear();
    }

    unawaited(_persistSelectedView());
    unawaited(_persistSelectedWorkingTreePathMap());
    notifyListeners();
    await _loadDiffForCurrentSelection();
  }

  Future<void> stageWorkingTreeEntry(WorkingTreeEntry entry) async {
    await _runUserGitAction(['add', '--', entry.path]);
  }

  Future<void> stageWorkingTreeEntries(List<WorkingTreeEntry> entries) async {
    final paths = entries.map((entry) => entry.path).toSet().toList();
    if (paths.isEmpty) {
      return;
    }
    selectedWorkingTreeBatchPaths.clear();
    await _runUserGitAction(['add', '--', ...paths]);
  }

  Future<void> stageAllWorkingTreeEntries() async {
    selectedWorkingTreeBatchPaths.clear();
    await _runUserGitAction(const ['add', '--all']);
  }

  Future<void> stageSelectedWorkingTreeEntries() async {
    final paths = _selectedEntriesForFilter(
      WorkingTreeViewFilter.unstaged,
    ).map((entry) => entry.path).toList();
    if (paths.isEmpty) {
      return;
    }
    selectedWorkingTreeBatchPaths.clear();
    await _runUserGitAction(['add', '--', ...paths]);
  }

  Future<void> unstageWorkingTreeEntry(WorkingTreeEntry entry) async {
    await _runUserGitAction(['reset', '--', entry.path]);
  }

  Future<void> unstageWorkingTreeEntries(List<WorkingTreeEntry> entries) async {
    final paths = entries.map((entry) => entry.path).toSet().toList();
    if (paths.isEmpty) {
      return;
    }
    selectedWorkingTreeBatchPaths.clear();
    await _runUserGitAction(['reset', '--', ...paths]);
  }

  Future<void> unstageAllWorkingTreeEntries() async {
    selectedWorkingTreeBatchPaths.clear();
    await _runUserGitAction(const ['reset']);
  }

  Future<void> unstageSelectedWorkingTreeEntries() async {
    final paths = _selectedEntriesForFilter(
      WorkingTreeViewFilter.staged,
    ).map((entry) => entry.path).toList();
    if (paths.isEmpty) {
      return;
    }
    selectedWorkingTreeBatchPaths.clear();
    await _runUserGitAction(['reset', '--', ...paths]);
  }

  Future<void> discardWorkingTreeEntry(WorkingTreeEntry entry) async {
    if (entry.isIgnored) {
      return;
    }
    if (entry.isUntracked) {
      await _runUserGitAction(['clean', '-f', '--', entry.path]);
      return;
    }
    if (entry.hasPendingChanges) {
      await _runUserGitAction(['restore', '--', entry.path]);
      return;
    }
    if (entry.hasStagedChanges) {
      await _runUserGitAction([
        'restore',
        '--staged',
        '--worktree',
        '--',
        entry.path,
      ]);
    }
  }

  Future<void> _runGitCommand(List<String> args) async {
    final repo = snapshot;
    if (repo == null) {
      return;
    }

    isRunningCommand = true;
    errorMessage = null;
    _appendCommand('\$ git ${args.join(' ')}');
    notifyListeners();

    try {
      await _gitService.runCommand(
        args,
        workingDirectory: repo.path,
        onLine: _appendCommand,
      );
      _appendCommand('');
    } on GitCliException catch (error) {
      errorMessage = error.message;
      _appendCommand(error.message);
      _appendCommand('');
    } finally {
      isRunningCommand = false;
      unawaited(_persistCommandLog());
      notifyListeners();
    }
  }

  Future<void> _runUserGitAction(List<String> args) async {
    final previousSelection = selectedWorkingTreeEntry?.path;
    await _runGitCommand(args);
    if (snapshot == null) {
      return;
    }
    if (previousSelection != null) {
      _selectedWorkingTreePathByRepoPath[snapshot!.path] = previousSelection;
    }
    await refresh();
  }

  List<WorkingTreeEntry> _selectedEntriesForFilter(
    WorkingTreeViewFilter filter,
  ) {
    final workingTree = snapshot?.workingTree;
    if (workingTree == null || selectedWorkingTreeBatchPaths.isEmpty) {
      return const [];
    }
    return workingTree
        .entriesForFilter(filter)
        .where((entry) => selectedWorkingTreeBatchPaths.contains(entry.path))
        .toList();
  }

  void _appendCommand(String line) {
    commandLog.add(line);
    if (commandLog.length > 200) {
      commandLog.removeRange(0, commandLog.length - 200);
    }
  }

  void _rememberRepo(String path) {
    recentRepoPaths.remove(path);
    recentRepoPaths.insert(0, path);
    if (recentRepoPaths.length > 5) {
      recentRepoPaths.removeRange(5, recentRepoPaths.length);
    }
    unawaited(_persistRecentRepos());
  }

  List<String> _tokenize(String input) {
    final matches = RegExp(r'"([^"]*)"|[^\s]+').allMatches(input);
    return matches.map((match) => match.group(1) ?? match.group(0)!).toList();
  }

  Future<void> _persistRecentRepos() async {
    final store = await _store();
    await store.writeStringList(_recentReposKey, recentRepoPaths);
  }

  Map<String, String> _loadSelectedCommitByRepoPath(LocalStateStore store) {
    return _loadStringMap(store, _selectedCommitByRepoKey);
  }

  Map<String, String> _loadStringMap(LocalStateStore store, String key) {
    final rawJson = store.readString(key, fallback: '{}');
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        return <String, String>{};
      }
      return decoded.map<String, String>(
        (key, value) => MapEntry(key, value?.toString() ?? ''),
      )..removeWhere((key, value) => value.isEmpty);
    } catch (_) {
      return <String, String>{};
    }
  }

  WorkbenchPrimaryView _readPrimaryView(LocalStateStore store) {
    final raw = store.readString(
      _selectedViewKey,
      fallback: WorkbenchPrimaryView.history.name,
    );
    return WorkbenchPrimaryView.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => WorkbenchPrimaryView.history,
    );
  }

  WorkingTreeViewFilter _readWorkingTreeFilter(LocalStateStore store) {
    final raw = store.readString(
      _workingTreeFilterKey,
      fallback: WorkingTreeViewFilter.unstaged.name,
    );
    if (raw == 'pending' || raw == 'untracked') {
      return WorkingTreeViewFilter.unstaged;
    }
    return WorkingTreeViewFilter.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => WorkingTreeViewFilter.unstaged,
    );
  }

  WorkingTreeLayout _readWorkingTreeLayout(LocalStateStore store) {
    final raw = store.readString(
      _workingTreeLayoutKey,
      fallback: WorkingTreeLayout.flat.name,
    );
    return WorkingTreeLayout.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => WorkingTreeLayout.flat,
    );
  }

  int _resolveSelectedCommitIndex(RepoSnapshot snapshot) {
    final sha = _selectedCommitByRepoPath[snapshot.path];
    if (sha == null || sha.isEmpty) {
      return 0;
    }
    final index = snapshot.commits.indexWhere((commit) => commit.sha == sha);
    return index == -1 ? 0 : index;
  }

  void _persistSelectedCommitForCurrentRepo() {
    final repo = snapshot;
    if (repo == null || repo.commits.isEmpty) {
      return;
    }
    final index = selectedCommitIndex.clamp(0, repo.commits.length - 1);
    final sha = repo.commits[index].sha;
    _selectedCommitByRepoPath[repo.path] = sha;
    unawaited(_persistSelectedCommitMap());
  }

  Future<void> _persistSelectedCommitMap() async {
    final store = await _store();
    await store.writeString(
      _selectedCommitByRepoKey,
      jsonEncode(_selectedCommitByRepoPath),
    );
  }

  Future<void> _persistSelectedView() async {
    final store = await _store();
    await store.writeString(_selectedViewKey, selectedView.name);
  }

  void _syncPrimaryViewForSnapshot(RepoSnapshot repo) {
    if (repo.workingTree.dirtyCount == 0 &&
        selectedView == WorkbenchPrimaryView.changes) {
      selectedView = WorkbenchPrimaryView.history;
      unawaited(_persistSelectedView());
    }
  }

  void _ensureWorkingTreeSelection(RepoSnapshot repo) {
    final entries = visibleWorkingTreeEntries;
    if (entries.isEmpty) {
      _selectedWorkingTreePathByRepoPath.remove(repo.path);
      activeDiff = null;
      unawaited(_persistSelectedWorkingTreePathMap());
      return;
    }
    final currentPath = _selectedWorkingTreePathByRepoPath[repo.path];
    if (currentPath != null &&
        entries.any((entry) => entry.path == currentPath)) {
      return;
    }
    _selectedWorkingTreePathByRepoPath[repo.path] = entries.first.path;
    unawaited(_persistSelectedWorkingTreePathMap());
  }

  void _pruneWorkingTreeBatchSelection(RepoSnapshot repo) {
    final currentPaths = repo.workingTree.entries.map((entry) => entry.path);
    selectedWorkingTreeBatchPaths.removeWhere(
      (path) => !currentPaths.contains(path),
    );
  }

  Future<void> _loadDiffForCurrentSelection({bool notify = true}) async {
    final repo = snapshot;
    final entry = selectedWorkingTreeEntry;
    if (repo == null || entry == null) {
      activeDiff = null;
      isLoadingDiff = false;
      if (notify) {
        notifyListeners();
      }
      return;
    }

    isLoadingDiff = true;
    if (notify) {
      notifyListeners();
    }
    try {
      activeDiff = await _gitService.loadWorkingTreeDiff(
        repoPath: repo.path,
        entry: entry,
      );
    } on GitCliException catch (error) {
      activeDiff = error.message;
    } catch (_) {
      activeDiff = 'Unable to load diff preview.';
    } finally {
      isLoadingDiff = false;
      notifyListeners();
    }
  }

  Future<void> _persistSelectedWorkingTreePathMap() async {
    final store = await _store();
    await store.writeString(
      _selectedWorkingTreePathByRepoKey,
      jsonEncode(_selectedWorkingTreePathByRepoPath),
    );
  }

  Future<void> _persistActiveRepoPath(String path) async {
    final store = await _store();
    await store.writeString(_activeRepoPathKey, path);
  }

  Future<void> _persistCommandLog() async {
    final store = await _store();
    await store.writeStringList(_commandLogKey, commandLog);
  }

  Future<LocalStateStore> _store() async {
    return _localStore ??= await LocalStateStore.load();
  }
}

enum WorkbenchPrimaryView { history, changes }

enum WorkingTreeLayout { flat, tree }
