import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/models/commit_entry.dart';
import '../../../core/models/repo_snapshot.dart';
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
  final GitCliService _gitService;
  LocalStateStore? _localStore;
  final Map<String, String> _selectedCommitByRepoPath = <String, String>{};

  RepoSnapshot? snapshot;
  String repoPath = '';
  String? errorMessage;
  bool isLoading = false;
  bool isRunningCommand = false;
  bool showRemoteBranches = false;
  int selectedCommitIndex = 0;
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
    commandLog
      ..clear()
      ..addAll(store.readStringList(_commandLogKey));
    if (commandLog.isEmpty) {
      commandLog.add('Connect a local repository to begin.');
    }
    _selectedCommitByRepoPath
      ..clear()
      ..addAll(_loadSelectedCommitByRepoPath(store));

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
      selectedCommitIndex = _resolveSelectedCommitIndex(nextSnapshot);
      _rememberRepo(nextSnapshot.path);
      unawaited(_persistActiveRepoPath(nextSnapshot.path));
      _persistSelectedCommitForCurrentRepo();
    } on GitCliException catch (error) {
      errorMessage = error.message;
    } catch (_) {
      errorMessage = 'Unable to inspect that repository.';
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
    _persistSelectedCommitForCurrentRepo();
    notifyListeners();
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
    final rawJson = store.readString(_selectedCommitByRepoKey, fallback: '{}');
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
