/// Configurable thresholds for emergency detection.
/// These can be calibrated with real datasets later.
class EmergencyThresholds {
  // Impact detection
  static const double impactThreshold = 30.0; // m/s² net acceleration
  static const double impactPeakThreshold = 50.0; // m/s² severe impact

  // Speed change detection
  static const double speedChangeThreshold = 20.0; // km/h sudden change
  static const double speedDropThreshold = 15.0; // km/h sudden deceleration

  // Rotation detection
  static const double rotationThreshold = 100.0; // degrees/s rapid rotation

  // Inactivity detection
  static const int inactivityDuration = 30; // seconds of no movement
  static const double stillnessThreshold = 0.5; // m/s² acceleration threshold

  // Emergency scoring
  static const int emergencyScoreThreshold = 70; // score out of 100 to trigger emergency

  // Verification
  static const int verificationTimeout = 90; // seconds to respond to verification

  // Scoring weights
  static const double impactWeight = 0.30;
  static const double speedChangeWeight = 0.25;
  static const double rotationWeight = 0.20;
  static const double inactivityWeight = 0.15;
  static const double movementAnomalyWeight = 0.10;

  // Activity classification thresholds
  static const double normalMovementMax = 15.0; // m/s²
  static const double suspiciousMovementMin = 20.0; // m/s²
  static const double emergencyMovementMin = 30.0; // m/s²

  // Life Replay buffer
  static const int replayBufferMaxSeconds = 60;
  static const int replayBufferMaxEvents = 100;
}

/// Multi-sensor accident detection thresholds.
///
/// These control the multi-sensor accident state machine:
/// - Moving state detection
/// - Deceleration rate detection
/// - Impact and rotation thresholds
/// - Post-event inactivity verification
/// - User response timeout
class AccidentThresholds {
  /// Speed must exceed this to be considered "moving" (km/h).
  static const double movingSpeedThreshold = 15.0;

  /// Speed below this is considered "stationary" (km/h).
  static const double stationaryThreshold = 3.0;

  /// Minimum deceleration rate to trigger SUDDEN_DECELERATION (km/h per second).
  /// Normal braking: 5-15 km/h/s. Emergency braking: 20-40 km/h/s.
  /// Set to detect genuinely sudden stops without catching normal braking.
  static const double decelerationRateThreshold = 18.0;

  /// Time limit for deceleration phase before classifying as normal (seconds).
  /// If no impact/rotation signal arrives within this time, the deceleration
  /// was likely normal braking and we return to idle.
  static const int decelerationTimeoutSeconds = 8;

  /// Net acceleration threshold for impact detection (m/s²).
  /// ~1.5g. Normal phone handling: 1-8 m/s². Car accident: 30-100+ m/s².
  static const double impactThreshold = 15.0;

  /// Rotation threshold for abnormal rotation detection (degrees/s).
  /// Normal phone movement: 0-50 deg/s. Device tumbling: 100+ deg/s.
  static const double rotationThreshold = 80.0;

  /// Number of consecutive stationary GPS readings required after impact.
  /// At ~1Hz GPS, this means ~4 seconds of stationary state.
  static const int stationaryCountRequired = 4;

  /// Seconds of post-impact inactivity before confirming emergency.
  /// Gives time to verify the device is truly stationary (not a brief stop).
  static const int postImpactInactivitySeconds = 6;

  /// Verification timeout — how long user has to respond (seconds).
  static const int verificationTimeout = 120;

  /// Maximum speed history age (seconds).
  static const int speedHistoryMaxSeconds = 30;
}

/// Speed-drop detection thresholds (LEGACY — kept for reference)
///
/// These thresholds control the GPS speed-based emergency detection:
/// - Moving state detection
/// - Speed drop detection
/// - Persistence verification
/// - User response timeout
class EmergencySpeedThresholds {
  /// Speed must exceed this to be considered "moving" (km/h)
  /// User must be going at least this fast for a drop to be considered
  static const double movingSpeedThreshold = 15.0;

  /// Speed must drop by at least this much to trigger detection (km/h)
  /// Prevents false alarms from gradual deceleration
  static const double speedDropMagnitude = 20.0;

  /// Time window in which the speed drop must occur (seconds)
  /// The drop from max to current must happen within this window
  static const int speedDropWindowSeconds = 3;

  /// Speed below this is considered "stopped" (km/h)
  /// GPS speed below this = user is stationary
  static const double stationaryThreshold = 3.0;

  /// How long speed must stay near zero before confirming emergency (seconds)
  /// Filters out traffic lights and brief stops
  static const int persistenceDuration = 8;

  /// How long user has to respond to verification (seconds)
  /// Spec requires 60-120 seconds. User may be unconscious.
  static const int verificationTimeout = 120;

  /// Minimum duration the user must have been moving before a drop is considered
  /// Prevents triggers from brief movements
  static const int minimumMovingDuration = 5;

  /// Maximum age of speed history records (seconds)
  /// Older records are pruned to save memory
  static const int speedHistoryMaxSeconds = 30;
}
