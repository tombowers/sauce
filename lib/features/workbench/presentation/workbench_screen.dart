import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/commit_entry.dart';
import '../../../core/models/repo_snapshot.dart';
import '../../../core/models/working_tree_entry.dart';
import '../../../core/services/local_state_store.dart';
import '../../../shared/widgets/surface_card.dart';
import '../application/workbench_controller.dart';

const _monoFontFamily = 'Consolas';
typedef _WorkingTreeEntryActivator =
    Future<void> Function({
      required String path,
      required List<String> visiblePaths,
      required bool isControlPressed,
      required bool isShiftPressed,
    });
const _graphLaneColors = <Color>[
  Color(0xFFFF6B6B),
  Color(0xFF2EC27E),
  Color(0xFF4D96FF),
  Color(0xFFB26BFF),
  Color(0xFFFFB020),
  Color(0xFF14B8A6),
];

Color _laneColorForKey(String laneKey) {
  final hash = laneKey.codeUnits.fold<int>(0, (value, unit) => value + unit);
  return _graphLaneColors[hash % _graphLaneColors.length];
}

String _nodeLaneKeyForCommit(CommitEntry commit) {
  return commit.graphLane < commit.beforeLaneKeys.length
      ? commit.beforeLaneKeys[commit.graphLane]
      : commit.graphLane < commit.afterLaneKeys.length
      ? commit.afterLaneKeys[commit.graphLane]
      : commit.graphLaneKey;
}

Color _nodeColorForCommit(CommitEntry commit) {
  return _laneColorForKey(_nodeLaneKeyForCommit(commit));
}

bool _isControlPressed() {
  final pressed = HardwareKeyboard.instance.logicalKeysPressed;
  return pressed.contains(LogicalKeyboardKey.controlLeft) ||
      pressed.contains(LogicalKeyboardKey.controlRight) ||
      pressed.contains(LogicalKeyboardKey.metaLeft) ||
      pressed.contains(LogicalKeyboardKey.metaRight);
}

bool _isShiftPressed() {
  final pressed = HardwareKeyboard.instance.logicalKeysPressed;
  return pressed.contains(LogicalKeyboardKey.shiftLeft) ||
      pressed.contains(LogicalKeyboardKey.shiftRight);
}

class WorkbenchScreen extends StatefulWidget {
  const WorkbenchScreen({super.key});

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen> {
  static const _collapsedConsoleHeight = 50.0;
  static const _minConsoleHeight = 220.0;

  late final WorkbenchController _controller;
  late final TextEditingController _repoPathController;
  late final TextEditingController _commandController;
  late final ScrollController _consoleScrollController;
  LocalStateStore? _localStore;
  bool _isConsoleCollapsed = false;
  double _consoleHeight = 420;

  @override
  void initState() {
    super.initState();
    _controller = WorkbenchController()..addListener(_syncRepoPathField);
    _repoPathController = TextEditingController(text: _controller.repoPath);
    _commandController = TextEditingController();
    _consoleScrollController = ScrollController();
    _controller.initialize();
    unawaited(_restoreConsoleState());
  }

  @override
  void dispose() {
    _controller.removeListener(_syncRepoPathField);
    _controller.dispose();
    _repoPathController.dispose();
    _commandController.dispose();
    _consoleScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final snapshot = _controller.snapshot;
        final selectedCommit = _controller.selectedCommit;

        return Scaffold(
          body: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xFFFDFDFC)),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 1180;
                  final maxConsoleHeight = math.max(
                    260.0,
                    constraints.maxHeight * 0.72,
                  );
                  final consoleHeight = _isConsoleCollapsed
                      ? _collapsedConsoleHeight
                      : _consoleHeight.clamp(
                          _minConsoleHeight,
                          maxConsoleHeight,
                        );
                  final content = isCompact
                      ? _CompactWorkbench(
                          snapshot: snapshot,
                          selectedCommit: selectedCommit,
                          controller: _controller,
                          onOpenRepoLibrary: _openRepoLibrary,
                        )
                      : Column(
                          children: [
                            _WorkbenchHeader(
                              snapshot: snapshot,
                              controller: _controller,
                              onOpenRepoLibrary: _openRepoLibrary,
                            ),
                            if (_controller.errorMessage != null) ...[
                              const SizedBox(height: 14),
                              _ErrorBanner(
                                message: _controller.errorMessage!,
                                onDismiss: _controller.dismissError,
                              ),
                            ],
                            const SizedBox(height: 18),
                            Expanded(
                              child: _WorkbenchPanels(
                                snapshot: snapshot,
                                selectedCommit: selectedCommit,
                                controller: _controller,
                              ),
                            ),
                          ],
                        );

                  return Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          child: content,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!_isConsoleCollapsed)
                        _ConsoleResizeHandle(
                          onDragDelta: (deltaY) =>
                              _resizeConsole(deltaY, maxConsoleHeight),
                        ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        height: consoleHeight,
                        child: _ConsoleCard(
                          lines: _controller.commandLog,
                          commandController: _commandController,
                          scrollController: _consoleScrollController,
                          onSubmit: _handleCommandSubmitted,
                          isBusy: _controller.isRunningCommand,
                          isConnected: _controller.hasRepository,
                          isCollapsed: _isConsoleCollapsed,
                          onToggleCollapsed: _toggleConsoleCollapsed,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _browseForRepository() async {
    final selectedPath = await getDirectoryPath(
      initialDirectory: _repoPathController.text.trim().isEmpty
          ? null
          : _repoPathController.text.trim(),
      confirmButtonText: 'Connect Repository',
    );

    if (selectedPath == null || selectedPath.isEmpty) {
      return;
    }

    _repoPathController.text = selectedPath;
    await _controller.connectToRepository(selectedPath);
  }

  Future<void> _handleCommandSubmitted(String value) async {
    final input = value.trim();
    if (input.isEmpty) {
      return;
    }

    _commandController.clear();
    await _controller.runConsoleCommand(input);
  }

  Future<void> _openRepoLibrary() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 32,
          ),
          child: _RepoLibrarySheet(
            controller: _controller,
            onAddRepository: () async {
              Navigator.of(context).pop();
              await _browseForRepository();
            },
          ),
        );
      },
    );
  }

  void _toggleConsoleCollapsed() {
    setState(() {
      _isConsoleCollapsed = !_isConsoleCollapsed;
    });
    _persistConsoleState();
  }

  void _resizeConsole(double dragDeltaY, double maxConsoleHeight) {
    final nextHeight = (_consoleHeight - dragDeltaY).clamp(
      _minConsoleHeight,
      maxConsoleHeight,
    );
    if (nextHeight == _consoleHeight) {
      return;
    }
    setState(() {
      _consoleHeight = nextHeight;
    });
    _persistConsoleState();
  }

  Future<void> _restoreConsoleState() async {
    final store = await _store();
    final savedState = store.readWorkbenchConsoleState(
      defaultCollapsed: _isConsoleCollapsed,
      defaultHeight: _consoleHeight,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isConsoleCollapsed = savedState.isCollapsed;
      _consoleHeight = savedState.height;
    });
  }

  void _persistConsoleState() {
    unawaited(_persistConsoleStateAsync());
  }

  Future<void> _persistConsoleStateAsync() async {
    final store = await _store();
    await store.writeWorkbenchConsoleState(
      isCollapsed: _isConsoleCollapsed,
      height: _consoleHeight,
    );
  }

  Future<LocalStateStore> _store() async {
    return _localStore ??= await LocalStateStore.load();
  }

  void _syncRepoPathField() {
    if (_repoPathController.text == _controller.repoPath) {
      return;
    }
    _repoPathController.value = _repoPathController.value.copyWith(
      text: _controller.repoPath,
      selection: TextSelection.collapsed(offset: _controller.repoPath.length),
      composing: TextRange.empty,
    );
  }
}

