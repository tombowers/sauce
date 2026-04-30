import 'dart:convert';
import 'dart:io';

import '../models/branch_entry.dart';
import '../models/commit_entry.dart';
import '../models/repo_snapshot.dart';
import '../models/working_tree_entry.dart';

class GitCliService {
  static const _defaultHistoryDepth = 80;
  static const _allRefsHistoryDepth = 200;

  Future<RepoSnapshot> loadSnapshot(
    String repoPath, {
    bool showRemoteBranches = false,
  }) async {
    final resolvedPath = await _resolveRepositoryRoot(repoPath);
    final statusResult = await _runGit([
      'status',
      '--branch',
      '--porcelain=v2',
      '-z',
      '--ignored=matching',
    ], workingDirectory: resolvedPath);
    final logArgs = <String>[
      'log',
      '--decorate=short',
      '--date=relative',
      '--shortstat',
      '--topo-order',
      '--pretty=format:%x1e%h%x1f%p%x1f%an%x1f%ar%x1f%d%x1f%s%n',
    ];
    if (showRemoteBranches) {
      logArgs.addAll([
        '--branches',
        '--remotes',
        '--tags',
        '-n',
        '$_allRefsHistoryDepth',
      ]);
    } else {
      logArgs.addAll(['HEAD', '--tags', '-n', '$_defaultHistoryDepth']);
    }
    final logResult = await _runGit(logArgs, workingDirectory: resolvedPath);
    final branchesResult = await _runGit([
      'for-each-ref',
      '--sort=-committerdate',
      '--format=%(refname:short)%x1f%(refname)%x1f%(upstream:short)%x1f%(HEAD)%x1f%(objectname:short)%x1f%(committerdate:relative)',
      'refs/heads',
      'refs/remotes',
    ], workingDirectory: resolvedPath);
    final branches = _parseBranches(branchesResult.stdout);
    final unpushedShas = await _loadUnpushedCommitShas(resolvedPath, branches);

    return _buildSnapshot(
      resolvedPath: resolvedPath,
      statusOutput: statusResult.stdout,
      logOutput: logResult.stdout,
      branches: branches,
      unpushedShas: unpushedShas,
    );
  }

  Future<GitCommandResult> runCommand(
    List<String> args, {
    required String workingDirectory,
    void Function(String line)? onLine,
  }) async {
    final process = await Process.start(
      'git',
      args,
      workingDirectory: workingDirectory,
      runInShell: true,
    );

    final stdoutLines = <String>[];
    final stderrLines = <String>[];

    Future<void> readStream(Stream<List<int>> stream, List<String> sink) async {
      await for (final chunk in stream.transform(systemEncoding.decoder)) {
        final lines = chunk.replaceAll('\r\n', '\n').split('\n');
        for (final rawLine in lines) {
          if (rawLine.isEmpty) {
            continue;
          }
          sink.add(rawLine);
          onLine?.call(rawLine);
        }
      }
    }

    await Future.wait([
      readStream(process.stdout, stdoutLines),
      readStream(process.stderr, stderrLines),
    ]);

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw GitCliException(
        stderrLines.isNotEmpty
            ? stderrLines.join('\n')
            : 'git ${args.join(' ')} failed with exit code $exitCode.',
      );
    }

