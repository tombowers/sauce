part of 'workbench_screen.dart';

class _WorkbenchHeader extends StatelessWidget {
  const _WorkbenchHeader({
    required this.snapshot,
    required this.controller,
    required this.onOpenRepoLibrary,
    required this.onOpenBranchSwitcher,
  });

  final RepoSnapshot? snapshot;
  final WorkbenchController controller;
  final VoidCallback onOpenRepoLibrary;
  final VoidCallback onOpenBranchSwitcher;

  @override
  Widget build(BuildContext context) {
    final isBusy = controller.isLoading || controller.isRunningCommand;
    final aheadBy = snapshot?.aheadBy ?? 0;
    final behindBy = snapshot?.behindBy ?? 0;
    final totalChanges = snapshot?.workingTree.dirtyCount ?? 0;

    return SurfaceCard(
      backgroundColor: const Color(0xFFFBFDFF),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _RepoSelectorButton(
                    snapshot: snapshot,
                    onTap: onOpenRepoLibrary,
                  ),
                ),
                const SizedBox(width: 12),
                _GitToolbar(controller: controller),
              ],
            ),
          ),
          const SizedBox(width: 20),
          if (isBusy) ...[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 14),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (snapshot != null) ...[
                _StatusPill(
                  label: snapshot!.branch,
                  icon: Icons.call_split_rounded,
                  tone: const Color(0xFFF26B5E),
                  onTap: onOpenBranchSwitcher,
                ),
                _StatusPill(
                  label: totalChanges == 0 ? 'clean' : '$totalChanges changes',
                  icon: totalChanges == 0
                      ? Icons.check_circle_outline_rounded
                      : Icons.edit_note_rounded,
                  tone: totalChanges == 0
                      ? const Color(0xFF1F9D74)
                      : const Color(0xFFFFB020),
                ),
                if (aheadBy > 0)
                  _StatusPill(
                    label: '+$aheadBy',
                    icon: Icons.arrow_upward_rounded,
                    tone: const Color(0xFF1F9D74),
                  ),
                if (behindBy > 0)
                  _StatusPill(
                    label: '-$behindBy',
                    icon: Icons.arrow_downward_rounded,
                    tone: const Color(0xFF3B82F6),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _GitToolbar extends StatelessWidget {
  const _GitToolbar({required this.controller});

  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) {
    final canRun =
        controller.hasRepository &&
        !controller.isLoading &&
        !controller.isRunningCommand;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ToolbarButton(
          label: 'Refresh',
          icon: Icons.refresh_rounded,
          onTap: canRun ? controller.refresh : null,
        ),
        _ToolbarButton(
          label: 'Fetch',
          icon: Icons.sync_rounded,
          onTap: canRun
              ? () => controller.runQuickCommand(const [
                  'fetch',
                  '--all',
                  '--prune',
                ])
              : null,
        ),
        _ToolbarButton(
          label: 'Pull',
          icon: Icons.south_west_rounded,
          onTap: canRun
              ? () => controller.runQuickCommand(const ['pull'])
              : null,
        ),
        _ToolbarButton(
          label: 'Push',
          icon: Icons.north_east_rounded,
          onTap: canRun
              ? () => controller.runQuickCommand(const ['push'])
              : null,
        ),
      ],
    );
  }
}

class _RepoSelectorButton extends StatelessWidget {
  const _RepoSelectorButton({required this.snapshot, required this.onTap});

  final RepoSnapshot? snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = snapshot?.name ?? 'Choose repository';
    final sublabel = snapshot == null
        ? 'No repository selected'
        : snapshot!.path;
    final branchLabel = snapshot?.branch;
    final changeCount = snapshot?.workingTree.dirtyCount ?? 0;
    final changeLabel = snapshot == null
        ? null
        : (changeCount == 0 ? 'clean' : '$changeCount changes');
    final changeTone = changeCount == 0
        ? const Color(0xFF1F9D74)
        : const Color(0xFFFFB020);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: snapshot == null
              ? const Color(0xFFF6F8FB)
              : const Color(0xFFF4F8FF),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            const Icon(Icons.folder_open_rounded, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (branchLabel != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE9F1FF),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            branchLabel,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontSize: 10,
                              color: const Color(0xFF356AD8),
                              fontFamily: _monoFontFamily,
                            ),
                          ),
                        ),
                      ],
                      if (changeLabel != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: changeTone.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            changeLabel,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontSize: 10,
                              color: changeTone,
                              fontFamily: _monoFontFamily,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    sublabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF667085),
                      fontFamily: _monoFontFamily,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.unfold_more_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _RepoLibrarySheet extends StatefulWidget {
  const _RepoLibrarySheet({
    required this.controller,
    required this.onAddRepository,
  });

  final WorkbenchController controller;
  final Future<void> Function() onAddRepository;

  @override
  State<_RepoLibrarySheet> createState() => _RepoLibrarySheetState();
}

