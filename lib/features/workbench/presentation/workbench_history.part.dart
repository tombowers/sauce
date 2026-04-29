part of 'workbench_screen.dart';

class _CommitTimelineCard extends StatelessWidget {
  const _CommitTimelineCard({
    required this.commits,
    required this.workingTree,
    required this.hasRepository,
    required this.selectedIndex,
    required this.onSelectCommit,
    required this.isWorkingTreeSelected,
    required this.onSelectWorkingTree,
    required this.isLoading,
    required this.showRemoteBranches,
    required this.onToggleRemoteBranches,
  });

  final List<CommitEntry> commits;
  final WorkingTreeSnapshot? workingTree;
  final bool hasRepository;
  final int selectedIndex;
  final ValueChanged<int> onSelectCommit;
  final bool isWorkingTreeSelected;
  final Future<void> Function() onSelectWorkingTree;
  final bool isLoading;
  final bool showRemoteBranches;
  final ValueChanged<bool> onToggleRemoteBranches;

  static const _authorColumnWidth = 168.0;
  static const _modifiedColumnWidth = 138.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalLanes = _CommitGraphMetrics.totalLanes(commits);
    final hasWorkingTreeRow = (workingTree?.dirtyCount ?? 0) > 0;
    final hasTimelineRows = commits.isNotEmpty || hasWorkingTreeRow;

    return SurfaceCard(
      elevation: SurfaceCardElevation.raised,
      backgroundColor: const Color(0xFFFBFDFF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Commits',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF526173),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              if (isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (isLoading) const SizedBox(width: 10),
              _InlineToggle(
                label: 'Remote branches',
                value: showRemoteBranches,
                onChanged: onToggleRemoteBranches,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _CommitColumnsHeader(
            authorColumnWidth: _authorColumnWidth,
            modifiedColumnWidth: _modifiedColumnWidth,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: !hasTimelineRows
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
                      decoration: BoxDecoration(color: const Color(0xFFF5F8FC)),
                      child: ListView.builder(
                        itemCount: commits.length + (hasWorkingTreeRow ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (hasWorkingTreeRow && index == 0) {
                            final headCommitIndex = commits.indexWhere(
                              (commit) => commit.refs.any(
                                (ref) => ref.startsWith('HEAD '),
                              ),
                            );
                            final headLane = headCommitIndex == -1
                                ? 0
                                : commits[headCommitIndex].graphLane;
                            return _UncommittedChangesRow(
                              snapshot: workingTree!,
                              lane: headLane,
                              totalLanes: totalLanes,
                              isSelected: isWorkingTreeSelected,
                              isOdd: false,
                              authorColumnWidth: _authorColumnWidth,
                              modifiedColumnWidth: _modifiedColumnWidth,
                              onTap: onSelectWorkingTree,
                            );
                          }
                          final commitIndex = hasWorkingTreeRow
                              ? index - 1
                              : index;
                          final commit = commits[commitIndex];
                          final nextCommit = commitIndex + 1 < commits.length
                              ? commits[commitIndex + 1]
                              : null;
                          return _CommitRow(
                            commit: commit,
                            nextCommit: nextCommit,
                            totalLanes: totalLanes,
                            authorColumnWidth: _authorColumnWidth,
                            modifiedColumnWidth: _modifiedColumnWidth,
                            isSelected:
                                !isWorkingTreeSelected &&
                                commitIndex == selectedIndex,
                            isOdd: index.isOdd,
                            onTap: () => onSelectCommit(commitIndex),
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

class _UncommittedChangesRow extends StatelessWidget {
  const _UncommittedChangesRow({
    required this.snapshot,
    required this.lane,
    required this.totalLanes,
    required this.isSelected,
    required this.isOdd,
    required this.authorColumnWidth,
    required this.modifiedColumnWidth,
    required this.onTap,
  });

  final WorkingTreeSnapshot snapshot;
  final int lane;
  final int totalLanes;
  final bool isSelected;
  final bool isOdd;
  final double authorColumnWidth;
  final double modifiedColumnWidth;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseRowColor = isOdd
        ? const Color(0xFFFFFBF3)
        : const Color(0xFFFFFCF7);
    final highlight = isSelected ? const Color(0xFFFFF1D6) : baseRowColor;
    final summaryParts = <String>[
      if (snapshot.stagedCount > 0) '${snapshot.stagedCount} staged',
      if (snapshot.pendingCount > 0) '${snapshot.pendingCount} unstaged',
      if (snapshot.untrackedCount > 0) '${snapshot.untrackedCount} untracked',
    ];
    final fileLabel = snapshot.dirtyCount == 1
        ? '1 file'
        : '${snapshot.dirtyCount} files';

    return InkWell(
      onTap: () => unawaited(onTap()),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: highlight),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _UncommittedGraphGlyph(totalLanes: totalLanes, lane: lane),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB020).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'DIRTY',
                      style: TextStyle(
                        fontFamily: _monoFontFamily,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFB54708),
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Uncommitted changes',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 12,
                        color: const Color(0xFF7A4B00),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: authorColumnWidth,
                    child: Text(
                      summaryParts.join('  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF8A5B00),
                        fontSize: 10.5,
                        fontFamily: _monoFontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: modifiedColumnWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  fileLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8A5B00),
                    fontSize: 10.5,
                    fontFamily: _monoFontFamily,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
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
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
                          fontSize: 12,
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
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
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
        fontSize: 10.5,
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
            fontSize: 10.5,
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
        fontSize: 10.5,
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

  static const _columnWidth = 108.0;

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

class _UncommittedGraphGlyph extends StatelessWidget {
  const _UncommittedGraphGlyph({required this.totalLanes, required this.lane});

  final int totalLanes;
  final int lane;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        width: _GraphGlyph._columnWidth,
        child: CustomPaint(
          painter: _UncommittedGraphPainter(totalLanes: totalLanes, lane: lane),
        ),
      ),
    );
  }
}

class _UncommittedGraphPainter extends CustomPainter {
  const _UncommittedGraphPainter({
    required this.totalLanes,
    required this.lane,
  });

  final int totalLanes;
  final int lane;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = _GraphLayoutMetrics(
      totalLanes: totalLanes,
      leadingInset: _GraphLayoutMetrics.leadingInsetFor(size.width),
    );
    final x = layout.xForLane(lane);
    final centerY = size.height / 2;
    final bottomY = size.height + 1;
    final stroke = Paint()
      ..color = const Color(0xFFFFB020)
      ..strokeWidth = 2.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    var segmentStart = centerY + 8;
    while (segmentStart < bottomY) {
      final segmentEnd = math.min(segmentStart + 6, bottomY);
      canvas.drawLine(Offset(x, segmentStart), Offset(x, segmentEnd), stroke);
      segmentStart += 11;
    }

    final halo = Paint()
      ..color = const Color(0xFFFFB020).withValues(alpha: 0.18);
    canvas.drawCircle(Offset(x, centerY), 10, halo);
    final fill = Paint()..color = const Color(0xFFFFB020);
    canvas.drawCircle(Offset(x, centerY), 5.5, fill);
    final outline = Paint()
      ..color = const Color(0xFFFDFEFF)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(x, centerY), 5.5, outline);
  }

  @override
  bool shouldRepaint(covariant _UncommittedGraphPainter oldDelegate) {
    return oldDelegate.totalLanes != totalLanes || oldDelegate.lane != lane;
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