    return GitCommandResult(
      stdout: stdoutLines,
      stderr: stderrLines,
      exitCode: exitCode,
    );
  }

  Future<String> loadWorkingTreeDiff({
    required String repoPath,
    required WorkingTreeEntry entry,
    WorkingTreeSelectionScope? scope,
  }) async {
    if (entry.isIgnored) {
      return 'Ignored files do not have a working diff.';
    }

    if (entry.isUntracked) {
      return _buildUntrackedDiff(repoPath, entry.path);
    }

    final sections = <String>[];
    final includeStaged = scope != WorkingTreeSelectionScope.unstaged;
    final includePending = scope != WorkingTreeSelectionScope.staged;

    if (includeStaged && entry.hasStagedChanges) {
      final stagedDiff = await _runGitAllowFailure([
        'diff',
        '--cached',
        '--',
        entry.path,
      ], workingDirectory: repoPath);
      final trimmed = stagedDiff.stdout.trimRight();
      if (trimmed.isNotEmpty) {
        sections.add(trimmed);
      }
    }

    if (includePending && entry.hasPendingChanges) {
      final pendingDiff = await _runGitAllowFailure([
        'diff',
        '--',
        entry.path,
      ], workingDirectory: repoPath);
      final trimmed = pendingDiff.stdout.trimRight();
      if (trimmed.isNotEmpty) {
        sections.add(trimmed);
      }
    }

    if (sections.isEmpty) {
      return 'No diff available for this file.';
    }

    return sections.join('\n\n');
  }

  Future<List<CommitFileChange>> loadCommitFiles({
    required String repoPath,
    required String sha,
  }) async {
    final result = await _runGitAllowFailure([
      'show',
      '--format=',
      '--name-status',
      '--find-renames',
      '--find-copies',
      sha,
      '--',
    ], workingDirectory: repoPath);
    if (result.exitCode != 0) {
      return const <CommitFileChange>[];
    }

    final changes = <CommitFileChange>[];
    for (final rawLine
        in (result.stdout as String).replaceAll('\r\n', '\n').split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        continue;
      }
      final fields = line.split('\t');
      if (fields.length < 2) {
        continue;
      }
      final statusCode = fields[0].trim();
      if (statusCode.startsWith('R') || statusCode.startsWith('C')) {
        if (fields.length < 3) {
          continue;
        }
        changes.add(
          CommitFileChange(
            path: fields[2].trim(),
            statusCode: statusCode,
            originalPath: fields[1].trim(),
          ),
        );
        continue;
      }
      changes.add(
        CommitFileChange(path: fields[1].trim(), statusCode: statusCode),
      );
    }
    return changes;
  }

  Future<String> loadCommitDiff({
    required String repoPath,
    required String sha,
    required CommitFileChange change,
  }) async {
    final result = await _runGitAllowFailure([
      'show',
      '--format=',
      '--find-renames',
      '--find-copies',
      sha,
      '--',
      change.path,
    ], workingDirectory: repoPath);
    if (result.exitCode != 0) {
      return 'Unable to load diff preview.';
    }
    final diff = (result.stdout as String).trimRight();
    if (diff.isNotEmpty) {
      return diff;
    }
    if (change.originalPath != null && change.originalPath != change.path) {
      final retry = await _runGitAllowFailure([
        'show',
        '--format=',
        '--find-renames',
        '--find-copies',
        sha,
        '--',
        change.originalPath!,
      ], workingDirectory: repoPath);
      if (retry.exitCode == 0) {
        final retryDiff = (retry.stdout as String).trimRight();
        if (retryDiff.isNotEmpty) {
          return retryDiff;
        }
      }
    }
    return 'No diff available for this file.';
  }

  Future<String> _resolveRepositoryRoot(String repoPath) async {
    final result = await _runGit([
      'rev-parse',
      '--show-toplevel',
    ], workingDirectory: repoPath);
    return result.stdout.trim();
  }

  Future<ProcessResult> _runGit(
    List<String> args, {
    required String workingDirectory,
  }) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: workingDirectory,
      runInShell: true,
    );

    if (result.exitCode != 0) {
      final stderr = (result.stderr as String).trim();
      throw GitCliException(
        stderr.isNotEmpty
            ? stderr
            : 'git ${args.join(' ')} failed with exit code ${result.exitCode}.',
      );
    }

    return result;
  }

  Future<ProcessResult> _runGitAllowFailure(
    List<String> args, {
    required String workingDirectory,
  }) {
    return Process.run(
      'git',
      args,
      workingDirectory: workingDirectory,
      runInShell: true,
    );
  }

  RepoSnapshot _buildSnapshot({
    required String resolvedPath,
    required String statusOutput,
    required String logOutput,
    required List<BranchEntry> branches,
    required Set<String> unpushedShas,
  }) {
    final statusSnapshot = _parseWorkingTree(statusOutput);
    final commits = _parseCommits(logOutput, unpushedShas);

    return RepoSnapshot(
      name: _repoNameFromPath(resolvedPath),
      path: resolvedPath,
      branch: statusSnapshot.branch,
      aheadBy: statusSnapshot.aheadBy,
      behindBy: statusSnapshot.behindBy,
      stagedCount: statusSnapshot.workingTree.stagedCount,
      unstagedCount: statusSnapshot.workingTree.pendingCount,
      untrackedCount: statusSnapshot.workingTree.untrackedCount,
      workingTree: statusSnapshot.workingTree,
      branches: branches,
      commits: commits,
    );
  }

  List<BranchEntry> _parseBranches(String branchOutput) {
    final branches = <BranchEntry>[];
    for (final rawLine in branchOutput.replaceAll('\r\n', '\n').split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        continue;
      }
      final fields = line.contains('\x1f')
          ? line.split('\x1f')
          : line.split('%x1f');
      if (fields.length < 6) {
        continue;
      }
      final name = fields[0].trim();
      final fullRefName = fields[1].trim();
      final upstream = fields[2].trim().isEmpty ? null : fields[2].trim();
      final headMarker = fields[3].trim();
      final commitSha = fields[4].trim();
      final relativeTime = fields[5].trim();
      final isRemote = fullRefName.startsWith('refs/remotes/');
      if (isRemote && name.endsWith('/HEAD')) {
        continue;
      }
      branches.add(
        BranchEntry(
          name: name,
          fullRefName: fullRefName,
          isRemote: isRemote,
          isCurrent: headMarker == '*',
          upstream: upstream,
          commitSha: commitSha,
          relativeTime: relativeTime,
        ),
      );
    }

    final locals = branches.where((branch) => !branch.isRemote).toList()
      ..sort(_compareBranches);
    final remotes = branches.where((branch) => branch.isRemote).toList()
      ..sort(_compareBranches);
    return [...locals, ...remotes];
  }

  int _compareBranches(BranchEntry left, BranchEntry right) {
    if (left.isCurrent != right.isCurrent) {
      return left.isCurrent ? -1 : 1;
    }
    return left.name.compareTo(right.name);
  }

  _ParsedStatusSnapshot _parseWorkingTree(String statusOutput) {
    final records = statusOutput.split('\x00');
    var branch = 'unknown';
    var aheadBy = 0;
    var behindBy = 0;
    var stagedCount = 0;
    var pendingCount = 0;
    var untrackedCount = 0;
    var ignoredCount = 0;
    final entries = <WorkingTreeEntry>[];

    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      if (record.isEmpty) {
        continue;
      }

      if (record.startsWith('# ')) {
        if (record.startsWith('# branch.head ')) {
          branch = record.substring('# branch.head '.length).trim();
        } else if (record.startsWith('# branch.ab ')) {
          final match = RegExp(
            r'# branch\.ab \+(\d+) \-(\d+)',
          ).firstMatch(record);
          if (match != null) {
            aheadBy = int.parse(match.group(1)!);
            behindBy = int.parse(match.group(2)!);
          }
        }
        continue;
      }

      final kind = record[0];
      if (kind == '?' || kind == '!') {
        final rawPath = record.length > 2 ? record.substring(2) : '';
        final normalizedPath = rawPath.replaceAll('\\', '/');
        final entry = _buildWorkingTreeEntry(
          path: normalizedPath,
          stagedKind: kind == '?'
              ? GitFileStatusKind.untracked
              : GitFileStatusKind.ignored,
          pendingKind: kind == '?'
              ? GitFileStatusKind.untracked
              : GitFileStatusKind.ignored,
          isUntracked: kind == '?',
          isIgnored: kind == '!',
        );
        entries.add(entry);
        if (kind == '?') {
          untrackedCount++;
        } else {
          ignoredCount++;
        }
        continue;
      }

      final parts = record.split(' ');
      if (parts.length < 2) {
        continue;
      }

      final xy = parts[1];
      final stagedKind = _statusKindFromCode(xy.isNotEmpty ? xy[0] : '.');
      final pendingKind = _statusKindFromCode(xy.length > 1 ? xy[1] : '.');
      final path = parts.last.replaceAll('\\', '/');
      String? originalPath;
      if (kind == '2' && index + 1 < records.length) {
        originalPath = records[++index].replaceAll('\\', '/');
      }

      final entry = _buildWorkingTreeEntry(
        path: path,
        originalPath: originalPath,
        stagedKind: stagedKind,
        pendingKind: pendingKind,
        isUntracked: false,
        isIgnored: false,
      );
      entries.add(entry);
      if (entry.hasStagedChanges) {
        stagedCount++;
      }
      if (entry.hasPendingChanges) {
        pendingCount++;
      }
    }

    entries.sort((a, b) => a.path.compareTo(b.path));

    return _ParsedStatusSnapshot(
      branch: branch == '(detached)' ? 'DETACHED' : branch,
      aheadBy: aheadBy,
      behindBy: behindBy,
      workingTree: WorkingTreeSnapshot(
        entries: entries,
        stagedCount: stagedCount,
        pendingCount: pendingCount,
        untrackedCount: untrackedCount,
        ignoredCount: ignoredCount,
      ),
    );
  }

  WorkingTreeEntry _buildWorkingTreeEntry({
    required String path,
    required GitFileStatusKind stagedKind,
    required GitFileStatusKind pendingKind,
    required bool isUntracked,
    required bool isIgnored,
    String? originalPath,
  }) {
    final normalizedPath = path.replaceAll('\\', '/');
    final lastSlash = normalizedPath.lastIndexOf('/');
    final directory = lastSlash == -1
        ? '.'
        : normalizedPath.substring(0, lastSlash);
    final displayName = lastSlash == -1
        ? normalizedPath
        : normalizedPath.substring(lastSlash + 1);
    return WorkingTreeEntry(
      path: normalizedPath,
      displayName: displayName,
      directory: directory,
      stagedKind: stagedKind,
      pendingKind: pendingKind,
      isUntracked: isUntracked,
      isIgnored: isIgnored,
      originalPath: originalPath,
    );
  }

  GitFileStatusKind _statusKindFromCode(String code) {
    switch (code) {
      case '.':
      case ' ':
        return GitFileStatusKind.unmodified;
      case 'M':
        return GitFileStatusKind.modified;
      case 'A':
        return GitFileStatusKind.added;
      case 'D':
        return GitFileStatusKind.deleted;
      case 'R':
        return GitFileStatusKind.renamed;
      case 'C':
        return GitFileStatusKind.copied;
      case 'U':
        return GitFileStatusKind.unmerged;
      case '?':
        return GitFileStatusKind.untracked;
      case '!':
        return GitFileStatusKind.ignored;
      default:
        return GitFileStatusKind.modified;
    }
  }

  List<CommitEntry> _parseCommits(String logOutput, Set<String> unpushedShas) {
    final lines = logOutput.replaceAll('\r\n', '\n').split('\n');
    final commits = <_PendingCommit>[];
    _PendingCommit? current;

    for (final line in lines) {
      if (line.contains('\x1e')) {
        if (current != null) {
          commits.add(current);
        }

        final separatorIndex = line.indexOf('\x1e');
        final fields = line.substring(separatorIndex + 1).split('\x1f');
        if (fields.length < 6) {
          continue;
        }

        current = _PendingCommit(
          sha: fields[0],
          parentShas: _parseParents(fields[1]),
          author: fields[2],
          relativeTime: fields[3],
          refs: _parseRefs(fields[4]),
          message: _sanitizeMessage(fields[5]),
        );
        continue;
      }

      if (current == null) {
        continue;
      }

      final trimmed = line.trim();
      if (!trimmed.contains('file changed') &&
          !trimmed.contains('files changed')) {
        continue;
      }

      current.applyShortStat(trimmed);
    }

    if (current != null) {
      commits.add(current);
    }

    return _applyGraphLayout(commits, unpushedShas);
  }

  List<String> _parseParents(String parents) {
    final trimmed = parents.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    return trimmed.split(' ').where((parent) => parent.isNotEmpty).toList();
  }

  List<String> _parseRefs(String decorations) {
    final trimmed = decorations.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final normalized = trimmed.startsWith('(') && trimmed.endsWith(')')
        ? trimmed.substring(1, trimmed.length - 1)
        : trimmed;

    return normalized
        .split(',')
        .map((ref) => ref.trim().replaceAll('HEAD -> ', 'HEAD '))
        .where((ref) => ref.isNotEmpty)
        .toList();
  }

  String _sanitizeMessage(String message) {
    return message
        .trimRight()
        .replaceFirst(RegExp(r'[|/\\]+$'), '')
        .trimRight();
  }

  List<CommitEntry> _applyGraphLayout(
    List<_PendingCommit> commits,
    Set<String> unpushedShas,
  ) {
    final activeLanes = <_ActiveLane>[];
    final laidOutPending = <_LaidOutPendingCommit>[];
    var generatedLaneId = 0;

    for (final commit in commits) {
      var lane = activeLanes.indexWhere((lane) => lane.targetSha == commit.sha);
      var hasTopContinuation = lane != -1;
      late String currentLaneKey;

      if (lane == -1) {
        lane = activeLanes.length;
        currentLaneKey = 'lane-${generatedLaneId++}';
        activeLanes.insert(
          lane,
          _ActiveLane(key: currentLaneKey, targetSha: commit.sha),
        );
      } else {
        currentLaneKey = activeLanes[lane].key;
      }

      final beforeLaneKeys = activeLanes.map((lane) => lane.key).toList();
      final beforeLaneCount = activeLanes.length;
      activeLanes.removeAt(lane);

      final parentLanes = <int>[];
      if (commit.parentShas.isNotEmpty) {
        final primaryParent = commit.parentShas.first;
        var primaryParentLane = activeLanes.indexWhere(
          (lane) => lane.targetSha == primaryParent,
        );
        if (primaryParentLane == -1) {
          primaryParentLane = lane.clamp(0, activeLanes.length);
          activeLanes.insert(
            primaryParentLane,
            _ActiveLane(key: currentLaneKey, targetSha: primaryParent),
          );
        }
        parentLanes.add(primaryParentLane);

        var insertIndex = primaryParentLane + 1;
        for (final parent in commit.parentShas.skip(1)) {
          var parentLane = activeLanes.indexWhere(
            (lane) => lane.targetSha == parent,
          );
          if (parentLane == -1) {
            parentLane = insertIndex.clamp(0, activeLanes.length);
            activeLanes.insert(
              parentLane,
              _ActiveLane(key: 'lane-${generatedLaneId++}', targetSha: parent),
            );
          }
          parentLanes.add(parentLane);
          insertIndex = parentLane + 1;
        }
      }

      final afterLaneKeys = activeLanes.map((lane) => lane.key).toList();
      final afterLaneCount = activeLanes.length;

      laidOutPending.add(
        _LaidOutPendingCommit(
          commit: commit,
          graphLane: lane,
          graphLaneKey: currentLaneKey,
          beforeLaneCount: beforeLaneCount,
          afterLaneCount: afterLaneCount,
          parentLanes: parentLanes,
          beforeLaneKeys: beforeLaneKeys,
          afterLaneKeys: afterLaneKeys,
          hasTopContinuation: hasTopContinuation,
        ),
      );
    }

    final visibleBelowByIndex = <int, List<String>>{};
    for (var index = 0; index < laidOutPending.length; index++) {
      final nextBeforeLaneKeys = index + 1 < laidOutPending.length
          ? laidOutPending[index + 1].beforeLaneKeys
          : const <String>[];
      visibleBelowByIndex[index] = laidOutPending[index].afterLaneKeys
          .where(nextBeforeLaneKeys.contains)
          .toList();
    }

    return [
      for (var index = 0; index < laidOutPending.length; index++)
        laidOutPending[index].commit.build(
          graphLane: laidOutPending[index].graphLane,
          graphLaneKey: laidOutPending[index].graphLaneKey,
          beforeLaneCount: laidOutPending[index].beforeLaneCount,
          afterLaneCount: laidOutPending[index].afterLaneCount,
          parentLanes: laidOutPending[index].parentLanes,
          beforeLaneKeys: laidOutPending[index].beforeLaneKeys,
          afterLaneKeys: laidOutPending[index].afterLaneKeys,
          hasTopContinuation: laidOutPending[index].hasTopContinuation,
          visibleChildLaneKeys: visibleBelowByIndex[index] ?? const [],
          isUnpushed: unpushedShas.contains(laidOutPending[index].commit.sha),
        ),
    ];
  }

  Future<Set<String>> _loadUnpushedCommitShas(
    String repoPath,
    List<BranchEntry> branches,
  ) async {
    final currentBranches = branches.where(
      (branch) => !branch.isRemote && branch.isCurrent,
    );
    final currentBranch = currentBranches.isEmpty
        ? null
        : currentBranches.first;
    final upstream = currentBranch?.upstream;
    if (upstream == null || upstream.isEmpty) {
      return <String>{};
    }
    final result = await _runGitAllowFailure([
      'rev-list',
      '$upstream..HEAD',
    ], workingDirectory: repoPath);
    if (result.exitCode != 0) {
      return <String>{};
    }
    return (result.stdout as String)
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toSet();
  }

  String _repoNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/');
    return segments.isNotEmpty ? segments.last : path;
  }

  Future<String> _buildUntrackedDiff(
    String repoPath,
    String relativePath,
  ) async {
    final file = File(
      '$repoPath${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    if (!await file.exists()) {
      return 'File no longer exists on disk.';
    }

    try {
      final contents = await file.readAsString();
      final lines = const LineSplitter().convert(contents);
      final buffer = StringBuffer()
        ..writeln('diff --git a/$relativePath b/$relativePath')
        ..writeln('new file mode 100644')
        ..writeln('--- /dev/null')
        ..writeln('+++ b/$relativePath')
        ..writeln('@@ -0,0 +1,${lines.length} @@');
      for (final line in lines) {
        buffer.writeln('+$line');
      }
      if (contents.endsWith('\n') && lines.isEmpty) {
        buffer.writeln('+');
      }
      return buffer.toString().trimRight();
    } on FileSystemException {
      return 'Unable to read file contents for diff preview.';
    } on FormatException {
      return 'Binary or non-text file. Diff preview is not available yet.';
    }
  }
}

