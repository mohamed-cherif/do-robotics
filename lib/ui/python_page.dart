import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/block_script_runner.dart' show ExecutionState;
import '../logic/code_generator.dart';
import '../logic/python_script_runner.dart';
import '../models/actuator_config.dart';
import '../models/block_factory.dart';
import '../models/block_snippets.dart';
import '../services/actuator_service.dart';
import '../services/python_script_store.dart';
import '../utils/execution_logger.dart';
import 'python_bus.dart';

// ── Palette (shared with LogicPage) ──────────────────────────────────────────
const Color _kIndigo = Color(0xFF6366F1);
const Color _kViolet = Color(0xFF8B5CF6);
const Color _kInk = Color(0xFF1F2937);
const Color _kMuted = Color(0xFF9CA3AF);
const Color _kGreen = Color(0xFF10B981);
const Color _kBackground = Color(0xFFF5F7FA);
const Color _kConsoleBg = Color(0xFF111827);
const Color _kConsoleText = Color(0xFFE5E7EB);

// ── Editor metrics ───────────────────────────────────────────────────────────
const String _kMonoFamily = 'monospace';
const double _kFontSize = 13.5;
const double _kLineHeightFactor = 1.5;
const double _kLineHeight = _kFontSize * _kLineHeightFactor;
const double _kEditorPadTop = 12;
const double _kEditorPadBottom = 120; // room to type past the FAB
const double _kGutterWidth = 44;

const TextStyle _kEditorStyle = TextStyle(
  fontFamily: _kMonoFamily,
  fontSize: _kFontSize,
  height: _kLineHeightFactor,
  color: _kInk,
);

const StrutStyle _kEditorStrut = StrutStyle(
  fontFamily: _kMonoFamily,
  fontSize: _kFontSize,
  height: _kLineHeightFactor,
  forceStrutHeight: true,
);

// ── Syntax highlighting controller ───────────────────────────────────────────

/// TextEditingController that colours RoboPython tokens line by line.
class _PyHighlightController extends TextEditingController {
  _PyHighlightController();

  static const Set<String> _keywords = {
    'if', 'elif', 'else', 'while', 'for', 'in', 'def', 'return', 'break',
    'continue', 'pass', 'and', 'or', 'not', 'True', 'False', 'None', 'import',
    'from', 'global', 'lambda',
  };
  static const Set<String> _apiNames = {'robot', 'time', 'math', 'random'};

  static const TextStyle _keywordStyle =
      TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.w600);
  static const TextStyle _stringStyle = TextStyle(color: Color(0xFF059669));
  static const TextStyle _numberStyle = TextStyle(color: Color(0xFF2563EB));
  static const TextStyle _commentStyle =
      TextStyle(color: Color(0xFF9CA3AF), fontStyle: FontStyle.italic);
  static const TextStyle _apiStyle =
      TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold);

  // Group 1 comment, 2 double-quoted string, 3 single-quoted string,
  // 4 number, 5 identifier. Strings match to end of line when unterminated.
  static final RegExp _tokenRe = RegExp(
    r'(#.*)'
    r'|([fFrRbB]?"(?:[^"\\]|\\.)*(?:"|$))'
    r"|([fFrRbB]?'(?:[^'\\]|\\.)*(?:'|$))"
    r'|(\b\d+(?:\.\d*)?(?:[eE][+-]?\d+)?\b|\B\.\d+\b)'
    r'|\b([A-Za-z_][A-Za-z0-9_]*)\b',
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? _kEditorStyle;
    final lines = text.split('\n');
    final spans = <TextSpan>[];
    for (int i = 0; i < lines.length; i++) {
      _highlightLine(lines[i], base, spans);
      if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    return TextSpan(style: base, children: spans);
  }

  static void _highlightLine(String line, TextStyle base, List<TextSpan> out) {
    int last = 0;
    for (final m in _tokenRe.allMatches(line)) {
      if (m.start > last) out.add(TextSpan(text: line.substring(last, m.start)));
      final tok = m[0]!;
      TextStyle? s;
      if (m[1] != null) {
        s = _commentStyle;
      } else if (m[2] != null || m[3] != null) {
        s = _stringStyle;
      } else if (m[4] != null) {
        s = _numberStyle;
      } else if (m[5] != null) {
        if (_keywords.contains(tok)) {
          s = _keywordStyle;
        } else if (_apiNames.contains(tok)) {
          s = _apiStyle;
        }
      }
      out.add(TextSpan(text: tok, style: s == null ? null : base.merge(s)));
      last = m.end;
    }
    if (last < line.length) out.add(TextSpan(text: line.substring(last)));
  }
}

