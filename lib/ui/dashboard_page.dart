import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/connectivity/bluetooth_strategy.dart';
import '../services/connectivity/connectivity_manager.dart';
import '../services/connectivity/robot_connection.dart';
import '../services/sensor_service.dart';
import '../models/tutorial_data.dart';
import '../services/connectivity/wifi_strategy.dart';
import 'logic_page.dart';
import 'actuator_settings_page.dart';
import 'neural_core_header.dart';
import 'python_bus.dart';
import 'python_page.dart';
import 'robot_picker_dialog.dart';
import 'robot_wifi_dialog.dart';
import 'sensors_page.dart';
import 'tutorial_detail_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with SingleTickerProviderStateMixin {
  final ConnectivityManager _connectivity = ConnectivityManager();
  final SensorService _sensorService = SensorService();
  int _selectedIndex = 0;
  late AnimationController _animController;
  StreamSubscription<RobotConnectionState>? _connectionSub;
  late final Stream<(bool, bool)> _shakeTiltStream = _sensorService
      .typeFilteredAccelStream
      .map((_) => (_sensorService.isShaking, _sensorService.isTilted))
      .distinct();
  RobotConnectionState _lastConnectionState = RobotConnectionState.disconnected;
  /// While the robot list is open, a stopped connect attempt isn't a failure.
  bool _robotListOpen = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animController.forward();
    
    _connectionSub = _connectivity.stateStream.listen(_onConnectionState);
    // Auto-connect with the last used transport (Bluetooth by default).
    _connectivity.connect();
    _sensorService.startListening();

    // Other pages (block editor → "Convert to Python") can ask for a tab.
    PythonBus.requestedTab.addListener(_onTabRequested);
  }

  void _onTabRequested() {
    final idx = PythonBus.requestedTab.value;
    if (idx >= 0 && mounted) {
      setState(() => _selectedIndex = idx);
      PythonBus.requestedTab.value = -1;
    }
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    PythonBus.requestedTab.removeListener(_onTabRequested);
    _animController.dispose();
    _sensorService.stopListening();
    super.dispose();
  }

  /// Switches transport (if needed) and connects. [reconnect] drops an
  /// existing link of the same type first — needed when the WiFi address
  /// changed, otherwise the app silently stayed on the old host.
  Future<void> _switchAndConnect(ConnectionType type, {bool reconnect = false}) async {
    if (reconnect &&
        _connectivity.activeType == type &&
        _connectivity.state != RobotConnectionState.disconnected) {
      await _connectivity.disconnect();
    }
    await _connectivity.setType(type);
    await _connectivity.connect();
  }

  /// Tells the user when a connection attempt ends without a link instead of
  /// failing silently (robot off, Bluetooth off, permission denied...).
  void _onConnectionState(RobotConnectionState s) {
    final wasConnecting = _lastConnectionState == RobotConnectionState.connecting;
    _lastConnectionState = s;
    if (!mounted || _robotListOpen || !wasConnecting || s != RobotConnectionState.disconnected) {
      return;
    }
    final hint = switch (_connectivity.activeType) {
      ConnectionType.bluetooth =>
        'Is the robot powered and nearby, and is Bluetooth on? Tap the header to retry.',
      ConnectionType.serial =>
        'Plug the board in with a USB-OTG cable and accept the USB permission prompt.',
      ConnectionType.wifi =>
        'Is the phone on the same WiFi as the robot (or on its ESP32_Robot_… hotspot)?',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("Couldn't connect over ${_connectivity.activeType.displayName}. $hint"),
      duration: const Duration(seconds: 5),
    ));
  }

  /// Lets the user pick one of the robots in range; it is remembered, so the
  /// app reconnects to that robot (not just the first one found) next time.
  Future<void> _chooseBluetoothRobot() async {
    _robotListOpen = true;
    try {
      // A Bluetooth connect attempt still searching would grab the first
      // robot the list's scan finds, so stop it first.
      if (_connectivity.activeType == ConnectionType.bluetooth &&
          _connectivity.state == RobotConnectionState.connecting) {
        await _connectivity.disconnect();
      }
      if (!mounted) return;
      final robot = await showDialog<FoundRobot>(
        context: context,
        builder: (_) => RobotPickerDialog(rememberedId: _connectivity.bluetoothDeviceId),
      );
      if (robot == null) return;
      await _connectivity.setBluetoothDevice(robot.id);
      _robotListOpen = false; // failures from here on are real
      await _switchAndConnect(ConnectionType.bluetooth, reconnect: true);
    } finally {
      _robotListOpen = false;
    }
  }

  Future<void> _promptWifiHost() async {
    final ctrl = TextEditingController(text: _connectivity.wifiHost);
    final host = await showDialog<String>(
      context: context,
      builder: (ctx) => _WifiConnectDialog(controller: ctrl),
    );
    if (host == null || host.isEmpty) return;
    await _connectivity.setWifiHost(host);
    await _switchAndConnect(ConnectionType.wifi, reconnect: true);
  }

  Future<void> _showRobotWifiSetup() async {
    final ip = await showDialog<String>(
      context: context,
      builder: (_) => const RobotWifiSetupDialog(),
    );
    if (ip != null && mounted) {
      // The user chose to switch to the robot's new WiFi address.
      await _switchAndConnect(ConnectionType.wifi, reconnect: true);
    }
  }

  void _showConnectionDialog() {
    final isConnected = _connectivity.state == RobotConnectionState.connected;
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text("Robot Connection"),
        children: [
          SimpleDialogOption(
            child: const Row(children: [Icon(Icons.bluetooth), SizedBox(width: 8), Text("Bluetooth")]),
            onPressed: () {
              Navigator.pop(context);
              _chooseBluetoothRobot();
            },
          ),
          // USB serial to a microcontroller is only possible on Android.
          if (Platform.isAndroid)
            SimpleDialogOption(
              child: const Row(children: [Icon(Icons.usb), SizedBox(width: 8), Text("USB Serial (OTG)")]),
              onPressed: () {
                Navigator.pop(context);
                _switchAndConnect(ConnectionType.serial);
              },
            ),
          SimpleDialogOption(
            child: const Row(children: [Icon(Icons.wifi), SizedBox(width: 8), Text("WiFi")]),
            onPressed: () {
              Navigator.pop(context);
              _promptWifiHost();
            },
          ),
          const Divider(height: 8),
          SimpleDialogOption(
            child: Row(children: [
              const Icon(Icons.settings_ethernet),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Set up robot WiFi"),
                    Text(
                      isConnected
                          ? "Send your network name and password to the ESP32"
                          : "Connect over Bluetooth or USB first",
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ]),
            onPressed: () {
              Navigator.pop(context);
              _showRobotWifiSetup();
            },
          ),
          if (isConnected) ...[
            const Divider(height: 8),
            SimpleDialogOption(
              child: const Row(children: [
                Icon(Icons.link_off, color: Colors.red),
                SizedBox(width: 8),
                Text("Disconnect", style: TextStyle(color: Colors.red)),
              ]),
              onPressed: () {
                Navigator.pop(context);
                _connectivity.disconnect();
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: IndexedStack(
        index: _selectedIndex,
        // IndexedStack keeps hidden tabs alive; TickerMode pauses their
        // animations (the header's particle animation ran forever).
        children: [
          TickerMode(enabled: _selectedIndex == 0, child: _buildHomePage()),
          TickerMode(enabled: _selectedIndex == 1, child: const LogicPage()),
          TickerMode(enabled: _selectedIndex == 2, child: const PythonPage()),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_rounded, "Home"),
                _buildNavItem(1, Icons.extension_rounded, "Blocks"),
                _buildNavItem(2, Icons.terminal_rounded, "Python"),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    // Unselected tabs are icon-only: give screen readers the name.
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[600],
              size: 24,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildHomePage() {
    return CustomScrollView(
      slivers: [
        // Animated Header
        SliverToBoxAdapter(
          child: StreamBuilder<RobotConnectionState>(
            stream: _connectivity.stateStream,
            initialData: RobotConnectionState.disconnected,
            builder: (context, snapshot) {
              final isConnected = snapshot.data == RobotConnectionState.connected;
              return NeuralCoreHeader(
                isConnected: isConnected,
                onConnect: _showConnectionDialog, // Show selector instead of auto-reconnect
              );
            },
          ),
        ),

        // Content
        SliverPadding(
          padding: const EdgeInsets.all(24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Welcome Section
              FadeTransition(
                opacity: _animController,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.rocket_launch, color: Colors.white, size: 40),
                      const SizedBox(height: 16),
                      const Text(
                        "Build Amazing Robots!",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Give your robot eyes, ears, and a brain using blocks — no typing needed!",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Featured Tutorials Hub
              _buildTutorialsSection(),

              const SizedBox(height: 32),

              // Section Title
              const Text(
                "Robot Senses",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Tap to activate sensors for your robot",
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[600],
                ),
              ),

              const SizedBox(height: 20),

              // Real-time Sensor Status
              _buildSensorStatusSection(),

              const SizedBox(height: 20),

              // Hardware Config Card
              _buildConfigCard(),

              const SizedBox(height: 24),

              // Brain Explorer - Main Feature
              _buildBrainExplorerCard(),

              const SizedBox(height: 32),

              // Quick Action
              _buildQuickActionButton(),
            ]),
          ),
        ),

      ],
    );
  }

  Widget _buildTutorialsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Featured Tutorials",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
              ),
            ),
            Text(
              "See all",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF6366F1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          "Learn how to build cool projects step-by-step",
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200, // Fixed height for horizontal scroll
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: TutorialRepository.tutorials.length,
            clipBehavior: Clip.none, // Allow shadows to overflow
            itemBuilder: (context, index) {
              final tutorial = TutorialRepository.tutorials[index];
              return _buildTutorialCard(tutorial);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTutorialCard(TutorialData tutorial) {
    return Container(
      width: 280, // Fixed width for cards
      margin: const EdgeInsets.only(right: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (c) => TutorialDetailPage(tutorial: tutorial)),
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: tutorial.cardColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: tutorial.cardColor.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      tutorial.emoji,
                      style: const TextStyle(fontSize: 40),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: tutorial.difficultyColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        tutorial.difficultyLabel,
                        style: TextStyle(
                          color: tutorial.difficultyColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  tutorial.title,
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  tutorial.shortDescription,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 13,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrainExplorerCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (c) => const SensorsPage()),
        ),
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)], // Blue/Teal mix
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0EA5E9).withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                     Container(
                       padding: const EdgeInsets.all(12),
                       decoration: BoxDecoration(
                         color: Colors.white.withValues(alpha: 0.2),
                         borderRadius: BorderRadius.circular(16),
                       ),
                       child: const Icon(Icons.settings_input_component, color: Colors.white, size: 32),
                     ),
                     const Icon(Icons.arrow_forward, color: Colors.white70),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  "Configure Sensors",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Camera • Mic • Motion",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    "Setup & Test",
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConfigCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (c) => const ActuatorSettingsPage()),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "⚙️ Configure Hardware",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Add motors, servos, and LEDs",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionButton() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF059669)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _selectedIndex = 1),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.code, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Text(
                  "Start Coding!",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSensorStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            "📊 Robot Status",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
        ),
        StreamBuilder<(bool, bool)>(
          // Rebuild only when shake/tilt actually change, not at 50 Hz.
          stream: _shakeTiltStream,
          builder: (context, snapshot) {
            // Both use the gravity-aware service math (tilt cannot be read
            // from the gravity-removed accelerometer).
            final isShaking = _sensorService.isShaking;
            final isTilted = _sensorService.isTilted;

            return Row(
              children: [
                Expanded(
                  child: _buildSensorStatusCard(
                    icon: Icons.vibration,
                    label: "Shake",
                    value: isShaking ? "YES" : "NO",
                    color: isShaking ? const Color(0xFFF59E0B) : Colors.grey,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSensorStatusCard(
                    icon: Icons.screen_rotation,
                    label: "Tilt",
                    value: isTilted ? "Active" : "Stable",
                    color: isTilted ? const Color(0xFF6366F1) : Colors.grey,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StreamBuilder<RobotConnectionState>(
                    stream: _connectivity.stateStream,
                    builder: (c, snap) {
                      final connected = snap.data == RobotConnectionState.connected;
                      final board = _connectivity.board;
                      return _buildSensorStatusCard(
                        icon: Icons.link,
                        label: _connectivity.activeType.displayName,
                        value: connected
                            ? (board.type != 'unknown' ? board.type.toUpperCase() : "OK")
                            : "Wait",
                        color: connected ? const Color(0xFF10B981) : Colors.red,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSensorStatusCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 18),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// WiFi address entry with mDNS discovery of robots on the current network.
class _WifiConnectDialog extends StatefulWidget {
  final TextEditingController controller;
  const _WifiConnectDialog({required this.controller});

  @override
  State<_WifiConnectDialog> createState() => _WifiConnectDialogState();
}

class _WifiConnectDialogState extends State<_WifiConnectDialog> {
  bool _searching = false;
  List<String> _found = const [];
  String? _note;

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _note = null;
    });
    final found = await WifiStrategy.discover();
    String? resolved;
    if (found.isEmpty) {
      resolved = await WifiStrategy.resolveMdns(WifiStrategy.mdnsHost);
    }
    if (!mounted) return;
    setState(() {
      _searching = false;
      _found = found.isNotEmpty
          ? found
          : (resolved != null ? ['$resolved:${WifiStrategy.defaultPort}'] : const []);
      if (_found.isEmpty) {
        _note = "No robot found on this network. Is the phone on the same WiFi, "
            "or use the robot's hotspot at ${WifiStrategy.defaultHost}.";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Connect over WiFi"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: widget.controller,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: "Robot address",
              hintText: "robot.local or 192.168.4.1:4210",
              helperText: "robot.local works once the ESP32 has joined your WiFi. "
                  "The hotspot address is 192.168.4.1.",
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _searching ? null : _search,
                icon: _searching
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search, size: 18),
                label: Text(_searching ? "Searching…" : "Find robot"),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => widget.controller.text = '${WifiStrategy.defaultHost}:${WifiStrategy.defaultPort}',
                child: const Text("Hotspot"),
              ),
            ],
          ),
          for (final f in _found)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.smart_toy_outlined),
              title: Text(f),
              onTap: () => Navigator.pop(context, f),
            ),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_note!, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, widget.controller.text.trim()),
          child: const Text("Connect"),
        ),
      ],
    );
  }
}
