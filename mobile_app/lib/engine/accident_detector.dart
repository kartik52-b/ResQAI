import 'package:flutter/foundation.dart';
import '../config/thresholds.dart';
import '../models/sensor_data.dart';
import '../models/emergency_event.dart';

/// Accident detection phases — strict state machine.
///
/// Only advances to VERIFYING when MULTIPLE independent signals agree.
/// Normal traffic stops, parking, walking must NOT trigger verification.
enum AccidentPhase {
  /// No movement detected. Waiting for movement to begin.
  idle,

  /// User is moving at sufficient speed. Monitoring for anomalies.
  normalMoving,

  /// GPS speed dropped rapidly while previously moving.
  /// Awaiting additional sensor confirmation (impact/rotation).
  suddenDeceleration,

  /// Accelerometer or gyroscope detected an anomaly during deceleration.
  /// Awaiting post-event inactivity to confirm the event was real.
  possibleImpact,

  /// Impact confirmed. Device is now stationary.
  /// Waiting for sustained inactivity before entering verification.
  postEventInactivity,

  /// Emergency confirmed via multi-sensor analysis.
  /// "Are you alright?" has been spoken. 120-second countdown active.
  verifying,
}

/// Callback when accident is detected and enters verification.
typedef AccidentDetectedCallback = void Function(EmergencyEvent event);

/// Detailed log entry for each detection transition.
class DetectionLog {
  final DateTime timestamp;
  final AccidentPhase fromPhase;
  final AccidentPhase toPhase;
  final String reason;
  final double gpsSpeedKmh;
  final double filteredSpeedKmh;
  final double accelNet;
  final double gyroMag;
  final double decelerationRate;
  final bool impactDetected;
  final bool rotationDetected;
  final int confidenceSignals;

  DetectionLog({
    required this.timestamp,
    required this.fromPhase,
    required this.toPhase,
    required this.reason,
    required this.gpsSpeedKmh,
    required this.filteredSpeedKmh,
    required this.accelNet,
    required this.gyroMag,
    required this.decelerationRate,
    required this.impactDetected,
    required this.rotationDetected,
    required this.confidenceSignals,
  });

  @override
  String toString() =>
      '[${timestamp.hour.toString().padLeft(2, '0')}:'
      '${timestamp.minute.toString().padLeft(2, '0')}:'
      '${timestamp.second.toString().padLeft(2, '0')}] '
      '${fromPhase.name.toUpperCase()} → ${toPhase.name.toUpperCase()}: $reason '
      '| GPS:${gpsSpeedKmh.toStringAsFixed(1)} '
      'filt:${filteredSpeedKmh.toStringAsFixed(1)} '
      'A:${accelNet.toStringAsFixed(1)} '
      'G:${gyroMag.toStringAsFixed(1)} '
      'decel:${decelerationRate.toStringAsFixed(1)} '
      'signals:$confidenceSignals';
}

/// Multi-sensor accident detection engine.
///
/// State machine:
///   IDLE → NORMAL_MOVING → SUDDEN_DECELERATION → POSSIBLE_IMPACT
///   → POST_EVENT_INACTIVITY → VERIFYING
///
/// Only enters VERIFYING when:
///   1. User was moving at significant speed
///   2. Speed dropped suddenly (GPS)
///   3. AND at least one of: impact (accel) or abnormal rotation (gyro)
///   4. AND device became stationary and stayed stationary
///
/// Normal stops (traffic lights, parking, walking) fail step 2 or 3.
class AccidentDetector {
  AccidentPhase _phase = AccidentPhase.idle;
  VoidCallback? onUpdate;
  AccidentDetectedCallback? _onAccidentDetected;
  bool _hasTriggered = false;
  String? _lastTriggeredEventId;

  // --- Speed tracking ---
  double _previousSpeedKmh = 0;
  DateTime? _previousSpeedTimestamp;
  double _maxSpeedDuringMovement = 0;
  DateTime? _movementStartTime;

  // --- Deceleration tracking ---
  DateTime? _decelerationStartTime;
  double _speedAtDecelerationStart = 0;
  double _decelerationRate = 0; // km/h per second

