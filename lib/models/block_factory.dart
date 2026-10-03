import '../models/block_models.dart';
import '../models/actuator_config.dart';

class BlockFactory {
  // Vision sensor block
  static BlockDefinition objectDetectedBlock() {
    return BlockDefinition(
      id: 'sense_object_detected',
      label: 'Object Detected',
      emoji: '👁️',
      color: BlockColors.sensor,
      shape: BlockShape.boolean,
      category: 'Sensors',
    );
  }

  static BlockDefinition objectLockedBlock() {
    return BlockDefinition(
      id: 'sense_object_locked',
      label: 'Lock Object Type',
      emoji: '🎯',
      color: BlockColors.sensor,
      shape: BlockShape.boolean,
      category: 'Sensors',
      inputs: [
        InputFieldDefinition(
          id: 'target',
          label: '',
          type: InputFieldType.dropdown,
          options: [
            'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train', 'truck',
            'boat', 'bird', 'cat', 'dog', 'horse', 'sheep', 'cow', 'apple', 'banana',
            'sandwich', 'chair', 'couch', 'potted plant', 'tv', 'laptop', 'mouse', 'remote',
            'keyboard', 'cell phone', 'microwave', 'oven', 'refrigerator', 'book', 'clock',
            'vase', 'teddy bear', 'bottle', 'cup', 'fork', 'knife', 'spoon', 'bowl',
            // Also detectable and listed in Vision Settings:
            'sports ball', 'backpack', 'umbrella', 'handbag', 'tie', 'suitcase',
            'orange', 'scissors', 'toothbrush',
          ],
          defaultValue: 'person',
        ),
      ],
    );
  }

  static BlockDefinition phoneShakeBlock() {
    return BlockDefinition(
      id: 'sense_shake',
      label: 'Phone Shaking',
      emoji: '📳',
      color: BlockColors.sensor,
      shape: BlockShape.boolean,
      category: 'Sensors',
    );
  }

  static BlockDefinition phoneTiltBlock() {
    return BlockDefinition(
      id: 'sense_tilt',
      label: 'Phone Tilted',
      emoji: '📐',
      color: BlockColors.sensor,
      shape: BlockShape.boolean,
      category: 'Sensors',
    );
  }

  static BlockDefinition micLoudBlock() {
    return BlockDefinition(
      id: 'sense_loud',
      label: 'Loud Noise',
      emoji: '🔊',
      color: BlockColors.sensor,
      shape: BlockShape.boolean,
      category: 'Sensors',
    );
  }

  static BlockDefinition voiceMatchBlock() {
    return BlockDefinition(
      id: 'sense_voice',
      label: 'Heard',
      emoji: '🗣️',
      color: BlockColors.sensor,
      shape: BlockShape.boolean,
      category: 'Sensors',
      inputs: [
        InputFieldDefinition(
          id: 'phrase',
          label: 'phrase',
          type: InputFieldType.text,
          defaultValue: 'go',
        ),
      ],
    );
  }

  // Tracking Blocks
  static BlockDefinition targetLockedBlock() {
    return BlockDefinition(
      id: 'sense_locked',
      label: 'Object Locked',
      emoji: '🎯',
      color: BlockColors.sensor,
      shape: BlockShape.boolean,
      category: 'Sensors',
    );
  }

  static BlockDefinition targetOffsetXBlock() {
    return BlockDefinition(
      id: 'sense_offset_x',
      label: 'Target X Offset',
      emoji: '↔️',
      color: BlockColors.sensor,
      shape: BlockShape.expression,
      category: 'Sensors',
    );
  }

  static BlockDefinition targetOffsetYBlock() {
    return BlockDefinition(
      id: 'sense_offset_y',
      label: 'Target Y Offset',
      emoji: '↕️',
      color: BlockColors.sensor,
      shape: BlockShape.expression,
      category: 'Sensors',
    );
  }

  static BlockDefinition targetSizeBlock() {
    return BlockDefinition(
      id: 'sense_target_size',
      label: 'Target Size %',
      emoji: '📏',
      color: BlockColors.sensor,
      shape: BlockShape.expression,
      category: 'Sensors',
    );
  }

  // ── Line following blocks ─────────────────────────────────────────────────

  static BlockDefinition lineDetectedBlock() {
    return BlockDefinition(
      id: 'sense_line_detected',
      label: 'Line Visible',
      emoji: '🛤️',
      color: BlockColors.sensor,
      shape: BlockShape.boolean,
      category: 'Sensors',
    );
  }

