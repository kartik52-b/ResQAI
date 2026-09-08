import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/safety_monitor_service.dart';

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

                // Large Speed Display
                if (monitor.gpsStatus == 'ACTIVE')
                  _buildSpeedDisplay(monitor),
                if (monitor.gpsStatus == 'ACTIVE')
                  const SizedBox(height: 20),

                // GPS Section
                _buildSectionTitle('GPS'),
                const SizedBox(height: 8),
                _buildGpsCard(monitor),
                const SizedBox(height: 20),

                // Sensors
                _buildSectionTitle('Sensors'),
                const SizedBox(height: 8),
                _buildSensorsCard(monitor),
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
                      color: Colors.red.withValues(alpha: 0.1),
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
                      color: Colors.black.withValues(alpha: 0.4),
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
                      color: Colors.black.withValues(alpha: 0.4),
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

                // Demo Mode (for judge presentation)
                _buildSectionTitle('Demo Mode'),
                const SizedBox(height: 8),
                _buildDemoModeCard(monitor),
                const SizedBox(height: 20),

                // Developer Test Mode
                _buildSectionTitle('Developer / Test Mode'),
                const SizedBox(height: 8),
                _buildTestModeCard(monitor),

                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpeedDisplay(SafetyMonitorService monitor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
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
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                monitor.currentSpeedKmh.toStringAsFixed(1),
                style: TextStyle(
                  color: monitor.currentSpeedKmh < 2.5
                      ? Colors.grey
                      : monitor.currentSpeedKmh < 30
                          ? Colors.cyan
                          : Colors.orange,
                  fontSize: 56,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 10, left: 4),
                child: Text(
                  'km/h',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Raw vs Filtered speed comparison
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSpeedChip('RAW', monitor.rawSpeedKmh, Colors.orange),
              const SizedBox(width: 12),
              _buildSpeedChip('FILTERED', monitor.currentSpeedKmh, Colors.cyan),
              const SizedBox(width: 12),
              _buildSpeedChip(
                'GPS',
                0,
                monitor.gpsStatus == 'ACTIVE' ? Colors.green : Colors.red,
                isStatus: true,
                statusText: monitor.gpsStatus,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSpeedChip(
                'STATE',
                0,
                monitor.gpsIsStationary ? Colors.grey : Colors.cyan,
                isStatus: true,
                statusText: monitor.gpsIsStationary ? 'STILL' : 'MOVING',
              ),
              const SizedBox(width: 12),
              _buildSpeedChip(
                'ACC',
                0,
                monitor.gpsAccuracy > 30
                    ? Colors.red
                    : monitor.gpsAccuracy > 15
                        ? Colors.orange
                        : Colors.green,
                isStatus: true,
                statusText: '${monitor.gpsAccuracy.toStringAsFixed(0)}m',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedChip(String label, double value, Color color,
      {bool isStatus = false, String? statusText}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
          const SizedBox(height: 2),
          Text(
            isStatus ? statusText! : '${value.toStringAsFixed(1)} km/h',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorsCard(SafetyMonitorService monitor) {
    final accelActive = monitor.sensorManager.isRunning &&
        monitor.sensorManager.accelerometerHealthy;
    final gyroActive = monitor.sensorManager.isRunning &&
        monitor.sensorManager.gyroscopeHealthy;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(
        children: [
          _buildRow(
            'Accelerometer',
            accelActive ? 'ACTIVE' : 'INACTIVE',
            accelActive ? Colors.green : Colors.red,
          ),
          _buildRow(
            'Gyroscope',
            gyroActive ? 'ACTIVE' : 'INACTIVE',
            gyroActive ? Colors.green : Colors.red,
          ),
          _buildRow(
            'GPS',
            monitor.gpsStatus,
            _getGpsColor(monitor.gpsStatus),
          ),
          _buildRow(
            'Fusion Timer',
            monitor.isProtecting ? 'RUNNING (10Hz)' : 'STOPPED',
            monitor.isProtecting ? Colors.green : Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildGpsCard(SafetyMonitorService monitor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(
        children: [
          _buildRow(
            'GPS Status',
            monitor.gpsStatus,
            _getGpsColor(monitor.gpsStatus),
          ),
          _buildRow(
            'Filtered Speed',
            monitor.gpsStatus == 'ACTIVE'
                ? '${monitor.currentSpeedKmh.toStringAsFixed(1)} km/h'
                : '--',
            monitor.currentSpeedKmh < 2.5 ? Colors.grey : Colors.cyan,
          ),
          _buildRow(
            'Raw Speed',
            monitor.gpsStatus == 'ACTIVE'
                ? '${monitor.rawSpeedKmh.toStringAsFixed(1)} km/h'
                : '--',
            Colors.orange,
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
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
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
    final voiceActive = monitor.voiceDetectionOn && monitor.isProtecting;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(
        children: [
          _buildRow(
            'Voice Detection',
            voiceActive ? 'AUTO-ACTIVE' : (monitor.isProtecting ? 'REQUESTING...' : 'OFF'),
            voiceActive ? Colors.green : Colors.grey,
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
          _buildRow(
            'Mode',
            'Automatic (starts with Protection)',
            Colors.grey.shade600,
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard(SafetyMonitorService monitor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
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
      case 'NORMALMOVING': return Colors.green;
      case 'MOVING': return Colors.green;
      case 'DECELERATING':
      case 'SUDDENDECELERATION': return Colors.orange;
      case 'POSSIBLEIMPACT': return Colors.red.shade300;
      case 'POSTEVENTINACTIVITY': return Colors.red.shade200;
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

  Widget _buildDemoModeCard(SafetyMonitorService monitor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: monitor.demoMode
            ? Colors.teal.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: monitor.demoMode
              ? Colors.teal.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.present_to_all,
                  size: 18,
                  color: monitor.demoMode ? Colors.teal : Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Demo Mode (Judge Presentation)',
                  style: TextStyle(
                    color: monitor.demoMode ? Colors.teal : Colors.grey.shade400,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Switch(
                value: monitor.demoMode,
                onChanged: (v) => monitor.toggleDemoMode(v),
                activeThumbColor: Colors.teal,
              ),
            ],
          ),
          if (monitor.demoMode) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer, color: Colors.teal, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Emergency timeout: 15 seconds (instead of 120s).\n'
                      'Use Test Mode presets to simulate accidents.',
                      style: TextStyle(
                        color: Colors.teal.shade300,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTestModeCard(SafetyMonitorService monitor) {
    return _TestModeCard(monitor: monitor);
  }
}

/// Stateful test mode card with speed/accel/gyro sliders.
class _TestModeCard extends StatefulWidget {
  final SafetyMonitorService monitor;
  const _TestModeCard({required this.monitor});

  @override
  State<_TestModeCard> createState() => _TestModeCardState();
}

class _TestModeCardState extends State<_TestModeCard> {
  double _testSpeed = 0;
  double _testAccel = 0;
  double _testGyro = 0;

  @override
  Widget build(BuildContext context) {
    final monitor = widget.monitor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: monitor.testMode
            ? Colors.orange.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: monitor.testMode
              ? Colors.orange.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science,
                  size: 18,
                  color: monitor.testMode ? Colors.orange : Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Test Mode',
                  style: TextStyle(
                    color: monitor.testMode ? Colors.orange : Colors.grey.shade400,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Switch(
                value: monitor.testMode,
                onChanged: (v) => monitor.toggleTestMode(v),
                activeThumbColor: Colors.orange,
              ),
            ],
          ),
          if (monitor.testMode) ...[
            const SizedBox(height: 12),
            Text(
              'Simulated data feeds the REAL detection engines.',
              style: TextStyle(
                color: Colors.orange.shade300,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
            _buildSlider(
              label: 'Speed',
              value: _testSpeed,
              min: 0,
              max: 120,
              unit: 'km/h',
              onChanged: (v) => setState(() => _testSpeed = v),
            ),
            const SizedBox(height: 12),
            _buildSlider(
              label: 'Impact (accel)',
              value: _testAccel,
              min: 0,
              max: 100,
              unit: 'm/s²',
              onChanged: (v) => setState(() => _testAccel = v),
            ),
            const SizedBox(height: 12),
            _buildSlider(
              label: 'Rotation (gyro)',
              value: _testGyro,
              min: 0,
              max: 300,
              unit: 'deg/s',
              onChanged: (v) => setState(() => _testGyro = v),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: monitor.isProtecting
                    ? () {
                        monitor.injectTestData(
                          speedKmh: _testSpeed,
                          accelNet: _testAccel,
                          gyroMag: _testGyro,
                        );
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  monitor.isProtecting
                      ? 'INJECT DATA'
                      : 'Enable Protection First',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'PRESET SCENARIOS',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPresetButton('Walking', 4, 1.5, 10, monitor),
                _buildPresetButton('Cycling', 20, 2, 25, monitor),
                _buildPresetButton('Driving 60', 60, 3, 15, monitor),
                _buildPresetButton('Stationary', 0, 0.5, 2, monitor),
                _buildPresetButton('Sudden Stop', 60, 40, 90, monitor),
                _buildPresetButton('Impact Only', 0, 80, 120, monitor),
                _buildPresetButton('Fall (walk)', 4, 25, 85, monitor),
                _buildPresetButton('Crash 80', 80, 60, 200, monitor),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
            Text('${value.toStringAsFixed(1)} $unit',
                style: const TextStyle(
                    color: Colors.orange, fontSize: 12, fontFamily: 'monospace')),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.orange,
            inactiveTrackColor: Colors.grey.shade800,
            thumbColor: Colors.orange,
            overlayColor: Colors.orange.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildPresetButton(
    String label,
    double speed,
    double accel,
    double gyro,
    SafetyMonitorService monitor,
  ) {
    return ElevatedButton(
      onPressed: monitor.isProtecting
          ? () {
              setState(() {
                _testSpeed = speed;
                _testAccel = accel;
                _testGyro = gyro;
              });
              monitor.injectTestData(
                speedKmh: speed,
                accelNet: accel,
                gyroMag: gyro,
              );
            }
          : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange.withValues(alpha: 0.15),
        foregroundColor: Colors.orange,
        disabledBackgroundColor: Colors.grey.shade800,
        disabledForegroundColor: Colors.grey.shade600,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}

extension<T> on List<T> {
  Iterable<T> takeLast(int count) {
    if (length <= count) return this;
    return skip(length - count);
  }
}
