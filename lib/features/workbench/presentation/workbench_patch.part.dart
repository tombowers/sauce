part of 'workbench_screen.dart';

class _DiffInspectorCard extends StatefulWidget {
  const _DiffInspectorCard({
    required this.controller,
    this.dense = false,
    this.showTitle = true,
    this.framed = true,
  });

  final WorkbenchController controller;
  final bool dense;
  final bool showTitle;
  final bool framed;

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
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showTitle) ...[
          Text(
            'Patch',
            style: theme.textTheme.labelMedium?.copyWith(
              color: const Color(0xFF7A6954),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          SizedBox(height: widget.dense ? 8 : 10),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: entry == null
                  ? Text(
                      'Diff',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: widget.dense ? 15 : 16,
                      ),
                    )
                  : _MiddleEllipsisText(
                      text: entry.path,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF667085),
                        fontFamily: _monoFontFamily,
                        fontSize: widget.dense ? 11 : 12,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            if (entry != null)
              _PatchActionsMenu(
                entry: entry,
                controller: controller,
                compact: widget.dense,
              ),
          ],
        ),
        SizedBox(height: widget.dense ? 12 : 16),
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
    );
    if (!widget.framed) {
      return content;
    }
    return SurfaceCard(
      elevation: SurfaceCardElevation.raised,
      backgroundColor: const Color(0xFFFFFCF8),
      padding: EdgeInsets.fromLTRB(14, widget.dense ? 12 : 16, 14, 14),
      child: content,
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
        decoration: const BoxDecoration(color: Color(0xFFFFFBF5)),
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

class _MiddleEllipsisText extends StatelessWidget {
  const _MiddleEllipsisText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = style ?? DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final displayText = _truncateMiddleText(
          text,
          resolvedStyle,
          constraints.maxWidth,
          Directionality.of(context),
        );
        return Text(
          displayText,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: resolvedStyle,
        );
      },
    );
  }
}

String _truncateMiddleText(
  String text,
  TextStyle style,
  double maxWidth,
  TextDirection textDirection,
) {
  if (text.isEmpty || !maxWidth.isFinite || maxWidth <= 0) {
    return text;
  }
  final painter = TextPainter(textDirection: textDirection, maxLines: 1);
  painter.text = TextSpan(text: text, style: style);
  painter.layout();
  if (painter.width <= maxWidth) {
    return text;
  }

  const ellipsis = '…';
  var low = 1;
  var high = text.length;
  var best = ellipsis;

  while (low <= high) {
    final keep = (low + high) ~/ 2;
    final leftCount = (keep / 2).ceil();
    final rightCount = keep - leftCount;
    final candidate =
        '${text.substring(0, leftCount)}$ellipsis${text.substring(text.length - rightCount)}';
    painter.text = TextSpan(text: candidate, style: style);
    painter.layout();
    if (painter.width <= maxWidth) {
      best = candidate;
      low = keep + 1;
    } else {
      high = keep - 1;
    }
  }
  return best;
}

class _PatchActionsMenu extends StatelessWidget {
  const _PatchActionsMenu({
    required this.entry,
    required this.controller,
    required this.compact,
  });

  final WorkingTreeEntry entry;
  final WorkbenchController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_PatchAction>(
      tooltip: 'Patch actions',
      onSelected: (_PatchAction action) {
        switch (action) {
          case _PatchAction.copyPath:
            Clipboard.setData(ClipboardData(text: entry.path));
          case _PatchAction.stage:
            unawaited(controller.stageWorkingTreeEntry(entry));
          case _PatchAction.unstage:
            unawaited(controller.unstageWorkingTreeEntry(entry));
          case _PatchAction.discard:
            unawaited(controller.discardWorkingTreeEntry(entry));
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _PatchAction.copyPath,
          child: Text('Copy path'),
        ),
        if (!entry.isIgnored && (entry.isUntracked || entry.hasPendingChanges))
          const PopupMenuItem(value: _PatchAction.stage, child: Text('Stage')),
        if (entry.hasStagedChanges)
          const PopupMenuItem(
            value: _PatchAction.unstage,
            child: Text('Unstage'),
          ),
        if (!entry.isIgnored &&
            (entry.isUntracked ||
                entry.hasPendingChanges ||
                entry.hasStagedChanges))
          const PopupMenuItem(
            value: _PatchAction.discard,
            child: Text('Discard'),
          ),
      ],
      child: Container(
        width: compact ? 28 : 30,
        height: compact ? 28 : 30,
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FB),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFFE6EBF2)),
        ),
        child: Icon(
          Icons.more_horiz_rounded,
          size: compact ? 16 : 18,
          color: const Color(0xFF344054),
        ),
      ),
    );
  }
}

enum _PatchAction { copyPath, stage, unstage, discard }

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
        background: const Color(0xFFF8F5EF),
        gutter: const Color(0xFFF0EAE1),
        marker: const Color(0xFFF8F5EF),
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
      final background = isOdd ? const Color(0xFFFFFCF8) : Colors.white;
      return _PatchRowColors(
        background: background,
        gutter: const Color(0xFFF5F1EA),
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
