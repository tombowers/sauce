part of 'workbench_screen.dart';

class _ChangesWorkspace extends StatelessWidget {
  const _ChangesWorkspace({required this.controller, required this.isCompact});

  final WorkbenchController controller;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return Column(
        children: [
          Expanded(
            flex: 5,
            child: _ChangesListCard(
              controller: controller,
              dense: true,
              showTitle: false,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: 4,
            child: _DiffInspectorCard(
              controller: controller,
              dense: true,
              showTitle: false,
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 4,
          child: _ChangesListCard(
            controller: controller,
            dense: true,
            showTitle: false,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: _DiffInspectorCard(
            controller: controller,
            dense: true,
            showTitle: false,
          ),
        ),
      ],
    );
  }
}

class _ChangesListCard extends StatelessWidget {
  const _ChangesListCard({
    required this.controller,
    this.dense = false,
    this.showTitle = true,
    this.showSelectionHint = true,
    this.framed = true,
    this.showToolbar = true,
    this.forceStagingBuckets = false,
    this.trailing,
  });

  final WorkbenchController controller;
  final bool dense;
  final bool showTitle;
  final bool showSelectionHint;
  final bool framed;
  final bool showToolbar;
  final bool forceStagingBuckets;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final entries = controller.filteredWorkingTreeEntries;
    final unstagedEntries =
        snapshot?.workingTree
            .entriesForFilter(WorkingTreeViewFilter.unstaged)
            .where((entry) => !entry.isIgnored)
            .toList() ??
        const <WorkingTreeEntry>[];
    final stagedEntries =
        snapshot?.workingTree
            .entriesForFilter(WorkingTreeViewFilter.staged)
            .where((entry) => !entry.isIgnored)
            .toList() ??
        const <WorkingTreeEntry>[];
    final showStagingBuckets =
        forceStagingBuckets ||
        controller.workingTreeFilter == WorkingTreeViewFilter.unstaged;
    final groups = _groupWorkingTreeEntries(entries);
    final selectedCount = controller.selectedWorkingTreeBatchPaths.length;
    final hasOnlyIgnoredFiles =
        snapshot != null &&
        snapshot.workingTree.dirtyCount == 0 &&
        snapshot.workingTree.ignoredCount > 0;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          Text(
            'Working set',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF526173),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          SizedBox(height: dense ? 8 : 10),
        ],
        if (showToolbar) ...[
          Row(
            children: [
              _WorkingTreeFilterMenu(
                filter: controller.workingTreeFilter,
                snapshot: snapshot,
                onChanged: controller.setWorkingTreeFilter,
                compact: dense,
              ),
              const Spacer(),
              if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
              _WorkingTreeLayoutToggle(
                value: controller.workingTreeLayout,
                onChanged: controller.setWorkingTreeLayout,
                compact: dense,
              ),
            ],
          ),
          if (showSelectionHint) ...[
            SizedBox(height: dense ? 6 : 12),
            _ChangesSelectionHint(selectedCount: selectedCount, compact: dense),
            SizedBox(height: dense ? 6 : 10),
          ] else
            SizedBox(height: dense ? 6 : 10),
        ] else if (showSelectionHint) ...[
          SizedBox(height: dense ? 6 : 10),
          _ChangesSelectionHint(selectedCount: selectedCount, compact: dense),
          SizedBox(height: dense ? 6 : 10),
        ],
        Expanded(
          child: showStagingBuckets
              ? _StagingBucketsList(
                  unstagedEntries: unstagedEntries,
                  stagedEntries: stagedEntries,
                  layout: controller.workingTreeLayout,
                  canRunActions: !controller.isRunningCommand,
                  selectedBatchPaths: controller.selectedWorkingTreeBatchPaths,
                  selectedPath: controller.selectedWorkingTreeEntry?.path,
                  controller: controller,
                  onActivate: controller.activateWorkingTreeEntry,
                  onStageAll: controller.stageAllWorkingTreeEntries,
                  onUnstageAll: controller.unstageAllWorkingTreeEntries,
                  onStageEntries: (entries) =>
                      unawaited(controller.stageWorkingTreeEntries(entries)),
                  onUnstageEntries: (entries) =>
                      unawaited(controller.unstageWorkingTreeEntries(entries)),
                  compact: dense,
                  trailing: trailing,
                )
              : entries.isEmpty
              ? _EmptyChangesState(
                  message: controller.hasRepository
                      ? _emptyChangesMessage(
                          controller.workingTreeFilter,
                          hasOnlyIgnoredFiles: hasOnlyIgnoredFiles,
                        )
                      : 'Connect a repository to inspect local changes.',
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Color(0xFFF4F7FB)),
                    child:
                        controller.workingTreeLayout == WorkingTreeLayout.tree
                        ? _WorkingTreeGroupedList(
                            groups: groups,
                            selectedBatchPaths:
                                controller.selectedWorkingTreeBatchPaths,
                            selectedScope: controller.selectedWorkingTreeScope,
                            selectedPath:
                                controller.selectedWorkingTreeEntry?.path,
                            onActivate: controller.activateWorkingTreeEntry,
                            compact: dense,
                          )
                        : _WorkingTreeFlatList(
                            entries: entries,
                            selectedBatchPaths:
                                controller.selectedWorkingTreeBatchPaths,
                            selectedScope: controller.selectedWorkingTreeScope,
                            selectedPath:
                                controller.selectedWorkingTreeEntry?.path,
                            onActivate: controller.activateWorkingTreeEntry,
                            compact: dense,
                          ),
                  ),
                ),
        ),
      ],
    );
    if (!framed) {
      return content;
    }
    return SurfaceCard(
      elevation: SurfaceCardElevation.raised,
      backgroundColor: const Color(0xFFF9FBFE),
      padding: EdgeInsets.fromLTRB(12, dense ? 10 : 18, 12, 12),
      child: content,
    );
  }
}

