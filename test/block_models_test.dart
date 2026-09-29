import 'package:flutter_test/flutter_test.dart';
import 'package:do_robotics/logic/code_generator.dart';
import 'package:do_robotics/models/block_factory.dart';
import 'package:do_robotics/models/block_models.dart';
import 'package:do_robotics/python/parser.dart';

void main() {
  final defs = BlockFactory.getAllStaticBlocks();
  BlockDefinition def(String id) => defs.firstWhere((d) => d.id == id);

  group('BlockInstance JSON', () {
    test('round-trips nested blocks, next chain, inputs and position', () {
      final script = [
        BlockInstance(
          instanceId: 'w1',
          definition: def('logic_while'),
          position: const Offset(10, 20),
          nestedBlocks: {
            'condition': BlockInstance(instanceId: 'c1', definition: def('bool_true')),
            'do': BlockInstance(
              instanceId: 'if1',
              definition: def('logic_if_else'),
              nestedBlocks: {
                'condition': BlockInstance(
                  instanceId: 'v1',
                  definition: def('sense_voice'),
                  inputValues: {'phrase': 'go'},
                ),
                'then': BlockInstance(
                  instanceId: 's1',
                  definition: def('act_say'),
                  inputValues: {'text': 'going'},
                ),
              },
              nextBlock: BlockInstance(
                instanceId: 'wait1',
                definition: def('logic_wait'),
                inputValues: {'seconds': 0.5},
              ),
            ),
          },
        ),
      ];

      final json = BlockInstance.listToJson(script);
      final restored = BlockInstance.listFromJson(json, defs);

      expect(restored, hasLength(1));
      final w = restored.first;
      expect(w.definition.id, 'logic_while');
      expect(w.position, const Offset(10, 20));
      expect(w.nestedBlocks['condition']!.definition.id, 'bool_true');
      final ifElse = w.nestedBlocks['do']!;
      expect(ifElse.definition.id, 'logic_if_else');
      expect(ifElse.nestedBlocks['condition']!.inputValues['phrase'], 'go');
      expect(ifElse.nestedBlocks['then']!.inputValues['text'], 'going');
      expect(ifElse.nestedBlocks['else'], isNull);
      expect(ifElse.nextBlock!.inputValues['seconds'], 0.5);
    });

    test('drops blocks whose definition no longer exists (deleted actuator)', () {
      final json = '[{"instanceId":"x","definitionId":"act_motor_deleted","inputValues":{},'
          '"nestedBlocks":{},"nextBlock":null,"position":{"dx":0,"dy":0}}]';
      expect(BlockInstance.listFromJson(json, defs), isEmpty);
    });
  });

  group('BlockFactory', () {
    test('block ids are unique', () {
      final ids = defs.map((d) => d.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('CodeGenerator', () {
    test('renders if/else, say and stop as runnable RoboPython', () {
      final script = [
        BlockInstance(
          instanceId: 'if1',
          definition: def('logic_if_else'),
          nestedBlocks: {
            'condition': BlockInstance(instanceId: 'l', definition: def('sense_loud')),
            'then': BlockInstance(
                instanceId: 's', definition: def('act_say'), inputValues: {'text': 'hi'}),
            'else': BlockInstance(instanceId: 'st', definition: def('logic_stop')),
          },
        ),
      ];
      final code = CodeGenerator.generateCode(script);
      expect(code, startsWith('import robot'));
      expect(code, contains("if robot.mic.loud:"));
      expect(code, contains("    robot.say('hi')"));
      expect(code, contains("else:"));
      expect(code, contains("    robot.stop()"));
      expect(Parser.parse(code), isNotNull); // it parses as RoboPython
    });

    test('declares actuator variables once and drives them', () {
      final motor = BlockDefinition(
        id: 'act_motor_abc',
        label: 'Left Wheel',
        emoji: '⚙️',
        color: BlockColors.action,
        shape: BlockShape.statement,
        inputs: [
          InputFieldDefinition(id: 'direction', label: '', type: InputFieldType.dropdown, options: ['FORWARD', 'BACKWARD', 'STOP']),
          InputFieldDefinition(id: 'speed', label: 'speed', type: InputFieldType.number),
        ],
      );
      final fwd = BlockInstance(instanceId: 'a', definition: motor, inputValues: {'direction': 'FORWARD', 'speed': 200});
      final stop = BlockInstance(instanceId: 'b', definition: motor, inputValues: {'direction': 'STOP'});
      final wait = BlockInstance(instanceId: 'w', definition: def('logic_wait'), inputValues: {'seconds': 0.5}, nextBlock: stop);
      fwd.nextBlock = wait;
      final loop = BlockInstance(
        instanceId: 'loop',
        definition: def('logic_while'),
        nestedBlocks: {'condition': BlockInstance(instanceId: 't', definition: def('bool_true')), 'do': fwd},
      );
      final code = CodeGenerator.generateCode([loop]);
      expect('left_wheel = robot.motor(\'Left Wheel\')'.allMatches(code).length, 1);
      expect(code, contains('while True:\n    left_wheel.forward(200)\n    robot.wait(0.5)\n    left_wheel.stop()\n    robot.wait(0.02)'));
      expect(Parser.parse(code), isNotNull);
    });
  });

  group('BlockInstance.containsInstance (editor cycle guard)', () {
    test('finds the block itself, nested blocks and the next chain', () {
      final inner = BlockInstance(instanceId: 'w', definition: def('logic_wait'));
      final ifBlock = BlockInstance(
        instanceId: 'if',
        definition: def('logic_if'),
        nestedBlocks: {'then': inner},
      );
      final after = BlockInstance(instanceId: 'after', definition: def('logic_wait'));
      final loop = BlockInstance(
        instanceId: 'loop',
        definition: def('logic_while'),
        nestedBlocks: {'do': ifBlock},
        nextBlock: after,
      );
      // Dropping `loop` into any of these would put it inside itself.
      expect(loop.containsInstance(loop), isTrue);
      expect(loop.containsInstance(ifBlock), isTrue);
      expect(loop.containsInstance(inner), isTrue);
      expect(loop.containsInstance(after), isTrue);
      // ...but a child may be moved out into an unrelated block.
      final other = BlockInstance(instanceId: 'other', definition: def('logic_if'));
      expect(loop.containsInstance(other), isFalse);
      expect(inner.containsInstance(loop), isFalse);
    });
  });
}
