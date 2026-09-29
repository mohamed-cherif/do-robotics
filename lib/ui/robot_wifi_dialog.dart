import 'dart:async';
import 'package:flutter/material.dart';
import '../services/connectivity/connectivity_manager.dart';
import '../services/connectivity/frame_parser.dart';
import '../services/connectivity/wifi_strategy.dart';

/// Sends WiFi credentials to an ESP32 over the current link (Bluetooth or
/// USB) and waits for the board to report its new IP address.
class RobotWifiSetupDialog extends StatefulWidget {
  const RobotWifiSetupDialog({super.key});

  @override
  State<RobotWifiSetupDialog> createState() => _RobotWifiSetupDialogState();
}

class _RobotWifiSetupDialogState extends State<RobotWifiSetupDialog> {
  final _ssid = TextEditingController();
  final _pass = TextEditingController();
  final _connectivity = ConnectivityManager();
  StreamSubscription? _sub;
  String _status = '';
  bool _busy = false;
  bool _hidePass = true;
  String? _ip;

  @override
  void initState() {
    super.initState();
    _sub = _connectivity.messages.listen(_onMessage);
    _connectivity.sendText('STATUS');
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ssid.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _onMessage(TextFrame f) {
    if (!mounted) return;
    final fields = f.fields;
    switch (f.command) {
      case 'WIFI':
        if (fields.length > 2 && fields[1] == 'CONNECTED') {
          setState(() {
            _busy = false;
            _ip = fields[2];
            _status = 'Robot joined the network at ${fields[2]}';
          });
        } else if (fields.length > 1 && fields[1] == 'FAILED') {
          setState(() {
            _busy = false;
            _status = 'Robot could not join: ${fields.length > 2 ? fields[2] : 'unknown reason'}';
          });
        }
        break;
      case 'STATUS':
        final map = {for (final kv in fields.skip(1).where((s) => s.contains('='))) kv.split('=')[0]: kv.split('=')[1]};
        if (map['sta'] == 'connected' && map['ip'] != null) {
          setState(() {
            _ip = map['ip'];
            _status = 'Robot is already on a network at ${map['ip']}';
          });
        }
        break;
      case 'OK':
        setState(() => _status = fields.length > 1 ? fields[1] : 'OK');
        break;
      case 'ERR':
        setState(() {
          _busy = false;
          _status = 'Robot replied: ${fields.length > 1 ? fields[1] : 'error'}';
        });
        break;
    }
  }

  Future<void> _send() async {
    final ssid = _ssid.text.trim();
    if (ssid.isEmpty) {
      setState(() => _status = 'Enter the network name first');
      return;
    }
    if (!_connectivity.isConnected) {
      setState(() => _status = 'Connect to the robot over Bluetooth or USB first');
      return;
    }
    setState(() {
      _busy = true;
      _ip = null;
      _status = 'Sending credentials…';
    });
    final reply = await _connectivity.request('WIFI\t$ssid\t${_pass.text}');
    if (!mounted) return;
    if (reply == null) {
      setState(() {
        _busy = false;
        _status = 'No answer from the board. Is it an ESP32 with the v2.0 firmware?';
      });
      return;
    }
    if (reply.command == 'OK') {
      setState(() => _status = 'Saved. Waiting for the robot to join "$ssid"… (up to 15 s)');
      Future.delayed(const Duration(seconds: 15), () {
        if (mounted && _busy) {
          setState(() {
            _busy = false;
            _status = 'Still waiting. Check the password, or look at the robot\'s serial log.';
          });
        }
      });
    }
  }

  Future<void> _useIp() async {
    final ip = _ip;
    if (ip == null) return;
    await _connectivity.setWifiHost('$ip:${WifiStrategy.defaultPort}');
    if (mounted) Navigator.pop(context, ip);
  }

  @override
  Widget build(BuildContext context) {
    final board = _connectivity.board;
    return AlertDialog(
      title: const Text('Robot WiFi setup'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _connectivity.isConnected
                  ? 'Connected over ${_connectivity.activeType.displayName}'
                      '${board.type != 'unknown' ? ' to ${board.type} (fw ${board.firmware})' : ''}. '
                      'The robot will join this network and announce itself as robot.local.'
                  : 'Connect to the robot over Bluetooth or USB first, then send it your WiFi details.',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ssid,
              decoration: const InputDecoration(labelText: 'Network name (SSID)'),
              autofocus: true,
            ),
            TextField(
              controller: _pass,
              obscureText: _hidePass,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  tooltip: _hidePass ? 'Show password' : 'Hide password',
                  icon: Icon(_hidePass ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _hidePass = !_hidePass),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_status.isNotEmpty)
              Row(
                children: [
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  Expanded(child: Text(_status, style: const TextStyle(fontSize: 13))),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        if (_ip != null)
          TextButton.icon(
            onPressed: _useIp,
            icon: const Icon(Icons.wifi),
            label: const Text('Use this address'),
          ),
        ElevatedButton(
          onPressed: _busy ? null : _send,
          child: const Text('Send to robot'),
        ),
      ],
    );
  }
}
