import 'package:flutter/foundation.dart';
import '../models/sensor_data.dart';
import 'movement_classifier.dart';

/// Combined analysis result from fusing all sensor data.
class FusedAnalysis {
  final double accelerationMagnitude;
  final double rotationMagnitude;
  final double speedKmh;
  final double speedChange;
  final bool hasImpact;
  final bool hasRapidRotation;
  final bool hasSuddenSpeedChange;
  final bool isStationary;
  final DateTime timestamp;

  /// Movement state from multi-sensor classification.
  final MovementState movementState;

  /// Filtered speed used for classification (may differ from raw GPS).
  final double filteredSpeedKmh;

  /// Diagnostic info for debugging.
  final MovementDiagnostics? diagnostics;

  FusedAnalysis({
    required this.accelerationMagnitude,
    required this.rotationMagnitude,
    required this.speedKmh,
    required this.speedChange,
    required this.hasImpact,
    required this.hasRapidRotation,
    required this.hasSuddenSpeedChange,
    required this.isStationary,
    required this.timestamp,
    required this.movementState,
    required this.filteredSpeedKmh,
    this.diagnostics,
  });
}

/// Engine that fuses raw sensor data into high-level analysis.
class SensorFusion {
  double _previousSpeed = 0;
  DateTime? _lastMovementTime;
  final MovementClassifier _classifier = MovementClassifier();

  MovementClassifier get classifier => _classifier;

  /// Analyze a fused sensor state and produce a combined analysis.
  FusedAnalysis analyze(FusedSensorState state) {
    // --- Raw sensor values ---
    final accelMag = state.accelerometer?.magnitude ?? 0;
    final netAccel = state.accelerometer?.netMagnitude ?? 0;
    final hasImpact = netAccel > 30.0; // ~3g impact

    final rotationMag = state.gyroscope?.magnitude ?? 0;
    final hasRapidRotation = rotationMag > 100.0; // 100 degrees/s

    final rawSpeedKmh = state.gps?.speedKmh ?? 0;
    final speedChange = (rawSpeedKmh - _previousSpeed).abs();
    final hasSuddenSpeedChange = speedChange > 20.0; // 20 km/h change
    _previousSpeed = rawSpeedKmh;

    // --- Multi-sensor movement classification ---
    final movementState = _classifier.classify(state);
    final diagnostics = _classifier.lastDiagnostics;

    // Use filtered speed from classifier for isStationary check
    final filteredSpeed = _classifier.filteredSpeedKmh;

    // Inactivity detection using multi-sensor data
    if (netAccel > 1.0 || rotationMag > 10) {
      _lastMovementTime = DateTime.now();
    }
    final secondsSinceMovement = _lastMovementTime != null
        ? DateTime.now().difference(_lastMovementTime!).inSeconds
        : 0;
    // Stationary requires BOTH low filtered speed AND no recent sensor activity
    final isStationary = secondsSinceMovement > 5 && filteredSpeed < 1.5;

    // Log diagnostics periodically (every ~2 seconds at 10Hz = every 20 readings)
    if (diagnostics != null) {
      debugPrint('MovementClassifier: ${diagnostics.toString()}');
    }

    return FusedAnalysis(
      accelerationMagnitude: accelMag,
      rotationMagnitude: rotationMag,
      speedKmh: rawSpeedKmh,
      speedChange: speedChange,
      hasImpact: hasImpact,
      hasRapidRotation: hasRapidRotation,
      hasSuddenSpeedChange: hasSuddenSpeedChange,
      isStationary: isStationary,
      timestamp: state.timestamp,
      movementState: movementState,
      filteredSpeedKmh: filteredSpeed,
      diagnostics: diagnostics,
    );
  }

  /// Reset internal state (e.g. when starting a new monitoring session)
  void reset() {
    _previousSpeed = 0;
    _lastMovementTime = null;
    _classifier.reset();
  }
}
