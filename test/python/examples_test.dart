import 'package:do_robotics/logic/code_generator.dart';
import 'package:do_robotics/logic/python_script_runner.dart';
import 'package:do_robotics/models/actuator_config.dart';
import 'package:do_robotics/models/block_factory.dart';
import 'package:do_robotics/models/block_models.dart';
import 'package:do_robotics/models/block_snippets.dart';
import 'package:do_robotics/ui/python_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every built-in Python example parses', () {
    final sources = pythonExampleSources();
    expect(sources, isNotEmpty);
    for (final src in sources) {
      expect(PythonScriptRunner.check(src), isNull, reason: src);
    }
  });

  group('Python examples are the block snippets', () {
    final motors = [
      for (final name in ['Left Wheel', 'Right Wheel'])
        BlockFactory.actuatorBlock(ActuatorConfig(
            id: name.toLowerCase().replaceAll(' ', '_'), name: name, type: ActuatorType.motor, pin: 0)),
    ];
    final defs = [...BlockFactory.getAllStaticBlocks(), ...motors];
    final snippets = blockSnippets(defs, motors);

    test('there is one Python example per snippet, with the same code', () {
      final sources = pythonExampleSources();
      for (final s in snippets) {
        final code = CodeGenerator.generateCode(s.build());
        expect(sources.where((src) => src.contains('Blocks › ⚡ Snippets › ${s.name}.')).length, 1,
            reason: s.name);
        expect(sources.any((src) => src.endsWith(code)), isTrue, reason: '${s.name}: same program');
      }
    });

    test('every snippet converts completely (no block left as a comment)', () {
      final labels = defs.map((BlockDefinition d) => '# ${d.label}').toSet();
      for (final s in snippets) {
        final code = CodeGenerator.generateCode(s.build());
        final leftovers = code.split('\n').map((l) => l.trim()).where(labels.contains).toList();
        expect(leftovers, isEmpty, reason: '${s.name} has unconverted blocks: $leftovers');
      }
    });
  });
}
