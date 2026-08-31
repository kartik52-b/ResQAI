import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/safety_monitor_service.dart';
import 'home_screen.dart';
import 'monitoring_screen.dart';
import 'contacts_screen.dart';

/// Main app shell with bottom navigation.
/// Manages page switching between Home, Monitoring, and Contacts.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  final _pages = const [
    HomeScreen(),
    MonitoringScreen(),
    ContactsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<SafetyMonitorService>();

    // Determine bottom nav color based on emergency state
    Color navColor = const Color(0xFF1E1E2E);
    if (monitor.emergencyStatus == 'CONFIRMED' ||
        monitor.emergencyStatus == 'SENDING SMS' ||
        monitor.emergencyStatus == 'CALLING CONTACT') {
      navColor = Colors.red.shade900;
    } else if (monitor.emergencyStatus == 'VERIFYING' ||
        monitor.emergencyStatus == 'VOICE VERIFICATION') {
      navColor = Colors.orange.shade900;
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        backgroundColor: navColor,
        indicatorColor: Colors.cyan.withOpacity(0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined, color: Colors.grey),
            selectedIcon: Icon(Icons.home, color: Colors.cyan),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.sensors_outlined, color: Colors.grey),
            selectedIcon: Icon(Icons.sensors, color: Colors.cyan),
            label: 'Monitoring',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline, color: Colors.grey),
            selectedIcon: Icon(Icons.people, color: Colors.cyan),
            label: 'Contacts',
          ),
        ],
      ),
    );
  }
}