class GitCommandResult {
  const GitCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  final List<String> stdout;
  final List<String> stderr;
  final int exitCode;
}

class GitCliException implements Exception {
  const GitCliException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _PendingCommit {
  _PendingCommit({
    required this.sha,
    required this.parentShas,
    required this.message,
    required this.author,
    required this.relativeTime,
    required this.refs,
  });

  final String sha;
  final List<String> parentShas;
  final String message;
  final String author;
  final String relativeTime;
  final List<String> refs;

  int filesChanged = 0;
  int insertions = 0;
  int deletions = 0;

  void applyShortStat(String statLine) {
    filesChanged = _extractInt(statLine, RegExp(r'(\d+) file[s]? changed'));
    insertions = _extractInt(statLine, RegExp(r'(\d+) insertion[s]?\(\+\)'));
    deletions = _extractInt(statLine, RegExp(r'(\d+) deletion[s]?\(-\)'));
  }

  int _extractInt(String source, RegExp pattern) {
    final match = pattern.firstMatch(source);
    return match == null ? 0 : int.parse(match.group(1)!);
  }

  CommitEntry build({
    required int graphLane,
    required String graphLaneKey,
    required int beforeLaneCount,
    required int afterLaneCount,
    required List<int> parentLanes,
    required List<String> beforeLaneKeys,
    required List<String> afterLaneKeys,
    required bool hasTopContinuation,
    required List<String> visibleChildLaneKeys,
    required bool isUnpushed,
  }) {
    return CommitEntry(
      sha: sha,
      parentShas: parentShas,
      message: message,
      author: author,
      relativeTime: relativeTime,
      refs: refs,
      filesChanged: filesChanged,
      insertions: insertions,
      deletions: deletions,
      graphLane: graphLane,
      graphLaneKey: graphLaneKey,
      beforeLaneCount: beforeLaneCount,
      afterLaneCount: afterLaneCount,
      parentLanes: parentLanes,
      beforeLaneKeys: beforeLaneKeys,
      afterLaneKeys: afterLaneKeys,
      hasTopContinuation: hasTopContinuation,
      visibleChildLaneKeys: visibleChildLaneKeys,
      isUnpushed: isUnpushed,
    );
  }
}

class _ActiveLane {
  const _ActiveLane({required this.key, required this.targetSha});

  final String key;
  final String targetSha;
}

class _LaidOutPendingCommit {
  const _LaidOutPendingCommit({
    required this.commit,
    required this.graphLane,
    required this.graphLaneKey,
    required this.beforeLaneCount,
    required this.afterLaneCount,
    required this.parentLanes,
    required this.beforeLaneKeys,
    required this.afterLaneKeys,
    required this.hasTopContinuation,
  });

  final _PendingCommit commit;
  final int graphLane;
  final String graphLaneKey;
  final int beforeLaneCount;
  final int afterLaneCount;
  final List<int> parentLanes;
  final List<String> beforeLaneKeys;
  final List<String> afterLaneKeys;
  final bool hasTopContinuation;
}

class _ParsedStatusSnapshot {
  const _ParsedStatusSnapshot({
    required this.branch,
    required this.aheadBy,
    required this.behindBy,
    required this.workingTree,
  });

  final String branch;
  final int aheadBy;
  final int behindBy;
  final WorkingTreeSnapshot workingTree;
}
