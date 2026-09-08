import 'package:flutter_test/flutter_test.dart';
import 'package:resq_ai/engine/accident_detector.dart';
import 'package:resq_ai/models/sensor_data.dart';
import 'package:resq_ai/models/emergency_event.dart';

/// Helper: create a GpsData at a given speed (km/h converted to m/s internally)
GpsData _gpsAtSpeed(double speedKmh, {DateTime? time}) {
  return GpsData(
    latitude: 28.6139,
    longitude: 77.2090,
    speed: speedKmh / 3.6,
    timestamp: time ?? DateTime.now(),
    accuracy: 5.0,
    rawSpeedKmh: speedKmh,
    groundSpeedKmh: speedKmh,
    isStationary: speedKmh < 2.0,
  );
}

void main() {
  group('AccidentDetector', () {
    late AccidentDetector detector;
    EmergencyEvent? detectedEvent;
    final baseTime = DateTime(2024, 1, 15, 10, 0, 0);

    setUp(() {
      detector = AccidentDetector();
      detectedEvent = null;
      detector.setCallback((event) => detectedEvent = event);
    });

    test('starts in IDLE phase', () {
      expect(detector.phase, AccidentPhase.idle);
    });

    test('transitions to NORMAL_MOVING when speed exceeds threshold (15 km/h)', () {
      detector.onGpsUpdate(_gpsAtSpeed(20, time: baseTime));
      expect(detector.phase, AccidentPhase.normalMoving);
    });

    test('stays IDLE at low speed (< 15 km/h)', () {
      detector.onGpsUpdate(_gpsAtSpeed(0, time: baseTime));
      expect(detector.phase, AccidentPhase.idle);

      detector.onGpsUpdate(_gpsAtSpeed(5, time: baseTime.add(const Duration(seconds: 1))));
      expect(detector.phase, AccidentPhase.idle);

      detector.onGpsUpdate(_gpsAtSpeed(10, time: baseTime.add(const Duration(seconds: 2))));
      expect(detector.phase, AccidentPhase.idle);
    });

    test('PATH A: high-speed driving → sudden deceleration + impact → verification', () {
      // Step 1: Start moving at high speed
      detector.onGpsUpdate(_gpsAtSpeed(60, time: baseTime));
      expect(detector.phase, AccidentPhase.normalMoving);

      // Step 2: Rapid deceleration (>18 km/h/s threshold)
      // 60→20 in 1 second = 40 km/h/s deceleration
      detector.onGpsUpdate(_gpsAtSpeed(20, time: baseTime.add(const Duration(seconds: 1))));
      expect(detector.phase, AccidentPhase.suddenDeceleration);

      // Step 3: Feed impact signal while in deceleration
      detector.updateSensorData(40.0, 100.0);
      expect(detector.phase, AccidentPhase.possibleImpact);

      // Step 4: Device becomes stationary
      for (int i = 0; i < 5; i++) {
        detector.onGpsUpdate(_gpsAtSpeed(0, time: baseTime.add(Duration(seconds: 2 + i))));
      }
      expect(detector.phase, AccidentPhase.postEventInactivity);
    });

    test('PATH B: severe impact at any speed enters possibleImpact', () {
      // Start moving (even at low speed below detection threshold)
      detector.onGpsUpdate(_gpsAtSpeed(10, time: baseTime));
      // Still IDLE because 10 < 15 km/h threshold
      expect(detector.phase, AccidentPhase.idle);

      // Severe impact detected (45+ m/s² = ~4.5g)
      detector.updateSensorData(45.0, 10.0);
      expect(detector.phase, AccidentPhase.possibleImpact);
    });

    test('PATH B: extreme rotation at any speed', () {
      detector.onGpsUpdate(_gpsAtSpeed(10, time: baseTime));
      expect(detector.phase, AccidentPhase.idle);

      // Extreme rotation (160 deg/s)
      detector.updateSensorData(5.0, 160.0);
      expect(detector.phase, AccidentPhase.possibleImpact);
    });

    test('PATH B: combined anomalous signals', () {
      detector.onGpsUpdate(_gpsAtSpeed(10, time: baseTime));
      expect(detector.phase, AccidentPhase.idle);

      // Both moderate (25 accel, 90 gyro)
      detector.updateSensorData(25.0, 90.0);
      expect(detector.phase, AccidentPhase.possibleImpact);
    });

    test('normal braking does not trigger emergency', () {
      // Driving then normal braking
      detector.onGpsUpdate(_gpsAtSpeed(40, time: baseTime));
      expect(detector.phase, AccidentPhase.normalMoving);

      // Gradual deceleration (no impact)
      detector.onGpsUpdate(_gpsAtSpeed(35, time: baseTime.add(const Duration(seconds: 1))));
      detector.onGpsUpdate(_gpsAtSpeed(25, time: baseTime.add(const Duration(seconds: 2))));
      detector.onGpsUpdate(_gpsAtSpeed(10, time: baseTime.add(const Duration(seconds: 3))));
      detector.onGpsUpdate(_gpsAtSpeed(0, time: baseTime.add(const Duration(seconds: 4))));

      // No impact signal → should return to idle
      expect(detector.phase, AccidentPhase.idle);
    });

    test('traffic light stop does not trigger emergency', () {
      detector.onGpsUpdate(_gpsAtSpeed(30, time: baseTime));
      expect(detector.phase, AccidentPhase.normalMoving);

      // Gradual stop over 5 seconds
      detector.onGpsUpdate(_gpsAtSpeed(20, time: baseTime.add(const Duration(seconds: 1))));
      detector.onGpsUpdate(_gpsAtSpeed(10, time: baseTime.add(const Duration(seconds: 2))));
      detector.onGpsUpdate(_gpsAtSpeed(0, time: baseTime.add(const Duration(seconds: 3))));

      expect(detector.phase, AccidentPhase.idle);
    });

    test('speed recovery during deceleration returns to normalMoving', () {
      detector.onGpsUpdate(_gpsAtSpeed(60, time: baseTime));
      detector.onGpsUpdate(_gpsAtSpeed(30, time: baseTime.add(const Duration(seconds: 1)))); // rapid drop
      expect(detector.phase, AccidentPhase.suddenDeceleration);

      // Speed recovers
      detector.onGpsUpdate(_gpsAtSpeed(50, time: baseTime.add(const Duration(seconds: 2))));
      expect(detector.phase, AccidentPhase.normalMoving);
    });

    test('reset returns to IDLE', () {
      detector.onGpsUpdate(_gpsAtSpeed(60, time: baseTime));
      expect(detector.phase, AccidentPhase.normalMoving);

      detector.reset();
      expect(detector.phase, AccidentPhase.idle);
    });

    test('onVerificationComplete returns to IDLE', () {
      detector.onGpsUpdate(_gpsAtSpeed(60, time: baseTime));
      detector.onGpsUpdate(_gpsAtSpeed(30, time: baseTime.add(const Duration(seconds: 1))));
      detector.updateSensorData(40.0, 100.0);

      // Force to verifying
      detector.onVerificationComplete();
      expect(detector.phase, AccidentPhase.idle);
    });

    test('low-speed impact during IDLE enters possibleImpact', () {
      // Phone on desk, gets slammed
      expect(detector.phase, AccidentPhase.idle);
      detector.updateSensorData(50.0, 10.0); // 50 m/s² impact while idle
      expect(detector.phase, AccidentPhase.possibleImpact);
    });

    test('GPS-driven path advances through postEventInactivity', () {
      final now = DateTime.now();

      // 1. Moving at high speed
      detector.onGpsUpdate(_gpsAtSpeed(60, time: now));
      // 2. Rapid deceleration
      detector.onGpsUpdate(_gpsAtSpeed(20, time: now.add(const Duration(seconds: 1))));
      // 3. Impact detected while decelerating → enters possibleImpact
      detector.updateSensorData(40.0, 100.0);
      expect(detector.phase, AccidentPhase.possibleImpact);

      // 4. Speed drops to near zero — stationaryCount increments but stays < required (4)
      detector.onGpsUpdate(_gpsAtSpeed(0, time: now.add(const Duration(seconds: 2))));
      detector.onGpsUpdate(_gpsAtSpeed(0, time: now.add(const Duration(seconds: 3))));
      detector.onGpsUpdate(_gpsAtSpeed(0, time: now.add(const Duration(seconds: 4))));
      expect(detector.phase, AccidentPhase.possibleImpact);

      // 5. 4th stationary reading → stationaryCount reaches 4 → postEventInactivity
      detector.onGpsUpdate(_gpsAtSpeed(0, time: now.add(const Duration(seconds: 5))));
      expect(detector.phase, AccidentPhase.postEventInactivity);

      // 6. Post-impact inactivity exceeds threshold (6s since impact) → triggers emergency
      detector.onGpsUpdate(_gpsAtSpeed(0, time: now.add(const Duration(seconds: 15))));
      expect(detector.phase, AccidentPhase.verifying);
      expect(detectedEvent, isNotNull);
    });
  });

  group('AccidentDetector — edge cases', () {
    final baseTime = DateTime(2024, 1, 15, 10, 0, 0);

    test('stationary phone does not trigger emergency', () {
      final detector = AccidentDetector();
      for (int i = 0; i < 20; i++) {
        detector.onGpsUpdate(_gpsAtSpeed(0, time: baseTime.add(Duration(seconds: i))));
        detector.updateSensorData(0.5, 2.0);
      }
      expect(detector.phase, AccidentPhase.idle);
    });

    test('walking does not trigger emergency', () {
      final detector = AccidentDetector();
      detector.onGpsUpdate(_gpsAtSpeed(4, time: baseTime));
      // 4 km/h is below the 15 km/h moving threshold → stays IDLE
      expect(detector.phase, AccidentPhase.idle);

      // Walking then stopping → still IDLE (never entered normalMoving)
      detector.onGpsUpdate(_gpsAtSpeed(0, time: baseTime.add(const Duration(seconds: 1))));
      expect(detector.phase, AccidentPhase.idle);
    });

    test('GPS jitter does not trigger emergency', () {
      final detector = AccidentDetector();
      detector.onGpsUpdate(_gpsAtSpeed(60, time: baseTime));
      expect(detector.phase, AccidentPhase.normalMoving);

      // Small jitter
      detector.onGpsUpdate(_gpsAtSpeed(55, time: baseTime.add(const Duration(seconds: 1))));
      detector.onGpsUpdate(_gpsAtSpeed(58, time: baseTime.add(const Duration(seconds: 2))));
      detector.onGpsUpdate(_gpsAtSpeed(56, time: baseTime.add(const Duration(seconds: 3))));
      expect(detector.phase, AccidentPhase.normalMoving);
    });
  });
}