class _StagingBucketsList extends StatelessWidget {
  const _StagingBucketsList({
    required this.unstagedEntries,
    required this.stagedEntries,
    required this.controller,
    required this.layout,
    required this.canRunActions,
    required this.selectedBatchPaths,
    required this.selectedPath,
    required this.onActivate,
    required this.onStageAll,
    required this.onUnstageAll,
    required this.onStageEntries,
    required this.onUnstageEntries,
    required this.compact,
    this.trailing,
  });

  final List<WorkingTreeEntry> unstagedEntries;
  final List<WorkingTreeEntry> stagedEntries;
  final WorkbenchController controller;
  final WorkingTreeLayout layout;
  final bool canRunActions;
  final Set<String> selectedBatchPaths;
  final String? selectedPath;
  final _WorkingTreeEntryActivator onActivate;
  final VoidCallback onStageAll;
  final VoidCallback onUnstageAll;
  final ValueChanged<List<WorkingTreeEntry>> onStageEntries;
  final ValueChanged<List<WorkingTreeEntry>> onUnstageEntries;
  final bool compact;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFFF4F7FB)),
        child: Column(
          children: [
            Container(
              height: compact ? 30 : 34,
              padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
              color: const Color(0xFFEFF3F8),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Unstaged ${unstagedEntries.length}',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: const Color(0xFF44556B),
                                fontSize: compact ? 12 : null,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: trailing != null
                                    ? (compact ? 70 : 78)
                                    : 0,
                              ),
                              child: Text(
                                'Staged ${stagedEntries.length}',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: const Color(0xFF44556B),
                                  fontSize: compact ? 12 : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Icon(
                          Icons.sync_alt_rounded,
                          size: compact ? 14 : 16,
                          color: const Color(0xFF98A2B3),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (unstagedEntries.isNotEmpty)
                          _HeaderIconButton(
                            icon: Icons.library_add_check_rounded,
                            onTap: canRunActions ? onStageAll : null,
                            tooltip: 'Stage all files',
                          ),
                        if (stagedEntries.isNotEmpty) ...[
                          SizedBox(width: compact ? 6 : 8),
                          _HeaderIconButton(
                            icon: Icons.playlist_remove_rounded,
                            onTap: canRunActions ? onUnstageAll : null,
                            tooltip: 'Unstage all files',
                          ),
                        ],
                        if (trailing != null) ...[
                          SizedBox(width: compact ? 6 : 8),
                          trailing!,
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _WorkingTreeBucketSection(
                      entries: unstagedEntries,
                      selectionScope: WorkingTreeSelectionScope.unstaged,
                      layout: layout,
                      controller: controller,
                      selectedBatchPaths: selectedBatchPaths,
                      selectedPath: selectedPath,
                      onActivate: onActivate,
                      compact: compact,
                      onDropEntries: canRunActions
                          ? (entries) {
                              if (entries.isEmpty ||
                                  entries.any(
                                    (entry) => !entry.hasStagedChanges,
                                  )) {
                                return;
                              }
                              onUnstageEntries(entries);
                            }
                          : null,
                    ),
                  ),
                  Container(width: 1, color: const Color(0xFFE7ECF2)),
                  Expanded(
                    child: _WorkingTreeBucketSection(
                      entries: stagedEntries,
                      selectionScope: WorkingTreeSelectionScope.staged,
                      layout: layout,
                      controller: controller,
                      selectedBatchPaths: selectedBatchPaths,
                      selectedPath: selectedPath,
                      onActivate: onActivate,
                      compact: compact,
                      onDropEntries: canRunActions
                          ? (entries) {
                              if (entries.isEmpty ||
                                  entries.any(
                                    (entry) =>
                                        entry.isIgnored ||
                                        (!entry.isUntracked &&
                                            !entry.hasPendingChanges),
                                  )) {
                                return;
                              }
                              onStageEntries(entries);
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkingTreeBucketSection extends StatelessWidget {
  const _WorkingTreeBucketSection({
    required this.entries,
    required this.selectionScope,
    required this.layout,
    required this.controller,
    required this.selectedBatchPaths,
    required this.selectedPath,
    required this.onActivate,
    required this.compact,
    this.onDropEntries,
  });

  final List<WorkingTreeEntry> entries;
  final WorkingTreeSelectionScope selectionScope;
  final WorkingTreeLayout layout;
  final WorkbenchController controller;
  final Set<String> selectedBatchPaths;
  final String? selectedPath;
  final _WorkingTreeEntryActivator onActivate;
  final bool compact;
  final ValueChanged<List<WorkingTreeEntry>>? onDropEntries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget body;
    if (entries.isEmpty) {
      body = Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 8 : 12,
        ),
        child: Text(
          'No files',
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF98A2B3),
            fontSize: compact ? 11 : null,
          ),
        ),
      );
    } else if (layout == WorkingTreeLayout.tree) {
      body = ListView(
        padding: EdgeInsets.zero,
        children: [
          for (final group in _groupWorkingTreeEntries(entries))
            _DirectorySection(
              group: group,
              selectedBatchPaths: selectedBatchPaths,
              selectedScope: selectionScope,
              selectedPath: selectedPath,
              onActivate: onActivate,
              compact: compact,
            ),
        ],
      );
    } else {
      body = ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: entries.length,
        itemBuilder: (context, index) => _WorkingTreeRow(
          entry: entries[index],
          isOdd: index.isOdd,
          isSelected: controller.isWorkingTreeEntrySelected(
            entries[index],
            selectionScope,
          ),
          isBatchSelected: selectedBatchPaths.contains(entries[index].path),
          showDirectory: true,
          visiblePaths: entries.map((entry) => entry.path).toList(),
          onActivate: onActivate,
          compact: compact,
          selectedBatchPaths: selectedBatchPaths,
          visibleEntries: entries,
          selectionScope: selectionScope,
        ),
      );
    }
    if (onDropEntries == null) {
      return body;
    }
    return DragTarget<_WorkingTreeDragPayload>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) => onDropEntries!(details.data.entries),
      builder: (context, candidateData, rejectedData) {
        final isActive = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: isActive ? const Color(0x12007AFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: body,
        );
      },
    );
  }
}