class _ConsoleResizeHandle extends StatelessWidget {
  const _ConsoleResizeHandle({required this.onDragDelta});

  final ValueChanged<double> onDragDelta;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) => onDragDelta(details.delta.dy),
        child: SizedBox(
          height: 14,
          child: Center(
            child: Container(
              width: 52,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD4DBE4),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactWorkbench extends StatelessWidget {
  const _CompactWorkbench({
    required this.snapshot,
    required this.selectedCommit,
    required this.controller,
    required this.onOpenRepoLibrary,
  });
  final RepoSnapshot? snapshot;
  final CommitEntry? selectedCommit;
  final WorkbenchController controller;
  final VoidCallback onOpenRepoLibrary;
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _WorkbenchHeader(
          snapshot: snapshot,
          controller: controller,
          onOpenRepoLibrary: onOpenRepoLibrary,
        ),
        if (controller.errorMessage != null) ...[
          const SizedBox(height: 14),
          _ErrorBanner(
            message: controller.errorMessage!,
            onDismiss: controller.dismissError,
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: controller.selectedView == WorkbenchPrimaryView.history
              ? 900
              : 980,
          child: _WorkbenchPanels(
            snapshot: snapshot,
            selectedCommit: selectedCommit,
            controller: controller,
            isCompact: true,
          ),
        ),
      ],
    );
  }
}

class _WorkbenchPanels extends StatelessWidget {
  const _WorkbenchPanels({
    required this.snapshot,
    required this.selectedCommit,
    required this.controller,
    this.isCompact = false,
  });

  final RepoSnapshot? snapshot;
  final CommitEntry? selectedCommit;
  final WorkbenchController controller;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    if (controller.selectedView == WorkbenchPrimaryView.changes) {
      return _ChangesWorkspace(controller: controller, isCompact: isCompact);
    }

    if (isCompact) {
      return Column(
        children: [
          Expanded(
            child: _CommitTimelineCard(
              commits: snapshot?.commits ?? const [],
              hasRepository: controller.hasRepository,
              selectedIndex: controller.selectedCommitIndex,
              onSelectCommit: controller.selectCommit,
              isLoading: controller.isLoading,
              showRemoteBranches: controller.showRemoteBranches,
              onToggleRemoteBranches: controller.setShowRemoteBranches,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(height: 280, child: _DetailsCard(commit: selectedCommit)),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: _CommitTimelineCard(
            commits: snapshot?.commits ?? const [],
            hasRepository: controller.hasRepository,
            selectedIndex: controller.selectedCommitIndex,
            onSelectCommit: controller.selectCommit,
            isLoading: controller.isLoading,
            showRemoteBranches: controller.showRemoteBranches,
            onToggleRemoteBranches: controller.setShowRemoteBranches,
          ),
        ),
        const SizedBox(width: 18),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: SizedBox(
            width: 300,
            child: _DetailsCard(commit: selectedCommit),
          ),
        ),
      ],
    );
  }
}

class _WorkbenchHeader extends StatelessWidget {
  const _WorkbenchHeader({
    required this.snapshot,
    required this.controller,
    required this.onOpenRepoLibrary,
  });

  final RepoSnapshot? snapshot;
  final WorkbenchController controller;
  final VoidCallback onOpenRepoLibrary;

  @override
  Widget build(BuildContext context) {
    final isBusy = controller.isLoading || controller.isRunningCommand;
    final aheadBy = snapshot?.aheadBy ?? 0;
    final behindBy = snapshot?.behindBy ?? 0;
    final totalChanges = snapshot?.workingTree.dirtyCount ?? 0;

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
                const SizedBox(width: 14),
                _PrimaryViewSwitch(
                  value: controller.selectedView,
                  onChanged: controller.setPrimaryView,
                ),
                const SizedBox(width: 20),
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

class _PrimaryViewSwitch extends StatelessWidget {
  const _PrimaryViewSwitch({required this.value, required this.onChanged});

  final WorkbenchPrimaryView value;
  final ValueChanged<WorkbenchPrimaryView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeTabButton(
            label: 'History',
            selected: value == WorkbenchPrimaryView.history,
            onTap: () => onChanged(WorkbenchPrimaryView.history),
          ),
          _ModeTabButton(
            label: 'Changes',
            selected: value == WorkbenchPrimaryView.changes,
            onTap: () => onChanged(WorkbenchPrimaryView.changes),
          ),
        ],
      ),
    );
  }
}

class _ModeTabButton extends StatelessWidget {
  const _ModeTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x10000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected ? const Color(0xFF1F2937) : const Color(0xFF667085),
          ),
        ),
      ),
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
                            fontSize: 17,
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
                              fontSize: 11,
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
                              fontSize: 11,
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
              const SizedBox(width: 8),
              Text(label, style: theme.textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangesWorkspace extends StatelessWidget {
  const _ChangesWorkspace({required this.controller, required this.isCompact});

  final WorkbenchController controller;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return Column(
        children: [
          Expanded(flex: 5, child: _ChangesListCard(controller: controller)),
          const SizedBox(height: 18),
          Expanded(flex: 4, child: _DiffInspectorCard(controller: controller)),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 4, child: _ChangesListCard(controller: controller)),
        const SizedBox(width: 18),
        Expanded(flex: 5, child: _DiffInspectorCard(controller: controller)),
      ],
    );
  }
}

class _ChangesListCard extends StatelessWidget {
  const _ChangesListCard({required this.controller});