// ── Example programs ─────────────────────────────────────────────────────────

class _Example {
  final String title;
  final String description;
  final IconData icon;
  final String source;
  const _Example(this.title, this.description, this.icon, this.source);
}

/// Source of every built-in example, for tests (they must parse).
@visibleForTesting
List<String> pythonExampleSources() => _buildExamples().map((e) => e.source).toList();

String _pyStr(String s) => '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

List<_Example> _buildExamples() {
  final actuators = ActuatorService().actuators;
  final leds = actuators.where((a) => a.type == ActuatorType.led).toList();
  final ledName = leds.isNotEmpty ? leds[0].name : 'Headlight';
  final led = _pyStr(ledName);

  return [
    _Example(
      'Hello robot',
      'Says hello and blinks an LED three times.',
      Icons.waving_hand_outlined,
      '''
# Hello robot: says hello, then blinks the LED three times.
# Setup: connect the robot and add an LED named $led in the Actuators tab.
import robot

led = robot.led($led)

robot.say("Hello")
for i in range(3):
    led.on()
    robot.wait(0.3)
    led.off()
    robot.wait(0.3)
print("Done")
''',
    ),
    // The rest are the block snippets, converted: the same programs as
    // Blocks › ⚡ Snippets, ready to edit.
    for (final snippet in _snippetsForPython(actuators))
      _Example(
        snippet.name,
        snippet.description,
        _snippetIcons[snippet.name] ?? Icons.extension_outlined,
        _snippetSource(snippet),
      ),
  ];
}

/// Block snippets built with the configured motors, or with placeholder
/// "Left Wheel" / "Right Wheel" motors when fewer than two are set up (the
/// example then shows which names to configure).
List<BlockSnippet> _snippetsForPython(List<ActuatorConfig> actuators) {
  var motors = actuators.where((a) => a.type == ActuatorType.motor).toList();
  if (motors.length < 2) {
    motors = [
      ActuatorConfig(id: 'example_left', name: 'Left Wheel', type: ActuatorType.motor, pin: 0),
      ActuatorConfig(id: 'example_right', name: 'Right Wheel', type: ActuatorType.motor, pin: 0),
    ];
  }
  final motorDefs = [for (final m in motors) BlockFactory.actuatorBlock(m)];
  final defs = [...BlockFactory.getAllStaticBlocks(), ...motorDefs];
  return blockSnippets(defs, motorDefs);
}

String _snippetSource(BlockSnippet snippet) {
  final header = StringBuffer()
    ..writeln('# ${snippet.name}: the same program as Blocks › ⚡ Snippets › ${snippet.name}.')
    ..writeln('# Change anything below; this copy is yours.');
  // Wrap the description into comment lines of at most ~76 characters.
  var line = '#';
  for (final word in snippet.description.split(' ')) {
    if (line.length + word.length + 1 > 76) {
      header.writeln(line);
      line = '#';
    }
    line += ' $word';
  }
  if (line != '#') header.writeln(line);
  return '$header\n${CodeGenerator.generateCode(snippet.build())}';
}

const Map<String, IconData> _snippetIcons = {
  'Motor Forward Test': Icons.settings_outlined,
  'Pivot Left Test': Icons.turn_left,
  'Pivot Right Test': Icons.turn_right,
  'Person Follower': Icons.directions_walk,
  'Voice Control': Icons.mic_none,
  'Fetch Bot': Icons.sports_baseball_outlined,
  'Line Follower': Icons.timeline,
  'Tilt Steering': Icons.screen_rotation_outlined,
  'Compass Patrol': Icons.explore_outlined,
};

