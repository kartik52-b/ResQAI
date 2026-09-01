import 'package:flutter_test/flutter_test.dart';
import 'package:resq_ai/engine/movement_classifier.dart';
import 'package:resq_ai/models/sensor_data.dart';

/// Helper to create a fused sensor state with given parameters
FusedSensorState _fusedState({
  double gpsSpeedKmh = 0,
  double accelNet = 0,
  double gyroMag = 0,
  bool gpsStationary = true,
  double latitude = 28.6139,
  double longitude = 77.2090,
}) {
  return FusedSensorState(
    accelerometer: AccelerometerData(
      x: 0, y: 0,
      z: 9.81 + accelNet, // z includes gravity
      timestamp: DateTime.now(),
    ),
    gyroscope: GyroscopeData(
      x: gyroMag > 0 ? gyroMag * 0.577 : 0,
      y: gyroMag > 0 ? gyroMag * 0.577 : 0,
      z: gyroMag > 0 ? gyroMag * 0.577 : 0,
      timestamp: DateTime.now(),
    ),
    gps: GpsData(
      latitude: latitude,
      longitude: longitude,
      speed: gpsSpeedKmh / 3.6,
      timestamp: DateTime.now(),
      accuracy: 5.0,
      isStationary: gpsStationary,
    ),
    timestamp: DateTime.now(),
  );
}

void main() {
  group('MovementClassifier', () {
    late MovementClassifier classifier;

    setUp(() {
      classifier = MovementClassifier();
    });

    test('classifies as stationary when GPS reports stationary', () {
      final state = _fusedState(gpsSpeedKmh: 0, gpsStationary: true);
      final result = classifier.classify(state);
      expect(result, MovementState.stationary);
    });

    test('classifies as stationary when speed is very low', () {
      final state = _fusedState(gpsSpeedKmh: 1.0, accelNet: 0.5, gyroMag: 5, gpsStationary: false);
      final result = classifier.classify(state);
      expect(result, MovementState.stationary);
    });

    test('classifies as walking at moderate speed', () {
      // Need multiple readings for hysteresis
      MovementState result = MovementState.stationary;
      for (int i = 0; i < 5; i++) {
        result = classifier.classify(_fusedState(
          gpsSpeedKmh: 4.5,
          accelNet: 2.0,
          gyroMag: 20,
          gpsStationary: false,
        ));
      }
      expect(result, MovementState.walking);
    });

    test('classifies as driving at high speed', () {
      MovementState result = MovementState.stationary;
      for (int i = 0; i < 5; i++) {
        result = classifier.classify(_fusedState(
          gpsSpeedKmh: 60,
          accelNet: 0.5,
          gyroMag: 5,
          gpsStationary: false,
        ));
      }
      expect(result, MovementState.driving);
    });

    test('classifies as cycling at moderate-high speed', () {
      MovementState result = MovementState.stationary;
      for (int i = 0; i < 5; i++) {
        result = classifier.classify(_fusedState(
          gpsSpeedKmh: 20,
          accelNet: 1.0,
          gyroMag: 20,
          gpsStationary: false,
        ));
      }
      expect(result, MovementState.cycling);
    });

    test('stationary detection uses dead zone', () {
      // Very low speed + no accel/gyro activity
      final state = _fusedState(
        gpsSpeedKmh: 1.5,
        accelNet: 0.3,
        gyroMag: 3,
        gpsStationary: false,
      );
      final result = classifier.classify(state);
      expect(result, MovementState.stationary);
    });

    test('reset clears state', () {
      for (int i = 0; i < 5; i++) {
        classifier.classify(_fusedState(gpsSpeedKmh: 60, gpsStationary: false));
      }
      classifier.reset();
      // After reset, should start fresh
      final result = classifier.classify(_fusedState(gpsSpeedKmh: 0, gpsStationary: true));
      expect(result, MovementState.stationary);
    });
  });
}
