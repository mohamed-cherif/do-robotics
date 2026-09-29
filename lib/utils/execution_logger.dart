import 'dart:async';
import 'dart:collection';

class ExecutionLogger {
  static final ExecutionLogger _instance = ExecutionLogger._internal();
  factory ExecutionLogger() => _instance;
  ExecutionLogger._internal();

  final Queue<String> _logs = Queue();
  final int _maxLogs = 100;
  final StreamController<void> _notifyController = StreamController<void>.broadcast();

  Stream<void> get onChange => _notifyController.stream;

  void log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    _logs.add("[$timestamp] $message");
    if (_logs.length > _maxLogs) {
      _logs.removeFirst();
    }
    _notifyController.add(null);
  }

  List<String> get logs => _logs.toList();
  void clear() {
    _logs.clear();
    _notifyController.add(null);
  }
}
