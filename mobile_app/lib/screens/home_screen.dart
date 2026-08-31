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
                    const SizedBox(height: 32),

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
            ? Colors.green.withOpacity(0.1)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: monitor.isProtecting
              ? Colors.green.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
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
                  ? Colors.green.withOpacity(0.2)
                  : Colors.grey.withOpacity(0.1),
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
                      ? 'Monitoring sensors and location'
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
            activeColor: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard(SafetyMonitorService monitor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
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
                SizedBox(
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.mic,
              size: 18,
              color: monitor.voiceDetectionOn ? Colors.purple : Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voice Detection',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                ),
                if (monitor.voiceDetectionOn)
                  Text(
                    'Mic: ${monitor.voiceMicStatus}',
                    style: TextStyle(
                      color: monitor.voiceMicStatus == 'ACTIVE'
                          ? Colors.green
                          : monitor.voiceMicStatus == 'ERROR'
                              ? Colors.red
                              : Colors.grey,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          if (monitor.isProtecting)
            Switch(
              value: monitor.voiceDetectionOn,
              onChanged: (v) => monitor.toggleVoiceDetection(v),
              activeColor: Colors.purple,
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
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
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
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
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

  Widget _buildStatusCard(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
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
