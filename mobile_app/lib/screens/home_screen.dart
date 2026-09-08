import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/safety_monitor_service.dart';
import '../services/contact_service.dart';
import '../services/emergency_orchestrator.dart' show OrchestratorState;
import 'emergency_screen.dart';

/// Simplified home dashboard — status-only control surface.
/// All monitoring logic lives in SafetyMonitorService.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SafetyMonitorService>(
      builder: (context, monitor, _) {
        return Stack(
          children: [
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // App title
                    const Text(
                      'RESQ AI',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Background Safety Monitoring',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Demo Mode banner
                    if (monitor.demoMode)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.present_to_all, color: Colors.teal, size: 16),
                            SizedBox(width: 8),
                            Text(
                              'DEMO MODE — 15s countdown',
                              style: TextStyle(
                                color: Colors.teal,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Protection toggle
                    _buildProtectionToggle(context, monitor),
                    const SizedBox(height: 24),

                    // Safety status
                    _buildStatusCard(
                      'Safety Status',
                      monitor.safetyStatus,
                      _getStatusColor(monitor.safetyStatus),
                    ),
                    const SizedBox(height: 12),

                    // Emergency status
                    _buildStatusCard(
                      'Emergency',
                      monitor.emergencyStatus,
                      _getEmergencyColor(monitor.emergencyStatus),
                    ),
                    const SizedBox(height: 12),

                    // GPS + Location
                    _buildLocationCard(monitor),
                    const SizedBox(height: 12),

                    // Live Speed Display
                    if (monitor.isProtecting && monitor.gpsStatus == 'ACTIVE')
                      _buildSpeedCard(monitor),
                    if (monitor.isProtecting && monitor.gpsStatus == 'ACTIVE')
                      const SizedBox(height: 12),

                    // Background service
                    _buildStatusCard(
                      'Background Service',
                      monitor.isProtecting ? 'ACTIVE' : 'INACTIVE',
                      monitor.isProtecting ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(height: 12),

                    // Voice monitoring
                    _buildVoiceCard(context, monitor),
                    const SizedBox(height: 12),

                    // Last incident
                    _buildStatusCard(
                      'Last Incident',
                      monitor.lastIncident,
                      Colors.grey,
                    ),

                    // Orchestrator status (if active)
                    if (monitor.orchestratorMessage.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildStatusCard(
                        'Emergency Response',
                        monitor.orchestratorMessage,
                        Colors.cyan,
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Trusted contacts summary
                    _buildContactsSummary(context),

                    const SizedBox(height: 24),

                    // Emergency history shortcut
                    if (monitor.lifeReplay.events.isNotEmpty)
                      _buildHistoryShortcut(monitor),
                  ],
                ),
              ),
            ),

            // Emergency verification overlay
            if (monitor.orchestrator.state == OrchestratorState.possibleEmergency ||
                monitor.orchestrator.state == OrchestratorState.voiceVerifying)
              EmergencyScreen(
                remainingSeconds: monitor.orchestrator.remainingSeconds,
                currentEvent: monitor.orchestrator.currentEvent,
                onOk: monitor.orchestrator.userConfirmedOk,
                onHelp: monitor.orchestrator.userConfirmedHelp,
              ),
          ],
        );
      },
    );
  }

  Widget _buildProtectionToggle(BuildContext context, SafetyMonitorService monitor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: monitor.isProtecting
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: monitor.isProtecting
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: monitor.isProtecting
                  ? Colors.green.withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.1),
            ),
            child: Icon(
              monitor.isProtecting ? Icons.shield : Icons.shield_outlined,
              color: monitor.isProtecting ? Colors.green : Colors.grey,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  monitor.isProtecting ? 'PROTECTION ON' : 'PROTECTION OFF',
                  style: TextStyle(
                    color: monitor.isProtecting ? Colors.green : Colors.grey,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  monitor.isProtecting
                      ? 'Sensors + GPS + Voice monitoring active'
                      : 'Tap to enable safety monitoring',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: monitor.isProtecting,
            onChanged: (value) async {
              if (value) {
                await monitor.startProtection();
              } else {
                monitor.stopProtection();
              }
            },
            activeThumbColor: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard(SafetyMonitorService monitor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.location_on,
                  size: 18,
                  color: _getGpsStatusColor(monitor.gpsStatus)),
              const SizedBox(width: 8),
              Text('GPS: ',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
              Text(monitor.gpsStatus,
                  style: TextStyle(
                    color: _getGpsStatusColor(monitor.gpsStatus),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  )),
              const Spacer(),
              if (monitor.gpsAccuracy > 0 && monitor.gpsStatus == 'ACTIVE')
                Text('${monitor.gpsAccuracy.toStringAsFixed(0)}m',
                    style: TextStyle(
                      color: monitor.gpsAccuracy > 30 ? Colors.red : Colors.green,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    )),
            ],
          ),
          if (monitor.gpsStatus == 'SEARCHING') ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.amber,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Waiting for GPS fix...',
                  style: TextStyle(
                    color: Colors.amber.shade300,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
          if ((monitor.gpsStatus == 'PERMISSION DENIED' ||
              monitor.gpsStatus == 'SERVICE OFF' ||
              monitor.gpsStatus == 'ERROR')) ...[
            const SizedBox(height: 6),
            Text(
              monitor.gpsStatus == 'SERVICE OFF'
                  ? 'Enable location services in device settings'
                  : 'Grant location permission in app settings',
              style: TextStyle(
                color: Colors.red.shade300,
                fontSize: 11,
              ),
            ),
          ],
          if (monitor.gpsStatus == 'ACTIVE' &&
              (monitor.currentLatitude != 0 || monitor.currentLongitude != 0)) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.my_location, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${monitor.currentLatitude.toStringAsFixed(5)}, ${monitor.currentLongitude.toStringAsFixed(5)}',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _getGpsStatusColor(String status) {
    switch (status) {
      case 'ACTIVE':
        return Colors.green;
      case 'SEARCHING':
        return Colors.amber;
      case 'STARTING':
        return Colors.grey;
      case 'PERMISSION DENIED':
      case 'SERVICE OFF':
      case 'ERROR':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildVoiceCard(BuildContext context, SafetyMonitorService monitor) {
    // Voice detection is automatic — status indicator only, no manual toggle.
    final voiceActive = monitor.voiceDetectionOn && monitor.isProtecting;
    final voiceStatus = monitor.voiceMicStatus;
    final voiceColor = voiceActive
        ? (voiceStatus == 'ACTIVE' ? Colors.green : voiceStatus == 'ERROR' ? Colors.red : Colors.grey)
        : Colors.grey;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.mic, size: 18, color: voiceColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voice Emergency Detection',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                ),
                Text(
                  voiceActive
                      ? '● AUTO-ACTIVE — Mic: $voiceStatus'
                      : monitor.isProtecting
                          ? '● WAITING — Requesting permission...'
                          : '● OFF — Enable Protection to activate',
                  style: TextStyle(
                    color: voiceColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactsSummary(BuildContext context) {
    return Consumer<ContactService>(
      builder: (context, contacts, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.people, size: 18, color: Colors.cyan.shade300),
                  const SizedBox(width: 8),
                  Text(
                    'Trusted Contacts',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  ),
                  const Spacer(),
                  Text(
                    '${contacts.contacts.length}/${ContactService.maxContacts}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
              if (contacts.primaryContact != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Primary: ${contacts.primaryContact!.name}',
                  style: TextStyle(
                    color: Colors.cyan.shade300,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'SMS → All  |  Call → ${contacts.primaryContact!.name}',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ],
              if (contacts.contacts.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'No contacts configured',
                  style: TextStyle(color: Colors.orange.shade300, fontSize: 12),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryShortcut(SafetyMonitorService monitor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 18, color: Colors.grey.shade400),
              const SizedBox(width: 8),
              Text(
                'Recent Activity (${monitor.lifeReplay.events.length} events)',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...monitor.lifeReplay.events.takeLast(3).map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Text(
                      '${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11,
                          fontFamily: 'monospace'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.description,
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildSpeedCard(SafetyMonitorService monitor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(
        children: [
          Text(
            'CURRENT SPEED',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 12,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            monitor.currentSpeedKmh.toStringAsFixed(1),
            style: TextStyle(
              color: monitor.currentSpeedKmh < 2.5
                  ? Colors.grey
                  : monitor.currentSpeedKmh < 30
                      ? Colors.cyan
                      : Colors.orange,
              fontSize: 48,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            'km/h',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildMiniLabel(
                'GPS',
                monitor.gpsStatus,
                _getGpsStatusColor(monitor.gpsStatus),
              ),
              const SizedBox(width: 20),
              _buildMiniLabel(
                'ACC',
                '${monitor.gpsAccuracy.toStringAsFixed(0)}m',
                monitor.gpsAccuracy > 30 ? Colors.red : Colors.green,
              ),
              const SizedBox(width: 20),
              _buildMiniLabel(
                'STATE',
                monitor.gpsIsStationary ? 'STILL' : 'MOVING',
                monitor.gpsIsStationary ? Colors.grey : Colors.cyan,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniLabel(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 10)),
        Text(value,
            style: TextStyle(
                color: valueColor, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildStatusCard(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'ACTIVE':
      case 'NORMAL':
        return Colors.green;
      case 'STANDBY':
        return Colors.grey;
      case 'SPEED DROP DETECTED':
        return Colors.red;
      default:
        return Colors.white;
    }
  }

  Color _getEmergencyColor(String status) {
    switch (status) {
      case 'SAFE':
        return Colors.green;
      case 'VERIFYING':
      case 'VOICE VERIFICATION':
        return Colors.orange;
      case 'CONFIRMED':
      case 'SENDING SMS':
      case 'CALLING CONTACT':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

extension<T> on List<T> {
  Iterable<T> takeLast(int count) {
    if (length <= count) return this;
    return skip(length - count);
  }
}
