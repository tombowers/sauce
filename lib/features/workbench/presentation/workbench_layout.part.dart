part of 'workbench_screen.dart';

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

class _HorizontalSplitHandle extends StatelessWidget {
  const _HorizontalSplitHandle({required this.onDragPosition});

  final ValueChanged<double> onDragPosition;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) =>
            onDragPosition(details.globalPosition.dx),
        child: const SizedBox(
          width: 12,
          child: Center(
            child: SizedBox(
              width: 4,
              height: 36,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFD4DBE4),
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
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
    required this.onOpenBranchSwitcher,
    required this.onOpenChangesDock,
  });
  final RepoSnapshot? snapshot;
  final CommitEntry? selectedCommit;
  final WorkbenchController controller;
  final VoidCallback onOpenRepoLibrary;
  final VoidCallback onOpenBranchSwitcher;
  final VoidCallback onOpenChangesDock;
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _WorkbenchHeader(
          snapshot: snapshot,
          controller: controller,
          onOpenRepoLibrary: onOpenRepoLibrary,
          onOpenBranchSwitcher: onOpenBranchSwitcher,
          onOpenChangesDock: onOpenChangesDock,
        ),
        if (controller.errorMessage != null) ...[
          const SizedBox(height: 14),
          _ErrorBanner(
            message: controller.errorMessage!,
            onDismiss: controller.dismissError,
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          height: 980,
          child: _WorkbenchPanels(
            snapshot: snapshot,
            selectedCommit: selectedCommit,
            controller: controller,
            isCompact: true,
            onOpenChangesDock: onOpenChangesDock,
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
    required this.onOpenChangesDock,
    this.inspectorFraction = 0.50,
    this.onInspectorFractionChanged,
    this.isCompact = false,
  });

  final RepoSnapshot? snapshot;
  final CommitEntry? selectedCommit;
  final WorkbenchController controller;
  final VoidCallback onOpenChangesDock;
  final double inspectorFraction;
  final ValueChanged<double>? onInspectorFractionChanged;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return Column(
        children: [
          Expanded(
            child: _CommitTimelineCard(
              commits: snapshot?.commits ?? const [],
              workingTree: snapshot?.workingTree,
              hasRepository: controller.hasRepository,
              selectedIndex: controller.selectedCommitIndex,
              onSelectCommit: controller.selectCommit,
              isWorkingTreeSelected:
                  controller.selectedView == WorkbenchPrimaryView.changes,
              onSelectWorkingTree: controller.selectUncommittedChanges,
              isLoading: controller.isLoading,
              showRemoteBranches: controller.showRemoteBranches,
              onToggleRemoteBranches: controller.setShowRemoteBranches,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _WorkbenchInspector(
              controller: controller,
              selectedCommit: selectedCommit,
              onOpenChangesDock: onOpenChangesDock,
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const handleWidth = 12.0;
        const minInspectorWidth = 320.0;
        const minGraphWidth = 360.0;
        final contentWidth = constraints.maxWidth - handleWidth;
        final inspectorWidth = (contentWidth * inspectorFraction)
            .clamp(
              minInspectorWidth,
              math.max(minInspectorWidth, contentWidth - minGraphWidth),
            )
            .toDouble();
        final graphWidth = contentWidth - inspectorWidth;
        return Builder(
          builder: (rowContext) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: graphWidth,
                  child: _CommitTimelineCard(
                    commits: snapshot?.commits ?? const [],
                    workingTree: snapshot?.workingTree,
                    hasRepository: controller.hasRepository,
                    selectedIndex: controller.selectedCommitIndex,
                    onSelectCommit: controller.selectCommit,
                    isWorkingTreeSelected:
                        controller.selectedView == WorkbenchPrimaryView.changes,
                    onSelectWorkingTree: controller.selectUncommittedChanges,
                    isLoading: controller.isLoading,
                    showRemoteBranches: controller.showRemoteBranches,
                    onToggleRemoteBranches: controller.setShowRemoteBranches,
                  ),
                ),
                _HorizontalSplitHandle(
                  onDragPosition: (globalDx) {
                    final box = rowContext.findRenderObject() as RenderBox?;
                    if (box == null) {
                      return;
                    }
                    final localDx = box.globalToLocal(Offset(globalDx, 0)).dx;
                    final nextGraphWidth = (localDx - (handleWidth / 2))
                        .clamp(minGraphWidth, contentWidth - minInspectorWidth)
                        .toDouble();
                    onInspectorFractionChanged?.call(
                      (contentWidth - nextGraphWidth) / contentWidth,
                    );
                  },
                ),
                SizedBox(
                  width: inspectorWidth,
                  child: _WorkbenchInspector(
                    controller: controller,
                    selectedCommit: selectedCommit,
                    onOpenChangesDock: onOpenChangesDock,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _WorkbenchInspector extends StatelessWidget {
  const _WorkbenchInspector({
    required this.controller,
    required this.selectedCommit,
    required this.onOpenChangesDock,
  });

  final WorkbenchController controller;
  final CommitEntry? selectedCommit;
  final VoidCallback onOpenChangesDock;

  @override
  Widget build(BuildContext context) {
    if (controller.selectedView == WorkbenchPrimaryView.changes) {
      return SurfaceCard(
        elevation: SurfaceCardElevation.raised,
        backgroundColor: const Color(0xFFFBFDFF),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          children: [
            Expanded(
              flex: 4,
              child: _ChangesListCard(
                controller: controller,
                dense: true,
                showTitle: false,
                showSelectionHint: false,
                framed: false,
                forceStagingBuckets: true,
                showToolbar: false,
                trailing: _HeaderIconButton(
                  icon: Icons.open_in_full_rounded,
                  onTap: onOpenChangesDock,
                  tooltip: 'Open larger patch dock',
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFE7ECF2)),
            const SizedBox(height: 10),
            Expanded(
              flex: 5,
              child: _DiffInspectorCard(
                controller: controller,
                dense: true,
                showTitle: false,
                framed: false,
              ),
            ),
          ],
        ),
      );
    }

    return _DetailsCard(controller: controller, commit: selectedCommit);
  }
}
