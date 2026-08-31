import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/safety_monitor_service.dart';
import '../engine/speed_drop_detector.dart';

/// Monitoring diagnostics screen — shows sensor and detection details.
class MonitoringScreen extends StatelessWidget {
  const MonitoringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SafetyMonitorService>(
      builder: (context, monitor, _) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'MONITORING',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 24),

                // GPS Section
                _buildSectionTitle('GPS'),
                const SizedBox(height: 8),
                _buildGpsCard(monitor),
                const SizedBox(height: 20),

                // Detection Phase
                _buildSectionTitle('Detection'),
                const SizedBox(height: 8),
                _buildDetectionCard(monitor),
                const SizedBox(height: 20),

                // Voice Monitoring
                _buildSectionTitle('Voice Monitoring'),
                const SizedBox(height: 8),
                _buildVoiceCard(monitor),
                const SizedBox(height: 20),

                // Background Service
                _buildSectionTitle('Background Service'),
                const SizedBox(height: 8),
                _buildServiceCard(monitor),

                // Last detected phrase
                if (monitor.voiceDetectedPhrase.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _buildSectionTitle('Last Voice Detection'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning, color: Colors.red, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '"${monitor.voiceDetectedPhrase}"',
                            style: const TextStyle(color: Colors.red, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Accident Detection Log
                if (monitor.accidentDetector.detectionLog.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _buildSectionTitle('Accident Detection Log'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: monitor.accidentDetector.detectionLog
                          .takeLast(10)
                          .map((log) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  log.toString(),
                                  style: TextStyle(
                                    color: log.toPhase.name == 'verifying'
                                        ? Colors.red
                                        : Colors.grey.shade400,
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ],

                // Movement diagnostics
                if (monitor.movementDiagnostics.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _buildSectionTitle('Sensor Diagnostics'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      monitor.movementDiagnostics,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGpsCard(SafetyMonitorService monitor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Column(
        children: [
          _buildRow(
            'GPS Status',
            monitor.gpsStatus,
            _getGpsColor(monitor.gpsStatus),
          ),
          _buildRow(
            'Speed',
            monitor.gpsStatus == 'ACTIVE'
                ? '${monitor.currentSpeedKmh.toStringAsFixed(1)} km/h'
                : '--',
            monitor.currentSpeedKmh < 2.5 ? Colors.grey : Colors.cyan,
          ),
          _buildRow(
            'Accuracy',
            monitor.gpsStatus == 'ACTIVE'
                ? '${monitor.gpsAccuracy.toStringAsFixed(1)}m'
                : '--',
            monitor.gpsAccuracy > 30
                ? Colors.red
                : monitor.gpsAccuracy > 15
                    ? Colors.orange
                    : Colors.green,
          ),
          _buildRow(
            'Stationary',
            monitor.gpsStatus == 'ACTIVE'
                ? (monitor.gpsIsStationary ? 'YES' : 'NO')
                : '--',
            monitor.gpsIsStationary ? Colors.grey : Colors.green,
          ),
          _buildRow(
            'Location',
            monitor.gpsStatus == 'ACTIVE' && monitor.currentLatitude != 0
                ? '${monitor.currentLatitude.toStringAsFixed(5)}, ${monitor.currentLongitude.toStringAsFixed(5)}'
                : 'No fix',
            Colors.grey.shade500,
          ),
        ],
      ),
    );
  }

  Color _getGpsColor(String status) {
    switch (status) {
      case 'ACTIVE': return Colors.green;
      case 'SEARCHING': return Colors.amber;
      case 'STARTING': return Colors.grey;
      case 'PERMISSION DENIED':
      case 'SERVICE OFF':
      case 'ERROR': return Colors.red;
      default: return Colors.grey;
    }
  }

  Widget _buildDetectionCard(SafetyMonitorService monitor) {
    final phase = monitor.detectionPhase;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Column(
        children: [
          _buildRow(
            'Phase',
            phase,
            _getPhaseColor(phase),
          ),
          _buildRow(
            'Emergency Score',
            '${monitor.emergencyScore}/100',
            _getScoreColor(monitor.emergencyScore),
          ),
          _buildRow(
            'Safety Status',
            monitor.safetyStatus,
            Colors.grey.shade400,
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceCard(SafetyMonitorService monitor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Column(
        children: [
          _buildRow(
            'Voice Detection',
            monitor.voiceDetectionOn ? 'ON' : 'OFF',
            monitor.voiceDetectionOn ? Colors.green : Colors.grey,
          ),
          _buildRow(
            'Microphone',
            monitor.voiceMicStatus,
            monitor.voiceMicStatus == 'ACTIVE'
                ? Colors.green
                : monitor.voiceMicStatus == 'ERROR'
                    ? Colors.red
                    : Colors.grey,
          ),
          _buildRow(
            'Detection State',
            monitor.voiceDetectionStatus,
            Colors.grey.shade400,
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard(SafetyMonitorService monitor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Column(
        children: [
          _buildRow(
            'Foreground Service',
            monitor.isProtecting ? 'RUNNING' : 'STOPPED',
            monitor.isProtecting ? Colors.green : Colors.grey,
          ),
          _buildRow(
            'Orchestrator',
            monitor.orchestrator.state.name.toUpperCase(),
            Colors.grey.shade400,
          ),
          _buildRow(
            'Voice Transcript',
            monitor.voiceTranscript.isNotEmpty
                ? monitor.voiceTranscript
                : 'None',
            Colors.grey.shade500,
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: Colors.grey.shade400,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 2,
      ),
    );
  }

  Color _getPhaseColor(String phase) {
    switch (phase) {
      case 'IDLE': return Colors.grey;
      case 'MOVING': return Colors.green;
      case 'DECELERATING': return Colors.orange;
      case 'STATIONARY': return Colors.yellow;
      case 'DETECTED':
      case 'VERIFYING': return Colors.red;
      default: return Colors.white;
    }
  }

  Color _getScoreColor(int score) {
    if (score >= 70) return Colors.red;
    if (score >= 50) return Colors.orange;
    if (score >= 30) return Colors.yellow;
    return Colors.green;
  }
}

extension<T> on List<T> {
  Iterable<T> takeLast(int count) {
    if (length <= count) return this;
    return skip(length - count);
  }
}
