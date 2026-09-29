import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/block_models.dart';
import '../models/block_factory.dart';
import '../models/actuator_config.dart';
import '../services/actuator_service.dart';
import '../logic/block_script_runner.dart';
import 'block_widgets/statement_block.dart';
import 'block_widgets/boolean_block.dart';
import 'execution_log_viewer.dart';
import '../logic/code_generator.dart';
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

    _runnerStateSub = _runner.stateStream.listen((state) {
      if (mounted) setState(() => _executionState = state);
    });

    _runnerBlockSub = _runner.executingBlockStream.listen((index) {
      if (mounted) setState(() => _executingBlockIndex = index);
    });
  }

  @override
  void dispose() {
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
                if (actuator.type == ActuatorType.servo)
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
                  setState(() {
                    _script.clear();
                    _script.addAll(report.blocks);
                  });
                  if (report.skipped > 0) {
                    messenger.showSnackBar(SnackBar(
                        content: Text('Loaded. ${report.skipped} block(s) were left out because '
                            'their device no longer exists in Configure Hardware.')));
                  }
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

    // Helper to create a motor block instance
    BlockInstance motorBlock(BlockDefinition def, String direction, int speed) {
      return BlockInstance(
        instanceId: _uuid.v4(),
        definition: def,
        inputValues: {'direction': direction, 'speed': speed},
      );
    }

    // Helper to find a definition by id
    BlockDefinition findDef(String id) => defs.firstWhere((d) => d.id == id);

    final snippets = <Map<String, dynamic>>[
      {
        'emoji': '\u{1F50C}', // 🔌
        'name': 'Motor Forward Test',
        'description': 'Drives both motors forward for 3 seconds then stops. Good first test.',
        'requiredMotors': 2,
        'build': () {
          final leftDef = motors[0];
          final rightDef = motors[1];
          final waitDef = findDef('logic_wait');

          final stopRight = motorBlock(rightDef, 'STOP', 0);
          final stopLeft = motorBlock(leftDef, 'STOP', 0)..nextBlock = stopRight;
          final wait = BlockInstance(
            instanceId: _uuid.v4(),
            definition: waitDef,
            inputValues: {'seconds': 3},
          )..nextBlock = stopLeft;
          final fwdRight = motorBlock(rightDef, 'FORWARD', 200)..nextBlock = wait;
          final fwdLeft = motorBlock(leftDef, 'FORWARD', 200)..nextBlock = fwdRight;
          fwdLeft.position = const Offset(100, 100);
          return [fwdLeft];
        },
      },
      {
        'emoji': '\u{21A9}\u{FE0F}', // ↩️
        'name': 'Pivot Left Test',
        'description': 'Stops left motor, runs right motor to pivot left for 2s.',
        'requiredMotors': 2,
        'build': () {
          final leftDef = motors[0];
          final rightDef = motors[1];
          final waitDef = findDef('logic_wait');

          final stopRight = motorBlock(rightDef, 'STOP', 0);
          final stopLeft = motorBlock(leftDef, 'STOP', 0)..nextBlock = stopRight;
          final wait = BlockInstance(
            instanceId: _uuid.v4(),
            definition: waitDef,
            inputValues: {'seconds': 2},
          )..nextBlock = stopLeft;
          final fwdRight = motorBlock(rightDef, 'FORWARD', 200)..nextBlock = wait;
          final stopLeftStart = motorBlock(leftDef, 'STOP', 0)..nextBlock = fwdRight;
          stopLeftStart.position = const Offset(100, 100);
          return [stopLeftStart];
        },
      },
      {
        'emoji': '\u{21AA}\u{FE0F}', // ↪️
        'name': 'Pivot Right Test',
        'description': 'Runs left motor, stops right motor to pivot right for 2s.',
        'requiredMotors': 2,
        'build': () {
          final leftDef = motors[0];
          final rightDef = motors[1];
          final waitDef = findDef('logic_wait');

          final stopRight = motorBlock(rightDef, 'STOP', 0);
          final stopLeft = motorBlock(leftDef, 'STOP', 0)..nextBlock = stopRight;
          final wait = BlockInstance(
            instanceId: _uuid.v4(),
            definition: waitDef,
            inputValues: {'seconds': 2},
          )..nextBlock = stopLeft;
          final stopRightStart = motorBlock(rightDef, 'STOP', 0)..nextBlock = wait;
          final fwdLeft = motorBlock(leftDef, 'FORWARD', 200)..nextBlock = stopRightStart;
          fwdLeft.position = const Offset(100, 100);
          return [fwdLeft];
        },
      },
      {
        'emoji': '\u{1F916}', // 🤖
        'name': 'Person Follower',
        'description': 'Complete AI person-following program. Car pivots to keep person centred in frame.',
        'requiredMotors': 2,
        'build': () {
          final leftDef = motors[0];
          final rightDef = motors[1];
          final whileDef = findDef('logic_while');
          final ifDef = findDef('logic_if');
          final ltDef = findDef('math_less_than');
          final gtDef = findDef('math_greater_than');
          final andDef = findDef('bool_and');
          final numDef = findDef('math_number');
          final waitDef = findDef('logic_wait');
          final boolTrueDef = findDef('bool_true');
          final offsetXDef = findDef('sense_offset_x');
          final targetSizeDef = findDef('sense_target_size');
          final detectedDef = findDef('sense_object_locked');

          // Helper for sense_offset_x
          BlockInstance senseOffsetX() => BlockInstance(
            instanceId: _uuid.v4(),
            definition: offsetXDef,
          );

          // Helper for math_number
          BlockInstance num(double value) => BlockInstance(
            instanceId: _uuid.v4(),
            definition: numDef,
            inputValues: {'value': value},
          );

          // Forward-first architecture: always drive toward person.
          // Corrections override one motor only when offset is clearly large (>0.30).
          // Avoids oscillation from detection jitter (±0.1–0.2 per frame).

          // Step 1: always both motors forward (baseline)
          final pfRightFwd = motorBlock(rightDef, 'FORWARD', 200);
          final pfAlwaysFwd = motorBlock(leftDef, 'FORWARD', 200)..nextBlock = pfRightFwd;

          // Step 2: if clearly right AND not too close → stop right motor (curve right)
          final pfCorrRight = BlockInstance(
            instanceId: _uuid.v4(),
            definition: ifDef,
            nestedBlocks: {
              'condition': BlockInstance(
                instanceId: _uuid.v4(),
                definition: andDef,
                nestedBlocks: {
                  'left': BlockInstance(
                    instanceId: _uuid.v4(),
                    definition: gtDef,
                    nestedBlocks: {'left': senseOffsetX(), 'right': num(0.20)},
                  ),
                  'right': BlockInstance(
                    instanceId: _uuid.v4(),
                    definition: ltDef,
                    nestedBlocks: {
                      'left': BlockInstance(instanceId: _uuid.v4(), definition: targetSizeDef),
                      'right': num(40),
                    },
                  ),
                },
              ),
              'then': motorBlock(leftDef, 'FORWARD', 200)
                ..nextBlock = motorBlock(rightDef, 'STOP', 0),
            },
          );

          // Step 3: if clearly left AND not too close → stop left motor (curve left)
          final pfCorrLeft = BlockInstance(
            instanceId: _uuid.v4(),
            definition: ifDef,
            nestedBlocks: {
              'condition': BlockInstance(
                instanceId: _uuid.v4(),
                definition: andDef,
                nestedBlocks: {
                  'left': BlockInstance(
                    instanceId: _uuid.v4(),
                    definition: ltDef,
                    nestedBlocks: {'left': senseOffsetX(), 'right': num(-0.20)},
                  ),
                  'right': BlockInstance(
                    instanceId: _uuid.v4(),
                    definition: ltDef,
                    nestedBlocks: {
                      'left': BlockInstance(instanceId: _uuid.v4(), definition: targetSizeDef),
                      'right': num(40),
                    },
                  ),
                },
              ),
              'then': motorBlock(leftDef, 'STOP', 0)
                ..nextBlock = motorBlock(rightDef, 'FORWARD', 200),
            },
          );

          // Step 4: if too close → stop both
          final pfTooClose = BlockInstance(
            instanceId: _uuid.v4(),
            definition: ifDef,
            nestedBlocks: {
              'condition': BlockInstance(
                instanceId: _uuid.v4(),
                definition: gtDef,
                nestedBlocks: {
                  'left': BlockInstance(instanceId: _uuid.v4(), definition: targetSizeDef),
                  'right': num(39),
                },
              ),
              'then': motorBlock(leftDef, 'STOP', 0)
                ..nextBlock = motorBlock(rightDef, 'STOP', 0),
            },
          );

          // Chain: forward → correct right? → correct left? → too close? → yield
          pfRightFwd.nextBlock = pfCorrRight;
          pfCorrRight.nextBlock = pfCorrLeft;
          pfCorrLeft.nextBlock = pfTooClose;
          pfTooClose.nextBlock = BlockInstance(
            instanceId: _uuid.v4(),
            definition: waitDef,
            inputValues: {'seconds': 0.02},
          );

          // After inner while exits (person lost): stop both motors + 0.5s pause
          // so the outer while(true) doesn't busy-loop when person is absent
          final stopAfterLost = motorBlock(leftDef, 'STOP', 0)
            ..nextBlock = (motorBlock(rightDef, 'STOP', 0)
              ..nextBlock = BlockInstance(
                instanceId: _uuid.v4(),
                definition: waitDef,
                inputValues: {'seconds': 0.5},
              ));

          // Inner while: while(lockOn:person) { pivot logic }
          // nextBlock chains the stop+wait to run when person is lost
          final innerWhile = BlockInstance(
            instanceId: _uuid.v4(),
            definition: whileDef,
            nestedBlocks: {
              'condition': BlockInstance(
                instanceId: _uuid.v4(),
                definition: detectedDef,
                inputValues: {'target': 'person'},
              ),
              'do': pfAlwaysFwd,
            },
          )..nextBlock = stopAfterLost;

          // Outer while(true): keeps the program looping forever (like Arduino loop())
          final outerWhile = BlockInstance(
            instanceId: _uuid.v4(),
            definition: whileDef,
            nestedBlocks: {
              'condition': BlockInstance(
                instanceId: _uuid.v4(),
                definition: boolTrueDef,
              ),
              'do': innerWhile,
            },
          );
          outerWhile.position = const Offset(100, 100);

          return [outerWhile]; // Single root block — self-contained infinite loop
        },
      },

      // ── SNIPPET 5: Voice Control ──────────────────────────────────────────────
      {
        'emoji': '🎙️',
        'name': 'Voice Control',
        'description': 'Say "forward", "stop", "left", or "right" to drive the robot hands-free.',
        'requiredMotors': 2,
        'build': () {
          final leftDef = motors[0];
          final rightDef = motors[1];
          final whileDef = findDef('logic_while');
          final ifDef    = findDef('logic_if');
          final voiceDef = findDef('sense_voice');
          final boolTrueDef = findDef('bool_true');

          BlockInstance voiceBlock(String phrase) => BlockInstance(
            instanceId: _uuid.v4(),
            definition: voiceDef,
            inputValues: {'phrase': phrase},
          );

          // if heard("forward") → both FORWARD
          final ifForward = BlockInstance(
            instanceId: _uuid.v4(),
            definition: ifDef,
            nestedBlocks: {
              'condition': voiceBlock('forward'),
              'then': motorBlock(leftDef, 'FORWARD', 200)
                ..nextBlock = motorBlock(rightDef, 'FORWARD', 200),
            },
          );

          // if heard("stop") → both STOP
          final ifStop = BlockInstance(
            instanceId: _uuid.v4(),
            definition: ifDef,
            nestedBlocks: {
              'condition': voiceBlock('stop'),
              'then': motorBlock(leftDef, 'STOP', 0)
                ..nextBlock = motorBlock(rightDef, 'STOP', 0),
            },
          );

          // if heard("left") → pivot left (left STOP, right FORWARD)
          final ifLeft = BlockInstance(
            instanceId: _uuid.v4(),
            definition: ifDef,
            nestedBlocks: {
              'condition': voiceBlock('left'),
              'then': motorBlock(leftDef, 'STOP', 0)
                ..nextBlock = motorBlock(rightDef, 'FORWARD', 200),
            },
          );

          // if heard("right") → pivot right (left FORWARD, right STOP)
          final ifRight = BlockInstance(
            instanceId: _uuid.v4(),
            definition: ifDef,
            nestedBlocks: {
              'condition': voiceBlock('right'),
              'then': motorBlock(leftDef, 'FORWARD', 200)
                ..nextBlock = motorBlock(rightDef, 'STOP', 0),
            },
          );

          // Chain: forward → stop → left → right
          ifForward.nextBlock = ifStop;
          ifStop.nextBlock    = ifLeft;
          ifLeft.nextBlock    = ifRight;

          // while(true) wrapper keeps listening forever (like Arduino loop())
          final outerWhile = BlockInstance(
            instanceId: _uuid.v4(),
            definition: whileDef,
            nestedBlocks: {
              'condition': BlockInstance(
                instanceId: _uuid.v4(),
                definition: boolTrueDef,
              ),
              'do': ifForward,
            },
          );
          outerWhile.position = const Offset(100, 100);

          return [outerWhile];
        },
      },

      // ── SNIPPET 6: Fetch Bot ──────────────────────────────────────────────────
      {
        'emoji': '🎾',
        'name': 'Fetch Bot',
        'description': 'Native PD controller: searches for object, drives toward it with momentum-aware steering, stops when close. Uses Smart Follow block.',
        'requiredMotors': 2,
        'build': () {
          // Smart Follow is a single self-contained block that runs a tight
          // 30ms control loop inside the runner. It handles search, tracking,
          // PD steering, and stop-on-arrival — so the snippet is just one block.
          final smartFollowDef = findDef('act_smart_follow');
          final smartFollow = BlockInstance(
            instanceId: _uuid.v4(),
            definition: smartFollowDef,
            inputValues: {
              'mode': 'FETCH',
              'baseSpeed': 100,
              'minSpeed': 60,
              'arrivedPct': 30,
              'steering': 'NORMAL',
            },
          );
          smartFollow.position = const Offset(100, 100);
          return [smartFollow];
        },
      },

      // ── SNIPPET 7: Line Follower ───────────────────────────────────────────────
      {
        'emoji': '🛤️',
        'name': 'Line Follower',
        'description': 'Uses Sobel CV to follow a line on the floor. Point phone camera down at tape.',
        'requiredMotors': 2,
        'build': () {
          final leftDef = motors[0];
          final rightDef = motors[1];
          final whileDef = findDef('logic_while');
          final ifDef = findDef('logic_if');
          final boolTrueDef = findDef('bool_true');
          final lineDetectedDef = findDef('sense_line_detected');
          final lineOffsetDef = findDef('sense_line_offset_x');
          final ltDef = findDef('math_less_than');
          final gtDef = findDef('math_greater_than');
          final numDef = findDef('math_number');
          final waitDef = findDef('logic_wait');

          BlockInstance num(double v) => BlockInstance(
            instanceId: _uuid.v4(),
            definition: numDef,
            inputValues: {'value': v},
          );
          BlockInstance lineOffset() => BlockInstance(
            instanceId: _uuid.v4(),
            definition: lineOffsetDef,
          );

          // if line_offset_x < -0.2 → turn left (line is to the left)
          final ifTurnLeft = BlockInstance(
            instanceId: _uuid.v4(),
            definition: ifDef,
            nestedBlocks: {
              'condition': BlockInstance(
                instanceId: _uuid.v4(),
                definition: ltDef,
                nestedBlocks: {'left': lineOffset(), 'right': num(-0.2)},
              ),
              'then': motorBlock(leftDef, 'STOP', 0)
                ..nextBlock = motorBlock(rightDef, 'FORWARD', 180),
            },
          );

          // if line_offset_x > 0.2 → turn right
          final ifTurnRight = BlockInstance(
            instanceId: _uuid.v4(),
            definition: ifDef,
            nestedBlocks: {
              'condition': BlockInstance(
                instanceId: _uuid.v4(),
                definition: gtDef,
                nestedBlocks: {'left': lineOffset(), 'right': num(0.2)},
              ),
              'then': motorBlock(leftDef, 'FORWARD', 180)
                ..nextBlock = motorBlock(rightDef, 'STOP', 0),
            },
          );

          // else: centered → go straight
          final ifStraight = BlockInstance(
            instanceId: _uuid.v4(),
            definition: ifDef,
            nestedBlocks: {
              'condition': BlockInstance(
                instanceId: _uuid.v4(),
                definition: findDef('bool_and'),
                nestedBlocks: {
                  'left': BlockInstance(
                    instanceId: _uuid.v4(),
                    definition: gtDef,
                    nestedBlocks: {'left': lineOffset(), 'right': num(-0.2)},
                  ),
                  'right': BlockInstance(
                    instanceId: _uuid.v4(),
                    definition: ltDef,
                    nestedBlocks: {'left': lineOffset(), 'right': num(0.2)},
                  ),
                },
              ),
              'then': motorBlock(leftDef, 'FORWARD', 200)
                ..nextBlock = motorBlock(rightDef, 'FORWARD', 200),
            },
          );

          ifTurnLeft.nextBlock = ifTurnRight;
          ifTurnRight.nextBlock = ifStraight;

          // Stop + wait when line lost
          final stopLost = motorBlock(leftDef, 'STOP', 0)
            ..nextBlock = (motorBlock(rightDef, 'STOP', 0)
              ..nextBlock = BlockInstance(
                instanceId: _uuid.v4(),
                definition: waitDef,
                inputValues: {'seconds': 0.5},
              ));

          // Inner while: follow while line is detected
          final followWhile = BlockInstance(
            instanceId: _uuid.v4(),
            definition: whileDef,
            nestedBlocks: {
              'condition': BlockInstance(instanceId: _uuid.v4(), definition: lineDetectedDef),
              'do': ifTurnLeft,
            },
          )..nextBlock = stopLost;

          // Outer while(true) forever loop
          final outerWhile = BlockInstance(
            instanceId: _uuid.v4(),
            definition: whileDef,
            nestedBlocks: {
              'condition': BlockInstance(instanceId: _uuid.v4(), definition: boolTrueDef),
              'do': followWhile,
            },
          );
          outerWhile.position = const Offset(100, 100);
          return [outerWhile];
        },
      },

      // ── SNIPPET 8: Tilt Steering ──────────────────────────────────────────────
      {
        'emoji': '📱',
        'name': 'Tilt Steering',
        'description': 'Tilt phone forward/back to drive, left/right to steer. Flat = stop.',
        'requiredMotors': 2,
        'build': () {
          final leftDef = motors[0];
          final rightDef = motors[1];
          final whileDef = findDef('logic_while');
          final ifDef = findDef('logic_if');
          final boolTrueDef = findDef('bool_true');
          final ltDef = findDef('math_less_than');
          final gtDef = findDef('math_greater_than');
          final numDef = findDef('math_number');
          final tiltXDef = findDef('sense_tilt_angle_x');
          final tiltYDef = findDef('sense_tilt_angle_y');

          BlockInstance num(double v) => BlockInstance(
            instanceId: _uuid.v4(),
            definition: numDef,
            inputValues: {'value': v},
          );
          BlockInstance tiltX() => BlockInstance(instanceId: _uuid.v4(), definition: tiltXDef);
          BlockInstance tiltY() => BlockInstance(instanceId: _uuid.v4(), definition: tiltYDef);

          // Priority order: forward > back > right turn > left turn > stop.
          // Each condition is checked independently — last matching if wins,
          // but since we stop by default and only activate motors when tilted,
          // the most recently-set state is what matters each loop iteration.
          // Using a stop-first approach: always stop, then apply corrections.

          // STOP first — baseline every loop
          final alwaysStop = motorBlock(leftDef, 'STOP', 0)
            ..nextBlock = motorBlock(rightDef, 'STOP', 0);

          // if tiltX < -25 → forward (screen tilts toward you = top of phone tilts away)
          final ifForward = BlockInstance(
            instanceId: _uuid.v4(),
            definition: ifDef,
            nestedBlocks: {
              'condition': BlockInstance(instanceId: _uuid.v4(), definition: ltDef,
                nestedBlocks: {'left': tiltX(), 'right': num(-25)}),
              'then': motorBlock(leftDef, 'FORWARD', 150)
                ..nextBlock = motorBlock(rightDef, 'FORWARD', 150),
            },
          );

          // if tiltX > 25 → reverse (screen tilts away from you)
          final ifBack = BlockInstance(
            instanceId: _uuid.v4(),
            definition: ifDef,
            nestedBlocks: {
              'condition': BlockInstance(instanceId: _uuid.v4(), definition: gtDef,
                nestedBlocks: {'left': tiltX(), 'right': num(25)}),
              'then': motorBlock(leftDef, 'BACKWARD', 150)
                ..nextBlock = motorBlock(rightDef, 'BACKWARD', 150),
            },
          );

          // if tiltY > 15 → pivot right (left motor drives, right stops)
          final ifRight = BlockInstance(
            instanceId: _uuid.v4(),
            definition: ifDef,
            nestedBlocks: {
              'condition': BlockInstance(instanceId: _uuid.v4(), definition: gtDef,
                nestedBlocks: {'left': tiltY(), 'right': num(15)}),
              'then': motorBlock(leftDef, 'FORWARD', 150)
                ..nextBlock = motorBlock(rightDef, 'STOP', 0),
            },
          );

          // if tiltY < -15 → pivot left (right motor drives, left stops)
          final ifLeft = BlockInstance(
            instanceId: _uuid.v4(),
            definition: ifDef,
            nestedBlocks: {
              'condition': BlockInstance(instanceId: _uuid.v4(), definition: ltDef,
                nestedBlocks: {'left': tiltY(), 'right': num(-15)}),
              'then': motorBlock(leftDef, 'STOP', 0)
                ..nextBlock = motorBlock(rightDef, 'FORWARD', 150),
            },
          );

          // Wait after IFs so the motor command is sustained before the loop
          // restarts with alwaysStop. Without this, the loop cycles ~10ms and
          // the motor gets FORWARD then immediately STOP before it can respond.
          final cycleWait = BlockInstance(
            instanceId: _uuid.v4(),
            definition: findDef('logic_wait'),
            inputValues: {'seconds': 0.15},
          );

          // Chain: stop → forward? → back? → right? → left? → wait 150ms
          // Last fired wins. right/left fire even if also forward-tilted (no guard).
          alwaysStop.nextBlock!.nextBlock = ifForward;
          ifForward.nextBlock = ifBack;
          ifBack.nextBlock = ifRight;
          ifRight.nextBlock = ifLeft;
          ifLeft.nextBlock = cycleWait;

          final outerWhile = BlockInstance(
            instanceId: _uuid.v4(),
            definition: whileDef,
            nestedBlocks: {
              'condition': BlockInstance(instanceId: _uuid.v4(), definition: boolTrueDef),
              'do': alwaysStop,
            },
          );
          outerWhile.position = const Offset(100, 100);
          return [outerWhile];
        },
      },

      // ── SNIPPET 9: Compass Patrol ─────────────────────────────────────────────
      {
        'emoji': '🧭',
        'name': 'Compass Patrol',
        'description': 'Drives North, turns East, drives East, turns North — patrols a square using compass.',
        'requiredMotors': 2,
        'build': () {
          final leftDef = motors[0];
          final rightDef = motors[1];
          final whileDef = findDef('logic_while');
          final boolTrueDef = findDef('bool_true');
          final notDef = findDef('bool_not');
          final facingDef = findDef('sense_facing');
          final waitDef = findDef('logic_wait');

          BlockInstance facingBlock(String dir) => BlockInstance(
            instanceId: _uuid.v4(),
            definition: facingDef,
            inputValues: {'direction': dir},
          );
          BlockInstance spinRight() => motorBlock(leftDef, 'FORWARD', 160)
            ..nextBlock = motorBlock(rightDef, 'STOP', 0);
          BlockInstance stopBoth() => motorBlock(leftDef, 'STOP', 0)
            ..nextBlock = motorBlock(rightDef, 'STOP', 0);

          // Step 1: Drive North for 2s then stop.
          // Build end first, work backwards so nextBlock chain is clean (no cycles).
          final waitNorth = BlockInstance(
            instanceId: _uuid.v4(), definition: waitDef,
            inputValues: {'seconds': 2},
          );
          final driveNorthR = motorBlock(rightDef, 'FORWARD', 200)..nextBlock = waitNorth;
          final driveNorthL = motorBlock(leftDef, 'FORWARD', 200)..nextBlock = driveNorthR;

          final stopNorthR = motorBlock(rightDef, 'STOP', 0);
          final stopNorthL = motorBlock(leftDef, 'STOP', 0)..nextBlock = stopNorthR;
          waitNorth.nextBlock = stopNorthL;

          // Step 2: Spin right until facing East.
          final turnToEast = BlockInstance(
            instanceId: _uuid.v4(),
            definition: whileDef,
            nestedBlocks: {
              'condition': BlockInstance(instanceId: _uuid.v4(), definition: notDef,
                nestedBlocks: {'value': facingBlock('East')}),
              'do': spinRight(),
            },
          );
          stopNorthR.nextBlock = turnToEast;

          // Step 3: Drive East for 2s then stop.
          final waitEast = BlockInstance(
            instanceId: _uuid.v4(), definition: waitDef,
            inputValues: {'seconds': 2},
          );
          final driveEastR = motorBlock(rightDef, 'FORWARD', 200)..nextBlock = waitEast;
          final driveEastL = motorBlock(leftDef, 'FORWARD', 200)..nextBlock = driveEastR;
          turnToEast.nextBlock = driveEastL;

          final stopEastR = motorBlock(rightDef, 'STOP', 0);
          final stopEastL = motorBlock(leftDef, 'STOP', 0)..nextBlock = stopEastR;
          waitEast.nextBlock = stopEastL;

          // Step 4: Spin right until facing North.
          // nextBlock = null → end of do-block; outer while(true) restarts from driveNorthL.
          final turnToNorth = BlockInstance(
            instanceId: _uuid.v4(),
            definition: whileDef,
            nestedBlocks: {
              'condition': BlockInstance(instanceId: _uuid.v4(), definition: notDef,
                nestedBlocks: {'value': facingBlock('North')}),
              'do': spinRight(),
            },
          );
          stopEastR.nextBlock = turnToNorth;
          // turnToNorth.nextBlock stays null — outer while(true) loops back automatically.

          // Safety stop after each full patrol lap.
          final safeStop = stopBoth();
          turnToNorth.nextBlock = safeStop;

          // Outer while(true): runs driveNorthL..safeStop as one lap, then repeats.
          final outerWhile = BlockInstance(
            instanceId: _uuid.v4(),
            definition: whileDef,
            nestedBlocks: {
              'condition': BlockInstance(instanceId: _uuid.v4(), definition: boolTrueDef),
              'do': driveNorthL,
            },
          );
          outerWhile.position = const Offset(100, 100);
          return [outerWhile];
        },
      },
    ];

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
                        final required = s['requiredMotors'] as int;
                        final hasEnough = motorCount >= required;

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
                                s['emoji'] as String,
                                style: const TextStyle(fontSize: 28),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s['name'] as String,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      s['description'] as String,
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
                                    final blocks = (s['build'] as List<BlockInstance> Function())();
                                    setState(() {
                                      _script.clear();
                                      _script.addAll(blocks);
                                    });
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Snippet loaded \u{2713}'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
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
                                    '\u{26A0} Needs $required motors',
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
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            _buildBlockPalette(),
            Expanded(child: _buildCanvas()),
          ],
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
          // Gradient icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.extension, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
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
          // Snippets chip button
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
          const SizedBox(width: 6),
          // Save
          IconButton(
            onPressed: _showSaveDialog,
            icon: const Icon(Icons.save_outlined, size: 20),
            tooltip: 'Save Script',
          ),
          // Load
          IconButton(
            onPressed: _showLoadDialog,
            icon: const Icon(Icons.folder_open_outlined, size: 20),
            tooltip: 'Load Script',
          ),
          // Popup menu for secondary actions
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            tooltip: 'More options',
            onSelected: (value) {
              switch (value) {
                case 'clear':
                  setState(() => _script.clear());
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
         onInputChanged: (fieldId, value) {
           setState(() {
             block.inputValues[fieldId] = value;
           });
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
         setState(() {
           block.inputValues[fieldId] = value;
         });
       },
     );
  }

  Widget _buildPlayButton() {
    final isRunning = _executionState == ExecutionState.running;

    return FloatingActionButton.extended(
      onPressed: () {
        if (isRunning) {
          _runner.stop();
        } else {
          // Flatten the script from roots (sorted by Y)
          _runningRoots = sortedRoots;
          _runner.loadScript(_runningRoots);
          _runner.play();
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