  // --- Sensor anomaly tracking ---
  double _peakAccelDuringDeceleration = 0;
  double _peakGyroDuringDeceleration = 0;
  bool _impactDetectedDuringDecel = false;
  bool _rotationDetectedDuringDecel = false;

  // --- Post-impact tracking ---
  DateTime? _impactConfirmedTime;
  int _stationaryCountAfterImpact = 0;

  // --- Current sensor values (for logging) ---
  double _lastAccelNet = 0;
  double _lastGyroMag = 0;

  // --- Detection log ---
  final List<DetectionLog> _detectionLog = [];
  static const int _maxLogEntries = 50;

  AccidentPhase get phase => _phase;
  bool get isDetecting =>
      _phase == AccidentPhase.possibleImpact ||
      _phase == AccidentPhase.postEventInactivity ||
      _phase == AccidentPhase.verifying;
  int get lastDetectedScore => _lastScore;
  List<DetectionLog> get detectionLog => List.unmodifiable(_detectionLog);
  int _lastScore = 0;

  /// Set callback for accident detection.
  void setCallback(AccidentDetectedCallback callback) {
    _onAccidentDetected = callback;
  }

  /// Feed fused sensor data (accelerometer + gyroscope).
  /// Called from SafetyMonitorService on each fused sensor update (~10Hz).
  void updateSensorData(double accelNetMagnitude, double gyroMagnitude) {
    _lastAccelNet = accelNetMagnitude;
    _lastGyroMag = gyroMagnitude;

    // Track anomalies during deceleration phase
    if (_phase == AccidentPhase.suddenDeceleration ||
        _phase == AccidentPhase.possibleImpact) {
      if (accelNetMagnitude > AccidentThresholds.impactThreshold) {
        _impactDetectedDuringDecel = true;
        if (accelNetMagnitude > _peakAccelDuringDeceleration) {
          _peakAccelDuringDeceleration = accelNetMagnitude;
        }
      }
      if (gyroMagnitude > AccidentThresholds.rotationThreshold) {
        _rotationDetectedDuringDecel = true;
        if (gyroMagnitude > _peakGyroDuringDeceleration) {
          _peakGyroDuringDeceleration = gyroMagnitude;
        }
      }

      // If we're in suddenDeceleration and now have an impact signal, advance
      if (_phase == AccidentPhase.suddenDeceleration &&
          (_impactDetectedDuringDecel || _rotationDetectedDuringDecel)) {
        _transition(
          AccidentPhase.possibleImpact,
          _impactDetectedDuringDecel
              ? 'Impact detected (accel=${_peakAccelDuringDeceleration.toStringAsFixed(1)} m/s²)'
              : 'Abnormal rotation detected (gyro=${_peakGyroDuringDeceleration.toStringAsFixed(1)} deg/s)',
        );
      }
    }
  }

  /// Process a new GPS data point — the main detection loop.
  void onGpsUpdate(GpsData gpsData) {
    final speed = gpsData.speedKmh;
    final now = gpsData.timestamp;

    switch (_phase) {
      case AccidentPhase.idle:
        _handleIdle(speed, now);
        break;
      case AccidentPhase.normalMoving:
        _handleNormalMoving(speed, now, gpsData);
        break;
      case AccidentPhase.suddenDeceleration:
        _handleSuddenDeceleration(speed, now, gpsData);
        break;
      case AccidentPhase.possibleImpact:
        _handlePossibleImpact(speed, now, gpsData);
        break;
      case AccidentPhase.postEventInactivity:
        _handlePostEventInactivity(speed, now, gpsData);
        break;
      case AccidentPhase.verifying:
        // Do not process new data during verification
        break;
    }

    _previousSpeedKmh = speed;
    _previousSpeedTimestamp = now;
    onUpdate?.call();
  }

  // ====================================================================
  // STATE HANDLERS
  // ====================================================================

  void _handleIdle(double speed, DateTime now) {
    if (speed > AccidentThresholds.movingSpeedThreshold) {
      _movementStartTime = now;
      _maxSpeedDuringMovement = speed;
      _resetDecelerationTracking();
      _resetImpactTracking();
      _transition(AccidentPhase.normalMoving,
          'Movement started at ${speed.toStringAsFixed(1)} km/h');
    }
  }

