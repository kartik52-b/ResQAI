import '../config/thresholds.dart';
import 'sensor_fusion.dart';

/// Score breakdown showing individual component contributions.
class ScoreBreakdown {
  final double impactScore;
  final double speedChangeScore;
  final double rotationScore;
  final double inactivityScore;
  final double movementAnomalyScore;
  final double totalScore;

  ScoreBreakdown({
    required this.impactScore,
    required this.speedChangeScore,
    required this.rotationScore,
    required this.inactivityScore,
    required this.movementAnomalyScore,
    required this.totalScore,
  });
}

/// Calculates emergency score from fused sensor analysis.
class EmergencyScorer {
  /// Calculate emergency score (0-100) from a fused analysis.
  ScoreBreakdown calculate(FusedAnalysis analysis, {int secondsSinceImpact = 0}) {
    // Impact score (0-100)
    final impactScore = _calculateImpactScore(analysis.accelerationMagnitude);

    // Speed change score (0-100)
    final speedChangeScore = _calculateSpeedChangeScore(analysis.speedChange);

    // Rotation score (0-100)
    final rotationScore = _calculateRotationScore(analysis.rotationMagnitude);

    // Inactivity score (0-100)
    final inactivityScore = _calculateInactivityScore(
      analysis.isStationary,
      secondsSinceImpact,
    );

    // Movement anomaly score (0-100)
    final movementAnomalyScore = _calculateMovementAnomaly(analysis);

    // Weighted total
    final total = (impactScore * EmergencyThresholds.impactWeight) +
        (speedChangeScore * EmergencyThresholds.speedChangeWeight) +
        (rotationScore * EmergencyThresholds.rotationWeight) +
        (inactivityScore * EmergencyThresholds.inactivityWeight) +
        (movementAnomalyScore * EmergencyThresholds.movementAnomalyWeight);

    return ScoreBreakdown(
      impactScore: impactScore,
      speedChangeScore: speedChangeScore,
      rotationScore: rotationScore,
      inactivityScore: inactivityScore,
      movementAnomalyScore: movementAnomalyScore,
      totalScore: total.clamp(0, 100),
    );
  }

  double _calculateImpactScore(double magnitude) {
    if (magnitude <= EmergencyThresholds.impactThreshold) return 0;
    // Scale from threshold to peak: 0-100
    final range = EmergencyThresholds.impactPeakThreshold -
        EmergencyThresholds.impactThreshold;
    if (range <= 0) return magnitude > 0 ? 100 : 0;
    final normalized =
        (magnitude - EmergencyThresholds.impactThreshold) / range;
    return (normalized * 100).clamp(0, 100);
  }

  double _calculateSpeedChangeScore(double speedChange) {
    if (speedChange <= EmergencyThresholds.speedChangeThreshold) return 0;
    final range = 60.0 - EmergencyThresholds.speedChangeThreshold;
    if (range <= 0) return 100;
    final normalized = speedChange / range;
    return (normalized * 100).clamp(0, 100);
  }

  double _calculateRotationScore(double rotation) {
    if (rotation <= EmergencyThresholds.rotationThreshold) return 0;
    final range = 500.0 - EmergencyThresholds.rotationThreshold;
    if (range <= 0) return 100;
    final normalized = rotation / range;
    return (normalized * 100).clamp(0, 100);
  }

  double _calculateInactivityScore(bool isStationary, int secondsSinceImpact) {
    if (!isStationary) return 0;
    if (secondsSinceImpact < 5) return 0;
    // Ramp up over 30 seconds
    final normalized = secondsSinceImpact / EmergencyThresholds.inactivityDuration;
    return (normalized * 100).clamp(0, 100);
  }

  double _calculateMovementAnomaly(FusedAnalysis analysis) {
    int anomalies = 0;
    if (analysis.hasImpact) anomalies++;
    if (analysis.hasRapidRotation) anomalies++;
    if (analysis.hasSuddenSpeedChange) anomalies++;
    if (analysis.isStationary) anomalies++;
    // Score based on number of concurrent anomalies
    return (anomalies / 4.0 * 100).clamp(0, 100);
  }
}
