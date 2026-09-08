import 'package:flutter/foundation.dart';
import '../config/thresholds.dart';
import '../models/sensor_data.dart';
import '../models/emergency_event.dart';

/// A single speed record with timestamp.
class SpeedRecord {
  final double speedKmh;
  final DateTime timestamp;

  SpeedRecord({required this.speedKmh, required this.timestamp});
}

/// Detection phases for the speed-drop detector.
enum DetectionPhase {
  idle,
  moving,
  decelerating,
  stationary,
  detected,
  verifying,
}

/// Callback when an emergency is detected.
typedef EmergencyDetectedCallback = void Function(EmergencyEvent event);

/// Core engine that detects emergencies based on GPS speed patterns.
///
/// Detection logic:
/// 1. Track speed history continuously
/// 2. Detect when user was moving (speed > movingThreshold) and
///    speed suddenly drops by dropMagnitude within dropWindow
/// 3. Confirm speed stays near zero for persistenceDuration
/// 4. Trigger emergency verification
///
/// Multi-sensor scoring:
/// - GPS speed drop is the PRIMARY trigger
/// - Accelerometer impact and gyroscope rotation boost the score
/// - Higher pre-drop speed + larger drop + impact + rotation = higher score
class SpeedDropDetector extends ChangeNotifier {
  final List<SpeedRecord> _speedHistory = [];
  DetectionPhase _phase = DetectionPhase.idle;
  DateTime? _decelerationTime;
  DateTime? _movingStartTime;
  double _preDropMaxSpeed = 0;
  int _lastDetectedScore = 0;
  EmergencyDetectedCallback? _onEmergencyDetected;
  bool _hasTriggeredCurrentEvent = false;
  String? _lastTriggeredEventId;

  // Multi-sensor tracking during movement phase
  double _peakAccelDuringMovement = 0;
  double _peakGyroDuringMovement = 0;
  double _lastAccelNet = 0;
  double _lastGyroMag = 0;

  DetectionPhase get phase => _phase;
  int get lastDetectedScore => _lastDetectedScore;
  bool get isDetecting =>
      _phase == DetectionPhase.detected || _phase == DetectionPhase.verifying;

  /// Recent speed history for display
  List<SpeedRecord> get speedHistory => List.unmodifiable(_speedHistory);

  /// Set the callback for emergency detection
  void setCallback(EmergencyDetectedCallback callback) {
    _onEmergencyDetected = callback;
  }

  /// Feed multi-sensor data for scoring enrichment.
  /// Called from SafetyMonitorService on each fused sensor update.
  void updateSensorData(double accelNetMagnitude, double gyroMagnitude) {
    _lastAccelNet = accelNetMagnitude;
    _lastGyroMag = gyroMagnitude;

    // Track peaks during movement phase for scoring
    if (_phase == DetectionPhase.moving) {
      if (accelNetMagnitude > _peakAccelDuringMovement) {
        _peakAccelDuringMovement = accelNetMagnitude;
      }
      if (gyroMagnitude > _peakGyroDuringMovement) {
        _peakGyroDuringMovement = gyroMagnitude;
      }
    }
  }

  /// Called when the user responds to verification (OK or Help)
  void onVerificationComplete() {
    _phase = DetectionPhase.idle;
    _hasTriggeredCurrentEvent = false;
    _decelerationTime = null;
    _movingStartTime = null;
    _preDropMaxSpeed = 0;
    _lastDetectedScore = 0;
    _peakAccelDuringMovement = 0;
    _peakGyroDuringMovement = 0;
    notifyListeners();
  }

  /// Process a new GPS data point
  void onGpsUpdate(GpsData gpsData) {
    final speed = gpsData.speedKmh;
    final now = gpsData.timestamp;

    // Add to history
    _speedHistory.add(SpeedRecord(speedKmh: speed, timestamp: now));
    _pruneHistory(now);

    switch (_phase) {
      case DetectionPhase.idle:
        _handleIdle(speed, now);
        break;
      case DetectionPhase.moving:
        _handleMoving(speed, now);
        break;
      case DetectionPhase.decelerating:
        _handleDecelerating(speed, now);
        break;
      case DetectionPhase.stationary:
        _handleStationary(speed, now, gpsData);
        break;
      case DetectionPhase.detected:
      case DetectionPhase.verifying:
        // Don't process new data during verification
        break;
    }

    notifyListeners();
  }

