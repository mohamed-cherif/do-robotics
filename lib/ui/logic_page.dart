import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/block_models.dart';
import '../models/block_factory.dart';
import '../models/block_snippets.dart';
import '../models/actuator_config.dart';
import '../services/actuator_service.dart';
import '../logic/block_script_runner.dart';
import 'block_widgets/statement_block.dart';
import 'block_widgets/boolean_block.dart';
import 'execution_log_viewer.dart';
import '../logic/code_generator.dart';
import '../logic/script_validator.dart';
import '../services/connectivity/connectivity_manager.dart';
import '../services/script_save_service.dart';
import 'python_bus.dart';

class LogicPage extends StatefulWidget {
  const LogicPage({super.key});

  @override
  State<LogicPage> createState() => LogicPageState();

  static LogicPageState? of(BuildContext context) {
    return context.findAncestorStateOfType<LogicPageState>();
  }
}

class LogicPageState extends State<LogicPage> with SingleTickerProviderStateMixin {
  final List<BlockInstance> _script = []; // These are now ROOT blocks
  final ActuatorService _actuatorService = ActuatorService();
  final BlockScriptRunner _runner = BlockScriptRunner();
  final ScriptSaveService _saveService = ScriptSaveService();
  final Uuid _uuid = const Uuid();
  final TransformationController _transformController = TransformationController();
  final GlobalKey _canvasKey = GlobalKey();
  bool _isDraggingBlock = false; // Disables InteractiveViewer pan while dragging a canvas block

  late TabController _tabController;
  int _selectedTab = 0;
  ExecutionState _executionState = ExecutionState.idle;
  int _executingBlockIndex = -1; // Index in the linear execution list (not roots)

  StreamSubscription? _actuatorsSub;
  StreamSubscription? _runnerStateSub;
  StreamSubscription? _runnerBlockSub;

  // Undo/redo history of canvas snapshots (JSON), and the autosaved draft
  // that restores the canvas after the app is closed or killed.
  static const String _draftKey = 'blocks_draft';
  static const int _maxHistory = 50;
  final List<String> _history = [];
  int _historyIndex = -1;
  Timer? _draftTimer;
  Timer? _inputSnapshotTimer;

  List<BlockDefinition> _sensorBlocks = [];
  List<BlockDefinition> _logicBlocks = [];
  List<BlockDefinition> _mathBlocks = [];
  List<BlockDefinition> _actuatorBlocks = [];

  // Sort roots by Y position to determine execution order linearly
  /// Roots in the order they were handed to the runner (for highlighting).
  List<BlockInstance> _runningRoots = const [];

