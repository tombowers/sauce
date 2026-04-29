class CommitEntry {
  const CommitEntry({
    required this.sha,
    required this.parentShas,
    required this.message,
    required this.author,
    required this.relativeTime,
    required this.refs,
    required this.filesChanged,
    required this.insertions,
    required this.deletions,
    required this.graphLane,
    required this.graphLaneKey,
    required this.beforeLaneCount,
    required this.afterLaneCount,
    required this.parentLanes,
    required this.beforeLaneKeys,
    required this.afterLaneKeys,
    required this.hasTopContinuation,
    required this.visibleChildLaneKeys,
    required this.isUnpushed,
  });

  final String sha;
  final List<String> parentShas;
  final String message;
  final String author;
  final String relativeTime;
  final List<String> refs;
  final int filesChanged;
  final int insertions;
  final int deletions;
  final int graphLane;
  final String graphLaneKey;
  final int beforeLaneCount;
  final int afterLaneCount;
  final List<int> parentLanes;
  final List<String> beforeLaneKeys;
  final List<String> afterLaneKeys;
  final bool hasTopContinuation;
  final List<String> visibleChildLaneKeys;
  final bool isUnpushed;
}

class CommitFileChange {
  const CommitFileChange({
    required this.path,
    required this.statusCode,
    this.originalPath,
  });

  final String path;
  final String statusCode;
  final String? originalPath;

  bool get isRename => statusCode.startsWith('R');
  bool get isCopy => statusCode.startsWith('C');
  String get shortStatus => statusCode.isEmpty ? '?' : statusCode[0];
}