  void _handleIdle(double speed, DateTime now) {
    if (speed > EmergencySpeedThresholds.movingSpeedThreshold) {
      _phase = DetectionPhase.moving;
      _movingStartTime = now;
      // Reset multi-sensor peaks for this movement session
      _peakAccelDuringMovement = _lastAccelNet;
      _peakGyroDuringMovement = _lastGyroMag;
    }
  }

  void _handleMoving(double speed, DateTime now) {
    final movingDuration =
        _movingStartTime != null ? now.difference(_movingStartTime!).inSeconds : 0;

    // Check if speed has suddenly dropped
    final dropDetected = _detectSpeedDrop(speed, now);

    if (dropDetected &&
        movingDuration >= EmergencySpeedThresholds.minimumMovingDuration) {
      _phase = DetectionPhase.decelerating;
      _decelerationTime = now;
      _preDropMaxSpeed = _getRecentMaxSpeed(now);
    } else if (speed < EmergencySpeedThresholds.stationaryThreshold) {
      _phase = DetectionPhase.idle;
      _movingStartTime = null;
    }
  }

  void _handleDecelerating(double speed, DateTime now) {
    if (speed < EmergencySpeedThresholds.stationaryThreshold) {
      _phase = DetectionPhase.stationary;
    } else if (speed > EmergencySpeedThresholds.movingSpeedThreshold) {
      _phase = DetectionPhase.moving;
      _movingStartTime = now;
      _decelerationTime = null;
      _peakAccelDuringMovement = _lastAccelNet;
      _peakGyroDuringMovement = _lastGyroMag;
    }
  }

  void _handleStationary(double speed, DateTime now, GpsData gpsData) {
    if (speed > EmergencySpeedThresholds.movingSpeedThreshold) {
      _phase = DetectionPhase.moving;
      _movingStartTime = now;
      _decelerationTime = null;
      _peakAccelDuringMovement = _lastAccelNet;
      _peakGyroDuringMovement = _lastGyroMag;
      return;
    }

    if (speed >= EmergencySpeedThresholds.stationaryThreshold) {
      _phase = DetectionPhase.decelerating;
      return;
    }

    if (_decelerationTime != null) {
      final secondsSinceDrop = now.difference(_decelerationTime!).inSeconds;
      if (secondsSinceDrop >= EmergencySpeedThresholds.persistenceDuration) {
        _triggerEmergency(gpsData);
      }
    }
  }

  bool _detectSpeedDrop(double currentSpeed, DateTime now) {
    const windowDuration = Duration(
      seconds: EmergencySpeedThresholds.speedDropWindowSeconds,
    );

    final recentRecords = _speedHistory
        .where((r) => now.difference(r.timestamp) <= windowDuration)
        .toList();

    if (recentRecords.isEmpty) return false;

    double maxRecentSpeed = 0;
    for (final record in recentRecords) {
      if (record.speedKmh > maxRecentSpeed) {
        maxRecentSpeed = record.speedKmh;
      }
    }

    if (maxRecentSpeed >= EmergencySpeedThresholds.movingSpeedThreshold) {
      final dropMagnitude = maxRecentSpeed - currentSpeed;
      if (dropMagnitude >= EmergencySpeedThresholds.speedDropMagnitude) {
        return true;
      }
    }

    return false;
  }

  double _getRecentMaxSpeed(DateTime now) {
    const window = Duration(
      seconds: EmergencySpeedThresholds.speedDropWindowSeconds,
    );
    double maxSpeed = 0;
    for (final record in _speedHistory) {
      if (now.difference(record.timestamp) <= window) {
        if (record.speedKmh > maxSpeed) {
          maxSpeed = record.speedKmh;
        }
      }
    }
    return maxSpeed;
  }