  List<BlockInstance> get sortedRoots {
    final list = List<BlockInstance>.from(_script);
    list.sort((a, b) => a.position.dy.compareTo(b.position.dy));
    return list;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      setState(() => _selectedTab = _tabController.index);
    });

    _loadBlocks();
    _actuatorsSub = _actuatorService.actuatorsStream.listen((_) => _loadBlocks());
    _restoreDraft();

    _runnerStateSub = _runner.stateStream.listen((state) {
      if (mounted) setState(() => _executionState = state);
    });

    _runnerBlockSub = _runner.executingBlockStream.listen((index) {
      if (mounted) setState(() => _executingBlockIndex = index);
    });
  }

  @override
  void dispose() {
    _inputSnapshotTimer?.cancel();
    if (_draftTimer?.isActive ?? false) {
      _draftTimer!.cancel();
      _saveDraft(_currentJson);
    }
    _actuatorsSub?.cancel();
    _runnerStateSub?.cancel();
    _runnerBlockSub?.cancel();
    _tabController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _loadBlocks() {
    setState(() {
      _sensorBlocks = BlockFactory.getSensorBlocks();
      _logicBlocks = BlockFactory.getLogicBlocks();
      _mathBlocks = BlockFactory.getMathBlocks();
      _actuatorBlocks = _actuatorService.actuators
          .expand((actuator) => [
                BlockFactory.actuatorBlock(actuator),
                // Track X points a positional servo; it would make a
                // continuous-rotation servo spin.
                if (actuator.type == ActuatorType.servo && !actuator.isContinuous)
                  BlockFactory.actuatorTrackingBlock(actuator)
              ])
          .toList();
      // Smart Follow: one standalone block per app, needs 2+ motors to operate.
      final motorCount = _actuatorService.actuators
          .where((a) => a.type == ActuatorType.motor)
          .length;
      if (motorCount >= 2) {
        _actuatorBlocks.add(BlockFactory.smartFollowBlock());
      }
    });
  }

  // ── Undo / redo / draft ─────────────────────────────────────────────────────

  String get _currentJson => BlockInstance.listToJson(_script);
  bool get _canUndo => _historyIndex > 0;
  bool get _canRedo => _historyIndex >= 0 && _historyIndex < _history.length - 1;

  /// Records the canvas if it changed since the last snapshot. Called after
  /// every gesture on the page (drags end with a pointer-up), after field
  /// edits (debounced) and after load / clear / snippet.
  void _snapshot() {
    if (!mounted || _historyIndex < 0) return;
    final json = _currentJson;
    if (_history[_historyIndex] == json) return;
    _history.removeRange(_historyIndex + 1, _history.length);
    _history.add(json);
    if (_history.length > _maxHistory) _history.removeAt(0);
    _historyIndex = _history.length - 1;
    _scheduleDraftSave();
    setState(() {}); // refresh the undo/redo buttons
  }

  void _scheduleInputSnapshot() {
    _inputSnapshotTimer?.cancel();
    _inputSnapshotTimer = Timer(const Duration(milliseconds: 700), _snapshot);
  }

  void _restoreSnapshot(String json) {
    final report = BlockInstance.loadScript(json, _loadDefinitions);
    setState(() {
      _script
        ..clear()
        ..addAll(report.blocks);
    });
    _scheduleDraftSave();
  }

  void _undo() {
    if (!_canUndo) return;
    _historyIndex--;
    _restoreSnapshot(_history[_historyIndex]);
  }

  void _redo() {
    if (!_canRedo) return;
    _historyIndex++;
    _restoreSnapshot(_history[_historyIndex]);
  }

  void _scheduleDraftSave() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 800), () => _saveDraft(_currentJson));
  }

  Future<void> _saveDraft(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftKey, json);
  }

  Future<void> _restoreDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_draftKey);
    if (!mounted) return;
    if (json != null && _script.isEmpty) {
      final report = BlockInstance.loadScript(json, _loadDefinitions);
      if (report.blocks.isNotEmpty) setState(() => _script.addAll(report.blocks));
    }
    _history
      ..clear()
      ..add(_currentJson);
    _historyIndex = 0;
    if (mounted) setState(() {});
  }

  /// Replaces the canvas and offers a one-tap undo instead of a confirmation.
  void _replaceCanvas(List<BlockInstance> blocks, String message) {
    setState(() {
      _script
        ..clear()
        ..addAll(blocks);
    });
    _snapshot();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
      action: _canUndo ? SnackBarAction(label: 'UNDO', onPressed: _undo) : null,
      // A SnackBar with an action otherwise stays until swiped away; Undo
      // is also in the header.
      persist: false,
    ));
  }

  // ── Save / Load ────────────────────────────────────────────────────────────

  /// Everything a saved script may contain, including blocks that are not
  /// in the palette right now (hidden ones, Smart Follow without 2 motors),
  /// so loading never silently drops them.
  List<BlockDefinition> get _loadDefinitions => [
        ...BlockFactory.getAllStaticBlocks(),
        BlockFactory.targetLockedBlock(),
        ..._actuatorBlocks,
      ];

  List<BlockDefinition> get _allDefinitions => [
    ..._sensorBlocks,
    ..._logicBlocks,
    ..._mathBlocks,
    ..._actuatorBlocks,
  ];

  void _showSaveDialog() {
    final nameCtrl = TextEditingController(text: 'My Script');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Script'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Follower Bot'),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              await _saveService.save(name, _script);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Saved "$name"'), duration: const Duration(seconds: 2)),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showLoadDialog() async {
    final slots = await _saveService.listSlots();
    if (!mounted) return;
    if (slots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No saved scripts yet'), duration: Duration(seconds: 2)),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Load Script'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: slots.length,
            itemBuilder: (_, i) {
              final name = slots[i];
              return ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(name),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () async {
                    await _saveService.delete(name);
                    if (ctx.mounted) Navigator.pop(ctx);
                    _showLoadDialog(); // Reopen with updated list
                  },
                ),
                onTap: () async {
                  final report = await _saveService.load(name, _loadDefinitions);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  final messenger = ScaffoldMessenger.of(context);
                  if (report == null || report.damaged) {
                    messenger.showSnackBar(const SnackBar(
                        content: Text("This script is damaged and can't be opened.")));
                    return;
                  }
                  if (report.blocks.isEmpty) {
                    messenger.showSnackBar(const SnackBar(
                        content: Text('Nothing to load: the script is empty or only uses devices '
                            'that were removed in Configure Hardware.')));
                    return;
                  }
                  _replaceCanvas(
                      report.blocks,
                      report.skipped > 0
                          ? 'Loaded "$name". ${report.skipped} block(s) were left out because '
                              'their device no longer exists in Configure Hardware.'
                          : 'Loaded "$name".');
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
  }

  // ── Block interaction ──────────────────────────────────────────────────────

  // Public methods for Block interaction
  void addRoot(BlockInstance block, Offset position) {
    setState(() {
      // Ensure it's not already in roots
      if (!_script.contains(block)) {
        block.position = position;
        _script.add(block);
      } else {
        // Just update position
        block.position = position;
      }
    });
  }

  void removeRoot(BlockInstance block) {
    setState(() {
      _script.remove(block);
    });
  }

  // ── Snippets ───────────────────────────────────────────────────────────────

  void _showSnippetsSheet() {
    final defs = _allDefinitions;
    final motors = defs.where((d) => d.id.startsWith('act_motor_')).toList();
    final motorCount = motors.length;

    final snippets = blockSnippets(defs, motors);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header row
                  Row(
                    children: [
                      const Text(
                        '\u{26A1} Quick Start Snippets',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, size: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Snippet list
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      itemCount: snippets.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final s = snippets[i];
                        final required = s.requiredMotors;
                        final servoCount =
                            defs.where((d) => d.id.startsWith('act_servo_track_x_')).length;
                        final needsServo = servoCount < s.requiredServos;
                        final hasEnough = motorCount >= required && !needsServo;

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            children: [
                              Text(
                                s.emoji,
                                style: const TextStyle(fontSize: 28),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      s.description,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (hasEnough)
                                ElevatedButton(
                                  onPressed: () {
                                    final blocks = s.build();
                                    Navigator.pop(ctx);
                                    _replaceCanvas(blocks, 'Snippet loaded \u{2713}');
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6366F1),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  ),
                                  child: const Text('Load'),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    needsServo
                                        ? '\u{26A0} Needs a servo (not continuous)'
                                        : '\u{26A0} Needs $required motors',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF92400E),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Listener(
          // Every edit ends with a pointer-up (drag & drop, trash, taps);
          // record the result for undo/redo and the autosaved draft. Drops
          // are applied after this listener sees the event, so snapshot once
          // the current event has been fully processed.
          onPointerUp: (_) => Timer.run(_snapshot),
          child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            _buildBlockPalette(),
            Expanded(child: _buildCanvas()),
          ],
        ),
        ),
      ),
      // Keep STOP reachable while running, even if the canvas was cleared.
      floatingActionButton: _script.isNotEmpty || _executionState == ExecutionState.running
          ? _buildPlayButton()
          : null,
    );
  }

  Widget _buildHeader() {
    final isRunning = _executionState == ExecutionState.running;
    final blockCount = _script.length;
    final narrow = MediaQuery.sizeOf(context).width < 420;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Gradient icon (hidden on narrow phones to leave room for the title)
          if (!narrow) Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.extension, color: Colors.white, size: 20),
          ),
          if (!narrow) const SizedBox(width: 12),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Block Editor',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 2),
                if (isRunning)
                  const Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: Color(0xFF10B981)),
                      SizedBox(width: 5),
                      Text(
                        'Running',
                        style: TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.w500),
                      ),
                    ],
                  )
                else
                  Text(
                    '$blockCount block${blockCount == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                  ),
              ],
            ),
          ),
          // Snippets
          if (narrow)
            IconButton(
              onPressed: _showSnippetsSheet,
              icon: const Icon(Icons.bolt, color: Color(0xFF6366F1)),
              tooltip: 'Snippets',
            )
          else
          ActionChip(
            avatar: const Icon(Icons.bolt, size: 16, color: Color(0xFF6366F1)),
            label: const Text('Snippets'),
            labelStyle: const TextStyle(
              color: Color(0xFF6366F1),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
            side: BorderSide.none,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            onPressed: _showSnippetsSheet,
          ),
          const SizedBox(width: 2),
          IconButton(
            onPressed: _canUndo ? _undo : null,
            icon: const Icon(Icons.undo, size: 20),
            tooltip: 'Undo',
          ),
          IconButton(
            onPressed: _canRedo ? _redo : null,
            icon: const Icon(Icons.redo, size: 20),
            tooltip: 'Redo',
          ),
          // Popup menu for secondary actions
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            tooltip: 'More options',
            onSelected: (value) {
              switch (value) {
                case 'clear':
                  _replaceCanvas([], 'Canvas cleared');
                  break;
                case 'save':
                  _showSaveDialog();
                  break;
                case 'load':
                  _showLoadDialog();
                  break;
                case 'reset_view':
                  _transformController.value = Matrix4.identity();
                  break;
                case 'logs':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (c) => const ExecutionLogViewer()),
                  );
                  break;
                case 'code':
                  final code = CodeGenerator.generateCode(sortedRoots);
                  PythonBus.openInPython(code);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'save',
                child: ListTile(
                  leading: Icon(Icons.save_outlined),
                  title: Text('Save Script'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'load',
                child: ListTile(
                  leading: Icon(Icons.folder_open_outlined),
                  title: Text('Load Script'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Clear All'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'reset_view',
                child: ListTile(
                  leading: Icon(Icons.center_focus_strong),
                  title: Text('Reset View'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'logs',
                child: ListTile(
                  leading: Icon(Icons.bug_report),
                  title: Text('View Logs'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'code',
                child: ListTile(
                  leading: Icon(Icons.code),
                  title: Text('Convert to Python'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFF6366F1),
        unselectedLabelColor: Colors.grey,
        indicatorColor: const Color(0xFF6366F1),
        tabs: const [
          Tab(text: "Sensors"),
          Tab(text: "Logic"),
          Tab(text: "Math"),
          Tab(text: "Actuators"),
        ],
      ),
    );
  }

  Widget _buildBlockPalette() {
    List<BlockDefinition> blocks;
    switch (_selectedTab) {
      case 0:
        blocks = _sensorBlocks;
        break;
      case 1:
        blocks = _logicBlocks;
        break;
      case 2:
        blocks = _mathBlocks;
        break;
      case 3:
        blocks = _actuatorBlocks;
        break;
      default:
        blocks = [];
    }

    if (blocks.isEmpty && _selectedTab == 3) {
      return Container(
        height: 100,
        color: Colors.white,
        child: const Center(child: Text("No actuators configured")),
      );
    }

    return Container(
      height: 130,
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: blocks.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: _buildDraggablePaletteItem(blocks[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDraggablePaletteItem(BlockDefinition definition) {
    final instance = BlockInstance(
      instanceId: _uuid.v4(),
      definition: definition,
    );

    Widget feedbackWidget = definition.shape == BlockShape.boolean
        ? BooleanBlockWidget(block: instance, isPreview: false)
        : StatementBlockWidget(block: instance, isPreview: false);

    // Provide a preview look for palette
    Widget paletteWidget = definition.shape == BlockShape.boolean
        ? BooleanBlockWidget(block: instance, isPreview: true)
        : StatementBlockWidget(block: instance, isPreview: true);

    return Draggable<BlockInstance>(
      data: instance,
      // Blocks are dragged down onto the canvas; horizontal swipes scroll
      // the palette instead of picking up a block.
      affinity: Axis.vertical,
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(scale: 1.1, child: feedbackWidget),
      ),
      child: paletteWidget,
    );
  }

  Widget _buildCanvas() {
    return Stack(
      children: [
        // Canvas Layer
        Positioned.fill(
          child: Container(
            color: const Color(0xFFF5F7FA),
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: 0.1,
              maxScale: 2.0,
              boundaryMargin: const EdgeInsets.all(5000),
              constrained: false,
              panEnabled: !_isDraggingBlock,
              scaleEnabled: !_isDraggingBlock,
              child: _buildCanvasContent(),
            ),
          ),
        ),

        // UI Overlay Layer (Trash Can)
        Positioned(
          bottom: 32,
          left: 32,
          child: DragTarget<BlockInstance>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (details) {
              // Delete block — remove from roots if present.
              // For nested blocks, onDragCompleted fires onDetach which
              // removes from parent. The trash just needs to not re-add it.
              setState(() {
                _script.remove(details.data);
              });

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Block deleted"), duration: Duration(milliseconds: 500)),
              );
            },
            builder: (context, candidates, rejected) {
              final isHovered = candidates.isNotEmpty;
              return Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: isHovered ? Colors.redAccent : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                     BoxShadow(
                       color: Colors.black.withValues(alpha: 0.2),
                       blurRadius: 10,
                       spreadRadius: 2,
                     )
                  ],
                ),
                child: Icon(
                  Icons.delete_outline,
                  color: isHovered ? Colors.white : Colors.red,
                  size: 32,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCanvasContent() {
    return DragTarget<BlockInstance>(
       onWillAcceptWithDetails: (details) {
         // Reject drop if it lands inside the trash zone (bottom-left 80x80 px, screen coords)
         final screenSize = MediaQuery.of(context).size;
         final dy = details.offset.dy;
         final dx = details.offset.dx;
         final inTrash = dx < 96 && dy > screenSize.height - 96;
         return !inTrash;
       },
       onAcceptWithDetails: (details) {
         // Use the canvas container's own RenderBox so the InteractiveViewer
         // transform is correctly accounted for in globalToLocal.
         final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
         if (box == null) return;
         final localOffset = box.globalToLocal(details.offset);
         addRoot(details.data, localOffset);
       },
       builder: (_, candidates, rejected) {
         return Container(
           key: _canvasKey,
           width: 3000,
           height: 3000,
           color: const Color(0xFFF5F7FA),
           child: Stack(
             clipBehavior: Clip.none, // Prevent nested block content from being clipped
             children: [
               // Empty-state hint
               if (_script.isEmpty)
                 const Positioned(
                   left: 0, right: 0, top: 0, bottom: 0,
                   child: Center(
                     child: Column(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         Icon(Icons.extension_outlined, size: 64, color: Color(0xFFD1D5DB)),
                         SizedBox(height: 12),
                         Text("Drag blocks here to build your program",
                             style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 16, fontWeight: FontWeight.w500)),
                         SizedBox(height: 6),
                         Text("or tap \u{26A1} Snippets to load a ready program",
                             style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 13)),
                       ],
                     ),
                   ),
                 ),

               // Render all root blocks — drag is handled by the block widgets
               // themselves via onBlockDragStarted/onBlockDragEnd callbacks.
               for (final block in _script)
                 Positioned(
                   left: block.position.dx,
                   top: block.position.dy,
                   child: _buildBlockWidget(block),
                 ),
             ],
           ),
         );
       },
    );
  }

  Widget _buildBlockWidget(BlockInstance block, {bool isPreview = false}) {
     if (block.definition.shape == BlockShape.boolean) {
       return BooleanBlockWidget(
         block: block,
         isPreview: isPreview,
         onBlockDragStarted: isPreview ? null : () => setState(() => _isDraggingBlock = true),
         onBlockDragEnd: isPreview ? null : () => setState(() => _isDraggingBlock = false),
         // The edited block has already stored its own value; this callback
         // is also called for nested/chained blocks, so it must not write into
         // the root block (that overwrote e.g. the first Wait of a chain).
         onInputChanged: (fieldId, value) {
           setState(() {});
           _scheduleInputSnapshot();
         },
       );
     }
     return StatementBlockWidget(
       block: block,
       isPreview: isPreview,
       // The runner reports an index into the list it was given (roots
       // sorted top-to-bottom at RUN time), not into _script.
       isExecuting: _executingBlockIndex >= 0 &&
           _executingBlockIndex < _runningRoots.length &&
           identical(_runningRoots[_executingBlockIndex], block),
       onBlockDragStarted: isPreview ? null : () => setState(() => _isDraggingBlock = true),
       onBlockDragEnd: isPreview ? null : () => setState(() => _isDraggingBlock = false),
       onInputChanged: (fieldId, value) {
         setState(() {});
         _scheduleInputSnapshot();
       },
     );
  }

  /// Shows beginner-friendly warnings (empty conditions, removed devices,
  /// robot not connected...) before running; the user can run anyway.
  Future<void> _checkAndRun() async {
    final roots = sortedRoots;
    final issues = ScriptValidator.validate(
      roots,
      actuators: _actuatorService.actuators,
      robotConnected: ConnectivityManager().isConnected,
    );
    if (issues.isNotEmpty) {
      final run = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Before you run…'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final issue in issues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          issue.level == IssueLevel.problem ? Icons.error_outline : Icons.info_outline,
                          size: 20,
                          color: issue.level == IssueLevel.problem ? Colors.red : Colors.blueGrey,
                          semanticLabel: issue.level == IssueLevel.problem ? 'Problem' : 'Hint',
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(issue.message)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Fix it')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Run anyway')),
          ],
        ),
      );
      if (run != true || !mounted) return;
    }
    // Flatten the script from roots (sorted by Y)
    _runningRoots = roots;
    _runner.loadScript(_runningRoots);
    _runner.play();
  }

  Widget _buildPlayButton() {
    final isRunning = _executionState == ExecutionState.running;

    return FloatingActionButton.extended(
      onPressed: () {
        if (isRunning) {
          _runner.stop();
        } else {
          _checkAndRun();
        }
      },
      backgroundColor: isRunning ? Colors.red : const Color(0xFF10B981),
      icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
      label: Text(
        isRunning ? "STOP" : "RUN",
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