const String _kApiReference = '''
RoboPython API reference

import robot, time

left  = robot.motor("Left Wheel")     # by configured actuator name
right = robot.motor("Right Wheel")
led   = robot.led("Headlight")
buzz  = robot.buzzer("Buzzer")
sw    = robot.switch("Relay")
arm   = robot.servo("Arm")

left.forward(200); left.backward(150); left.stop()   # speed 0-255
arm.angle(90)                                        # positional servo
arm.forward(75); arm.backward(40); arm.stop()        # continuous servo, %
led.on(); led.off(); led.toggle()                    # led / buzzer / switch

robot.vision.detected        # bool - any object in the current frame
robot.vision.lock("person")  # bool - lock on the most confident "person"
robot.vision.locked          # bool
robot.vision.label           # str  - label of the locked object
robot.vision.offset_x        # -1..1 (left..right)
robot.vision.offset_y        # -1..1 (top..bottom)
robot.vision.size            # 0..100 - % of frame, a closeness proxy
robot.vision.objects         # list of labels in frame
robot.vision.line_visible    # bool  (line-following mode)
robot.vision.line_offset     # -1..1
robot.vision.unlock()

robot.imu.pitch, robot.imu.roll        # degrees
robot.imu.yaw_rate                     # deg/s
robot.imu.shaking, robot.imu.tilted, robot.imu.spinning
robot.compass.heading                  # 0..360
robot.compass.facing("North")          # or degrees; +/-22.5 deg
robot.mic.loud                         # bool
robot.mic.heard("go forward")          # bool, consumes the phrase
robot.mic.words                        # last recognized text

robot.say("Hello")                     # text-to-speech (blocks until spoken)
robot.wait(0.5)                        # same as time.sleep
robot.stop_all()                       # every actuator off
robot.pin.digital(13, 1)               # raw pin control
robot.pin.pwm(9, 128)
robot.pin.servo(5, 90)
robot.connected                        # bool

Motors, servos and LEDs resolve by actuator name (case-insensitive) or id.
An unknown name is a runtime error that lists the configured actuators.
The camera starts on first robot.vision access (line mode when line_visible
or line_offset is used); the microphone on first robot.mic access.

Language subset
  Literals   int, float, str, f"{x:.2f}", True False None, lists [...]
  Operators  + - * / // % **, not, and, or, < <= > >= == !=, in, not in,
             a if c else b
  Statements x = 1, += -= *= /=, if/elif/else, while, for x in ...,
             def f(a, b=1):, return, break, continue, pass, global,
             import robot | time | math
  Builtins   print len range abs min max int float str bool round list
             sum enumerate
  Methods    str: lower upper strip split startswith endswith replace
             list: append pop insert remove index count
  Modules    time.sleep(s), time.time(), math.sqrt sin cos atan2 pi floor ceil
  Errors     reported as "line N: message" in the console; the program stops.
''';

// ── Page ─────────────────────────────────────────────────────────────────────

class PythonPage extends StatefulWidget {
  const PythonPage({super.key});

  @override
  State<PythonPage> createState() => _PythonPageState();
}

class _PythonPageState extends State<PythonPage> {
  final _PyHighlightController _controller = _PyHighlightController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _vScroll = ScrollController();
  final ScrollController _hScroll = ScrollController();
  final ScrollController _consoleScroll = ScrollController();

  final PythonScriptRunner _runner = PythonScriptRunner();
  final PythonScriptStore _store = PythonScriptStore();
  final ExecutionLogger _logger = ExecutionLogger();

  StreamSubscription<ExecutionState>? _stateSub;
  StreamSubscription<int>? _lineSub;
  StreamSubscription<void>? _logSub;
  Timer? _draftTimer;

  ExecutionState _state = ExecutionState.idle;
  int _execLine = -1;
  int _lineCount = 1;
  int _longestLine = 0;
  bool _consoleOpen = true;
  bool _pristineExample = false; // editor holds the untouched default example
  String? _currentName;
  String _lastText = '';
  List<String> _logs = const [];

