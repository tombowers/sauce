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

class _CommitComposer extends StatefulWidget {
  const _CommitComposer({required this.controller, this.onClose});

  final WorkbenchController controller;
  final VoidCallback? onClose;

  @override
  State<_CommitComposer> createState() => _CommitComposerState();
}

class _CommitComposerState extends State<_CommitComposer> {
  late final TextEditingController _controller;

  bool get _canSubmit => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController()..addListener(_handleChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    super.dispose();
  }

  void _handleChanged() {
    setState(() {});
  }

  Future<void> _handleCommit() async {
    if (!_canSubmit) {
      return;
    }
    final committed = await widget.controller.commitChanges(_controller.text);
    if (!mounted || !committed) {
      return;
    }
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = widget.controller.snapshot;
    final stagedCount = snapshot?.workingTree.stagedCount ?? 0;
    final canCommit =
        stagedCount > 0 &&
        !widget.controller.isRunningCommand &&
        !widget.controller.isLoading;

    return SurfaceCard(
      elevation: SurfaceCardElevation.standard,
      backgroundColor: const Color(0xFFFBFDFF),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Commit', style: theme.textTheme.titleSmall),
              const SizedBox(width: 10),
              Text(
                stagedCount == 0
                    ? 'Stage changes to enable commit'
                    : '$stagedCount staged ${stagedCount == 1 ? 'file' : 'files'} ready',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF667085),
                  fontFamily: _monoFontFamily,
                ),
              ),
              const Spacer(),
              if (widget.onClose != null)
                _HeaderIconButton(
                  icon: Icons.close_rounded,
                  onTap: widget.onClose,
                  tooltip: 'Close dock',
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 2,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: _monoFontFamily,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Write a commit message',
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF98A2B3),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE6EBF2)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE6EBF2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF7AA2FF)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _ToolbarButton(
                label: 'Commit',
                icon: Icons.task_alt_rounded,
                onTap: canCommit && _canSubmit ? _handleCommit : null,
              ),
            ],
          ),
        ],
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
    return 'Ignored';
  }
  if (entry.isUntracked) {
    return 'New file';
  }
  if (entry.hasStagedChanges && entry.hasPendingChanges) {
    if (entry.stagedKind == entry.pendingKind) {
      return 'Staged, then edited again';
    }
    return 'Staged ${_longStatusLabel(entry.stagedKind)}, then changed again in working tree';
  }
  if (entry.hasStagedChanges) {
    return 'Staged ${_longStatusLabel(entry.stagedKind)}';
  }
  if (entry.hasPendingChanges) {
    return 'Unstaged ${_longStatusLabel(entry.pendingKind)}';
  }
  return 'No changes';
}

String _fileStateGlyphLabel(WorkingTreeEntry entry) {
  if (entry.isIgnored) {
    return 'I';
  }
  if (entry.isUntracked) {
    return 'U';
  }
  if (entry.hasStagedChanges && entry.hasPendingChanges) {
    return 'S+';
  }
  if (entry.hasStagedChanges) {
    return 'S';
  }
  return _shortStatusLabel(entry.pendingKind).toUpperCase().substring(0, 1);
}

String _shortStatusLabel(GitFileStatusKind kind) {
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

String _longStatusLabel(GitFileStatusKind kind) {
  switch (kind) {
    case GitFileStatusKind.modified:
      return 'changes';
    case GitFileStatusKind.added:
      return 'new file';
    case GitFileStatusKind.deleted:
      return 'deletion';
    case GitFileStatusKind.renamed:
      return 'rename';
    case GitFileStatusKind.copied:
      return 'copy';
    case GitFileStatusKind.unmerged:
      return 'merge conflict';
    case GitFileStatusKind.untracked:
      return 'new file';
    case GitFileStatusKind.ignored:
      return 'ignored file';
    case GitFileStatusKind.unmodified:
      return 'clean file';
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