  final WorkbenchController controller;

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
        controller.workingTreeFilter == WorkingTreeViewFilter.unstaged;
    final groups = _groupWorkingTreeEntries(entries);
    final selectedCount = controller.selectedWorkingTreeBatchPaths.length;
    final hasOnlyIgnoredFiles =
        snapshot != null &&
        snapshot.workingTree.dirtyCount == 0 &&
        snapshot.workingTree.ignoredCount > 0;

    return SurfaceCard(
      elevation: SurfaceCardElevation.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _WorkingTreeFilterMenu(
                filter: controller.workingTreeFilter,
                snapshot: snapshot,
                onChanged: controller.setWorkingTreeFilter,
              ),
              const Spacer(),
              _WorkingTreeLayoutToggle(
                value: controller.workingTreeLayout,
                onChanged: controller.setWorkingTreeLayout,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ChangesSelectionHint(selectedCount: selectedCount),
          const SizedBox(height: 10),
          Expanded(
            child: showStagingBuckets
                ? _StagingBucketsList(
                    unstagedEntries: unstagedEntries,
                    stagedEntries: stagedEntries,
                    layout: controller.workingTreeLayout,
                    canRunActions: !controller.isRunningCommand,
                    selectedBatchPaths:
                        controller.selectedWorkingTreeBatchPaths,
                    selectedPath: controller.selectedWorkingTreeEntry?.path,
                    onActivate: controller.activateWorkingTreeEntry,
                    onStageSelected: controller.stageSelectedWorkingTreeEntries,
                    onStageAll: controller.stageAllWorkingTreeEntries,
                    onUnstageSelected:
                        controller.unstageSelectedWorkingTreeEntries,
                    onUnstageAll: controller.unstageAllWorkingTreeEntries,
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
                      decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                      child:
                          controller.workingTreeLayout == WorkingTreeLayout.tree
                          ? _WorkingTreeGroupedList(
                              groups: groups,
                              selectedBatchPaths:
                                  controller.selectedWorkingTreeBatchPaths,
                              selectedPath:
                                  controller.selectedWorkingTreeEntry?.path,
                              onActivate: controller.activateWorkingTreeEntry,
                            )
                          : _WorkingTreeFlatList(
                              entries: entries,
                              selectedBatchPaths:
                                  controller.selectedWorkingTreeBatchPaths,
                              selectedPath:
                                  controller.selectedWorkingTreeEntry?.path,
                              onActivate: controller.activateWorkingTreeEntry,
                            ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StagingBucketsList extends StatelessWidget {
  const _StagingBucketsList({
    required this.unstagedEntries,
    required this.stagedEntries,
    required this.layout,
    required this.canRunActions,
    required this.selectedBatchPaths,
    required this.selectedPath,
    required this.onActivate,
    required this.onStageSelected,
    required this.onStageAll,
    required this.onUnstageSelected,
    required this.onUnstageAll,
  });

  final List<WorkingTreeEntry> unstagedEntries;
  final List<WorkingTreeEntry> stagedEntries;
  final WorkingTreeLayout layout;
  final bool canRunActions;
  final Set<String> selectedBatchPaths;
  final String? selectedPath;
  final _WorkingTreeEntryActivator onActivate;
  final VoidCallback onStageSelected;
  final VoidCallback onStageAll;
  final VoidCallback onUnstageSelected;
  final VoidCallback onUnstageAll;

  @override
  Widget build(BuildContext context) {
    final selectedUnstagedCount = unstagedEntries
        .where((entry) => selectedBatchPaths.contains(entry.path))
        .length;
    final selectedStagedCount = stagedEntries
        .where((entry) => selectedBatchPaths.contains(entry.path))
        .length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
        child: ListView(
          children: [
            _WorkingTreeBucketSection(
              label: 'Unstaged',
              count: unstagedEntries.length,
              entries: unstagedEntries,
              layout: layout,
              selectedBatchPaths: selectedBatchPaths,
              actions: [
                if (selectedUnstagedCount > 0)
                  _BucketAction(
                    label: 'Stage selected',
                    icon: Icons.playlist_add_check_rounded,
                    tooltip: 'Stage selected files',
                    onTap: canRunActions ? onStageSelected : null,
                  ),
                if (unstagedEntries.isNotEmpty)
                  _BucketAction(
                    label: 'Stage all',
                    icon: Icons.add_circle_outline_rounded,
                    tooltip: 'Stage all files',
                    onTap: canRunActions ? onStageAll : null,
                  ),
              ],
              selectedPath: selectedPath,
              onActivate: onActivate,
            ),
            _WorkingTreeBucketSection(
              label: 'Staged',
              count: stagedEntries.length,
              entries: stagedEntries,
              layout: layout,
              selectedBatchPaths: selectedBatchPaths,
              actions: [
                if (selectedStagedCount > 0)
                  _BucketAction(
                    label: 'Unstage selected',
                    icon: Icons.playlist_remove_rounded,
                    tooltip: 'Unstage selected files',
                    onTap: canRunActions ? onUnstageSelected : null,
                  ),
                if (stagedEntries.isNotEmpty)
                  _BucketAction(
                    label: 'Unstage all',
                    icon: Icons.remove_circle_outline_rounded,
                    tooltip: 'Unstage all files',
                    onTap: canRunActions ? onUnstageAll : null,
                  ),
              ],
              selectedPath: selectedPath,
              onActivate: onActivate,
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkingTreeBucketSection extends StatelessWidget {
  const _WorkingTreeBucketSection({
    required this.label,
    required this.count,
    required this.entries,
    required this.layout,
    required this.selectedBatchPaths,
    required this.actions,
    required this.selectedPath,
    required this.onActivate,
  });

  final String label;
  final int count;
  final List<WorkingTreeEntry> entries;
  final WorkingTreeLayout layout;
  final Set<String> selectedBatchPaths;
  final List<_BucketAction> actions;
  final String? selectedPath;
  final _WorkingTreeEntryActivator onActivate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          color: const Color(0xFFF3F6FA),
          child: Row(
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF44556B),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF667085),
                  fontFamily: _monoFontFamily,
                ),
              ),
              const Spacer(),
              for (final action in actions) ...[
                _BucketActionButton(action: action),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Text(
              'No ${label.toLowerCase()} files',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF98A2B3),
              ),
            ),
          )
        else if (layout == WorkingTreeLayout.tree)
          for (final group in _groupWorkingTreeEntries(entries))
            _DirectorySection(
              group: group,
              selectedBatchPaths: selectedBatchPaths,
              selectedPath: selectedPath,
              onActivate: onActivate,
            )
        else
          for (var index = 0; index < entries.length; index++)
            _WorkingTreeRow(
              entry: entries[index],
              isOdd: index.isOdd,
              isSelected: selectedPath == entries[index].path,
              isBatchSelected: selectedBatchPaths.contains(entries[index].path),
              showDirectory: true,
              visiblePaths: entries.map((entry) => entry.path).toList(),
              onActivate: onActivate,
            ),
      ],
    );
  }
}

class _BucketAction {
  const _BucketAction({
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
}

class _BucketActionButton extends StatelessWidget {
  const _BucketActionButton({required this.action});

  final _BucketAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = action.onTap != null;
    return Tooltip(
      message: action.tooltip,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: action.onTap,
          child: Ink(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE6EBF2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(action.icon, size: 14, color: const Color(0xFF344054)),
                const SizedBox(width: 5),
                Text(
                  action.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF344054),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChangesSelectionHint extends StatelessWidget {
  const _ChangesSelectionHint({required this.selectedCount});

  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelection = selectedCount > 0;
    return Container(
      height: 28,
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
                fontSize: 11,
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
  });

  final WorkingTreeViewFilter filter;
  final RepoSnapshot? snapshot;
  final ValueChanged<WorkingTreeViewFilter> onChanged;

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
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
  });

  final WorkingTreeLayout value;
  final ValueChanged<WorkingTreeLayout> onChanged;

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
          ),
          _LayoutIconButton(
            icon: Icons.account_tree_outlined,
            tooltip: 'Directory tree',
            selected: value == WorkingTreeLayout.tree,
            onTap: () => onChanged(WorkingTreeLayout.tree),
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
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
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
            size: 17,
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
    required this.selectedPath,
    required this.onActivate,
  });

  final List<WorkingTreeEntry> entries;
  final Set<String> selectedBatchPaths;
  final String? selectedPath;
  final _WorkingTreeEntryActivator onActivate;

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
          isSelected: selectedPath == entry.path,
          isBatchSelected: selectedBatchPaths.contains(entry.path),
          showDirectory: true,
          visiblePaths: visiblePaths,
          onActivate: onActivate,
        );
      },
    );
  }
}

