import 'package:flutter/foundation.dart';

/// Tiny cross-page channel: the block editor pushes converted source here and
/// asks the dashboard to switch to the Python tab; the Python page consumes it.
class PythonBus {
  PythonBus._();

  /// Source waiting to be loaded into the Python editor (null = nothing).
  static final ValueNotifier<String?> incomingSource = ValueNotifier<String?>(null);

  /// Dashboard bottom-nav index requested by another page (-1 = none).
  static final ValueNotifier<int> requestedTab = ValueNotifier<int>(-1);

  /// Index of the Python tab in the dashboard's IndexedStack.
  static const int pythonTabIndex = 2;

  static void openInPython(String source) {
    incomingSource.value = source;
    requestedTab.value = pythonTabIndex;
  }
}
