import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/branch_entry.dart';
import '../../../core/models/commit_entry.dart';
import '../../../core/models/repo_snapshot.dart';
import '../../../core/models/working_tree_entry.dart';
import '../../../core/services/local_state_store.dart';
import '../../../shared/widgets/surface_card.dart';
import '../application/workbench_controller.dart';

part 'workbench_layout.part.dart';
part 'workbench_header.part.dart';
part 'workbench_changes.part.dart';
part 'workbench_patch.part.dart';
part 'workbench_history.part.dart';
part 'workbench_support.part.dart';

const _monoFontFamily = 'Consolas';
typedef _WorkingTreeEntryActivator =
    Future<void> Function({
      required String path,
      required List<String> visiblePaths,
      required bool isControlPressed,
      required bool isShiftPressed,
      required WorkingTreeSelectionScope selectionScope,
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

class _WorkbenchScreenState extends State<WorkbenchScreen>
    with WidgetsBindingObserver {
  static const _collapsedConsoleHeight = 50.0;
  static const _minConsoleHeight = 220.0;
  static const _foregroundRefreshDebounce = Duration(seconds: 2);
  static const _inspectorFractionKey = 'workbench.main.inspector_fraction';

  late final WorkbenchController _controller;
  late final TextEditingController _repoPathController;
  late final TextEditingController _commandController;
  late final ScrollController _consoleScrollController;
  LocalStateStore? _localStore;
  bool _isConsoleCollapsed = false;
  double _consoleHeight = 420;
  double _inspectorFraction = 0.50;
  DateTime? _lastForegroundRefreshAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = WorkbenchController()..addListener(_syncRepoPathField);
    _repoPathController = TextEditingController(text: _controller.repoPath);
    _commandController = TextEditingController();
    _consoleScrollController = ScrollController();
    _controller.initialize();
    unawaited(_restoreConsoleState());
    unawaited(_restoreWorkbenchLayoutState());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_syncRepoPathField);
    _controller.dispose();
    _repoPathController.dispose();
    _commandController.dispose();
    _consoleScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshForForegroundReturn());
    }
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.state == ViewFocusState.focused) {
      unawaited(_refreshForForegroundReturn());
    }
  }

  Future<void> _refreshForForegroundReturn() async {
    if (!_controller.hasRepository ||
        _controller.isLoading ||
        _controller.isRunningCommand) {
      return;
    }
    final now = DateTime.now();
    if (_lastForegroundRefreshAt != null &&
        now.difference(_lastForegroundRefreshAt!) <
            _foregroundRefreshDebounce) {
      return;
    }
    _lastForegroundRefreshAt = now;
    await _controller.refresh();
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
                          onOpenBranchSwitcher: _openBranchSwitcher,
                          onOpenChangesDock: _openChangesDock,
                          onConfirmPush: _handlePushRequested,
                        )
                      : Column(
                          children: [
                            _WorkbenchHeader(
                              snapshot: snapshot,
                              controller: _controller,
                              onOpenRepoLibrary: _openRepoLibrary,
                              onOpenBranchSwitcher: _openBranchSwitcher,
                              onOpenChangesDock: _openChangesDock,
                              onConfirmPush: _handlePushRequested,
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
                                onOpenChangesDock: _openChangesDock,
                                inspectorFraction: _inspectorFraction,
                                onInspectorFractionChanged:
                                    _updateInspectorFraction,
                              ),
                            ),
                          ],
                        );

                  return Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                          child: content,
                        ),
                      ),
                      const SizedBox(height: 10),
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

  Future<void> _openBranchSwitcher() async {
    if (!_controller.hasRepository) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.72,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: _BranchSwitcherSheet(controller: _controller),
          ),
        );
      },
    );
  }

  Future<void> _openChangesDock() async {
    if (!_controller.hasRepository) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(20),
              child: SizedBox(
                width: 1180,
                height: 760,
                child: SurfaceCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CommitComposer(
                        controller: _controller,
                        onClose: () => Navigator.of(context).pop(),
                        onCommitRequested:
                            ({
                              required String message,
                              required bool pushAfterCommit,
                            }) async {
                              final navigator = Navigator.of(context);
                              final committed = await _handleCommitRequested(
                                dialogContext: context,
                                message: message,
                                pushAfterCommit: pushAfterCommit,
                              );
                              if (committed && navigator.mounted) {
                                navigator.pop();
                              }
                              return committed;
                            },
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Color(0xFFE7ECF2)),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _ChangesWorkspace(
                          controller: _controller,
                          isCompact: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
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

  Future<void> _restoreWorkbenchLayoutState() async {
    final store = await _store();
    final savedFraction = store.readDouble(
      _inspectorFractionKey,
      fallback: _inspectorFraction,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _inspectorFraction = savedFraction.clamp(0.18, 0.82);
    });
  }

  void _persistConsoleState() {
    unawaited(_persistConsoleStateAsync());
  }

  void _updateInspectorFraction(double value) {
    final nextValue = value.clamp(0.18, 0.82);
    if ((nextValue - _inspectorFraction).abs() < 0.001) {
      return;
    }
    setState(() {
      _inspectorFraction = nextValue;
    });
    unawaited(_persistWorkbenchLayoutState());
  }

  Future<void> _persistConsoleStateAsync() async {
    final store = await _store();
    await store.writeWorkbenchConsoleState(
      isCollapsed: _isConsoleCollapsed,
      height: _consoleHeight,
    );
  }

  Future<void> _persistWorkbenchLayoutState() async {
    final store = await _store();
    await store.writeDouble(_inspectorFractionKey, _inspectorFraction);
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

  Future<bool> _handleCommitRequested({
    required BuildContext dialogContext,
    required String message,
    required bool pushAfterCommit,
  }) async {
    if (pushAfterCommit) {
      final confirmed = await _showPushConfirmationDialog(
        dialogContext,
        additionalCommits: 1,
      );
      if (!mounted || !confirmed) {
        return false;
      }
    }

    final committed = await _controller.commitChanges(message);
    if (!mounted) {
      return false;
    }
    if (!committed) {
      await _showActionFailureDialog(
        context,
        title: 'Commit failed',
        message: _controller.errorMessage ?? 'Unable to create the commit.',
      );
      return false;
    }
    if (!pushAfterCommit) {
      return true;
    }

    final pushed = await _controller.pushCurrentBranch();
    if (!mounted) {
      return false;
    }
    if (!pushed) {
      await _showActionFailureDialog(
        context,
        title: 'Commit created, but push failed',
        message:
            _controller.errorMessage ??
            'The commit succeeded locally, but the push did not complete.',
      );
      return true;
    }
    return true;
  }

  Future<void> _handlePushRequested() async {
    final confirmed = await _showPushConfirmationDialog(context);
    if (!mounted) {
      return;
    }
    if (!confirmed) {
      return;
    }
    final pushed = await _controller.pushCurrentBranch();
    if (!mounted) {
      return;
    }
    if (pushed) {
      return;
    }
    await _showActionFailureDialog(
      context,
      title: 'Push failed',
      message: _controller.errorMessage ?? 'Unable to push the current branch.',
    );
  }

  Future<bool> _showPushConfirmationDialog(
    BuildContext dialogContext, {
    int additionalCommits = 0,
  }) async {
    final preparation = _controller.pushPreparation;
    if (preparation == null) {
      return false;
    }
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: true,
      builder: (context) => _PushConfirmationDialog(
        preparation: preparation,
        additionalCommits: additionalCommits,
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _showActionFailureDialog(
    BuildContext dialogContext, {
    required String title,
    required String message,
  }) async {
    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
