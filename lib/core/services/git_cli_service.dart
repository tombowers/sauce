import 'dart:io';

import '../models/commit_entry.dart';
import '../models/repo_snapshot.dart';

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
      '--short',
      '--branch',
      '--porcelain=v1',
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

    return _buildSnapshot(
      resolvedPath: resolvedPath,
      statusOutput: statusResult.stdout,
      logOutput: logResult.stdout,
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

  RepoSnapshot _buildSnapshot({
    required String resolvedPath,
    required String statusOutput,
    required String logOutput,
  }) {
    final statusLines = statusOutput
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((line) => line.isNotEmpty)
        .toList();

    final branchLine = statusLines.isNotEmpty ? statusLines.first : '';
    var stagedCount = 0;
    var unstagedCount = 0;
    var untrackedCount = 0;

    for (final line in statusLines.skip(1)) {
      if (line.startsWith('??')) {
        untrackedCount++;
        continue;
      }

      if (line.length >= 2) {
        if (line[0] != ' ') {
          stagedCount++;
        }
        if (line[1] != ' ') {
          unstagedCount++;
        }
      }
    }

    final branchName = _parseBranchName(branchLine);
    final aheadBy = _parseAheadBehind(branchLine, 'ahead');
    final behindBy = _parseAheadBehind(branchLine, 'behind');
    final commits = _parseCommits(logOutput);

    return RepoSnapshot(
      name: _repoNameFromPath(resolvedPath),
      path: resolvedPath,
      branch: branchName,
      aheadBy: aheadBy,
      behindBy: behindBy,
      stagedCount: stagedCount,
      unstagedCount: unstagedCount,
      untrackedCount: untrackedCount,
      commits: commits,
    );
  }

  String _parseBranchName(String branchLine) {
    if (!branchLine.startsWith('## ')) {
      return 'unknown';
    }

    final content = branchLine.substring(3);
    final splitIndex = content.indexOf('...');
    if (splitIndex == -1) {
      return content;
    }
    return content.substring(0, splitIndex);
  }

  int _parseAheadBehind(String branchLine, String label) {
    final match = RegExp('$label (\\d+)').firstMatch(branchLine);
    return match == null ? 0 : int.parse(match.group(1)!);
  }

  List<CommitEntry> _parseCommits(String logOutput) {
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

    return _applyGraphLayout(commits);
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

  List<CommitEntry> _applyGraphLayout(List<_PendingCommit> commits) {
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
        ),
    ];
  }

  String _repoNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/');
    return segments.isNotEmpty ? segments.last : path;
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