  @override
  void initState() {
    super.initState();
    _state = _runner.state;
    _logs = _logger.logs;
    _focusNode.onKeyEvent = _handleKey;
    _controller.addListener(_onTextChanged);

    _stateSub = _runner.stateStream.listen((s) {
      if (!mounted) return;
      setState(() {
        _state = s;
        if (s == ExecutionState.idle) _execLine = -1;
      });
    });
    _lineSub = _runner.lineStream.listen((line) {
      if (!mounted) return;
      setState(() => _execLine = line);
      if (line > 0) _revealLine(line);
    });
    _logSub = _logger.onChange.listen((_) {
      if (!mounted) return;
      setState(() => _logs = _logger.logs);
      _scrollConsoleToEnd();
    });

    PythonBus.incomingSource.addListener(_onIncomingSource);
    _loadInitial();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _stateSub?.cancel();
    _lineSub?.cancel();
    _logSub?.cancel();
    PythonBus.incomingSource.removeListener(_onIncomingSource);
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _vScroll.dispose();
    _hScroll.dispose();
    _consoleScroll.dispose();
    super.dispose();
  }

  // ── Loading / persistence ──────────────────────────────────────────────────

  Future<void> _loadInitial() async {
    final draft = await _store.loadDraft();
    if (!mounted) return;
    if (draft == null || draft.trim().isEmpty) {
      _setText(_buildExamples().first.source, name: 'Hello robot');
      _pristineExample = true;
    } else {
      _setText(draft);
    }
    // A conversion may already be waiting (e.g. pushed before first build).
    if (PythonBus.incomingSource.value != null) _onIncomingSource();
  }

