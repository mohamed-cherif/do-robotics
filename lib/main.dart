import 'package:flutter/material.dart';
import 'ui/dashboard_page.dart';
import 'ui/vision_settings_page.dart';
import 'services/actuator_service.dart';
import 'services/connectivity/connectivity_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ActuatorService().initialize();
  await ConnectivityManager().loadPreferences();
  runApp(const NeuralApp());
}

class NeuralApp extends StatelessWidget {
  const NeuralApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neural Link',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF0F4F8),
        useMaterial3: true,
      ),
      home: const DashboardPage(),
      routes: {
        '/vision-settings': (context) => const VisionSettingsPage(),
      },
    );
  }
}
