import 'branch_entry.dart';
import 'commit_entry.dart';
import 'working_tree_entry.dart';

class RepoSnapshot {
  const RepoSnapshot({
    required this.name,
    required this.path,
    required this.branch,
    required this.aheadBy,
    required this.behindBy,
    required this.stagedCount,
    required this.unstagedCount,
    required this.untrackedCount,
    required this.workingTree,
    required this.branches,
    required this.commits,
  });

  final String name;
  final String path;
  final String branch;
  final int aheadBy;
  final int behindBy;
  final int stagedCount;
  final int unstagedCount;
  final int untrackedCount;
  final WorkingTreeSnapshot workingTree;
  final List<BranchEntry> branches;
  final List<CommitEntry> commits;
}