class _RepoLibrarySheetState extends State<_RepoLibrarySheet> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FractionallySizedBox(
      heightFactor: 0.72,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SurfaceCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Repositories', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  _ToolbarButton(
                    label: 'Add',
                    icon: Icons.add_rounded,
                    onTap: widget.onAddRepository,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (widget.controller.recentRepoPaths.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'No saved repositories yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF667085),
                    ),
                  ),
                )
              else
                Expanded(
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: ListView.separated(
                      controller: _scrollController,
                      itemCount: widget.controller.recentRepoPaths.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final path = widget.controller.recentRepoPaths[index];
                        final isActive =
                            widget.controller.snapshot?.path == path;
                        return _RepoLibraryItem(
                          path: path,
                          isActive: isActive,
                          onSelect: () async {
                            Navigator.of(context).pop();
                            await widget.controller.connectToRepository(path);
                          },
                          onRemove: () =>
                              widget.controller.removeRecentRepository(path),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepoLibraryItem extends StatelessWidget {
  const _RepoLibraryItem({
    required this.path,
    required this.isActive,
    required this.onSelect,
    required this.onRemove,
  });

  final String path;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = path.replaceAll('\\', '/');
    final name = normalized.split('/').last;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onSelect,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFF0F6FF) : const Color(0xFFF6F8FB),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF667085),
                      fontFamily: _monoFontFamily,
                    ),
                  ),
                ],
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.check_rounded,
                size: 18,
                color: Color(0xFF3B82F6),
              ),
            ],
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: 'Remove from saved repositories',
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchSwitcherSheet extends StatelessWidget {
  const _BranchSwitcherSheet({required this.controller});

  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) {
    final localBranches = controller.localBranches;
    final remoteBranches = controller.remoteBranches;
    final theme = Theme.of(context);

    return SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Branches', style: theme.textTheme.titleLarge),
              const Spacer(),
              if (controller.isRunningCommand)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Switch local branches or track a remote branch into a new local branch.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF667085),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _BranchSection(
                    title: 'Local',
                    branches: localBranches,
                    controller: controller,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _BranchSection(
                    title: 'Remote',
                    branches: remoteBranches,
                    controller: controller,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchSection extends StatelessWidget {
  const _BranchSection({
    required this.title,
    required this.branches,
    required this.controller,
  });

  final String title;
  final List<BranchEntry> branches;
  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title ${branches.length}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: const Color(0xFF526173),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: branches.isEmpty
                  ? Center(
                      child: Text(
                        'No $title branches',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF98A2B3),
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: branches.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final branch = branches[index];
                        return _BranchRow(
                          branch: branch,
                          controller: controller,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchRow extends StatelessWidget {
  const _BranchRow({required this.branch, required this.controller});

  final BranchEntry branch;
  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBusy = controller.isRunningCommand;
    final actionLabel = branch.isRemote
        ? 'Track'
        : branch.isCurrent
        ? 'Current'
        : 'Switch';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: branch.isCurrent ? const Color(0xFFF0F6FF) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: branch.isCurrent
              ? const Color(0xFFD6E5FF)
              : const Color(0xFFE6EBF2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: branch.isRemote
                  ? const Color(0xFFFFF5E8)
                  : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(
              branch.isRemote
                  ? Icons.cloud_queue_rounded
                  : Icons.call_split_rounded,
              size: 16,
              color: branch.isRemote
                  ? const Color(0xFFD97706)
                  : const Color(0xFF356AD8),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        branch.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (branch.isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE9F1FF),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'HEAD',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF356AD8),
                            fontFamily: _monoFontFamily,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  branch.upstream == null
                      ? '${branch.commitSha}  ${branch.relativeTime}'
                      : '${branch.upstream}  ${branch.commitSha}  ${branch.relativeTime}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF667085),
                    fontFamily: _monoFontFamily,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _ToolbarButton(
            label: actionLabel,
            icon: branch.isRemote
                ? Icons.south_west_rounded
                : Icons.arrow_forward_rounded,
            onTap: isBusy || branch.isCurrent
                ? null
                : () {
                    Navigator.of(context).pop();
                    unawaited(controller.switchToBranch(branch));
                  },
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({required this.label, required this.icon, this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE6EBF2)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 7),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
