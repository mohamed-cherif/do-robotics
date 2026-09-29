import 'package:flutter_test/flutter_test.dart';
import 'package:do_robotics/logic/block_script_runner.dart';
import 'package:do_robotics/models/block_factory.dart';
import 'package:do_robotics/models/block_models.dart';

BlockInstance _b(String defId, {Map<String, BlockInstance?>? nested, BlockInstance? next}) {
  final def = BlockFactory.getAllStaticBlocks().firstWhere((d) => d.id == defId);
  return BlockInstance(instanceId: defId, definition: def, nestedBlocks: nested, nextBlock: next);
}

void main() {
  group('ScriptUtils.matchesPhrase', () {
    test('matches whole words only', () {
      expect(ScriptUtils.matchesPhrase('please stop now', 'stop'), isTrue);
      expect(ScriptUtils.matchesPhrase('start the stopwatch', 'stop'), isFalse);
    });

    test('ignores case and punctuation', () {
      expect(ScriptUtils.matchesPhrase('Go, Forward!', 'go forward'), isTrue);
    });

    test('multi-word phrases must appear in order', () {
      expect(ScriptUtils.matchesPhrase('turn left please', 'turn left'), isTrue);
      expect(ScriptUtils.matchesPhrase('left turn please', 'turn left'), isFalse);
    });

    test('empty input never matches', () {
      expect(ScriptUtils.matchesPhrase('', 'go'), isFalse);
      expect(ScriptUtils.matchesPhrase('go', ''), isFalse);
    });
  });

  group('ScriptUtils numeric parsing', () {
    test('accepts num, numeric strings, falls back otherwise', () {
      expect(ScriptUtils.toDouble(2, 0), 2.0);
      expect(ScriptUtils.toDouble('0.5', 0), 0.5);
      expect(ScriptUtils.toDouble('abc', 7), 7.0);
      expect(ScriptUtils.toDouble(null, 3), 3.0);
      expect(ScriptUtils.toInt('12', 0), 12);
    });
  });

  group('ScriptUtils tree scanning', () {
    test('finds line-following blocks nested inside loops', () {
      // while(true) { while(line detected) { ... } }
      final inner = _b('logic_while', nested: {'condition': _b('sense_line_detected')});
      final outer = _b('logic_while', nested: {'condition': _b('bool_true'), 'do': inner});
      expect(ScriptUtils.usesLineFollowing([outer]), isTrue);
      expect(ScriptUtils.usesVision([outer]), isTrue);
      expect(ScriptUtils.usesVoice([outer]), isFalse);
    });

    test('finds voice blocks along the next-chain', () {
      final say = _b('act_say');
      final wait = _b('logic_wait', next: say);
      final ifVoice = _b('logic_if', nested: {'condition': _b('sense_voice')}, next: wait);
      expect(ScriptUtils.usesVoice([ifVoice]), isTrue);
      expect(ScriptUtils.usesSpeech([ifVoice]), isTrue);
      expect(ScriptUtils.usesVision([ifVoice]), isFalse);
    });
  });
}