class _ChangesSelectionHint extends StatelessWidget {
  const _ChangesSelectionHint({
    required this.selectedCount,
    this.compact = false,
  });

  final int selectedCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelection = selectedCount > 0;
    return Container(
      height: compact ? 24 : 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: hasSelection ? const Color(0xFFEAF3FF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            hasSelection
                ? Icons.checklist_rounded
                : Icons.keyboard_command_key_rounded,
            size: 14,
            color: hasSelection
                ? const Color(0xFF3B82F6)
                : const Color(0xFF98A2B3),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              hasSelection
                  ? '$selectedCount selected. Use the section actions to stage or unstage.'
                  : 'Click previews a file. Ctrl/Cmd-click toggles selection; Shift-click selects a range.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: hasSelection
                    ? const Color(0xFF2556B8)
                    : const Color(0xFF667085),
                fontSize: compact ? 10 : 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkingTreeFilterMenu extends StatelessWidget {
  const _WorkingTreeFilterMenu({
    required this.filter,
    required this.snapshot,
    required this.onChanged,
    this.compact = false,
  });

  final WorkingTreeViewFilter filter;
  final RepoSnapshot? snapshot;
  final ValueChanged<WorkingTreeViewFilter> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<WorkingTreeViewFilter>(
      tooltip: 'Change file state',
      initialValue: filter,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in WorkingTreeViewFilter.values)
          PopupMenuItem(
            value: option,
            child: Row(
              children: [
                Expanded(child: Text(_workingTreeFilterLabel(option))),
                Text(
                  '${snapshot?.workingTree.countForFilter(option) ?? 0}',
                  style: const TextStyle(fontFamily: _monoFontFamily),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: compact ? 34 : 38,
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FB),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _workingTreeFilterLabel(filter),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(width: 8),
            Text(
              '${snapshot?.workingTree.countForFilter(filter) ?? 0}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: const Color(0xFF667085),
                fontFamily: _monoFontFamily,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _WorkingTreeLayoutToggle extends StatelessWidget {
  const _WorkingTreeLayoutToggle({
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final WorkingTreeLayout value;
  final ValueChanged<WorkingTreeLayout> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LayoutIconButton(
            icon: Icons.view_list_rounded,
            tooltip: 'Flat list',
            selected: value == WorkingTreeLayout.flat,
            onTap: () => onChanged(WorkingTreeLayout.flat),
            compact: compact,
          ),
          _LayoutIconButton(
            icon: Icons.account_tree_outlined,
            tooltip: 'Directory tree',
            selected: value == WorkingTreeLayout.tree,
            onTap: () => onChanged(WorkingTreeLayout.tree),
            compact: compact,
          ),
        ],
      ),
    );
  }
}

class _LayoutIconButton extends StatelessWidget {
  const _LayoutIconButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: compact ? 28 : 32,
          height: compact ? 28 : 32,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x0F000000),
                      blurRadius: 5,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: compact ? 15 : 17,
            color: selected ? const Color(0xFF344054) : const Color(0xFF98A2B3),
          ),
        ),
      ),
    );
  }
}