class _WorkingTreeGroupedList extends StatelessWidget {
  const _WorkingTreeGroupedList({
    required this.groups,
    required this.selectedBatchPaths,
    required this.selectedPath,
    required this.onActivate,
  });

  final List<_WorkingTreeDirectoryGroup> groups;
  final Set<String> selectedBatchPaths;
  final String? selectedPath;
  final _WorkingTreeEntryActivator onActivate;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return _DirectorySection(
          group: group,
          selectedBatchPaths: selectedBatchPaths,
          selectedPath: selectedPath,
          onActivate: onActivate,
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
    required this.selectedPath,
    required this.onActivate,
  });

  final _WorkingTreeDirectoryGroup group;
  final Set<String> selectedBatchPaths;
  final String? selectedPath;
  final _WorkingTreeEntryActivator onActivate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visiblePaths = group.entries.map((entry) => entry.path).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          color: const Color(0xFFF3F6FA),
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
                    fontSize: 12,
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
            isSelected: selectedPath == group.entries[index].path,
            isBatchSelected: selectedBatchPaths.contains(
              group.entries[index].path,
            ),
            showDirectory: false,
            visiblePaths: visiblePaths,
            onActivate: onActivate,
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
  });

  final WorkingTreeEntry entry;
  final bool isOdd;
  final bool isSelected;
  final bool isBatchSelected;
  final bool showDirectory;
  final List<String> visiblePaths;
  final _WorkingTreeEntryActivator onActivate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = isBatchSelected
        ? const Color(0xFFEAF3FF)
        : isSelected
        ? const Color(0xFFF0F6FF)
        : (isOdd ? const Color(0xFFF8FAFC) : Colors.white);
    final subtitle = showDirectory && entry.directory != '.'
        ? entry.directory
        : null;
    return InkWell(
      onTap: () => onActivate(
        path: entry.path,
        visiblePaths: visiblePaths,
        isControlPressed: _isControlPressed(),
        isShiftPressed: _isShiftPressed(),
      ),
      child: Container(
        height: subtitle == null ? 42 : 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        color: background,
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 3,
              height: subtitle == null ? 24 : 32,
              decoration: BoxDecoration(
                color: isBatchSelected
                    ? const Color(0xFF3B82F6)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 7),
            _FileStateGlyph(entry: entry),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontSize: 13),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF667085),
                        fontFamily: _monoFontFamily,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileStateGlyph extends StatelessWidget {
  const _FileStateGlyph({required this.entry});

  final WorkingTreeEntry entry;

  @override
  Widget build(BuildContext context) {
    final tone = _workingTreeEntryTone(entry);
    final label = entry.isIgnored
        ? 'I'
        : entry.isUntracked
        ? 'U'
        : entry.hasStagedChanges
        ? 'S'
        : _statusLabel(entry.pendingKind).toUpperCase().substring(0, 1);
    return Tooltip(
      message: _fileStateSummary(entry),
      child: Container(
        width: 26,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: _monoFontFamily,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: tone,
          ),
        ),
      ),
    );
  }
}

class _DiffInspectorCard extends StatefulWidget {
  const _DiffInspectorCard({required this.controller});

  final WorkbenchController controller;

  @override
  State<_DiffInspectorCard> createState() => _DiffInspectorCardState();
}

class _DiffInspectorCardState extends State<_DiffInspectorCard> {
  late final ScrollController _verticalScrollController;
  late final ScrollController _horizontalScrollController;