  void _triggerEmergency(GpsData gpsData) {
    final eventId = _decelerationTime?.millisecondsSinceEpoch.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();

    if (_hasTriggeredCurrentEvent && _lastTriggeredEventId == eventId) {
      return;
    }

    _phase = DetectionPhase.detected;
    _hasTriggeredCurrentEvent = true;
    _lastTriggeredEventId = eventId;

    final dropMagnitude = _preDropMaxSpeed - gpsData.speedKmh;
    final score = _calculateMultiSensorScore(
      _preDropMaxSpeed,
      dropMagnitude,
      _peakAccelDuringMovement,
      _peakGyroDuringMovement,
    );
    _lastDetectedScore = score;

    final event = EmergencyEvent(
      id: eventId,
      timestamp: DateTime.now(),
      emergencyScore: score,
      activityType: ActivityType.emergency,
      status: EmergencyStatus.possibleEmergency,
      impactMagnitude: _peakAccelDuringMovement,
      speedKmh: _preDropMaxSpeed,
      rotationSpeed: _peakGyroDuringMovement,
      location: {
        'latitude': gpsData.latitude,
        'longitude': gpsData.longitude,
      },
    );

    _onEmergencyDetected?.call(event);
    notifyListeners();
  }

  /// Multi-sensor emergency score (0-100).
  ///
  /// Combines GPS speed drop with accelerometer impact and gyroscope rotation
  /// for a more reliable accident confidence score.
  int _calculateMultiSensorScore(
    double preDropSpeed,
    double dropMagnitude,
    double peakAccel,
    double peakGyro,
  ) {
    double score = 0;

    // --- GPS speed component (0-40 points) ---
    if (preDropSpeed >= 80) {
      score += 40;
    } else if (preDropSpeed >= 60) {
      score += 35;
    } else if (preDropSpeed >= 40) {
      score += 30;
    } else if (preDropSpeed >= 20) {
      score += 20;
    } else {
      score += 10;
    }

    // --- Speed drop magnitude (0-25 points) ---
    if (dropMagnitude >= 60) {
      score += 25;
    } else if (dropMagnitude >= 40) {
      score += 20;
    } else if (dropMagnitude >= 20) {
      score += 15;
    } else {
      score += 8;
    }

    // --- Accelerometer impact (0-20 points) ---
    // Net acceleration > 30 m/s² (~3g) = significant impact
    if (peakAccel >= 50) {
      score += 20;
    } else if (peakAccel >= 30) {
      score += 15;
    } else if (peakAccel >= 15) {
      score += 8;
    } else if (peakAccel >= 5) {
      score += 3;
    }

    // --- Gyroscope rotation (0-10 points) ---
    // Rotation > 100 deg/s = device tumbling/spinning
    if (peakGyro >= 200) {
      score += 10;
    } else if (peakGyro >= 100) {
      score += 7;
    } else if (peakGyro >= 50) {
      score += 4;
    }

    // --- Persistence confirmed (5 points) ---
    score += 5;

    // Clamp to [0, 100]
    return score.clamp(0, 100).toInt();
  }

  void _pruneHistory(DateTime now) {
    _speedHistory.removeWhere(
      (r) =>
          now.difference(r.timestamp).inSeconds >
          EmergencySpeedThresholds.speedHistoryMaxSeconds,
    );
  }

  void reset() {
    _speedHistory.clear();
    _phase = DetectionPhase.idle;
    _decelerationTime = null;
    _movingStartTime = null;
    _preDropMaxSpeed = 0;
    _lastDetectedScore = 0;
    _hasTriggeredCurrentEvent = false;
    _lastTriggeredEventId = null;
    _peakAccelDuringMovement = 0;
    _peakGyroDuringMovement = 0;
    _lastAccelNet = 0;
    _lastGyroMag = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _speedHistory.clear();
    super.dispose();
  }
}
