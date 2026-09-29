import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'robot_connection.dart';
import 'robot_protocol.dart';

class WifiStrategy implements RobotConnection {
  Socket? _socket;
  final StreamController<RobotConnectionState> _stateController =
      StreamController<RobotConnectionState>.broadcast();
  final StreamController<Uint8List> _inboundController =
      StreamController<Uint8List>.broadcast();
  RobotConnectionState _currentState = RobotConnectionState.disconnected;
  Timer? _heartbeatTimer;
  StreamSubscription? _socketSub;

  /// Default soft-AP address of receiver.ino (WiFi.softAP → 192.168.4.1:4210).
  static const String defaultHost = '192.168.4.1';
  static const int defaultPort = 4210;
  /// mDNS name the ESP32 announces once it has joined a WiFi network.
  static const String mdnsHost = 'robot.local';
  static const String mdnsService = '_dorobot._tcp.local';

  /// Last address that actually connected (host:port), for the UI to remember.
  String? lastResolved;

  @override
  Stream<RobotConnectionState> get stateStream => _stateController.stream;
  @override
  RobotConnectionState get currentState => _currentState;
  @override
  Stream<Uint8List> get inbound => _inboundController.stream;

  void _updateState(RobotConnectionState state) {
    if (_currentState == state) return;
    _currentState = state;
    _stateController.add(state);
  }

  /// Resolves a `.local` hostname via mDNS. Returns null when not found.
  static Future<String?> resolveMdns(String host, {Duration timeout = const Duration(seconds: 3)}) async {
    final client = MDnsClient();
    try {
      await client.start();
      await for (final rec in client
          .lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(host))
          .timeout(timeout, onTimeout: (sink) => sink.close())) {
        return rec.address.address;
      }
    } catch (e) {
      debugPrint("mDNS lookup failed: $e");
    } finally {
      client.stop();
    }
    return null;
  }

  /// Browses for robots advertising `_dorobot._tcp`. Returns "host:port" list.
  static Future<List<String>> discover({Duration timeout = const Duration(seconds: 3)}) async {
    final client = MDnsClient();
    final found = <String>{};
    try {
      await client.start();
      await for (final ptr in client
          .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(mdnsService))
          .timeout(timeout, onTimeout: (sink) => sink.close())) {
        await for (final srv in client
            .lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))
            .timeout(const Duration(seconds: 1), onTimeout: (sink) => sink.close())) {
          await for (final ip in client
              .lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target))
              .timeout(const Duration(seconds: 1), onTimeout: (sink) => sink.close())) {
            found.add('${ip.address.address}:${srv.port}');
          }
        }
      }
    } catch (e) {
      debugPrint("mDNS discovery failed: $e");
    } finally {
      client.stop();
    }
    return found.toList();
  }

  /// [deviceId] may be "host", "host:port", or "robot.local[:port]".
  @override
  Future<void> connect({String? deviceId}) async {
    if (_currentState != RobotConnectionState.disconnected) return;
    _updateState(RobotConnectionState.connecting);

    String host = defaultHost;
    int port = defaultPort;
    if (deviceId != null && deviceId.trim().isNotEmpty) {
      final parts = deviceId.trim().split(':');
      host = parts[0];
      if (parts.length > 1) port = int.tryParse(parts[1]) ?? defaultPort;
    }

    if (host.endsWith('.local')) {
      final ip = await resolveMdns(host);
      if (ip == null) {
        debugPrint("WiFi: could not resolve $host (is the robot on this network?)");
        _updateState(RobotConnectionState.disconnected);
        return;
      }
      debugPrint("WiFi: $host → $ip");
      host = ip;
    }

    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      socket.setOption(SocketOption.tcpNoDelay, true); // latency over throughput
      _socket = socket;
      lastResolved = '$host:$port';
      _updateState(RobotConnectionState.connected);
      _startHeartbeat();

      _socketSub?.cancel();
      _socketSub = socket.listen(
        (data) => _inboundController.add(Uint8List.fromList(data)),
        onError: (_) => _handleDisconnect(),
        onDone: () => _handleDisconnect(),
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint("WiFi Connection Error ($host:$port): $e");
      _updateState(RobotConnectionState.disconnected);
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(RobotProtocol.heartbeatInterval, (_) {
      _send(RobotProtocol.heartbeatPacket);
    });
  }

  void _send(List<int> packet) {
    final socket = _socket;
    if (socket == null || _currentState != RobotConnectionState.connected) return;
    try {
      socket.add(packet);
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    if (_currentState == RobotConnectionState.disconnected) return;
    _cleanup();
    _updateState(RobotConnectionState.disconnected);
  }

  void _cleanup() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _socketSub?.cancel();
    _socketSub = null;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
  }

  @override
  Future<void> disconnect() async {
    final socket = _socket;
    if (socket != null) {
      try {
        await socket.flush();
        await socket.close();
      } catch (_) {}
    }
    _cleanup();
    _updateState(RobotConnectionState.disconnected);
  }

  @override
  Future<void> sendCommand(int cmd, int pin, int value) async {
    _send(RobotProtocol.buildPacket(cmd, pin, value));
  }

  @override
  Future<void> sendBytes(List<int> bytes) async => _send(bytes);

  @override
  Future<void> dispose() async {
    await disconnect();
    _stateController.close();
    _inboundController.close();
  }
}