  @override
  void initState() {
    super.initState();
    _verticalScrollController = ScrollController();
    _horizontalScrollController = ScrollController();
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    final entry = controller.selectedWorkingTreeEntry;
    final ignoredOnly =
        controller.snapshot != null &&
        controller.snapshot!.workingTree.dirtyCount == 0 &&
        controller.snapshot!.workingTree.ignoredCount > 0;
    return SurfaceCard(
      elevation: SurfaceCardElevation.raised,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: entry == null
                    ? Text(
                        'Diff',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 16,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.displayName,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.path,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF667085),
                              fontFamily: _monoFontFamily,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 12),
              if (entry != null)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _DiffActionButton(
                      label: 'Copy path',
                      icon: Icons.content_copy_rounded,
                      onTap: () =>
                          Clipboard.setData(ClipboardData(text: entry.path)),
                    ),
                    if (!entry.isIgnored &&
                        (entry.isUntracked || entry.hasPendingChanges))
                      _DiffActionButton(
                        label: 'Stage',
                        icon: Icons.add_circle_outline_rounded,
                        onTap: controller.isRunningCommand
                            ? null
                            : () => controller.stageWorkingTreeEntry(entry),
                      ),
                    if (entry.hasStagedChanges)
                      _DiffActionButton(
                        label: 'Unstage',
                        icon: Icons.remove_circle_outline_rounded,
                        onTap: controller.isRunningCommand
                            ? null
                            : () => controller.unstageWorkingTreeEntry(entry),
                      ),
                    if (!entry.isIgnored &&
                        (entry.isUntracked ||
                            entry.hasPendingChanges ||
                            entry.hasStagedChanges))
                      _DiffActionButton(
                        label: 'Discard',
                        icon: Icons.restore_rounded,
                        onTap: controller.isRunningCommand
                            ? null
                            : () => controller.discardWorkingTreeEntry(entry),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: entry == null
                ? _DiffEmptyState(ignoredOnly: ignoredOnly)
                : entry.isIgnored
                ? _IgnoredFileDetails(entry: entry)
                : _PatchViewer(
                    diffText:
                        controller.activeDiff ??
                        'No diff available for this file.',
                    isLoading: controller.isLoadingDiff,
                    verticalController: _verticalScrollController,
                    horizontalController: _horizontalScrollController,
                  ),
          ),
        ],
      ),
    );
  }
}

class _PatchViewer extends StatelessWidget {
  const _PatchViewer({
    required this.diffText,
    required this.isLoading,
    required this.verticalController,
    required this.horizontalController,
  });