  void _handleNormalMoving(double speed, DateTime now, GpsData gpsData) {
    // Track max speed during this movement session
    if (speed > _maxSpeedDuringMovement) {
      _maxSpeedDuringMovement = speed;
    }

    // Calculate deceleration rate
    final decel = _calculateDeceleration(speed, now);

    // Check for sudden deceleration
    if (decel > AccidentThresholds.decelerationRateThreshold &&
        _maxSpeedDuringMovement >= AccidentThresholds.movingSpeedThreshold) {
      _decelerationStartTime = now;
      _speedAtDecelerationStart = _previousSpeedKmh;
      _peakAccelDuringDeceleration = _lastAccelNet;
      _peakGyroDuringDeceleration = _lastGyroMag;
      _impactDetectedDuringDecel = false;
      _rotationDetectedDuringDecel = false;
      _decelerationRate = decel;

      // Check if impact/rotation already present at moment of deceleration
      if (_lastAccelNet > AccidentThresholds.impactThreshold) {
        _impactDetectedDuringDecel = true;
        _peakAccelDuringDeceleration = _lastAccelNet;
      }
      if (_lastGyroMag > AccidentThresholds.rotationThreshold) {
        _rotationDetectedDuringDecel = true;
        _peakGyroDuringDeceleration = _lastGyroMag;
      }

      _transition(
        AccidentPhase.suddenDeceleration,
        'Speed dropped from ${_maxSpeedDuringMovement.toStringAsFixed(1)} → '
        '${speed.toStringAsFixed(1)} km/h '
        '(decel=${decel.toStringAsFixed(1)} km/h/s, '
        'impact=${_impactDetectedDuringDecel}, '
        'rotation=${_rotationDetectedDuringDecel})',
      );
    } else if (speed < AccidentThresholds.stationaryThreshold) {
      // Slow movement or stopped — no anomaly, return to idle
      _movementStartTime = null;
      _maxSpeedDuringMovement = 0;
      _transition(AccidentPhase.idle,
          'Speed dropped to ${speed.toStringAsFixed(1)} km/h without anomaly');
    }
  }

  void _handleSuddenDeceleration(double speed, DateTime now, GpsData gpsData) {
    // If speed recovers, the deceleration was normal (e.g., braking for traffic)
    if (speed > AccidentThresholds.movingSpeedThreshold) {
      _resetDecelerationTracking();
      _resetImpactTracking();
      _movementStartTime = now;
      _maxSpeedDuringMovement = speed;
      _transition(AccidentPhase.normalMoving,
          'Speed recovered to ${speed.toStringAsFixed(1)} km/h — normal braking');
      return;
    }

    // If speed is still dropping and we've been in this phase too long without
    // impact/rotation signal, this is probably normal deceleration
    if (_decelerationStartTime != null) {
      final elapsed = now.difference(_decelerationStartTime!).inSeconds;
      if (elapsed > AccidentThresholds.decelerationTimeoutSeconds &&
          !_impactDetectedDuringDecel &&
          !_rotationDetectedDuringDecel) {
        _transition(AccidentPhase.idle,
            'No impact/rotation signal after ${elapsed}s — normal deceleration');
        _resetDecelerationTracking();
        _resetImpactTracking();
      }
    }

    // If speed is now near zero, advance to possibleImpact (waiting for confirmation)
    if (speed < AccidentThresholds.stationaryThreshold &&
        (_impactDetectedDuringDecel || _rotationDetectedDuringDecel)) {
      _impactConfirmedTime = now;
      _stationaryCountAfterImpact = 0;
      _transition(AccidentPhase.possibleImpact,
          'Speed near zero with ${_impactDetectedDuringDecel ? "impact" : "rotation"} confirmed');
    }
  }