  static BlockDefinition lineOffsetXBlock() {
    return BlockDefinition(
      id: 'sense_line_offset_x',
      label: 'Line Offset X',
      emoji: '↔️',
      color: BlockColors.sensor,
      shape: BlockShape.expression,
      category: 'Sensors',
    );
  }

  // ── Gyroscope blocks ───────────────────────────────────────────────────────

  static BlockDefinition isRotatingBlock() {
    return BlockDefinition(
      id: 'sense_rotating',
      label: 'Phone Spinning',
      emoji: '🌀',
      color: BlockColors.sensor,
      shape: BlockShape.boolean,
      category: 'Sensors',
    );
  }

  static BlockDefinition rotationRateBlock() {
    return BlockDefinition(
      id: 'sense_rotation_rate',
      label: 'Rotation Rate °/s',
      emoji: '🔃',
      color: BlockColors.sensor,
      shape: BlockShape.expression,
      category: 'Sensors',
    );
  }

  static BlockDefinition tiltAngleXBlock() {
    return BlockDefinition(
      id: 'sense_tilt_angle_x',
      label: 'Tilt Pitch °',
      emoji: '📐',
      color: BlockColors.sensor,
      shape: BlockShape.expression,
      category: 'Sensors',
    );
  }

  static BlockDefinition tiltAngleYBlock() {
    return BlockDefinition(
      id: 'sense_tilt_angle_y',
      label: 'Tilt Roll °',
      emoji: '📏',
      color: BlockColors.sensor,
      shape: BlockShape.expression,
      category: 'Sensors',
    );
  }

  // ── Compass / magnetometer blocks ─────────────────────────────────────────

  static BlockDefinition compassHeadingBlock() {
    return BlockDefinition(
      id: 'sense_heading',
      label: 'Compass Heading °',
      emoji: '🧭',
      color: BlockColors.sensor,
      shape: BlockShape.expression,
      category: 'Sensors',
    );
  }

  static BlockDefinition facingDirectionBlock() {
    return BlockDefinition(
      id: 'sense_facing',
      label: 'Facing Direction',
      emoji: '🧭',
      color: BlockColors.sensor,
      shape: BlockShape.boolean,
      category: 'Sensors',
      inputs: [
        InputFieldDefinition(
          id: 'direction',
          label: '',
          type: InputFieldType.dropdown,
          options: ['North', 'Northeast', 'East', 'Southeast', 'South', 'Southwest', 'West', 'Northwest'],
          defaultValue: 'North',
        ),
      ],
    );
  }

  // Logic blocks
  static BlockDefinition ifBlock() {
    return BlockDefinition(
      id: 'logic_if',
      label: 'If',
      emoji: '❓',
      color: BlockColors.logic,
      shape: BlockShape.statement,
      category: 'Logic',
      inputs: [
        InputFieldDefinition(
          id: 'condition',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.boolean,
        ),
        InputFieldDefinition(
          id: 'then',
          label: 'then do',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.statement,
        ),
      ],
    );
  }

  static BlockDefinition ifElseBlock() {
    return BlockDefinition(
      id: 'logic_if_else',
      label: 'If / Else',
      emoji: '🔀',
      color: BlockColors.logic,
      shape: BlockShape.statement,
      category: 'Logic',
      inputs: [
        InputFieldDefinition(
          id: 'condition',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.boolean,
        ),
        InputFieldDefinition(
          id: 'then',
          label: 'then do',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.statement,
        ),
        InputFieldDefinition(
          id: 'else',
          label: 'else do',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.statement,
        ),
      ],
    );
  }

  static BlockDefinition stopProgramBlock() {
    return BlockDefinition(
      id: 'logic_stop',
      label: 'Stop Program',
      emoji: '🛑',
      color: BlockColors.logic,
      shape: BlockShape.statement,
      category: 'Logic',
    );
  }

  /// Text-to-speech through the phone speaker.
  static BlockDefinition sayBlock() {
    return BlockDefinition(
      id: 'act_say',
      label: 'Say',
      emoji: '💬',
      color: BlockColors.action,
      shape: BlockShape.statement,
      category: 'Logic',
      inputs: [
        InputFieldDefinition(
          id: 'text',
          label: '',
          type: InputFieldType.text,
          defaultValue: 'Hello!',
        ),
      ],
    );
  }

