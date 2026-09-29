import 'dart:async';
import 'package:flutter/material.dart';
import '../services/connectivity/bluetooth_strategy.dart';

/// Lists the robots a Bluetooth scan finds, closest first; pops with the
/// one the user taps (or null). The scan is stopped before the dialog
/// closes, so a connect attempt that follows gets the radio to itself.
class RobotPickerDialog extends StatefulWidget {
  /// The robot connected last time (marked in the list).
  final String? rememberedId;

  /// Starts a scan; replaced in tests.
  final Stream<List<FoundRobot>> Function() scan;

  const RobotPickerDialog({
    super.key,
    this.rememberedId,
    this.scan = BluetoothStrategy.scanForRobots,
  });

  @override
  State<RobotPickerDialog> createState() => _RobotPickerDialogState();
}

class _RobotPickerDialogState extends State<RobotPickerDialog> {
  StreamSubscription<List<FoundRobot>>? _sub;
  List<FoundRobot> _robots = const [];
  bool _scanning = false;
  bool _failed = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _startScan() {
    _sub?.cancel();
    _robots = const [];
    _scanning = true;
    _failed = false;
    _sub = widget.scan().listen(
      (robots) {
        if (!mounted) return;
        setState(() => _robots = [...robots]..sort((a, b) => b.rssi.compareTo(a.rssi)));
      },
      onError: (Object e) {
        debugPrint('Robot scan failed: $e');
        if (mounted) setState(() => _failed = true);
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  /// Stops the scan (and waits for it, briefly) before closing.
  Future<void> _close([FoundRobot? robot]) async {
    if (_closing) return; // a double tap must not pop the page underneath
    _closing = true;
    final sub = _sub;
    _sub = null;
    await sub?.cancel().timeout(const Duration(seconds: 2), onTimeout: () {});
    if (mounted) Navigator.of(context).pop(robot);
  }

  static String _signal(int rssi) {
    if (rssi >= -60) return 'Very close';
    if (rssi >= -75) return 'Nearby';
    return 'Far away';
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_failed) {
      body = const Text(
        "Couldn't search for robots. Turn Bluetooth on and allow Nearby "
        "devices (on Android 11 and older: Location), then try again.",
        style: TextStyle(color: Colors.red),
      );
    } else if (_robots.isEmpty) {
      body = Text(_scanning
          ? 'Looking for robots… Make sure yours is switched on.'
          : 'No robots found. Is the robot switched on and close by, and is '
              'Bluetooth on?');
    } else {
      body = Flexible(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final r in _robots)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.smart_toy_outlined),
                title: Text(r.name),
                subtitle: Text(r.id == widget.rememberedId
                    ? '${_signal(r.rssi)} · last used'
                    : _signal(r.rssi)),
                onTap: () => _close(r),
              ),
          ],
        ),
      );
    }

    return AlertDialog(
      title: const Text('Choose your robot'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_scanning) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            body,
          ],
        ),
      ),
      actions: [
        if (!_scanning)
          TextButton(
            onPressed: () => setState(_startScan),
            child: const Text('Search again'),
          ),
        TextButton(onPressed: () => _close(), child: const Text('Cancel')),
      ],
    );
  }
}