  void _handlePossibleImpact(double speed, DateTime now, GpsData gpsData) {
    // If speed recovers, this was a false alarm
    if (speed > AccidentThresholds.movingSpeedThreshold) {
      _transition(AccidentPhase.normalMoving,
          'Speed recovered to ${speed.toStringAsFixed(1)} km/h — false alarm');
      _resetDecelerationTracking();
      _resetImpactTracking();
      _movementStartTime = now;
      _maxSpeedDuringMovement = speed;
      return;
    }

    // Count consecutive stationary readings
    if (speed < AccidentThresholds.stationaryThreshold) {
      _stationaryCountAfterImpact++;
    } else {
      _stationaryCountAfterImpact = 0;
    }

    // Require sustained stationary state
    if (_stationaryCountAfterImpact >= AccidentThresholds.stationaryCountRequired) {
      _transition(AccidentPhase.postEventInactivity,
          'Device stationary for ${_stationaryCountAfterImpact} consecutive readings');
    }
  }

  void _handlePostEventInactivity(double speed, DateTime now, GpsData gpsData) {
    // If speed recovers, false alarm
    if (speed > AccidentThresholds.movingSpeedThreshold) {
      _transition(AccidentPhase.normalMoving,
          'Speed recovered — false alarm during inactivity check');
      _resetDecelerationTracking();
      _resetImpactTracking();
      _movementStartTime = now;
      _maxSpeedDuringMovement = speed;
      return;
    }

    // Check if inactivity has persisted long enough
    if (_impactConfirmedTime != null) {
      final secondsSinceImpact = now.difference(_impactConfirmedTime!).inSeconds;

      if (secondsSinceImpact >= AccidentThresholds.postImpactInactivitySeconds) {
        // All conditions met — trigger emergency
        _triggerEmergency(gpsData, secondsSinceImpact);
      }
    }
  }

  // ====================================================================
  // EMERGENCY TRIGGER
  // ====================================================================

  void _triggerEmergency(GpsData gpsData, int secondsSinceImpact) {
    final eventId = _decelerationStartTime?.millisecondsSinceEpoch.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();

    if (_hasTriggered && _lastTriggeredEventId == eventId) {
      return; // Prevent duplicate triggers
    }

    _hasTriggered = true;
    _lastTriggeredEventId = eventId;

    // Calculate confidence score
    final score = _calculateConfidenceScore(secondsSinceImpact);
    _lastScore = score;

    _transition(AccidentPhase.verifying,
        'EMERGENCY CONFIRMED — score=$score, '
        'preDropSpeed=${_maxSpeedDuringMovement.toStringAsFixed(1)} km/h, '
        'impact=${_peakAccelDuringDeceleration.toStringAsFixed(1)} m/s², '
        'rotation=${_peakGyroDuringDeceleration.toStringAsFixed(1)} deg/s, '
        'inactivity=${secondsSinceImpact}s');

    final event = EmergencyEvent(
      id: eventId,
      timestamp: DateTime.now(),
      emergencyScore: score,
      activityType: ActivityType.emergency,
      status: EmergencyStatus.possibleEmergency,
      impactMagnitude: _peakAccelDuringDeceleration,
      speedKmh: _maxSpeedDuringMovement,
      rotationSpeed: _peakGyroDuringDeceleration,
      location: {
        'latitude': gpsData.latitude,
        'longitude': gpsData.longitude,
      },
    );

    _onAccidentDetected?.call(event);
  }

  /// Calculate confidence score (0-100) based on multi-sensor evidence.
  ///
  /// Higher score = more confidence this is a real accident.
  /// Requires multiple independent signals for high score.
  int _calculateConfidenceScore(int secondsSinceImpact) {
    double score = 0;

    // --- Pre-drop speed component (0-30 points) ---
    // Higher speed before drop = more severe potential accident
    if (_maxSpeedDuringMovement >= 80) {
      score += 30;
    } else if (_maxSpeedDuringMovement >= 60) {
      score += 25;
    } else if (_maxSpeedDuringMovement >= 40) {
      score += 20;
    } else if (_maxSpeedDuringMovement >= 20) {
      score += 15;
    } else {
      score += 5;
    }

    // --- Impact severity (0-25 points) ---
    // Net acceleration > 15 m/s² (~1.5g) indicates significant impact
    if (_peakAccelDuringDeceleration >= 50) {
      score += 25;
    } else if (_peakAccelDuringDeceleration >= 30) {
      score += 20;
    } else if (_peakAccelDuringDeceleration >= 15) {
      score += 12;
    } else if (_peakAccelDuringDeceleration >= AccidentThresholds.impactThreshold) {
      score += 5;
    }

    // --- Abnormal rotation (0-20 points) ---
    // Rotation > 100 deg/s suggests device tumbling
    if (_peakGyroDuringDeceleration >= 200) {
      score += 20;
    } else if (_peakGyroDuringDeceleration >= 100) {
      score += 15;
    } else if (_peakGyroDuringDeceleration >= 50) {
      score += 8;
    }

    // --- Deceleration severity (0-15 points) ---
    // Rapid deceleration from high speed is more concerning
    if (_decelerationRate >= 40) {
      score += 15;
    } else if (_decelerationRate >= 25) {
      score += 10;
    } else if (_decelerationRate >= AccidentThresholds.decelerationRateThreshold) {
      score += 5;
    }

    // --- Post-event inactivity (0-10 points) ---
    // Longer inactivity after impact = more confident
    if (secondsSinceImpact >= 15) {
      score += 10;
    } else if (secondsSinceImpact >= 10) {
      score += 7;
    } else {
      score += 3;
    }

    return score.clamp(0, 100).toInt();
  }