  static BlockDefinition whileBlock() {
    return BlockDefinition(
      id: 'logic_while',
      label: 'While',
      emoji: '🔁',
      color: BlockColors.logic,
      shape: BlockShape.statement,
      category: 'Logic',
      inputs: [
        InputFieldDefinition(
          id: 'condition',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.boolean,
        ),
        InputFieldDefinition(
          id: 'do',
          label: 'do',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.statement,
        ),
      ],
    );
  }

  /// Runs its body over and over until the program is stopped.
  static BlockDefinition foreverBlock() {
    return BlockDefinition(
      id: 'logic_forever',
      label: 'Forever',
      emoji: '♾️',
      color: BlockColors.logic,
      shape: BlockShape.statement,
      category: 'Logic',
      inputs: [
        InputFieldDefinition(
          id: 'do',
          label: 'do',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.statement,
        ),
      ],
    );
  }

  /// Runs its body until the condition becomes true.
  static BlockDefinition repeatUntilBlock() {
    return BlockDefinition(
      id: 'logic_repeat_until',
      label: 'Repeat Until',
      emoji: '🔂',
      color: BlockColors.logic,
      shape: BlockShape.statement,
      category: 'Logic',
      inputs: [
        InputFieldDefinition(
          id: 'condition',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.boolean,
        ),
        InputFieldDefinition(
          id: 'do',
          label: 'do',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.statement,
        ),
      ],
    );
  }

  static BlockDefinition repeatBlock() {
    return BlockDefinition(
      id: 'logic_repeat',
      label: 'Repeat',
      emoji: '🔢',
      color: BlockColors.logic,
      shape: BlockShape.statement,
      category: 'Logic',
      inputs: [
        InputFieldDefinition(
          id: 'times',
          label: 'times',
          type: InputFieldType.number,
          defaultValue: 3,
          min: 1,
          max: 100,
        ),
        InputFieldDefinition(
          id: 'do',
          label: 'do',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.statement,
        ),
      ],
    );
  }

  static BlockDefinition waitBlock() {
    return BlockDefinition(
      id: 'logic_wait',
      label: 'Wait',
      emoji: '⏱️',
      color: BlockColors.logic,
      shape: BlockShape.statement,
      category: 'Logic',
      inputs: [
        InputFieldDefinition(
          id: 'seconds',
          label: 'seconds',
          type: InputFieldType.number,
          defaultValue: 1,
          min: 0,
          max: 60,
        ),
      ],
    );
  }

  // Boolean operator blocks
  static BlockDefinition andBlock() {
    return BlockDefinition(
      id: 'bool_and',
      label: 'AND',
      emoji: '&',
      color: BlockColors.boolean,
      shape: BlockShape.boolean,
      category: 'Logic',
      inputs: [
        InputFieldDefinition(
          id: 'left',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.boolean,
        ),
        InputFieldDefinition(
          id: 'right',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.boolean,
        ),
      ],
    );
  }

  static BlockDefinition orBlock() {
    return BlockDefinition(
      id: 'bool_or',
      label: 'OR',
      emoji: '|',
      color: BlockColors.boolean,
      shape: BlockShape.boolean,
      category: 'Logic',
      inputs: [
        InputFieldDefinition(
          id: 'left',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.boolean,
        ),
        InputFieldDefinition(
          id: 'right',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.boolean,
        ),
      ],
    );
  }

  static BlockDefinition notBlock() {
    return BlockDefinition(
      id: 'bool_not',
      label: 'NOT',
      emoji: '!',
      color: BlockColors.boolean,
      shape: BlockShape.boolean,
      category: 'Logic',
      inputs: [
        InputFieldDefinition(
          id: 'value',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.boolean,
        ),
      ],
    );
  }

  static BlockDefinition customExpressionBlock() {
    return BlockDefinition(
      id: 'logic_expression',
      label: 'Expression',
      emoji: '⌨️',
      color: BlockColors.logic,
      shape: BlockShape.boolean,
      category: 'Logic',
      inputs: [
        InputFieldDefinition(
          id: 'expression',
          label: '',
          type: InputFieldType.text,
          defaultValue: 'true',
        ),
      ],
    );
  }

  // Math blocks
  static BlockDefinition mathAddBlock() {
    return BlockDefinition(
      id: 'math_add',
      label: 'Add',
      emoji: '➕',
      color: BlockColors.value,
      shape: BlockShape.expression,
      category: 'Math',
      inputs: [
        InputFieldDefinition(
          id: 'left',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.expression,
        ),
        InputFieldDefinition(
          id: 'right',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.expression,
        ),
      ],
    );
  }

