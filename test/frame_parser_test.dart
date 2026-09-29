import 'package:flutter_test/flutter_test.dart';
import 'package:do_robotics/services/connectivity/frame_parser.dart';
import 'package:do_robotics/services/connectivity/robot_protocol.dart';

void main() {
  late List<ControlFrame> control;
  late List<TextFrame> text;
  late FrameParser parser;

  setUp(() {
    control = [];
    text = [];
    parser = FrameParser(onControl: control.add, onText: text.add);
  });

  test('decodes control packets and text frames from one stream', () {
    parser.feed([
      ...RobotProtocol.buildPacket(RobotProtocol.cmdDigitalWrite, 13, 1),
      ...FrameParser.encodeText('HELLO\tesp32\t2.0'),
    ]);
    expect(control.single.toString(), 'ControlFrame(cmd=1 pin=13 value=1)');
    expect(text.single.fields, ['HELLO', 'esp32', '2.0']);
    expect(text.single.command, 'HELLO');
  });

  test('handles frames split across reads and garbage between them', () {
    final frame = FrameParser.encodeText('STATUS\tsta=off');
    parser.feed([0x00, 0x11, ...frame.sublist(0, 4)]);
    expect(text, isEmpty);
    parser.feed([...frame.sublist(4), 0xFF, 0xAB, 200 /* bad len */, ...frame]);
    expect(text.map((t) => t.text), ['STATUS\tsta=off', 'STATUS\tsta=off']);
  });

  test('drops frames with a bad checksum and resynchronizes', () {
    final bad = FrameParser.encodeText('OK');
    bad[bad.length - 1] ^= 0x01;
    parser.feed([...bad, ...RobotProtocol.heartbeatPacket]);
    expect(text, isEmpty);
    expect(control.single.cmd, RobotProtocol.cmdHeartbeat);
  });

  test('encodeText refuses oversized frames', () {
    expect(() => FrameParser.encodeText('x' * 121), throwsArgumentError);
    expect(FrameParser.encodeText(''), [0xAB, 0, 0xAB]);
  });
}