class _WorkingTreeFlatList extends StatelessWidget {
  const _WorkingTreeFlatList({
    required this.entries,
    required this.selectedBatchPaths,
    required this.selectedScope,
    required this.selectedPath,
    required this.onActivate,
    required this.compact,
  });

  final List<WorkingTreeEntry> entries;
  final Set<String> selectedBatchPaths;
  final WorkingTreeSelectionScope? selectedScope;
  final String? selectedPath;
  final _WorkingTreeEntryActivator onActivate;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visiblePaths = entries.map((entry) => entry.path).toList();
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _WorkingTreeRow(
          entry: entry,
          isOdd: index.isOdd,
          isSelected:
              selectedPath == entry.path &&
              selectedScope == _defaultSelectionScopeForEntry(entry),
          isBatchSelected: selectedBatchPaths.contains(entry.path),
          showDirectory: true,
          visiblePaths: visiblePaths,
          onActivate: onActivate,
          compact: compact,
          selectedBatchPaths: selectedBatchPaths,
          visibleEntries: entries,
          selectionScope: _defaultSelectionScopeForEntry(entry),
        );
      },
    );
  }
}

class _WorkingTreeGroupedList extends StatelessWidget {
  const _WorkingTreeGroupedList({
    required this.groups,
    required this.selectedBatchPaths,
    required this.selectedScope,
    required this.selectedPath,
    required this.onActivate,
    required this.compact,
  });

