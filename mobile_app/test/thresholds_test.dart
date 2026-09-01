import 'package:flutter_test/flutter_test.dart';
import 'package:resq_ai/config/thresholds.dart';

void main() {
  group('AccidentThresholds', () {
    test('moving speed threshold is reasonable', () {
      // Should be above walking speed (~5 km/h) but below cycling
      expect(AccidentThresholds.movingSpeedThreshold, greaterThan(10));
      expect(AccidentThresholds.movingSpeedThreshold, lessThan(25));
    });

    test('stationary threshold is below moving threshold', () {
      expect(AccidentThresholds.stationaryThreshold, lessThan(AccidentThresholds.movingSpeedThreshold));
    });

    test('deceleration rate threshold is above normal braking', () {
      // Normal braking: 5-15 km/h/s. Threshold should catch only sudden stops.
      expect(AccidentThresholds.decelerationRateThreshold, greaterThan(15));
    });

    test('impact threshold catches real impacts', () {
      // ~1.5g is the threshold
      expect(AccidentThresholds.impactThreshold, greaterThan(10));
      expect(AccidentThresholds.impactThreshold, lessThan(30));
    });

    test('rotation threshold catches device tumbling', () {
      expect(AccidentThresholds.rotationThreshold, greaterThan(50));
    });

    test('stationary count required prevents false positives', () {
      expect(AccidentThresholds.stationaryCountRequired, greaterThanOrEqualTo(3));
    });

    test('verification timeout is within spec (60-120 seconds)', () {
      expect(AccidentThresholds.verificationTimeout, greaterThanOrEqualTo(60));
      expect(AccidentThresholds.verificationTimeout, lessThanOrEqualTo(120));
    });
  });

  group('EmergencySpeedThresholds', () {
    test('speed drop magnitude requires significant change', () {
      // Must drop by at least 20 km/h to be suspicious
      expect(EmergencySpeedThresholds.speedDropMagnitude, greaterThanOrEqualTo(15));
    });

    test('speed drop window is short', () {
      // The drop must happen within a few seconds
      expect(EmergencySpeedThresholds.speedDropWindowSeconds, lessThanOrEqualTo(5));
    });

    test('persistence duration filters traffic lights', () {
      // Need to be stationary for at least 5 seconds
      expect(EmergencySpeedThresholds.persistenceDuration, greaterThanOrEqualTo(5));
    });

    test('moving speed threshold matches accident threshold', () {
      expect(
        EmergencySpeedThresholds.movingSpeedThreshold,
        AccidentThresholds.movingSpeedThreshold,
      );
    });
  });

  group('EmergencyThresholds', () {
    test('scoring weights sum to approximately 1.0', () {
      final sum = EmergencyThresholds.impactWeight +
          EmergencyThresholds.speedChangeWeight +
          EmergencyThresholds.rotationWeight +
          EmergencyThresholds.inactivityWeight +
          EmergencyThresholds.movementAnomalyWeight;
      expect(sum, closeTo(1.0, 0.01));
    });

    test('emergency score threshold is high', () {
      expect(EmergencyThresholds.emergencyScoreThreshold, greaterThanOrEqualTo(60));
    });
  });
}
