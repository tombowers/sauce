enum WorkingTreeViewFilter { unstaged, staged, all, ignored }

enum GitFileStatusKind {
  unmodified,
  modified,
  added,
  deleted,
  renamed,
  copied,
  unmerged,
  untracked,
  ignored,
}

class WorkingTreeEntry {
  const WorkingTreeEntry({
    required this.path,
    required this.displayName,
    required this.directory,
    required this.stagedKind,
    required this.pendingKind,
    required this.isUntracked,
    required this.isIgnored,
    this.originalPath,
  });

  final String path;
  final String displayName;
  final String directory;
  final GitFileStatusKind stagedKind;
  final GitFileStatusKind pendingKind;
  final bool isUntracked;
  final bool isIgnored;
  final String? originalPath;

  bool get hasStagedChanges =>
      stagedKind != GitFileStatusKind.unmodified && !isIgnored && !isUntracked;

  bool get hasPendingChanges =>
      pendingKind != GitFileStatusKind.unmodified && !isIgnored && !isUntracked;

  bool get isTrackedChange =>
      !isIgnored && !isUntracked && (hasStagedChanges || hasPendingChanges);

  bool matchesFilter(WorkingTreeViewFilter filter) {
    switch (filter) {
      case WorkingTreeViewFilter.unstaged:
        return (hasPendingChanges || isUntracked) && !hasStagedChanges;
      case WorkingTreeViewFilter.staged:
        return hasStagedChanges;
      case WorkingTreeViewFilter.all:
        return hasStagedChanges || hasPendingChanges || isUntracked;
      case WorkingTreeViewFilter.ignored:
        return isIgnored;
    }
  }
}

class WorkingTreeSnapshot {
  const WorkingTreeSnapshot({
    required this.entries,
    required this.stagedCount,
    required this.pendingCount,
    required this.untrackedCount,
    required this.ignoredCount,
  });

  final List<WorkingTreeEntry> entries;
  final int stagedCount;
  final int pendingCount;
  final int untrackedCount;
  final int ignoredCount;

  int get totalCount => entries.length;
  int get dirtyCount => entries
      .where(
        (entry) =>
            entry.hasStagedChanges ||
            entry.hasPendingChanges ||
            entry.isUntracked,
      )
      .length;

  int countForFilter(WorkingTreeViewFilter filter) {
    return entriesForFilter(filter).length;
  }

  List<WorkingTreeEntry> entriesForFilter(WorkingTreeViewFilter filter) {
    return entries.where((entry) => entry.matchesFilter(filter)).toList()
      ..sort(_compareWorkingTreeEntries);
  }

  static int _compareWorkingTreeEntries(
    WorkingTreeEntry left,
    WorkingTreeEntry right,
  ) {
    final untrackedOrder = left.isUntracked == right.isUntracked
        ? 0
        : left.isUntracked
        ? 1
        : -1;
    if (untrackedOrder != 0) {
      return untrackedOrder;
    }
    return left.path.compareTo(right.path);
  }
}
