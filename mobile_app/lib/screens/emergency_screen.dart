import 'package:flutter/material.dart';
import '../models/emergency_event.dart';

/// Full-screen emergency overlay shown when a possible emergency is detected.
/// Displays countdown, action buttons, and emergency status.
///
/// Uses data directly from EmergencyOrchestrator (not VerificationSystem),
/// since the orchestrator owns the countdown timer and emergency event.
class EmergencyScreen extends StatelessWidget {
  final int remainingSeconds;
  final EmergencyEvent? currentEvent;
  final VoidCallback? onOk;
  final VoidCallback? onHelp;

  const EmergencyScreen({
    super.key,
    required this.remainingSeconds,
    this.currentEvent,
    this.onOk,
    this.onHelp,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.97),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),

              // Warning icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withOpacity(0.2),
                  border: Border.all(color: Colors.red, width: 3),
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  color: Colors.red,
                  size: 50,
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'POSSIBLE EMERGENCY\nDETECTED',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                'ARE YOU ALRIGHT?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 16),

              // Countdown timer
              Text(
                remainingSeconds.toString(),
                style: TextStyle(
                  color: remainingSeconds <= 10 ? Colors.red : Colors.white,
                  fontSize: 72,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'seconds remaining',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),

              const SizedBox(height: 20),

              // Emergency details
              if (currentEvent != null) ...[
                _buildDetailRow(
                  'Score',
                  '${currentEvent!.emergencyScore}/100',
                  Colors.red,
                ),
                if (currentEvent!.location != null) ...[
                  const SizedBox(height: 6),
                  _buildDetailRow(
                    'Location',
                    '${(currentEvent!.location!['latitude'] as num?)?.toStringAsFixed(5) ?? "N/A"}, '
                        '${(currentEvent!.location!['longitude'] as num?)?.toStringAsFixed(5) ?? "N/A"}',
                    Colors.cyan,
                  ),
                ],
                if (currentEvent!.speedKmh != null && currentEvent!.speedKmh! > 0) ...[
                  const SizedBox(height: 6),
                  _buildDetailRow(
                    'Speed at event',
                    '${currentEvent!.speedKmh!.toStringAsFixed(1)} km/h',
                    Colors.orange,
                  ),
                ],
              ],

              const Spacer(flex: 2),

              // I'M OK button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: onOk,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    "I'M OK",
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // I NEED HELP button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: onHelp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'I NEED HELP',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
