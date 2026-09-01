import '../models/emergency_event.dart';
import '../config/thresholds.dart';
import 'sensor_fusion.dart';
import 'movement_classifier.dart';
import 'emergency_scorer.dart';

/// Context analysis result combining activity classification with score.
class ContextResult {
  final ActivityType activityType;
  final EmergencyStatus status;
  final ScoreBreakdown score;
  final String description;

  ContextResult({
    required this.activityType,
    required this.status,
    required this.score,
    required this.description,
  });
}

/// Engine that distinguishes normal, suspicious, and emergency activity.
///
/// Emergency detection uses the EmergencyScorer thresholds (unchanged).
/// Activity display uses the MovementClassifier's multi-sensor result
/// instead of naive GPS-speed-only classification.
class ContextEngine {
  final EmergencyScorer _scorer = EmergencyScorer();
  int _secondsSinceImpact = 0;
  DateTime? _lastImpactTime;
  bool _impactDetected = false;

  /// Analyze fused sensor data and produce a context result.
  ContextResult analyze(FusedAnalysis analysis) {
    final score = _scorer.calculate(
      analysis,
      secondsSinceImpact: _secondsSinceImpact,
    );

    // Track impact timing
    if (analysis.hasImpact && !_impactDetected) {
      _lastImpactTime = DateTime.now();
      _impactDetected = true;
    }

    // Update seconds since impact
    if (_lastImpactTime != null) {
      _secondsSinceImpact = DateTime.now().difference(_lastImpactTime!).inSeconds;
    }

    // Classify activity — emergency first, then use MovementClassifier for display
    final activity = _classifyActivity(analysis, score);

    // Determine emergency status
    final status = _determineStatus(activity, score.totalScore);

    return ContextResult(
      activityType: activity,
      status: status,
      score: score,
      description: _getDescription(activity, score),
    );
  }

  ActivityType _classifyActivity(FusedAnalysis analysis, ScoreBreakdown score) {
    // --- EMERGENCY DETECTION (unchanged thresholds) ---
    // High impact + post-impact inactivity = likely accident
    if (score.totalScore >= EmergencyThresholds.emergencyScoreThreshold) {
      if (analysis.hasImpact && analysis.isStationary) {
        return ActivityType.emergency;
      }
      if (analysis.hasImpact && analysis.hasSuddenSpeedChange) {
        return ActivityType.emergency;
      }
    }

    // Phone drop: sudden acceleration spike, no sustained pattern
    if (analysis.hasImpact && !analysis.hasSuddenSpeedChange &&
        analysis.filteredSpeedKmh < 5) {
      return ActivityType.phoneDrop;
    }

    // --- NORMAL ACTIVITY DISPLAY (uses MovementClassifier result) ---
    // The MovementClassifier uses GPS + accelerometer + gyroscope together,
    // applies smoothing, dead-zone, and hysteresis.
    switch (analysis.movementState) {
      case MovementState.driving:
        return ActivityType.driving;
      case MovementState.cycling:
        return ActivityType.cycling;
      case MovementState.running:
        return ActivityType.running;
      case MovementState.walking:
        return ActivityType.walking;
      case MovementState.stationary:
        return ActivityType.normal;
    }
  }

  EmergencyStatus _determineStatus(ActivityType activity, double score) {
    switch (activity) {
      case ActivityType.emergency:
        return EmergencyStatus.possibleEmergency;
      case ActivityType.suspicious:
        return EmergencyStatus.possibleEmergency;
      case ActivityType.phoneDrop:
        return EmergencyStatus.safe; // Wait for more data
      default:
        return EmergencyStatus.safe;
    }
  }

  String _getDescription(ActivityType activity, ScoreBreakdown score) {
    switch (activity) {
      case ActivityType.normal:
        return 'Normal activity';
      case ActivityType.walking:
        return 'Walking detected';
      case ActivityType.running:
        return 'Running detected';
      case ActivityType.cycling:
        return 'Cycling detected';
      case ActivityType.driving:
        return 'Driving at ${score.totalScore.toStringAsFixed(0)}% risk';
      case ActivityType.phoneDrop:
        return 'Possible phone drop';
      case ActivityType.suspicious:
        return 'Unusual movement detected';
      case ActivityType.emergency:
        return 'EMERGENCY — Score: ${score.totalScore.toStringAsFixed(0)}';
    }
  }

  /// Reset impact tracking (e.g. after verification)
  void resetImpact() {
    _secondsSinceImpact = 0;
    _lastImpactTime = null;
    _impactDetected = false;
  }
}