  static BlockDefinition mathSubtractBlock() {
    return BlockDefinition(
      id: 'math_subtract',
      label: 'Subtract',
      emoji: '➖',
      color: BlockColors.value,
      shape: BlockShape.expression,
      category: 'Math',
      inputs: [
        InputFieldDefinition(
          id: 'left',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.expression,
        ),
        InputFieldDefinition(
          id: 'right',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.expression,
        ),
      ],
    );
  }

  static BlockDefinition mathMultiplyBlock() {
    return BlockDefinition(
      id: 'math_multiply',
      label: 'Multiply',
      emoji: '✖️',
      color: BlockColors.value,
      shape: BlockShape.expression,
      category: 'Math',
      inputs: [
        InputFieldDefinition(
          id: 'left',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.expression,
        ),
        InputFieldDefinition(
          id: 'right',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.expression,
        ),
      ],
    );
  }

  static BlockDefinition mathDivideBlock() {
    return BlockDefinition(
      id: 'math_divide',
      label: 'Divide',
      emoji: '➗',
      color: BlockColors.value,
      shape: BlockShape.expression,
      category: 'Math',
      inputs: [
        InputFieldDefinition(
          id: 'left',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.expression,
        ),
        InputFieldDefinition(
          id: 'right',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.expression,
        ),
      ],
    );
  }

  static BlockDefinition mathLessThanBlock() {
    return BlockDefinition(
      id: 'math_less_than',
      label: 'Less Than <',
      emoji: '🤏',
      color: BlockColors.boolean,
      shape: BlockShape.boolean,
      category: 'Math',
      inputs: [
        InputFieldDefinition(
          id: 'left',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.expression,
        ),
        InputFieldDefinition(
          id: 'right',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.expression,
        ),
      ],
    );
  }

  static BlockDefinition mathGreaterThanBlock() {
    return BlockDefinition(
      id: 'math_greater_than',
      label: 'Greater Than >',
      emoji: '👐',
      color: BlockColors.boolean,
      shape: BlockShape.boolean,
      category: 'Math',
      inputs: [
        InputFieldDefinition(
          id: 'left',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.expression,
        ),
        InputFieldDefinition(
          id: 'right',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.expression,
        ),
      ],
    );
  }

  static BlockDefinition mathEqualsBlock() {
    return BlockDefinition(
      id: 'math_equals',
      label: 'Equals =',
      emoji: '🟰',
      color: BlockColors.boolean,
      shape: BlockShape.boolean,
      category: 'Math',
      inputs: [
        InputFieldDefinition(
          id: 'left',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.expression,
        ),
        InputFieldDefinition(
          id: 'right',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.expression,
        ),
      ],
    );
  }

  /// A random whole number between "from" and "to" (both included).
  static BlockDefinition mathRandomBlock() {
    return BlockDefinition(
      id: 'math_random',
      label: 'Random',
      emoji: '🎲',
      color: BlockColors.value,
      shape: BlockShape.expression,
      category: 'Math',
      inputs: [
        InputFieldDefinition(id: 'from', label: 'from', type: InputFieldType.number, defaultValue: 1),
        InputFieldDefinition(id: 'to', label: 'to', type: InputFieldType.number, defaultValue: 10),
      ],
    );
  }

  static BlockDefinition numberStaticBlock() {
    return BlockDefinition(
      id: 'math_number',
      label: 'Number',
      emoji: '#️⃣',
      color: BlockColors.value,
      shape: BlockShape.expression,
      category: 'Math',
      inputs: [
        InputFieldDefinition(
          id: 'value',
          label: '',
          type: InputFieldType.number,
          defaultValue: 90,
        ),
      ],
    );
  }
  
  static BlockDefinition actuatorBlock(ActuatorConfig actuator) {
    switch (actuator.type) {
      case ActuatorType.led:
        return _ledBlock(actuator);
      case ActuatorType.motor:
        return _motorBlock(actuator);
      case ActuatorType.servo:
        return actuator.isContinuous
            ? _continuousServoBlock(actuator)
            : _servoBlock(actuator);
      case ActuatorType.buzzer:
        return _buzzerBlock(actuator);
      case ActuatorType.switchPin:
        return _switchBlock(actuator);
    }
  }