  final String diffText;
  final bool isLoading;
  final ScrollController verticalController;
  final ScrollController horizontalController;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final parsedDiff = _parseDiffRows(diffText);
    final rows = parsedDiff.rows;
    final rowWidth = _patchContentWidth(rows);
    final rowHeight = _patchRowHeight;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFFFBFCFE)),
        child: Scrollbar(
          controller: verticalController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: verticalController,
            child: Scrollbar(
              controller: horizontalController,
              thumbVisibility: true,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: horizontalController,
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: rowWidth,
                        height: rows.length * rowHeight,
                        child: Stack(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (
                                  var index = 0;
                                  index < rows.length;
                                  index++
                                )
                                  _PatchRowChrome(
                                    row: rows[index],
                                    isOdd: index.isOdd,
                                    width: rowWidth,
                                  ),
                              ],
                            ),
                            Positioned.fill(
                              left: _patchContentLeftInset,
                              right: 14,
                              child: SelectionArea(
                                child: _PatchSelectableContent(rows: rows),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (parsedDiff.wasTruncated)
                        _PatchTruncationNotice(width: rowWidth),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PatchTruncationNotice extends StatelessWidget {
  const _PatchTruncationNotice({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      color: const Color(0xFFFFF8E6),
      child: const Text(
        'Diff preview truncated for performance. Use the console for the full patch.',
        style: TextStyle(
          fontFamily: _monoFontFamily,
          fontSize: 12,
          color: Color(0xFF8A5B00),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

const _patchRowHeight = 25.0;
const _patchContentLeftInset = 112.0;

class _PatchRowChrome extends StatelessWidget {
  const _PatchRowChrome({
    required this.row,
    required this.isOdd,
    required this.width,
  });

  final _PatchRow row;
  final bool isOdd;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = _patchRowColors(row.kind, isOdd);
    return Container(
      width: width,
      height: _patchRowHeight,
      color: colors.background,
      padding: const EdgeInsets.only(right: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.fromLTRB(6, 5, 8, 4),
            color: colors.gutter,
            child: Text(
              row.oldLine == null ? '' : '${row.oldLine}',
              style: _patchGutterTextStyle,
            ),
          ),
          Container(
            width: 44,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.fromLTRB(6, 5, 8, 4),
            color: colors.gutter,
            child: Text(
              row.newLine == null ? '' : '${row.newLine}',
              style: _patchGutterTextStyle,
            ),
          ),
          Container(
            width: 24,
            alignment: Alignment.center,
            padding: const EdgeInsets.only(top: 5),
            color: colors.marker,
            child: Text(row.marker, style: colors.markerStyle),
          ),
        ],
      ),
    );
  }
}

class _PatchSelectableContent extends StatelessWidget {
  const _PatchSelectableContent({required this.rows});

  final List<_PatchRow> rows;

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      TextSpan(
        children: [
          for (var index = 0; index < rows.length; index++)
            TextSpan(
              text: index == rows.length - 1
                  ? rows[index].content
                  : '${rows[index].content}\n',
              style: _patchSelectableContentStyle(
                rows[index].kind,
                index.isOdd,
              ),
            ),
        ],
      ),
      maxLines: rows.length,
    );
  }
}

const _patchGutterTextStyle = TextStyle(
  fontFamily: _monoFontFamily,
  fontSize: 11,
  color: Color(0xFF8A98AA),
  height: 1.35,
);

_ParsedDiff _parseDiffRows(String diffText) {
  const maxRows = 1800;
  final rows = <_PatchRow>[];
  var oldLine = 0;
  var newLine = 0;
  var wasTruncated = false;

  for (final rawLine in diffText.replaceAll('\r\n', '\n').split('\n')) {
    if (rows.length >= maxRows) {
      wasTruncated = true;
      break;
    }

    final hunkMatch = RegExp(
      r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)$',
    ).firstMatch(rawLine);
    if (hunkMatch != null) {
      oldLine = int.parse(hunkMatch.group(1)!);
      newLine = int.parse(hunkMatch.group(2)!);
      rows.add(
        _PatchRow(kind: _PatchRowKind.hunk, marker: '@@', content: rawLine),
      );
      continue;
    }

    if (rawLine.startsWith('diff --git') ||
        rawLine.startsWith('index ') ||
        rawLine.startsWith('--- ') ||
        rawLine.startsWith('+++ ') ||
        rawLine.startsWith('new file mode') ||
        rawLine.startsWith('deleted file mode')) {
      continue;
    }

    if (rawLine.startsWith('+')) {
      rows.add(
        _PatchRow(
          kind: _PatchRowKind.addition,
          marker: '+',
          newLine: newLine++,
          content: rawLine.length > 1 ? rawLine.substring(1) : '',
        ),
      );
      continue;
    }

    if (rawLine.startsWith('-')) {
      rows.add(
        _PatchRow(
          kind: _PatchRowKind.deletion,
          marker: '-',
          oldLine: oldLine++,
          content: rawLine.length > 1 ? rawLine.substring(1) : '',
        ),
      );
      continue;
    }

    final content = rawLine.startsWith(' ') ? rawLine.substring(1) : rawLine;
    rows.add(
      _PatchRow(
        kind: _PatchRowKind.context,
        marker: '',
        oldLine: oldLine == 0 ? null : oldLine++,
        newLine: newLine == 0 ? null : newLine++,
        content: content,
      ),
    );
  }

  return _ParsedDiff(rows: rows, wasTruncated: wasTruncated);
}

double _patchContentWidth(List<_PatchRow> rows) {
  final longest = rows.fold<int>(
    0,
    (length, row) => math.max(length, row.content.length),
  );
  return (longest * 7.4 + 150).clamp(760.0, 2600.0);
}

_PatchRowColors _patchRowColors(_PatchRowKind kind, bool isOdd) {
  switch (kind) {
    case _PatchRowKind.metadata:
      return _PatchRowColors(
        background: const Color(0xFFF8FAFC),
        gutter: const Color(0xFFF1F5F9),
        marker: const Color(0xFFF8FAFC),
        markerStyle: _patchMarkerStyle(const Color(0xFF667085)),
        contentStyle: _patchContentStyle(
          color: const Color(0xFF44556B),
          fontWeight: FontWeight.w700,
        ),
      );
    case _PatchRowKind.hunk:
      return _PatchRowColors(
        background: const Color(0xFFEFF6FF),
        gutter: const Color(0xFFE5F0FF),
        marker: const Color(0xFFEFF6FF),
        markerStyle: _patchMarkerStyle(const Color(0xFF356AD8)),
        contentStyle: _patchContentStyle(
          color: const Color(0xFF2556B8),
          fontWeight: FontWeight.w700,
        ),
      );
    case _PatchRowKind.addition:
      return _PatchRowColors(
        background: const Color(0xFFF2FBF6),
        gutter: const Color(0xFFE6F7EE),
        marker: const Color(0xFFF2FBF6),
        markerStyle: _patchMarkerStyle(const Color(0xFF1F9D74)),
        contentStyle: _patchContentStyle(color: const Color(0xFF145F46)),
      );
    case _PatchRowKind.deletion:
      return _PatchRowColors(
        background: const Color(0xFFFFF5F4),
        gutter: const Color(0xFFFFE8E6),
        marker: const Color(0xFFFFF5F4),
        markerStyle: _patchMarkerStyle(const Color(0xFFD9483D)),
        contentStyle: _patchContentStyle(color: const Color(0xFF8F2F28)),
      );
    case _PatchRowKind.context:
      final background = isOdd ? const Color(0xFFFBFCFE) : Colors.white;
      return _PatchRowColors(
        background: background,
        gutter: const Color(0xFFF3F6FA),
        marker: background,
        markerStyle: _patchMarkerStyle(const Color(0xFF98A2B3)),
        contentStyle: _patchContentStyle(color: const Color(0xFF293241)),
      );
  }
}

TextStyle _patchContentStyle({
  required Color color,
  FontWeight fontWeight = FontWeight.w500,
}) {
  return TextStyle(
    fontFamily: _monoFontFamily,
    fontSize: 12,
    height: 1.35,
    color: color,
    fontWeight: fontWeight,
  );
}

TextStyle _patchSelectableContentStyle(_PatchRowKind kind, bool isOdd) {
  final baseStyle = _patchRowColors(kind, isOdd).contentStyle;
  return baseStyle.copyWith(height: _patchRowHeight / 12);
}

TextStyle _patchMarkerStyle(Color color) {
  return TextStyle(
    fontFamily: _monoFontFamily,
    fontSize: 12,
    height: 1.35,
    color: color,
    fontWeight: FontWeight.w700,
  );
}

enum _PatchRowKind { metadata, hunk, context, addition, deletion }

class _ParsedDiff {
  const _ParsedDiff({required this.rows, required this.wasTruncated});

  final List<_PatchRow> rows;
  final bool wasTruncated;
}

class _PatchRow {
  const _PatchRow({
    required this.kind,
    required this.marker,
    required this.content,
    this.oldLine,
    this.newLine,
  });

  final _PatchRowKind kind;
  final String marker;
  final String content;
  final int? oldLine;
  final int? newLine;
}

class _PatchRowColors {
  const _PatchRowColors({
    required this.background,
    required this.gutter,
    required this.marker,
    required this.markerStyle,
    required this.contentStyle,
  });

  final Color background;
  final Color gutter;
  final Color marker;
  final TextStyle markerStyle;
  final TextStyle contentStyle;
}

class _DiffEmptyState extends StatelessWidget {
  const _DiffEmptyState({required this.ignoredOnly});

  final bool ignoredOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        ignoredOnly
            ? 'No pending diff. Ignored files are excluded from the working set.'
            : 'Select a changed file to inspect its diff.',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: const Color(0xFF667085),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _IgnoredFileDetails extends StatelessWidget {
  const _IgnoredFileDetails({required this.entry});

  final WorkingTreeEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.visibility_off_outlined,
            size: 22,
            color: Color(0xFF98A2B3),
          ),
          const SizedBox(height: 12),
          Text('Ignored by Git', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            entry.path,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF667085),
              fontFamily: _monoFontFamily,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Ignored files are not staged, committed, or diffed.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF667085),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommitTimelineCard extends StatelessWidget {
  const _CommitTimelineCard({
    required this.commits,
    required this.hasRepository,
    required this.selectedIndex,
    required this.onSelectCommit,
    required this.isLoading,
    required this.showRemoteBranches,
    required this.onToggleRemoteBranches,
  });

  final List<CommitEntry> commits;
  final bool hasRepository;
  final int selectedIndex;
  final ValueChanged<int> onSelectCommit;
  final bool isLoading;
  final bool showRemoteBranches;
  final ValueChanged<bool> onToggleRemoteBranches;

  static const _authorColumnWidth = 190.0;
  static const _modifiedColumnWidth = 144.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalLanes = _CommitGraphMetrics.totalLanes(commits);

    return SurfaceCard(
      elevation: SurfaceCardElevation.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLoading)
            const Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (isLoading) const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: _InlineToggle(
              label: 'Remote branches',
              value: showRemoteBranches,
              onChanged: onToggleRemoteBranches,
            ),
          ),
          const SizedBox(height: 10),
          _CommitColumnsHeader(
            authorColumnWidth: _authorColumnWidth,
            modifiedColumnWidth: _modifiedColumnWidth,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: commits.isEmpty
                ? Center(
                    child: Text(
                      isLoading
                          ? 'Loading commit history...'
                          : hasRepository
                          ? 'This repository has no commits yet.'
                          : 'Connect a repository to see its commit graph.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF667085),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC)),
                      child: ListView.builder(
                        itemCount: commits.length,
                        itemBuilder: (context, index) {
                          final commit = commits[index];
                          final nextCommit = index + 1 < commits.length
                              ? commits[index + 1]
                              : null;
                          return _CommitRow(
                            commit: commit,
                            nextCommit: nextCommit,
                            totalLanes: totalLanes,
                            authorColumnWidth: _authorColumnWidth,
                            modifiedColumnWidth: _modifiedColumnWidth,
                            isSelected: index == selectedIndex,
                            isOdd: index.isOdd,
                            onTap: () => onSelectCommit(index),
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CommitRow extends StatelessWidget {
  const _CommitRow({
    required this.commit,
    required this.nextCommit,
    required this.totalLanes,
    required this.authorColumnWidth,
    required this.modifiedColumnWidth,
    required this.isSelected,
    required this.isOdd,
    required this.onTap,
  });

  final CommitEntry commit;
  final CommitEntry? nextCommit;
  final int totalLanes;
  final double authorColumnWidth;
  final double modifiedColumnWidth;
  final bool isSelected;
  final bool isOdd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseRowColor = isOdd ? const Color(0xFFF8FAFC) : Colors.white;
    final highlight = isSelected ? const Color(0xFFF0F6FF) : baseRowColor;
    final tagRef = commit.refs.where((ref) => ref.startsWith('tag:')).toList();
    final branchRef = commit.refs
        .where((ref) => !ref.startsWith('tag:'))
        .toList();
    final laneTone = _nodeColorForCommit(commit);

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: highlight),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GraphGlyph(
              commit: commit,
              nextCommit: nextCommit,
              totalLanes: totalLanes,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    if (branchRef.isNotEmpty) ...[
                      _InlineRefMarker(text: branchRef.first, tone: laneTone),
                      const SizedBox(width: 6),
                    ],
                    if (tagRef.isNotEmpty) ...[
                      _InlineRefMarker(text: tagRef.first, tone: laneTone),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        commit.message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 13,
                          height: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: authorColumnWidth,
                      child: _CommitAuthorCell(commit: commit),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: modifiedColumnWidth,
              child: _ChangeSummary(commit: commit),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommitColumnsHeader extends StatelessWidget {
  const _CommitColumnsHeader({
    required this.authorColumnWidth,
    required this.modifiedColumnWidth,
  });

  final double authorColumnWidth;
  final double modifiedColumnWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        children: [
          const SizedBox(width: _GraphGlyph._columnWidth + 10),
          Expanded(
            child: Text(
              'Subject',
              style: theme.textTheme.labelSmall?.copyWith(
                color: const Color(0xFF8A98AA),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: authorColumnWidth,
            child: Text(
              'Author',
              style: theme.textTheme.labelSmall?.copyWith(
                color: const Color(0xFF8A98AA),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: modifiedColumnWidth,
            child: Text(
              'Modified',
              textAlign: TextAlign.right,
              style: theme.textTheme.labelSmall?.copyWith(
                color: const Color(0xFF8A98AA),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommitAuthorCell extends StatelessWidget {
  const _CommitAuthorCell({required this.commit});

  final CommitEntry commit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '${commit.author}  ${commit.relativeTime}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: const Color(0xFF667085),
        fontSize: 11,
      ),
    );
  }
}

class _ChangeSummary extends StatelessWidget {
  const _ChangeSummary({required this.commit});

  final CommitEntry commit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileLabel = commit.filesChanged == 1
        ? '1 file'
        : '${commit.filesChanged} files';

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          fileLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF667085),
            fontSize: 11,
            fontFamily: _monoFontFamily,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 10),
        _DeltaToken(
          value: '+${commit.insertions}',
          color: commit.insertions == 0
              ? const Color(0xFF98A2B3)
              : const Color(0xFF1F9D74),
        ),
        const SizedBox(width: 6),
        _DeltaToken(
          value: '-${commit.deletions}',
          color: commit.deletions == 0
              ? const Color(0xFF98A2B3)
              : const Color(0xFFD9483D),
        ),
      ],
    );
  }
}

class _DeltaToken extends StatelessWidget {
  const _DeltaToken({required this.value, required this.color});

  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: color,
        fontSize: 11,
        fontFamily: _monoFontFamily,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _InlineRefMarker extends StatelessWidget {
  const _InlineRefMarker({required this.text, required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: _monoFontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: tone,
          height: 1.0,
        ),
      ),
    );
  }
}

class _GraphGlyph extends StatelessWidget {
  const _GraphGlyph({
    required this.commit,
    required this.nextCommit,
    required this.totalLanes,
  });

  final CommitEntry commit;
  final CommitEntry? nextCommit;
  final int totalLanes;

  static const _columnWidth = 120.0;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        width: _columnWidth,
        child: CustomPaint(
          painter: _GraphPainter(
            commit: commit,
            nextCommit: nextCommit,
            totalLanes: totalLanes,
          ),
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  const _GraphPainter({
    required this.commit,
    required this.nextCommit,
    required this.totalLanes,
  });

  final CommitEntry commit;
  final CommitEntry? nextCommit;
  final int totalLanes;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = _GraphLayoutMetrics(
      totalLanes: totalLanes,
      leadingInset: _GraphLayoutMetrics.leadingInsetFor(size.width),
    );
    const topY = -1.0;
    final centerY = size.height / 2;
    final bottomY = size.height + 1;
    const joinInset = 8.0;
    final laneShiftInset = math.min(size.height * 0.26, 16.0);
    final beforeIndexByKey = <String, int>{
      for (var i = 0; i < commit.beforeLaneKeys.length; i++)
        commit.beforeLaneKeys[i]: i,
    };
    final afterIndexByKey = <String, int>{
      for (var i = 0; i < commit.afterLaneKeys.length; i++)
        commit.afterLaneKeys[i]: i,
    };
    for (var lane = 0; lane < totalLanes; lane++) {
      final x = layout.xForLane(lane);
      final beforeKey = lane < commit.beforeLaneKeys.length
          ? commit.beforeLaneKeys[lane]
          : null;
      final afterKey = lane < commit.afterLaneKeys.length
          ? commit.afterLaneKeys[lane]
          : null;
      final laneKey = beforeKey ?? afterKey ?? 'lane-$lane';
      final color = lane == commit.graphLane
          ? _nodeColorForCommit(commit)
          : _laneColorForKey(laneKey);
      final activeStroke = Paint()
        ..color = color.withValues(alpha: 0.92)
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final beforeStroke = Paint()
        ..color = _laneColorForKey(beforeKey ?? laneKey).withValues(alpha: 0.88)
        ..strokeWidth = 2.1
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final afterStroke = Paint()
        ..color = _laneColorForKey(afterKey ?? laneKey).withValues(alpha: 0.88)
        ..strokeWidth = 2.1
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final nodeOutgoingStroke = Paint()
        ..color = color.withValues(alpha: 0.92)
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final beforeActive = lane < commit.beforeLaneCount;
      final afterActive = lane < commit.afterLaneCount;
      final isNodeLane = lane == commit.graphLane;
      final isParentLane = commit.parentLanes.contains(lane);
      final hasStraightParent = isNodeLane && isParentLane;
      final isNewAfterLane =
          afterKey != null && !commit.beforeLaneKeys.contains(afterKey);
      final afterContinues =
          afterKey != null && commit.visibleChildLaneKeys.contains(afterKey);
      final beforeMovesLane =
          beforeKey != null &&
          afterIndexByKey.containsKey(beforeKey) &&
          afterIndexByKey[beforeKey] != lane;
      final afterMovesLane =
          afterKey != null &&
          beforeIndexByKey.containsKey(afterKey) &&
          beforeIndexByKey[afterKey] != lane;
      final isPassingLaneShift =
          !isNodeLane &&
          beforeKey != null &&
          afterIndexByKey.containsKey(beforeKey) &&
          afterIndexByKey[beforeKey] != lane &&
          commit.visibleChildLaneKeys.contains(beforeKey);

      if (beforeActive) {
        if (isNodeLane) {
          if (commit.hasTopContinuation) {
            canvas.drawLine(
              Offset(x, topY),
              Offset(x, centerY - joinInset),
              activeStroke,
            );
          }
        } else if (!isPassingLaneShift) {
          canvas.drawLine(
            Offset(x, topY),
            Offset(x, beforeMovesLane ? centerY - laneShiftInset : centerY),
            beforeStroke,
          );
        }
      }

      if (afterActive &&
          afterContinues &&
          (!isNewAfterLane || isNodeLane) &&
          !isPassingLaneShift) {
        canvas.drawLine(
          Offset(
            x,
            isNodeLane
                ? centerY + joinInset
                : afterMovesLane
                ? centerY + laneShiftInset
                : centerY,
          ),
          Offset(x, bottomY),
          isNodeLane ? nodeOutgoingStroke : afterStroke,
        );
      }

      if (!isNodeLane) {
        continue;
      }

      for (
        var parentIndex = 0;
        parentIndex < commit.parentLanes.length;
        parentIndex++
      ) {
        final parentLane = commit.parentLanes[parentIndex];
        if (parentLane == lane) {
          continue;
        }
        final parentX = layout.xForLane(parentLane);
        final controlY = centerY + 14;
        final targetColor = color;
        final parentStroke = Paint()
          ..color = targetColor.withValues(alpha: 0.92)
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        final path = Path()
          ..moveTo(x, centerY + 2)
          ..cubicTo(x, controlY, parentX, controlY, parentX, bottomY);
        canvas.drawPath(path, parentStroke);
      }

      if (!afterActive && hasStraightParent) {
        canvas.drawLine(
          Offset(x, centerY + joinInset),
          Offset(x, bottomY),
          activeStroke,
        );
      }

      final halo = Paint()..color = color.withValues(alpha: 0.2);
      canvas.drawCircle(Offset(x, centerY), 10, halo);
      final fill = Paint()..color = color;
      canvas.drawCircle(Offset(x, centerY), 5.5, fill);
      final outline = Paint()
        ..color = const Color(0xFFFDFEFF)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(x, centerY), 5.5, outline);
    }

    for (final entry in beforeIndexByKey.entries) {
      final laneKey = entry.key;
      if (laneKey == commit.graphLaneKey ||
          !afterIndexByKey.containsKey(laneKey) ||
          !commit.visibleChildLaneKeys.contains(laneKey)) {
        continue;
      }

      final beforeLane = entry.value;
      final afterLane = afterIndexByKey[laneKey]!;
      if (beforeLane == afterLane) {
        continue;
      }

      final startX = layout.xForLane(beforeLane);
      final endX = layout.xForLane(afterLane);
      final targetColor = _laneColorForKey(laneKey);
      final stroke = Paint()
        ..color = targetColor.withValues(alpha: 0.88)
        ..strokeWidth = 2.1
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final startY = centerY - laneShiftInset;
      final endY = centerY + laneShiftInset;
      final controlInset = math.max(laneShiftInset * 1.02, 11.0);
      final path = Path()
        ..moveTo(startX, topY)
        ..lineTo(startX, startY)
        ..cubicTo(
          startX,
          startY + controlInset,
          endX,
          endY - controlInset,
          endX,
          endY,
        )
        ..lineTo(endX, bottomY);
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    return oldDelegate.commit != commit ||
        oldDelegate.nextCommit != nextCommit ||
        oldDelegate.totalLanes != totalLanes;
  }
}

class _GraphLayoutMetrics {
  const _GraphLayoutMetrics({
    required this.totalLanes,
    required this.leadingInset,
  });

  static const laneSpacing = 18.0;

  final int totalLanes;
  final double leadingInset;

  static double leadingInsetFor(double width) {
    return width <= 60 ? 4 : 10;
  }

  double xForLane(int lane) => leadingInset + lane * laneSpacing + 2;
}

class _CommitGraphMetrics {
  const _CommitGraphMetrics._();

  static int totalLanes(List<CommitEntry> commits) {
    var total = 1;
    for (final commit in commits) {
      final highestParentLane = commit.parentLanes.isEmpty
          ? 0
          : commit.parentLanes.reduce(math.max);
      total = math.max(
        total,
        math.max(
          commit.beforeLaneCount,
          math.max(
            commit.afterLaneCount,
            math.max(commit.graphLane + 1, highestParentLane + 1),
          ),
        ),
      );
    }
    return total;
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.commit});

  final CommitEntry? commit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: SingleChildScrollView(
        child: commit == null
            ? Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Center(
                  child: Text(
                    'Select a commit to inspect it.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF667085),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Details',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF667085),
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    commit!.message,
                    style: theme.textTheme.titleLarge?.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${commit!.sha} by ${commit!.author}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF667085),
                      fontFamily: _monoFontFamily,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Refs', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final ref in commit!.refs) _RefBadge(label: ref),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Change Summary', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 10),
                  _DetailMetric(
                    label: 'Files changed',
                    value: '${commit!.filesChanged}',
                  ),
                  _DetailMetric(
                    label: 'Insertions',
                    value: '+${commit!.insertions}',
                  ),
                  _DetailMetric(
                    label: 'Deletions',
                    value: '-${commit!.deletions}',
                  ),
                ],
              ),
      ),
    );
  }
}

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

class _DiffActionButton extends StatelessWidget {
  const _DiffActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Ink(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFFE6EBF2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: const Color(0xFF344054)),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF344054),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
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
  });

  final String label;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
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
