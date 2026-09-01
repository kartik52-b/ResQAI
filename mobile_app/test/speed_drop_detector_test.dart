import 'package:flutter_test/flutter_test.dart';
import 'package:resq_ai/engine/speed_drop_detector.dart';
import 'package:resq_ai/models/sensor_data.dart';
import 'package:resq_ai/models/emergency_event.dart';

/// Helper: create a GpsData at a given speed (km/h) with a specific timestamp
GpsData _gpsAtSpeed(double speedKmh, DateTime time) {
  return GpsData(
    latitude: 28.6139,
    longitude: 77.2090,
    speed: speedKmh / 3.6,
    timestamp: time,
    accuracy: 5.0,
    rawSpeedKmh: speedKmh,
    groundSpeedKmh: speedKmh,
    isStationary: speedKmh < 2.0,
  );
}

void main() {
  group('SpeedDropDetector', () {
    late SpeedDropDetector detector;
    EmergencyEvent? detectedEvent;
    final baseTime = DateTime(2024, 1, 15, 10, 0, 0);

    setUp(() {
      detector = SpeedDropDetector();
      detectedEvent = null;
      detector.setCallback((event) => detectedEvent = event);
    });

    test('starts in IDLE phase', () {
      expect(detector.phase, DetectionPhase.idle);
    });

    test('transitions to MOVING when speed exceeds threshold', () {
      detector.onGpsUpdate(_gpsAtSpeed(20, baseTime));
      expect(detector.phase, DetectionPhase.moving);
    });

    test('stays IDLE at low speed', () {
      detector.onGpsUpdate(_gpsAtSpeed(0, baseTime));
      expect(detector.phase, DetectionPhase.idle);

      detector.onGpsUpdate(_gpsAtSpeed(5, baseTime.add(Duration(seconds: 1))));
      expect(detector.phase, DetectionPhase.idle);
    });

    test('detects speed drop from high speed', () {
      // Move for a while (>minimumMovingDuration = 5s)
      for (int i = 0; i < 10; i++) {
        detector.onGpsUpdate(_gpsAtSpeed(60, baseTime.add(Duration(seconds: i))));
      }
      expect(detector.phase, DetectionPhase.moving);

      // Sudden drop to zero
      detector.onGpsUpdate(_gpsAtSpeed(0, baseTime.add(Duration(seconds: 10))));
      expect(detector.phase, DetectionPhase.decelerating);
    });

    test('stationary phone does not trigger', () {
      for (int i = 0; i < 20; i++) {
        detector.onGpsUpdate(_gpsAtSpeed(0, baseTime.add(Duration(seconds: i))));
      }
      expect(detector.phase, DetectionPhase.idle);
      expect(detectedEvent, null);
    });

    test('normal braking does not trigger (speed drops gradually)', () {
      // Move
      for (int i = 0; i < 10; i++) {
        detector.onGpsUpdate(_gpsAtSpeed(60, baseTime.add(Duration(seconds: i))));
      }

      // Gradual braking over many seconds (each 5 km/h drop per second)
      for (int i = 0; i < 12; i++) {
        detector.onGpsUpdate(
          _gpsAtSpeed((60 - i * 5).toDouble().clamp(0.0, 60.0), baseTime.add(Duration(seconds: 10 + i))),
        );
      }

      // Should not trigger — drop is gradual
      expect(detectedEvent, null);
    });

    test('persistence is required — brief stop does not trigger', () {
      // Move
      for (int i = 0; i < 10; i++) {
        detector.onGpsUpdate(_gpsAtSpeed(60, baseTime.add(Duration(seconds: i))));
      }

      // Speed recovers quickly
      detector.onGpsUpdate(_gpsAtSpeed(50, baseTime.add(Duration(seconds: 10))));
      expect(detector.phase, DetectionPhase.moving);
    });

    test('reset returns to IDLE', () {
      detector.onGpsUpdate(_gpsAtSpeed(60, baseTime));
      detector.reset();
      expect(detector.phase, DetectionPhase.idle);
      expect(detector.speedHistory, isEmpty);
    });

    test('onVerificationComplete resets state', () {
      detector.onGpsUpdate(_gpsAtSpeed(60, baseTime));
      detector.onVerificationComplete();
      expect(detector.phase, DetectionPhase.idle);
    });

    test('speed history is maintained', () {
      detector.onGpsUpdate(_gpsAtSpeed(10, baseTime));
      detector.onGpsUpdate(_gpsAtSpeed(20, baseTime.add(Duration(seconds: 1))));
      detector.onGpsUpdate(_gpsAtSpeed(30, baseTime.add(Duration(seconds: 2))));

      expect(detector.speedHistory.length, 3);
      expect(detector.speedHistory.last.speedKmh, closeTo(30, 0.1));
    });

    test('sensor data is tracked for scoring', () {
      detector.onGpsUpdate(_gpsAtSpeed(60, baseTime));
      detector.updateSensorData(10.0, 50.0);
      detector.updateSensorData(15.0, 60.0);

      expect(detector.phase, DetectionPhase.moving);
    });
  });

  group('SpeedDropDetector — false positive protection', () {
    final baseTime = DateTime(2024, 1, 15, 10, 0, 0);

    test('walking stop does not trigger', () {
      final detector = SpeedDropDetector();

      // Walking speed is below moving threshold (15 km/h)
      for (int i = 0; i < 10; i++) {
        detector.onGpsUpdate(_gpsAtSpeed(4, baseTime.add(Duration(seconds: i))));
      }
      // Stop
      detector.onGpsUpdate(_gpsAtSpeed(0, baseTime.add(Duration(seconds: 10))));

      // Walking speed is below moving threshold — stays idle
      expect(detector.phase, DetectionPhase.idle);
    });

    test('traffic light stop does not trigger', () {
      final detector = SpeedDropDetector();

      // Moderate speed for several seconds
      for (int i = 0; i < 10; i++) {
        detector.onGpsUpdate(_gpsAtSpeed(25, baseTime.add(Duration(seconds: i))));
      }

      // Gradual deceleration
      detector.onGpsUpdate(_gpsAtSpeed(15, baseTime.add(Duration(seconds: 10))));
      detector.onGpsUpdate(_gpsAtSpeed(5, baseTime.add(Duration(seconds: 11))));
      detector.onGpsUpdate(_gpsAtSpeed(0, baseTime.add(Duration(seconds: 12))));

      expect(detector.isDetecting, false);
    });
  });
}