  /// Replaces the editor content without asking.
  void _setText(String source, {String? name}) {
    _lastText = source;
    _controller.value = TextEditingValue(
      text: source,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _pristineExample = false;
    if (name != null) _currentName = name;
    _recomputeMetrics();
    _scheduleDraftSave();
    if (_vScroll.hasClients) _vScroll.jumpTo(0);
    if (_hScroll.hasClients) _hScroll.jumpTo(0);
    setState(() {});
  }

  /// Replaces the editor content, asking first when it would discard work.
  Future<void> _offerText(String source, {String? name}) async {
    final current = _controller.text;
    final needsConfirm =
        current.trim().isNotEmpty && current != source && !_pristineExample;
    if (needsConfirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Replace current code?'),
          content: const Text(
              'The code in the editor will be replaced. Save it first if you want to keep it.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Replace')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _setText(source, name: name);
  }

  void _onIncomingSource() {
    final src = PythonBus.incomingSource.value;
    if (src == null || !mounted) return;
    PythonBus.incomingSource.value = null;
    _offerText(src);
  }

  void _scheduleDraftSave() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 800), () {
      _store.saveDraft(_controller.text);
    });
  }

  // ── Editing helpers ────────────────────────────────────────────────────────

  void _recomputeMetrics() {
    final lines = _controller.text.split('\n');
    _lineCount = lines.length;
    int longest = 0;
    for (final l in lines) {
      if (l.length > longest) longest = l.length;
    }
    _longestLine = longest;
  }

  void _onTextChanged() {
    final text = _controller.text;
    if (text == _lastText) return; // selection-only change
    final old = _lastText;
    _lastText = text;
    _pristineExample = false;
    _autoIndentAfterNewline(old, text);
    _lastText = _controller.text;
    _recomputeMetrics();
    _scheduleDraftSave();
    setState(() {});
  }

  /// When exactly one '\n' was inserted at the caret, copy the previous line's
  /// indentation (plus four spaces after a ':').
  void _autoIndentAfterNewline(String old, String text) {
    final sel = _controller.selection;
    if (!sel.isValid || !sel.isCollapsed) return;
    final caret = sel.baseOffset;
    if (text.length != old.length + 1 || caret < 1 || caret > text.length) return;
    if (text[caret - 1] != '\n') return;
    if (text.substring(0, caret - 1) != old.substring(0, caret - 1)) return;
    if (text.substring(caret) != old.substring(caret - 1)) return;

    final prevStart = text.lastIndexOf('\n', caret - 2) + 1;
    final prevLine = text.substring(prevStart, caret - 1);
    final ws = RegExp(r'^[ \t]*').firstMatch(prevLine)?[0] ?? '';
    final code = prevLine.replaceFirst(RegExp(r'#.*$'), '').trimRight();
    final indent = code.endsWith(':') ? '$ws    ' : ws;
    if (indent.isEmpty) return;
    _controller.value = TextEditingValue(
      text: text.substring(0, caret) + indent + text.substring(caret),
      selection: TextSelection.collapsed(offset: caret + indent.length),
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _insertAtCursor('    ');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Inserts [snippet] replacing the selection; the caret lands at
  /// [cursorOffset] characters into the snippet (end by default).
  void _insertAtCursor(String snippet, {int? cursorOffset}) {
    final value = _controller.value;
    final text = value.text;
    var sel = value.selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: text.length);
    final start = math.min(sel.start, sel.end);
    final end = math.max(sel.start, sel.end);
    final newText = text.replaceRange(start, end, snippet);
    final caret = start + (cursorOffset ?? snippet.length);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: caret),
    );
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
  }

  void _moveCursorToLine(int line) {
    final lines = _controller.text.split('\n');
    final target = line.clamp(1, lines.length);
    int offset = 0;
    for (int i = 0; i < target - 1; i++) {
      offset += lines[i].length + 1;
    }
    _controller.selection = TextSelection.collapsed(offset: offset);
    _focusNode.requestFocus();
    _revealLine(target);
  }

  void _revealLine(int line) {
    if (!_vScroll.hasClients) return;
    final pos = _vScroll.position;
    final top = _kEditorPadTop + (line - 1) * _kLineHeight;
    final bottom = top + _kLineHeight;
    final viewTop = pos.pixels;
    final viewBottom = viewTop + pos.viewportDimension;
    double? target;
    if (top < viewTop) {
      target = top - _kLineHeight;
    } else if (bottom > viewBottom) {
      target = bottom - pos.viewportDimension + _kLineHeight * 2;
    }
    if (target == null) return;
    _vScroll.animateTo(
      target.clamp(0.0, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  void _scrollConsoleToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_consoleScroll.hasClients) return;
      _consoleScroll.jumpTo(_consoleScroll.position.maxScrollExtent);
    });
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _snack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ));
  }

  /// Returns true when the source parses. Otherwise reports the error and
  /// moves the caret to the offending line.
  bool _check({bool quiet = false}) {
    final error = PythonScriptRunner.check(_controller.text);
    if (error == null) {
      if (!quiet) _snack('No syntax errors', color: _kGreen);
      return true;
    }
    _snack(error, color: Colors.red.shade700);
    final m = RegExp(r'line (\d+)').firstMatch(error);
    if (m != null) _moveCursorToLine(int.parse(m[1]!));
    return false;
  }

  void _toggleRun() {
    if (_state == ExecutionState.running) {
      _runner.stop();
      return;
    }
    if (_controller.text.trim().isEmpty) return;
    if (!_check(quiet: true)) return;
    _focusNode.unfocus();
    setState(() => _consoleOpen = true);
    _runner.run(_controller.text);
  }

  void _clearEditor() {
    if (_controller.text.trim().isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear editor?'),
        content: const Text('All code in the editor will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _setText('');
              _currentName = null;
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showSaveDialog() {
    final nameCtrl = TextEditingController(text: _currentName ?? 'My Program');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Program'),
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
              await _store.save(name, _controller.text);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              setState(() => _currentName = name);
              _snack('Saved "$name"');
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLoadDialog() async {
    final names = await _store.listNames();
    if (!mounted) return;
    if (names.isEmpty) {
      _snack('No saved programs yet');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Load Program'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: names.length,
            itemBuilder: (_, i) {
              final name = names[i];
              return ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(name),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () async {
                    await _store.delete(name);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted && _currentName == name) _currentName = null;
                    _showLoadDialog(); // reopen with the updated list
                  },
                ),
                onTap: () async {
                  final src = await _store.load(name);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  if (src == null) {
                    _snack('Program not found');
                    return;
                  }
                  _offerText(src, name: name);
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

  void _showExamplesSheet() {
    final examples = _buildExamples();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Icon(Icons.bolt, color: _kIndigo),
                  SizedBox(width: 8),
                  Text(
                    'Examples',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _kInk),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: examples.length,
                itemBuilder: (_, i) {
                  final ex = examples[i];
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _kIndigo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(ex.icon, color: _kIndigo, size: 20),
                    ),
                    title: Text(ex.title, style: const TextStyle(fontWeight: FontWeight.w600, color: _kInk)),
                    subtitle: Text(ex.description, style: const TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _offerText(ex.source, name: ex.title);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showApiReference() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scroll) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.menu_book_outlined, color: _kIndigo),
                  SizedBox(width: 8),
                  Text(
                    'API reference',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _kInk),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    _kApiReference.trim(),
                    style: const TextStyle(
                      fontFamily: _kMonoFamily,
                      fontSize: 12,
                      height: 1.5,
                      color: _kInk,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final canRun = _controller.text.trim().isNotEmpty || _state == ExecutionState.running;
    return Scaffold(
      backgroundColor: _kBackground,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final consoleHeight = _consoleOpen ? constraints.maxHeight * 0.30 : 36.0;
                  return Column(
                    children: [
                      Expanded(child: _buildEditor()),
                      _buildQuickInsertBar(),
                      SizedBox(height: consoleHeight, child: _buildConsole()),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: canRun ? _buildPlayButton() : null,
    );
  }

  Widget _buildHeader() {
    final isRunning = _state == ExecutionState.running;
    // On narrow phones (360 dp) the full header overflowed by ~50 px.
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
          if (!narrow) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_kIndigo, _kViolet]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.code, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Python',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _kInk),
                ),
                const SizedBox(height: 2),
                if (isRunning)
                  Row(
                    children: [
                      const Icon(Icons.circle, size: 8, color: _kGreen),
                      const SizedBox(width: 5),
                      Text(
                        _execLine > 0 ? 'Running · line $_execLine' : 'Running',
                        style: const TextStyle(fontSize: 12, color: _kGreen, fontWeight: FontWeight.w500),
                      ),
                    ],
                  )
                else
                  Text(
                    '$_lineCount line${_lineCount == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 12, color: _kMuted),
                  ),
              ],
            ),
          ),
          if (narrow)
            _headerIcon(Icons.bolt, 'Examples', _showExamplesSheet)
          else
          ActionChip(
            avatar: const Icon(Icons.bolt, size: 16, color: _kIndigo),
            label: const Text('Examples'),
            labelStyle: const TextStyle(color: _kIndigo, fontWeight: FontWeight.w600, fontSize: 13),
            backgroundColor: _kIndigo.withValues(alpha: 0.1),
            side: BorderSide.none,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            onPressed: _showExamplesSheet,
          ),
          const SizedBox(width: 2),
          _headerIcon(Icons.check_circle_outline, 'Check syntax', _check),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            tooltip: 'More options',
            padding: EdgeInsets.zero,
            onSelected: (value) {
              switch (value) {
                case 'save':
                  _showSaveDialog();
                  break;
                case 'load':
                  _showLoadDialog();
                  break;
                case 'api':
                  _showApiReference();
                  break;
                case 'clear':
                  _clearEditor();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'save',
                child: ListTile(
                  leading: Icon(Icons.save_outlined),
                  title: Text('Save Program'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'load',
                child: ListTile(
                  leading: Icon(Icons.folder_open_outlined),
                  title: Text('Load Program'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'api',
                child: ListTile(
                  leading: Icon(Icons.menu_book_outlined),
                  title: Text('API reference'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Clear'),
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

  Widget _headerIcon(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  Widget _buildEditor() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final charWidth = _measureCharWidth(context);
          final minWidth = math.max(0.0, constraints.maxWidth - _kGutterWidth);
          final editorWidth = math.max(minWidth, _longestLine * charWidth + 48);
          return SingleChildScrollView(
            controller: _vScroll,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGutter(),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _hScroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: editorWidth,
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLines: null,
                        expands: false,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        autocorrect: false,
                        enableSuggestions: false,
                        smartDashesType: SmartDashesType.disabled,
                        smartQuotesType: SmartQuotesType.disabled,
                        textCapitalization: TextCapitalization.none,
                        style: _kEditorStyle,
                        strutStyle: _kEditorStrut,
                        cursorColor: _kIndigo,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.fromLTRB(8, _kEditorPadTop, 8, _kEditorPadBottom),
                          hintText: '# Write RoboPython here, or pick an example',
                          hintStyle: TextStyle(color: _kMuted, fontFamily: _kMonoFamily, fontSize: _kFontSize),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  double? _charWidthCache;
  double _measureCharWidth(BuildContext context) {
    if (_charWidthCache != null) return _charWidthCache!;
    final painter = TextPainter(
      text: const TextSpan(text: 'M', style: _kEditorStyle),
      textDirection: TextDirection.ltr,
      strutStyle: _kEditorStrut,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    _charWidthCache = painter.width;
    painter.dispose();
    return _charWidthCache!;
  }

  Widget _buildGutter() {
    return Container(
      width: _kGutterWidth,
      padding: const EdgeInsets.only(top: _kEditorPadTop, bottom: _kEditorPadBottom),
      decoration: BoxDecoration(
        color: _kBackground,
        border: Border(right: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(_lineCount, (i) {
          final n = i + 1;
          final active = n == _execLine;
          return Container(
            height: _kLineHeight,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 8),
            decoration: active
                ? BoxDecoration(
                    color: _kGreen.withValues(alpha: 0.18),
                    border: const Border(left: BorderSide(color: _kGreen, width: 3)),
                  )
                : null,
            child: Text(
              '$n',
              style: _kEditorStyle.copyWith(
                fontSize: 12,
                color: active ? _kGreen : _kMuted,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              ),
              strutStyle: _kEditorStrut,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildQuickInsertBar() {
    final chips = <MapEntry<String, VoidCallback>>[
      MapEntry('Tab', () => _insertAtCursor('    ')),
      MapEntry(':', () => _insertAtCursor(':')),
      MapEntry('()', () => _insertAtCursor('()', cursorOffset: 1)),
      MapEntry('=', () => _insertAtCursor('=')),
      MapEntry('"', () => _insertAtCursor('"')),
      MapEntry('robot.', () => _insertAtCursor('robot.')),
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final chip = chips[i];
          return ActionChip(
            label: Text(chip.key),
            labelStyle: const TextStyle(
              fontFamily: _kMonoFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _kInk,
            ),
            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            backgroundColor: Colors.white,
            side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onPressed: chip.value,
          );
        },
      ),
    );
  }

  Widget _buildConsole() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: _kConsoleBg,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _consoleOpen = !_consoleOpen),
            child: SizedBox(
              height: 36,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.terminal, size: 16, color: _kMuted),
                  const SizedBox(width: 8),
                  Text(
                    'Console${_logs.isEmpty ? '' : ' · ${_logs.length}'}',
                    style: const TextStyle(
                      color: _kConsoleText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _logs.isEmpty ? null : _logger.clear,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    color: _kMuted,
                    tooltip: 'Clear console',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  Icon(
                    _consoleOpen ? Icons.expand_more : Icons.expand_less,
                    size: 20,
                    color: _kMuted,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          if (_consoleOpen)
            Expanded(
              child: _logs.isEmpty
                  ? const Center(
                      child: Text(
                        'Output appears here when you run.',
                        style: TextStyle(color: _kMuted, fontSize: 12, fontFamily: _kMonoFamily),
                      ),
                    )
                  : ListView.builder(
                      controller: _consoleScroll,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      itemCount: _logs.length,
                      itemBuilder: (_, i) => _consoleLine(_logs[i]),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _consoleLine(String line) {
    // Logger lines look like "[hh:mm:ss] message".
    final body = line.startsWith('[') && line.length > 11 ? line.substring(11) : line;
    Color color = _kConsoleText;
    if (body.startsWith('❌') || body.startsWith('💥')) {
      color = const Color(0xFFF87171);
    } else if (body.startsWith('⚠️')) {
      color = const Color(0xFFFBBF24);
    }
    return SelectableText(
      line,
      style: TextStyle(fontFamily: _kMonoFamily, fontSize: 12, height: 1.45, color: color),
    );
  }

  Widget _buildPlayButton() {
    final isRunning = _state == ExecutionState.running;
    return FloatingActionButton.extended(
      onPressed: _toggleRun,
      backgroundColor: isRunning ? Colors.red : _kGreen,
      icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
      label: Text(
        isRunning ? 'STOP' : 'RUN',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