  final List<_WorkingTreeDirectoryGroup> groups;
  final Set<String> selectedBatchPaths;
  final WorkingTreeSelectionScope? selectedScope;
  final String? selectedPath;
  final _WorkingTreeEntryActivator onActivate;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return _DirectorySection(
          group: group,
          selectedBatchPaths: selectedBatchPaths,
          selectedScope: selectedScope,
          selectedPath: selectedPath,
          onActivate: onActivate,
          compact: compact,
        );
      },
    );
  }
}

class _EmptyChangesState extends StatelessWidget {
  const _EmptyChangesState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        message,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: const Color(0xFF667085),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _DirectorySection extends StatelessWidget {
  const _DirectorySection({
    required this.group,
    required this.selectedBatchPaths,
    required this.selectedScope,
    required this.selectedPath,
    required this.onActivate,
    required this.compact,
  });

  final _WorkingTreeDirectoryGroup group;
  final Set<String> selectedBatchPaths;
  final WorkingTreeSelectionScope? selectedScope;
  final String? selectedPath;
  final _WorkingTreeEntryActivator onActivate;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visiblePaths = group.entries.map((entry) => entry.path).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            compact ? 10 : 14,
            compact ? 7 : 10,
            compact ? 10 : 14,
            compact ? 6 : 8,
          ),
          color: const Color(0xFFE7EDF5),
          child: Row(
            children: [
              const Icon(
                Icons.folder_open_rounded,
                size: 15,
                color: Color(0xFF667085),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  group.directory == '.' ? 'Repository root' : group.directory,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF526173),
                    fontFamily: _monoFontFamily,
                    fontSize: compact ? 11 : 12,
                  ),
                ),
              ),
              Text(
                '${group.entries.length}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF667085),
                  fontFamily: _monoFontFamily,
                ),
              ),
            ],
          ),
        ),
        for (var index = 0; index < group.entries.length; index++)
          _WorkingTreeRow(
            entry: group.entries[index],
            isOdd: index.isOdd,
            isSelected:
                selectedPath == group.entries[index].path &&
                selectedScope ==
                    _defaultSelectionScopeForEntry(group.entries[index]),
            isBatchSelected: selectedBatchPaths.contains(
              group.entries[index].path,
            ),
            showDirectory: false,
            visiblePaths: visiblePaths,
            onActivate: onActivate,
            compact: compact,
            selectedBatchPaths: selectedBatchPaths,
            visibleEntries: group.entries,
            selectionScope: _defaultSelectionScopeForEntry(
              group.entries[index],
            ),
          ),
      ],
    );
  }
}

class _WorkingTreeRow extends StatelessWidget {
  const _WorkingTreeRow({
    required this.entry,
    required this.isOdd,
    required this.isSelected,
    required this.isBatchSelected,
    required this.showDirectory,
    required this.visiblePaths,
    required this.onActivate,
    required this.compact,
    required this.selectedBatchPaths,
    required this.visibleEntries,
    required this.selectionScope,
  });

