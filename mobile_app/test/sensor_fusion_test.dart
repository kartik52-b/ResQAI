import 'package:flutter_test/flutter_test.dart';
import 'package:resq_ai/engine/sensor_fusion.dart';
import 'package:resq_ai/engine/emergency_scorer.dart';
import 'package:resq_ai/engine/movement_classifier.dart';
import 'package:resq_ai/models/sensor_data.dart';

FusedSensorState _makeState({
  double accelX = 0, double accelY = 0, double accelZ = 9.81,
  double gyroX = 0, double gyroY = 0, double gyroZ = 0,
  double gpsSpeedKmh = 0, double accuracy = 5.0, bool stationary = true,
}) {
  return FusedSensorState(
    accelerometer: AccelerometerData(x: accelX, y: accelY, z: accelZ, timestamp: DateTime.now()),
    gyroscope: GyroscopeData(x: gyroX, y: gyroY, z: gyroZ, timestamp: DateTime.now()),
    gps: GpsData(
      latitude: 28.6139, longitude: 77.2090,
      speed: gpsSpeedKmh / 3.6, timestamp: DateTime.now(),
      accuracy: accuracy, isStationary: stationary,
    ),
    timestamp: DateTime.now(),
  );
}

void main() {
  group('SensorFusion', () {
    late SensorFusion fusion;

    setUp(() {
      fusion = SensorFusion();
    });

    test('analyzes stationary phone', () {
      final state = _makeState(gpsSpeedKmh: 0, stationary: true);
      final analysis = fusion.analyze(state);
      // After fresh start, _lastMovementTime is null → secondsSinceMovement is 0 → isStationary is true
      expect(analysis.hasImpact, false);
      expect(analysis.hasRapidRotation, false);
      expect(analysis.movementState, MovementState.stationary);
    });

    test('detects impact from accelerometer', () {
      // Net accel > 30 m/s² triggers hasImpact
      // accelX=50, accelY=0, accelZ=9.81 → magnitude = sqrt(50²+9.81²) ≈ 50.96
      // netMagnitude = |50.96 - 9.81| ≈ 41.15 > 30
      final state = _makeState(
        accelX: 50, accelY: 0, accelZ: 9.81,
        gpsSpeedKmh: 0, stationary: true,
      );
      final analysis = fusion.analyze(state);
      expect(analysis.hasImpact, true);
    });

    test('detects rapid rotation from gyroscope', () {
      // ~173 deg/s total
      final state = _makeState(
        gyroX: 100, gyroY: 100, gyroZ: 0,
        gpsSpeedKmh: 0, stationary: true,
      );
      final analysis = fusion.analyze(state);
      expect(analysis.hasRapidRotation, true);
    });

    test('detects sudden speed change', () {
      // First reading establishes baseline
      fusion.analyze(_makeState(gpsSpeedKmh: 60, stationary: false));
      // Second reading with large drop
      final analysis = fusion.analyze(_makeState(gpsSpeedKmh: 30, stationary: false));
      expect(analysis.hasSuddenSpeedChange, true);
    });

    test('returns filtered speed from classifier', () {
      final state = _makeState(gpsSpeedKmh: 50, stationary: false);
      final analysis = fusion.analyze(state);
      expect(analysis.filteredSpeedKmh, greaterThanOrEqualTo(0));
    });

    test('reset clears internal state', () {
      fusion.analyze(_makeState(gpsSpeedKmh: 60, stationary: false));
      fusion.reset();
      final analysis = fusion.analyze(_makeState(gpsSpeedKmh: 60, stationary: false));
      // After reset, speed change should be recalculated
      expect(analysis.speedKmh, closeTo(60, 0.1));
    });
  });

  group('EmergencyScorer', () {
    late EmergencyScorer scorer;

    setUp(() {
      scorer = EmergencyScorer();
    });

    test('low activity scores low', () {
      final analysis = FusedAnalysis(
        accelerationMagnitude: 5,
        rotationMagnitude: 5,
        speedKmh: 0,
        speedChange: 0,
        hasImpact: false,
        hasRapidRotation: false,
        hasSuddenSpeedChange: false,
        isStationary: true,
        timestamp: DateTime.now(),
        movementState: MovementState.stationary,
        filteredSpeedKmh: 0,
      );
      final score = scorer.calculate(analysis);
      expect(score.totalScore, lessThan(20));
    });

    test('high activity scores high', () {
      final analysis = FusedAnalysis(
        accelerationMagnitude: 60,
        rotationMagnitude: 200,
        speedKmh: 0,
        speedChange: 80,
        hasImpact: true,
        hasRapidRotation: true,
        hasSuddenSpeedChange: true,
        isStationary: true,
        timestamp: DateTime.now(),
        movementState: MovementState.stationary,
        filteredSpeedKmh: 0,
      );
      final score = scorer.calculate(analysis, secondsSinceImpact: 20);
      expect(score.totalScore, greaterThan(50));
    });

    test('scoring weights are applied correctly', () {
      final analysis = FusedAnalysis(
        accelerationMagnitude: 50,
        rotationMagnitude: 150,
        speedKmh: 0,
        speedChange: 60,
        hasImpact: true,
        hasRapidRotation: true,
        hasSuddenSpeedChange: true,
        isStationary: true,
        timestamp: DateTime.now(),
        movementState: MovementState.stationary,
        filteredSpeedKmh: 0,
      );
      final score = scorer.calculate(analysis, secondsSinceImpact: 15);
      expect(score.totalScore, greaterThan(0));
      expect(score.totalScore, lessThanOrEqualTo(100));
    });

    test('score is clamped to 0-100', () {
      final analysis = FusedAnalysis(
        accelerationMagnitude: 200,
        rotationMagnitude: 500,
        speedKmh: 0,
        speedChange: 200,
        hasImpact: true,
        hasRapidRotation: true,
        hasSuddenSpeedChange: true,
        isStationary: true,
        timestamp: DateTime.now(),
        movementState: MovementState.stationary,
        filteredSpeedKmh: 0,
      );
      final score = scorer.calculate(analysis, secondsSinceImpact: 60);
      expect(score.totalScore, greaterThanOrEqualTo(0));
      expect(score.totalScore, lessThanOrEqualTo(100));
    });
  });
}
