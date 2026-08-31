import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/app_shell.dart';
import 'services/api_service.dart';
import 'services/contact_service.dart';
import 'services/safety_monitor_service.dart';
import 'services/native_service_bridge.dart';
import 'sensors/sensor_manager.dart';

void main() {
  runApp(const ResQApp());
}

class ResQApp extends StatelessWidget {
  const ResQApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Core services
        ChangeNotifierProvider(create: (_) => SensorManager()),
        Provider(create: (_) => ApiService()),
        Provider(create: (_) => NativeServiceBridge()),
        ChangeNotifierProvider(create: (_) => ContactService()..loadContacts()),

        // Safety monitor service — owns the monitoring lifecycle
        ChangeNotifierProxyProvider4<SensorManager, ApiService, ContactService,
            NativeServiceBridge, SafetyMonitorService>(
          create: (ctx) => SafetyMonitorService(
            sensorManager: ctx.read<SensorManager>(),
            nativeBridge: ctx.read<NativeServiceBridge>(),
            apiService: ctx.read<ApiService>(),
            contactService: ctx.read<ContactService>(),
          ),
          update: (_, sensorManager, apiService, contacts, bridge, previous) =>
              previous!,
        ),
      ],
      child: MaterialApp(
        title: 'ResQ AI',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE53935),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF121212),
        ),
        home: const AppShell(),
      ),
    );
  }
}
