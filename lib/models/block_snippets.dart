import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'block_models.dart';

/// A ready-made block program (Blocks › ⚡ Snippets). The Python tab's
/// examples are these same programs converted to Python, so the two always
/// match.
class BlockSnippet {
  const BlockSnippet({
    required this.emoji,
    required this.name,
    required this.description,
    required this.requiredMotors,
    required this.build,
  });

  final String emoji;
  final String name;
  final String description;
  final int requiredMotors;

  /// Builds fresh block instances (new ids every call).
  final List<BlockInstance> Function() build;
}

/// The snippets. [defs]: every block definition available; [motors]: the
/// motor block definitions in configuration order. A snippet can only be
/// built when there are at least [BlockSnippet.requiredMotors] motors.
List<BlockSnippet> blockSnippets(List<BlockDefinition> defs, List<BlockDefinition> motors) {
  const uuid = Uuid();

  // Helper to create a motor block instance
  BlockInstance motorBlock(BlockDefinition def, String direction, int speed) {
    return BlockInstance(
      instanceId: uuid.v4(),
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
          instanceId: uuid.v4(),
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
          instanceId: uuid.v4(),
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
          instanceId: uuid.v4(),
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
          instanceId: uuid.v4(),
          definition: offsetXDef,
        );

        // Helper for math_number
        BlockInstance num(double value) => BlockInstance(
          instanceId: uuid.v4(),
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
          instanceId: uuid.v4(),
          definition: ifDef,
          nestedBlocks: {
            'condition': BlockInstance(
              instanceId: uuid.v4(),
              definition: andDef,
              nestedBlocks: {
                'left': BlockInstance(
                  instanceId: uuid.v4(),
                  definition: gtDef,
                  nestedBlocks: {'left': senseOffsetX(), 'right': num(0.20)},
                ),
                'right': BlockInstance(
                  instanceId: uuid.v4(),
                  definition: ltDef,
                  nestedBlocks: {
                    'left': BlockInstance(instanceId: uuid.v4(), definition: targetSizeDef),
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
          instanceId: uuid.v4(),
          definition: ifDef,
          nestedBlocks: {
            'condition': BlockInstance(
              instanceId: uuid.v4(),
              definition: andDef,
              nestedBlocks: {
                'left': BlockInstance(
                  instanceId: uuid.v4(),
                  definition: ltDef,
                  nestedBlocks: {'left': senseOffsetX(), 'right': num(-0.20)},
                ),
                'right': BlockInstance(
                  instanceId: uuid.v4(),
                  definition: ltDef,
                  nestedBlocks: {
                    'left': BlockInstance(instanceId: uuid.v4(), definition: targetSizeDef),
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
          instanceId: uuid.v4(),
          definition: ifDef,
          nestedBlocks: {
            'condition': BlockInstance(
              instanceId: uuid.v4(),
              definition: gtDef,
              nestedBlocks: {
                'left': BlockInstance(instanceId: uuid.v4(), definition: targetSizeDef),
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
          instanceId: uuid.v4(),
          definition: waitDef,
          inputValues: {'seconds': 0.02},
        );

        // After inner while exits (person lost): stop both motors + 0.5s pause
        // so the outer while(true) doesn't busy-loop when person is absent
        final stopAfterLost = motorBlock(leftDef, 'STOP', 0)
          ..nextBlock = (motorBlock(rightDef, 'STOP', 0)
            ..nextBlock = BlockInstance(
              instanceId: uuid.v4(),
              definition: waitDef,
              inputValues: {'seconds': 0.5},
            ));

        // Inner while: while(lockOn:person) { pivot logic }
        // nextBlock chains the stop+wait to run when person is lost
        final innerWhile = BlockInstance(
          instanceId: uuid.v4(),
          definition: whileDef,
          nestedBlocks: {
            'condition': BlockInstance(
              instanceId: uuid.v4(),
              definition: detectedDef,
              inputValues: {'target': 'person'},
            ),
            'do': pfAlwaysFwd,
          },
        )..nextBlock = stopAfterLost;

        // Outer while(true): keeps the program looping forever (like Arduino loop())
        final outerWhile = BlockInstance(
          instanceId: uuid.v4(),
          definition: whileDef,
          nestedBlocks: {
            'condition': BlockInstance(
              instanceId: uuid.v4(),
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
          instanceId: uuid.v4(),
          definition: voiceDef,
          inputValues: {'phrase': phrase},
        );

        // if heard("forward") → both FORWARD
        final ifForward = BlockInstance(
          instanceId: uuid.v4(),
          definition: ifDef,
          nestedBlocks: {
            'condition': voiceBlock('forward'),
            'then': motorBlock(leftDef, 'FORWARD', 200)
              ..nextBlock = motorBlock(rightDef, 'FORWARD', 200),
          },
        );

        // if heard("stop") → both STOP
        final ifStop = BlockInstance(
          instanceId: uuid.v4(),
          definition: ifDef,
          nestedBlocks: {
            'condition': voiceBlock('stop'),
            'then': motorBlock(leftDef, 'STOP', 0)
              ..nextBlock = motorBlock(rightDef, 'STOP', 0),
          },
        );

        // if heard("left") → pivot left (left STOP, right FORWARD)
        final ifLeft = BlockInstance(
          instanceId: uuid.v4(),
          definition: ifDef,
          nestedBlocks: {
            'condition': voiceBlock('left'),
            'then': motorBlock(leftDef, 'STOP', 0)
              ..nextBlock = motorBlock(rightDef, 'FORWARD', 200),
          },
        );

        // if heard("right") → pivot right (left FORWARD, right STOP)
        final ifRight = BlockInstance(
          instanceId: uuid.v4(),
          definition: ifDef,
          nestedBlocks: {
            'condition': voiceBlock('right'),
            'then': motorBlock(leftDef, 'FORWARD', 200)
              ..nextBlock = motorBlock(rightDef, 'STOP', 0),
          },
        );

        // Chain: forward → stop → left → right
        // "stop" is checked first: recognized text accumulates, so after
        // "forward ... stop" the forward check would match first and
        // consume the text, losing the stop command.
        ifStop.nextBlock    = ifForward;
        ifForward.nextBlock = ifLeft;
        ifLeft.nextBlock    = ifRight;

        // while(true) wrapper keeps listening forever (like Arduino loop())
        final outerWhile = BlockInstance(
          instanceId: uuid.v4(),
          definition: whileDef,
          nestedBlocks: {
            'condition': BlockInstance(
              instanceId: uuid.v4(),
              definition: boolTrueDef,
            ),
            'do': ifStop,
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
      'description': 'Chases the object in small steps while it sees it, waits while it does not, stops when close. One Smart Follow block: raise "min speed" if a wheel hums but does not turn.',
      'requiredMotors': 2,
      'build': () {
        // Smart Follow is a single self-contained block: search, tracking,
        // steering and stop-on-arrival, so the snippet is just one block.
        final smartFollowDef = findDef('act_smart_follow');
        final smartFollow = BlockInstance(
          instanceId: uuid.v4(),
          definition: smartFollowDef,
          inputValues: {
            'mode': 'FETCH',
            'baseSpeed': 150,
            'minSpeed': 100,
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
          instanceId: uuid.v4(),
          definition: numDef,
          inputValues: {'value': v},
        );
        BlockInstance lineOffset() => BlockInstance(
          instanceId: uuid.v4(),
          definition: lineOffsetDef,
        );

        // if line_offset_x < -0.2 → turn left (line is to the left)
        final ifTurnLeft = BlockInstance(
          instanceId: uuid.v4(),
          definition: ifDef,
          nestedBlocks: {
            'condition': BlockInstance(
              instanceId: uuid.v4(),
              definition: ltDef,
              nestedBlocks: {'left': lineOffset(), 'right': num(-0.2)},
            ),
            'then': motorBlock(leftDef, 'STOP', 0)
              ..nextBlock = motorBlock(rightDef, 'FORWARD', 180),
          },
        );

        // if line_offset_x > 0.2 → turn right
        final ifTurnRight = BlockInstance(
          instanceId: uuid.v4(),
          definition: ifDef,
          nestedBlocks: {
            'condition': BlockInstance(
              instanceId: uuid.v4(),
              definition: gtDef,
              nestedBlocks: {'left': lineOffset(), 'right': num(0.2)},
            ),
            'then': motorBlock(leftDef, 'FORWARD', 180)
              ..nextBlock = motorBlock(rightDef, 'STOP', 0),
          },
        );

        // else: centered → go straight
        final ifStraight = BlockInstance(
          instanceId: uuid.v4(),
          definition: ifDef,
          nestedBlocks: {
            'condition': BlockInstance(
              instanceId: uuid.v4(),
              definition: findDef('bool_and'),
              nestedBlocks: {
                'left': BlockInstance(
                  instanceId: uuid.v4(),
                  definition: gtDef,
                  nestedBlocks: {'left': lineOffset(), 'right': num(-0.2)},
                ),
                'right': BlockInstance(
                  instanceId: uuid.v4(),
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
              instanceId: uuid.v4(),
              definition: waitDef,
              inputValues: {'seconds': 0.5},
            ));

        // Inner while: follow while line is detected
        final followWhile = BlockInstance(
          instanceId: uuid.v4(),
          definition: whileDef,
          nestedBlocks: {
            'condition': BlockInstance(instanceId: uuid.v4(), definition: lineDetectedDef),
            'do': ifTurnLeft,
          },
        )..nextBlock = stopLost;

        // Outer while(true) forever loop
        final outerWhile = BlockInstance(
          instanceId: uuid.v4(),
          definition: whileDef,
          nestedBlocks: {
            'condition': BlockInstance(instanceId: uuid.v4(), definition: boolTrueDef),
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
          instanceId: uuid.v4(),
          definition: numDef,
          inputValues: {'value': v},
        );
        BlockInstance tiltX() => BlockInstance(instanceId: uuid.v4(), definition: tiltXDef);
        BlockInstance tiltY() => BlockInstance(instanceId: uuid.v4(), definition: tiltYDef);

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
          instanceId: uuid.v4(),
          definition: ifDef,
          nestedBlocks: {
            'condition': BlockInstance(instanceId: uuid.v4(), definition: ltDef,
              nestedBlocks: {'left': tiltX(), 'right': num(-25)}),
            'then': motorBlock(leftDef, 'FORWARD', 150)
              ..nextBlock = motorBlock(rightDef, 'FORWARD', 150),
          },
        );

        // if tiltX > 25 → reverse (screen tilts away from you)
        final ifBack = BlockInstance(
          instanceId: uuid.v4(),
          definition: ifDef,
          nestedBlocks: {
            'condition': BlockInstance(instanceId: uuid.v4(), definition: gtDef,
              nestedBlocks: {'left': tiltX(), 'right': num(25)}),
            'then': motorBlock(leftDef, 'BACKWARD', 150)
              ..nextBlock = motorBlock(rightDef, 'BACKWARD', 150),
          },
        );

        // Tilt Roll is negative when the phone is tilted right (right edge
        // down). The snippet used to pivot right on roll > 15, i.e. it
        // turned the opposite way to the tilt.
        // if tiltY < -15 → pivot right (left motor drives, right stops)
        final ifRight = BlockInstance(
          instanceId: uuid.v4(),
          definition: ifDef,
          nestedBlocks: {
            'condition': BlockInstance(instanceId: uuid.v4(), definition: ltDef,
              nestedBlocks: {'left': tiltY(), 'right': num(-15)}),
            'then': motorBlock(leftDef, 'FORWARD', 150)
              ..nextBlock = motorBlock(rightDef, 'STOP', 0),
          },
        );

        // if tiltY > 15 → pivot left (right motor drives, left stops)
        final ifLeft = BlockInstance(
          instanceId: uuid.v4(),
          definition: ifDef,
          nestedBlocks: {
            'condition': BlockInstance(instanceId: uuid.v4(), definition: gtDef,
              nestedBlocks: {'left': tiltY(), 'right': num(15)}),
            'then': motorBlock(leftDef, 'STOP', 0)
              ..nextBlock = motorBlock(rightDef, 'FORWARD', 150),
          },
        );

        // Wait after IFs so the motor command is sustained before the loop
        // restarts with alwaysStop. Without this, the loop cycles ~10ms and
        // the motor gets FORWARD then immediately STOP before it can respond.
        final cycleWait = BlockInstance(
          instanceId: uuid.v4(),
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
          instanceId: uuid.v4(),
          definition: whileDef,
          nestedBlocks: {
            'condition': BlockInstance(instanceId: uuid.v4(), definition: boolTrueDef),
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
          instanceId: uuid.v4(),
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
          instanceId: uuid.v4(), definition: waitDef,
          inputValues: {'seconds': 2},
        );
        final driveNorthR = motorBlock(rightDef, 'FORWARD', 200)..nextBlock = waitNorth;
        final driveNorthL = motorBlock(leftDef, 'FORWARD', 200)..nextBlock = driveNorthR;

        final stopNorthR = motorBlock(rightDef, 'STOP', 0);
        final stopNorthL = motorBlock(leftDef, 'STOP', 0)..nextBlock = stopNorthR;
        waitNorth.nextBlock = stopNorthL;

        // Step 2: Spin right until facing East.
        final turnToEast = BlockInstance(
          instanceId: uuid.v4(),
          definition: whileDef,
          nestedBlocks: {
            'condition': BlockInstance(instanceId: uuid.v4(), definition: notDef,
              nestedBlocks: {'value': facingBlock('East')}),
            'do': spinRight(),
          },
        );
        stopNorthR.nextBlock = turnToEast;

        // Step 3: Drive East for 2s then stop.
        final waitEast = BlockInstance(
          instanceId: uuid.v4(), definition: waitDef,
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
          instanceId: uuid.v4(),
          definition: whileDef,
          nestedBlocks: {
            'condition': BlockInstance(instanceId: uuid.v4(), definition: notDef,
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
          instanceId: uuid.v4(),
          definition: whileDef,
          nestedBlocks: {
            'condition': BlockInstance(instanceId: uuid.v4(), definition: boolTrueDef),
            'do': driveNorthL,
          },
        );
        outerWhile.position = const Offset(100, 100);
        return [outerWhile];
      },
    },
  ];

  return [
    for (final s in snippets)
      BlockSnippet(
        emoji: s['emoji'] as String,
        name: s['name'] as String,
        description: s['description'] as String,
        requiredMotors: s['requiredMotors'] as int,
        build: s['build'] as List<BlockInstance> Function(),
      ),
  ];
}