  // ====================================================================
  // HELPERS
  // ====================================================================

  /// Calculate deceleration rate in km/h per second.
  double _calculateDeceleration(double currentSpeed, DateTime now) {
    if (_previousSpeedTimestamp == null) return 0;

    final timeDelta =
        now.difference(_previousSpeedTimestamp!).inMilliseconds / 1000.0;
    if (timeDelta <= 0) return 0;

    final speedDelta = _previousSpeedKmh - currentSpeed; // positive = deceleration
    return speedDelta / timeDelta;
  }

  void _resetDecelerationTracking() {
    _decelerationStartTime = null;
    _speedAtDecelerationStart = 0;
    _decelerationRate = 0;
  }

  void _resetImpactTracking() {
    _impactConfirmedTime = null;
    _stationaryCountAfterImpact = 0;
    _peakAccelDuringDeceleration = 0;
    _peakGyroDuringDeceleration = 0;
    _impactDetectedDuringDecel = false;
    _rotationDetectedDuringDecel = false;
  }

  void _transition(AccidentPhase newPhase, String reason) {
    if (_phase == newPhase) return;

    final log = DetectionLog(
      timestamp: DateTime.now(),
      fromPhase: _phase,
      toPhase: newPhase,
      reason: reason,
      gpsSpeedKmh: _previousSpeedKmh,
      filteredSpeedKmh: _previousSpeedKmh, // GPS service already filters
      accelNet: _lastAccelNet,
      gyroMag: _lastGyroMag,
      decelerationRate: _decelerationRate,
      impactDetected: _impactDetectedDuringDecel,
      rotationDetected: _rotationDetectedDuringDecel,
      confidenceSignals: [
        _impactDetectedDuringDecel,
        _rotationDetectedDuringDecel,
        _decelerationRate > AccidentThresholds.decelerationRateThreshold,
      ].where((x) => x).length,
    );

    _detectionLog.add(log);
    if (_detectionLog.length > _maxLogEntries) {
      _detectionLog.removeAt(0);
    }

    debugPrint('AccidentDetector: $log');

    _phase = newPhase;
    onUpdate?.call();
  }

  /// Called when user responds to verification (OK or Help).
  void onVerificationComplete() {
    _phase = AccidentPhase.idle;
    _hasTriggered = false;
    _lastTriggeredEventId = null;
    _resetDecelerationTracking();
    _resetImpactTracking();
    _maxSpeedDuringMovement = 0;
    _movementStartTime = null;
    _lastScore = 0;
    onUpdate?.call();
  }

  /// Full reset (e.g., when protection is toggled off).
  void reset() {
    _phase = AccidentPhase.idle;
    _hasTriggered = false;
    _lastTriggeredEventId = null;
    _previousSpeedKmh = 0;
    _previousSpeedTimestamp = null;
    _maxSpeedDuringMovement = 0;
    _movementStartTime = null;
    _resetDecelerationTracking();
    _resetImpactTracking();
    _lastAccelNet = 0;
    _lastGyroMag = 0;
    _lastScore = 0;
    _detectionLog.clear();
    onUpdate?.call();
  }
}