  final WorkingTreeEntry entry;
  final bool isOdd;
  final bool isSelected;
  final bool isBatchSelected;
  final bool showDirectory;
  final List<String> visiblePaths;
  final _WorkingTreeEntryActivator onActivate;
  final bool compact;
  final Set<String> selectedBatchPaths;
  final List<WorkingTreeEntry> visibleEntries;
  final WorkingTreeSelectionScope selectionScope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDeleted = _hasDeletedChange(entry);
    final background = isBatchSelected
        ? (isDeleted ? const Color(0xFFFFE4E0) : const Color(0xFFE2EEFF))
        : isSelected
        ? (isDeleted ? const Color(0xFFFFEFEB) : const Color(0xFFEDF4FF))
        : isDeleted
        ? (isOdd ? const Color(0xFFFFF5F3) : const Color(0xFFFFFBFA))
        : (isOdd ? const Color(0xFFF7FAFD) : Colors.white);
    final subtitle = showDirectory && entry.directory != '.'
        ? entry.directory
        : null;
    final titleColor = isDeleted
        ? const Color(0xFFB42318)
        : const Color(0xFF101828);
    final rowChild = Container(
      height: compact
          ? (subtitle == null ? 34 : 40)
          : (subtitle == null ? 42 : 50),
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
      color: background,
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 3,
            height: compact
                ? (subtitle == null ? 18 : 24)
                : (subtitle == null ? 24 : 32),
            decoration: BoxDecoration(
              color: isBatchSelected
                  ? const Color(0xFF3B82F6)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          SizedBox(width: compact ? 5 : 7),
          _FileStateGlyph(entry: entry, compact: compact),
          SizedBox(width: compact ? 7 : 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: compact ? 12 : 13,
                    color: titleColor,
                    decoration: isDeleted
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    decorationColor: const Color(0xFFB42318),
                    decorationThickness: 1.6,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDeleted
                          ? const Color(0xFFB54708)
                          : const Color(0xFF667085),
                      fontFamily: _monoFontFamily,
                      fontSize: compact ? 10 : 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    final dragEntries = isBatchSelected
        ? visibleEntries
              .where((candidate) => selectedBatchPaths.contains(candidate.path))
              .toList()
        : <WorkingTreeEntry>[entry];
    final effectiveDragEntries = dragEntries.isEmpty
        ? <WorkingTreeEntry>[entry]
        : dragEntries;
    return Draggable<_WorkingTreeDragPayload>(
      data: _WorkingTreeDragPayload(entries: effectiveDragEntries),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD8E0EA)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x180F172A),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FileStateGlyph(entry: entry, compact: true),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  effectiveDragEntries.length == 1
                      ? entry.displayName
                      : '${effectiveDragEntries.length} files',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: rowChild),
      child: InkWell(
        onTap: () => onActivate(
          path: entry.path,
          visiblePaths: visiblePaths,
          isControlPressed: _isControlPressed(),
          isShiftPressed: _isShiftPressed(),
          selectionScope: selectionScope,
        ),
        child: rowChild,
      ),
    );
  }
}

class _WorkingTreeDragPayload {
  const _WorkingTreeDragPayload({required this.entries});

  final List<WorkingTreeEntry> entries;
}

class _FileStateGlyph extends StatelessWidget {
  const _FileStateGlyph({required this.entry, required this.compact});

  final WorkingTreeEntry entry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tone = _workingTreeEntryTone(entry);
    final isDeleted = _hasDeletedChange(entry);
    final label = _fileStateGlyphLabel(entry);
    return Tooltip(
      message: _fileStateSummary(entry),
      child: Container(
        width: compact ? 22 : 26,
        height: compact ? 18 : 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDeleted
              ? const Color(0xFFFEE4E2)
              : tone.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: isDeleted ? Border.all(color: const Color(0xFFFDA29B)) : null,
        ),
        child: isDeleted
            ? const Icon(
                Icons.delete_outline_rounded,
                size: 11,
                color: Color(0xFFB42318),
              )
            : Text(
                label,
                style: TextStyle(
                  fontFamily: _monoFontFamily,
                  fontSize: compact ? 9 : 10,
                  fontWeight: FontWeight.w800,
                  color: tone,
                ),
              ),
      ),
    );
  }
}

bool _hasDeletedChange(WorkingTreeEntry entry) {
  return entry.stagedKind == GitFileStatusKind.deleted ||
      entry.pendingKind == GitFileStatusKind.deleted;
}

WorkingTreeSelectionScope _defaultSelectionScopeForEntry(
  WorkingTreeEntry entry,
) {
  if (entry.hasStagedChanges &&
      !entry.hasPendingChanges &&
      !entry.isUntracked) {
    return WorkingTreeSelectionScope.staged;
  }
  return WorkingTreeSelectionScope.unstaged;
}
