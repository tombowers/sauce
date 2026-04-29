part of 'workbench_screen.dart';

class _InlineToggle extends StatelessWidget {
  const _InlineToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: value ? const Color(0xFFF0F6FF) : const Color(0xFFF6F8FB),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 8,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
              size: 18,
              color: value ? const Color(0xFF3B82F6) : const Color(0xFF667085),
            ),
            const SizedBox(width: 8),
            Text(label, style: theme.textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}

class _ConsoleCard extends StatelessWidget {
  const _ConsoleCard({
    required this.lines,
    required this.commandController,
    this.scrollController,
    required this.onSubmit,
    required this.isBusy,
    required this.isConnected,
    required this.isCollapsed,
    required this.onToggleCollapsed,
  });

  final List<String> lines;
  final TextEditingController commandController;
  final ScrollController? scrollController;
  final ValueChanged<String> onSubmit;
  final bool isBusy;
  final bool isConnected;
  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE7ECF2))),
        color: Color(0xFFFDFDFC),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 50,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Console',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _HeaderIconButton(
                    icon: isCollapsed
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    onTap: onToggleCollapsed,
                    tooltip: isCollapsed
                        ? 'Expand console'
                        : 'Collapse console',
                  ),
                  const Spacer(),
                  if (isBusy)
                    Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Running command',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: const Color(0xFF667085),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (!isCollapsed)
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xFF201C19),
                  border: Border(top: BorderSide(color: Color(0xFF2A2623))),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
                  child: Column(
                    children: [
                      Expanded(
                        child: scrollController == null
                            ? const SizedBox.shrink()
                            : Scrollbar(
                                controller: scrollController!,
                                thumbVisibility: true,
                                interactive: true,
                                child: _ConsoleLines(
                                  lines: lines,
                                  controller: scrollController!,
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text(
                            '\$',
                            style: TextStyle(
                              fontFamily: _monoFontFamily,
                              color: Color(0xFFF6BF87),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: commandController,
                              enabled: isConnected && !isBusy,
                              onSubmitted: onSubmit,
                              style: const TextStyle(
                                fontFamily: _monoFontFamily,
                                color: Color(0xFFF4EEDF),
                              ),
                              decoration: InputDecoration(
                                hintText: isConnected
                                    ? 'Enter a git command, for example: status --short'
                                    : 'Connect a repository to run commands',
                                hintStyle: const TextStyle(
                                  color: Color(0x80F4EEDF),
                                ),
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConsoleLines extends StatelessWidget {
  const _ConsoleLines({required this.lines, required this.controller});

  final List<String> lines;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView.builder(
      controller: controller,
      reverse: true,
      primary: false,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[lines.length - 1 - index];
        final color = line.startsWith(r'$')
            ? const Color(0xFFF6BF87)
            : const Color(0xFFE9DDCC);
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            line,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: _monoFontFamily,
              color: color,
            ),
          ),
        );
      },
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Ink(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8FB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE6EBF2)),
            ),
            child: Icon(icon, size: 18),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.icon,
    required this.tone,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFFE6EBF2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: tone,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 7),
            Icon(icon, size: 14, color: tone),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontFamily: _monoFontFamily,
                color: Color(0xFF344054),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefBadge extends StatelessWidget {
  const _RefBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: _monoFontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF44556B),
        ),
      ),
    );
  }
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: _monoFontFamily,
            ),
          ),
        ],
      ),
    );
  }
}

List<_WorkingTreeDirectoryGroup> _groupWorkingTreeEntries(
  List<WorkingTreeEntry> entries,
) {
  final groups = <String, List<WorkingTreeEntry>>{};
  for (final entry in entries) {
    groups.putIfAbsent(entry.directory, () => <WorkingTreeEntry>[]).add(entry);
  }

  final sortedKeys = groups.keys.toList()..sort();
  return sortedKeys
      .map(
        (key) => _WorkingTreeDirectoryGroup(
          directory: key,
          entries: groups[key]!..sort((a, b) => a.path.compareTo(b.path)),
        ),
      )
      .toList();
}

String _workingTreeFilterLabel(WorkingTreeViewFilter filter) {
  switch (filter) {
    case WorkingTreeViewFilter.unstaged:
      return 'Unstaged';
    case WorkingTreeViewFilter.staged:
      return 'Staged';
    case WorkingTreeViewFilter.all:
      return 'All';
    case WorkingTreeViewFilter.ignored:
      return 'Ignored';
  }
}

String _emptyChangesMessage(
  WorkingTreeViewFilter filter, {
  required bool hasOnlyIgnoredFiles,
}) {
  if (filter == WorkingTreeViewFilter.unstaged && hasOnlyIgnoredFiles) {
    return 'Working tree is clean. Ignored files are hidden from Unstaged.';
  }
  if (filter == WorkingTreeViewFilter.unstaged ||
      filter == WorkingTreeViewFilter.all) {
    return 'Working tree is clean.';
  }
  return 'Nothing in ${_workingTreeFilterLabel(filter).toLowerCase()}.';
}

String _fileStateSummary(WorkingTreeEntry entry) {
  if (entry.isIgnored) {
    return 'ignored';
  }
  if (entry.isUntracked) {
    return 'new';
  }
  final parts = <String>[];
  if (entry.hasStagedChanges) {
    parts.add('staged ${_statusLabel(entry.stagedKind)}');
  }
  if (entry.hasPendingChanges) {
    parts.add('pending ${_statusLabel(entry.pendingKind)}');
  }
  return parts.join('  ');
}

String _statusLabel(GitFileStatusKind kind) {
  switch (kind) {
    case GitFileStatusKind.modified:
      return 'mod';
    case GitFileStatusKind.added:
      return 'add';
    case GitFileStatusKind.deleted:
      return 'del';
    case GitFileStatusKind.renamed:
      return 'ren';
    case GitFileStatusKind.copied:
      return 'copy';
    case GitFileStatusKind.unmerged:
      return 'merge';
    case GitFileStatusKind.untracked:
      return 'new';
    case GitFileStatusKind.ignored:
      return 'ignored';
    case GitFileStatusKind.unmodified:
      return 'clean';
  }
}

Color _workingTreeEntryTone(WorkingTreeEntry entry) {
  if (entry.isIgnored) {
    return const Color(0xFF98A2B3);
  }
  if (entry.isUntracked) {
    return const Color(0xFF3B82F6);
  }
  if (entry.hasStagedChanges && entry.hasPendingChanges) {
    return const Color(0xFFB26BFF);
  }
  if (entry.hasStagedChanges) {
    return const Color(0xFF1F9D74);
  }
  return const Color(0xFFF26B5E);
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.warning_amber_rounded, color: Color(0xFFF26B5E)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: SelectableText(
                  message,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _WorkingTreeDirectoryGroup {
  const _WorkingTreeDirectoryGroup({
    required this.directory,
    required this.entries,
  });

  final String directory;
  final List<WorkingTreeEntry> entries;
}
