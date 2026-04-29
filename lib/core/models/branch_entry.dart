class BranchEntry {
  const BranchEntry({
    required this.name,
    required this.fullRefName,
    required this.isRemote,
    required this.isCurrent,
    required this.upstream,
    required this.commitSha,
    required this.relativeTime,
  });

  final String name;
  final String fullRefName;
  final bool isRemote;
  final bool isCurrent;
  final String? upstream;
  final String commitSha;
  final String relativeTime;

  String get shortName {
    if (!isRemote) {
      return name;
    }
    final slashIndex = name.indexOf('/');
    return slashIndex == -1 ? name : name.substring(slashIndex + 1);
  }

  String get remoteName {
    if (!isRemote) {
      return '';
    }
    final slashIndex = name.indexOf('/');
    return slashIndex == -1 ? name : name.substring(0, slashIndex);
  }
}
