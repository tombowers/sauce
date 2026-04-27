import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/models/commit_entry.dart';
import '../../../core/models/repo_snapshot.dart';
import '../../../core/services/local_state_store.dart';
import '../../../shared/widgets/surface_card.dart';
import '../application/workbench_controller.dart';

const _monoFontFamily = 'Consolas';
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
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: _CommitTimelineCard(
                                      commits: snapshot?.commits ?? const [],
                                      hasRepository: _controller.hasRepository,
                                      selectedIndex:
                                          _controller.selectedCommitIndex,
                                      onSelectCommit: _controller.selectCommit,
                                      isLoading: _controller.isLoading,
                                      showRemoteBranches:
                                          _controller.showRemoteBranches,
                                      onToggleRemoteBranches:
                                          _controller.setShowRemoteBranches,
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 18,
                                    ),
                                    child: SizedBox(
                                      width: 300,
                                      child: _DetailsCard(
                                        commit: selectedCommit,
                                      ),
                                    ),
                                  ),
                                ],
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
          height: 500,
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
        SizedBox(height: 380, child: _DetailsCard(commit: selectedCommit)),
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
    required this.isSelected,
    required this.isOdd,
    required this.onTap,
  });

  final CommitEntry commit;
  final CommitEntry? nextCommit;
  final int totalLanes;
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
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            _ChangeSummary(commit: commit),
          ],
        ),
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

    return Text(
      '${commit.filesChanged}f  +${commit.insertions}/-${commit.deletions}',
      style: theme.textTheme.bodySmall?.copyWith(
        color: const Color(0xFF5E738C),
        fontSize: 11,
        fontFamily: _monoFontFamily,
        fontFeatures: const [FontFeature.tabularFigures()],
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
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
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

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFF26B5E)),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