  static BlockDefinition actuatorTrackingBlock(ActuatorConfig actuator) {
    if (actuator.type != ActuatorType.servo) return _servoTrackXBlock(actuator); // Fallback but won't be called
    return _servoTrackXBlock(actuator);
  }

  // Smart Follow — steers the first two configured motors toward the locked
  // target, one speed update per camera frame (see SmartFollowControl). Runs
  // inside the runner (no block interpretation) so it reacts within a frame.
  static BlockDefinition smartFollowBlock() {
    return BlockDefinition(
      id: 'act_smart_follow',
      label: 'Smart Follow',
      emoji: '🎯',
      color: BlockColors.action,
      shape: BlockShape.statement,
      category: 'Actuators',
      inputs: [
        InputFieldDefinition(
          id: 'mode',
          label: '',
          type: InputFieldType.dropdown,
          options: ['FETCH', 'FOLLOW'],
          defaultValue: 'FETCH',
        ),
        InputFieldDefinition(
          id: 'baseSpeed',
          label: 'base speed',
          type: InputFieldType.number,
          defaultValue: 150,
          min: 60,
          max: 255,
        ),
        InputFieldDefinition(
          id: 'minSpeed',
          label: 'min speed',
          type: InputFieldType.number,
          defaultValue: 100,
          min: 0,
          max: 255,
        ),
        InputFieldDefinition(
          id: 'arrivedPct',
          label: 'arrived %',
          type: InputFieldType.number,
          defaultValue: 30,
          min: 1,
          max: 100,
        ),
        InputFieldDefinition(
          id: 'steering',
          label: '',
          type: InputFieldType.dropdown,
          options: ['NORMAL', 'REVERSED'],
          defaultValue: 'NORMAL',
        ),
      ],
    );
  }

  static BlockDefinition _servoTrackXBlock(ActuatorConfig actuator) {
    return BlockDefinition(
      id: 'act_servo_track_x_${actuator.id}',
      label: 'Track X: ${actuator.name}',
      emoji: '👀',
      color: BlockColors.action,
      shape: BlockShape.statement,
      category: 'Actuators',
      inputs: [
        InputFieldDefinition(
          id: 'multiplier',
          label: 'speed multi',
          type: InputFieldType.number,
          defaultValue: 90,
          min: 1,
          max: 180,
        ),
      ],
    );
  }

  static BlockDefinition _ledBlock(ActuatorConfig actuator) {
    return BlockDefinition(
      id: 'act_led_${actuator.id}',
      label: actuator.name,
      emoji: actuator.type.emoji,
      color: BlockColors.action,
      shape: BlockShape.statement,
      category: 'Actuators',
      inputs: [
        InputFieldDefinition(
          id: 'state',
          label: '',
          type: InputFieldType.dropdown,
          options: ['ON', 'OFF', 'TOGGLE'],
          defaultValue: 'ON',
        ),
      ],
    );
  }

  static BlockDefinition _motorBlock(ActuatorConfig actuator) {
    return BlockDefinition(
      id: 'act_motor_${actuator.id}',
      label: actuator.name,
      emoji: actuator.type.emoji,
      color: BlockColors.action,
      shape: BlockShape.statement,
      category: 'Actuators',
      inputs: [
        InputFieldDefinition(
          id: 'direction',
          label: '',
          type: InputFieldType.dropdown,
          options: ['FORWARD', 'BACKWARD', 'STOP'],
          defaultValue: 'FORWARD',
        ),
        InputFieldDefinition(
          id: 'speed',
          label: 'speed',
          type: InputFieldType.number,
          defaultValue: 128,
          min: actuator.minSpeed,
          max: actuator.maxSpeed,
        ),
      ],
    );
  }

  static BlockDefinition _continuousServoBlock(ActuatorConfig actuator) {
    return BlockDefinition(
      id: 'act_servo_${actuator.id}',
      label: actuator.name,
      emoji: '🔄',
      color: BlockColors.action,
      shape: BlockShape.statement,
      category: 'Actuators',
      inputs: [
        InputFieldDefinition(
          id: 'direction',
          label: '',
          type: InputFieldType.dropdown,
          options: ['FORWARD', 'BACKWARD', 'STOP'],
          defaultValue: 'FORWARD',
        ),
        InputFieldDefinition(
          id: 'speed',
          label: 'speed %',
          type: InputFieldType.number,
          defaultValue: 75,
          min: 0,
          max: 100,
        ),
      ],
    );
  }

