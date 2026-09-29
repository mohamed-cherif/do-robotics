import 'dart:convert';
import 'dart:typed_data';
import 'robot_protocol.dart';

/// A decoded control packet (0xAA).
class ControlFrame {
  final int cmd, pin, value;
  const ControlFrame(this.cmd, this.pin, this.value);
  @override
  String toString() => 'ControlFrame(cmd=$cmd pin=$pin value=$value)';
}

/// A decoded text frame (0xAB).
class TextFrame {
  final String text;
  const TextFrame(this.text);
  List<String> get fields => text.split('\t');
  String get command => fields.first;
  @override
  String toString() => 'TextFrame($text)';
}

/// Incremental parser for the byte stream coming back from the board.
/// Mirrors the firmware `FrameParser`: dispatches on the header byte and
/// silently resynchronizes on garbage or checksum failures.
class FrameParser {
  static const int textHeader = 0xAB;
  static const int maxTextLen = 120;

  int _state = 0; // 0 header, 1..3 control bytes, 4 control ck, 5 text len, 6 text body, 7 text ck
  int _cmd = 0, _pin = 0, _val = 0;
  int _len = 0, _sum = 0;
  final List<int> _buf = [];

  final void Function(ControlFrame) onControl;
  final void Function(TextFrame) onText;

  FrameParser({required this.onControl, required this.onText});

  void reset() {
    _state = 0;
    _buf.clear();
  }

  void feed(List<int> bytes) {
    for (final b in bytes) {
      _feedByte(b & 0xFF);
    }
  }

  void _feedByte(int b) {
    switch (_state) {
      case 0:
        if (b == RobotProtocol.header) {
          _state = 1;
        } else if (b == textHeader) {
          _sum = b;
          _state = 5;
        }
        break;
      case 1:
        _cmd = b;
        _state = 2;
        break;
      case 2:
        _pin = b;
        _state = 3;
        break;
      case 3:
        _val = b;
        _state = 4;
        break;
      case 4:
        if (b == RobotProtocol.checksum(_cmd, _pin, _val)) {
          onControl(ControlFrame(_cmd, _pin, _val));
        }
        _state = 0;
        break;
      case 5:
        if (b > maxTextLen) {
          _state = 0;
          break;
        }
        _len = b;
        _sum = (_sum + b) & 0xFF;
        _buf.clear();
        _state = _len == 0 ? 7 : 6;
        break;
      case 6:
        _buf.add(b);
        _sum = (_sum + b) & 0xFF;
        if (_buf.length >= _len) _state = 7;
        break;
      case 7:
        if (b == _sum) {
          onText(TextFrame(utf8.decode(_buf, allowMalformed: true)));
        }
        _state = 0;
        break;
    }
  }

  /// Encodes a text frame: [0xAB][LEN][bytes][CK].
  static Uint8List encodeText(String text) {
    final bytes = utf8.encode(text);
    if (bytes.length > maxTextLen) {
      throw ArgumentError('text frame too long (${bytes.length} > $maxTextLen bytes)');
    }
    int sum = textHeader + bytes.length;
    for (final b in bytes) {
      sum += b;
    }
    return Uint8List.fromList([textHeader, bytes.length, ...bytes, sum & 0xFF]);
  }
}