  static BlockDefinition _servoBlock(ActuatorConfig actuator) {
    return BlockDefinition(
      id: 'act_servo_${actuator.id}',
      label: actuator.name,
      emoji: actuator.type.emoji,
      color: BlockColors.action,
      shape: BlockShape.statement,
      category: 'Actuators',
      inputs: [
        InputFieldDefinition(
          id: 'angle',
          label: 'angle',
          type: InputFieldType.number,
          defaultValue: 90,
          min: actuator.minAngle,
          max: actuator.maxAngle,
          acceptedBlockShape: BlockShape.expression, // Accept expressions / numbers dynamically
        ),
      ],
    );
  }

  static BlockDefinition _buzzerBlock(ActuatorConfig actuator) {
    return BlockDefinition(
      id: 'act_buzzer_${actuator.id}',
      label: actuator.name,
      emoji: actuator.type.emoji,
      color: BlockColors.action,
      shape: BlockShape.statement,
      category: 'Actuators',
      inputs: [
        InputFieldDefinition(
          id: 'state',
          label: '',
          type: InputFieldType.dropdown,
          options: ['ON', 'OFF'],
          defaultValue: 'ON',
        ),
      ],
    );
  }

  static BlockDefinition _switchBlock(ActuatorConfig actuator) {
    return BlockDefinition(
      id: 'act_switch_${actuator.id}',
      label: actuator.name,
      emoji: actuator.type.emoji,
      color: BlockColors.action,
      shape: BlockShape.statement,
      category: 'Actuators',
      inputs: [
        InputFieldDefinition(
          id: 'state',
          label: '',
          type: InputFieldType.dropdown,
          options: ['ON', 'OFF'],
          defaultValue: 'ON',
        ),
      ],
    );
  }

  static List<BlockDefinition> getSensorBlocks() {
    return [
      objectDetectedBlock(),
      objectLockedBlock(),
      targetLockedBlock(),
      targetOffsetXBlock(),
      targetOffsetYBlock(),
      targetSizeBlock(),
      phoneShakeBlock(),
      phoneTiltBlock(),
      micLoudBlock(),
      voiceMatchBlock(),
      lineDetectedBlock(),
      lineOffsetXBlock(),
      isRotatingBlock(),
      rotationRateBlock(),
      tiltAngleXBlock(),
      tiltAngleYBlock(),
      compassHeadingBlock(),
      facingDirectionBlock(),
    ];
  }

  static List<BlockDefinition> getLogicBlocks() {
    return [
      ifBlock(),
      ifElseBlock(),
      foreverBlock(),
      whileBlock(),
      repeatBlock(),
      repeatUntilBlock(),
      waitBlock(),
      trueBlock(),
      falseBlock(),
      andBlock(),
      orBlock(),
      notBlock(),
      printBlock(),
      sayBlock(),
      stopProgramBlock(),
      customExpressionBlock(),
    ];
  }

  /// Every non-actuator definition, used to resolve saved scripts.
  static List<BlockDefinition> getAllStaticBlocks() => [
        ...getSensorBlocks(),
        ...getLogicBlocks(),
        ...getMathBlocks(),
        smartFollowBlock(),
      ];

  static List<BlockDefinition> getMathBlocks() {
    return [
      numberStaticBlock(),
      mathRandomBlock(),
      mathAddBlock(),
      mathSubtractBlock(),
      mathMultiplyBlock(),
      mathDivideBlock(),
      mathLessThanBlock(),
      mathGreaterThanBlock(),
      mathEqualsBlock(),
    ];
  }

  static BlockDefinition trueBlock() {
    return BlockDefinition(
      id: 'bool_true',
      label: 'True',
      emoji: '✅',
      color: BlockColors.boolean,
      shape: BlockShape.boolean,
      category: 'Logic',
    );
  }

  static BlockDefinition falseBlock() {
    return BlockDefinition(
      id: 'bool_false',
      label: 'False',
      emoji: '❌',
      color: BlockColors.boolean,
      shape: BlockShape.boolean,
      category: 'Logic',
    );
  }

  static BlockDefinition printBlock() {
    return BlockDefinition(
      id: 'act_print',
      label: 'Print to Log',
      emoji: '🖨️',
      color: BlockColors.action,
      shape: BlockShape.statement,
      category: 'Logic',
      inputs: [
        InputFieldDefinition(
          id: 'value',
          label: '',
          type: InputFieldType.blockSocket,
          acceptedBlockShape: BlockShape.expression,
        ),
      ],
    );
  }
}
