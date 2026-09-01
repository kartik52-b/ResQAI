import 'package:flutter_test/flutter_test.dart';
import 'package:resq_ai/models/sensor_data.dart';
import 'package:resq_ai/models/emergency_event.dart';
import 'package:resq_ai/models/trusted_contact.dart';

void main() {
  group('AccelerometerData', () {
    test('magnitude computes sqrt(x²+y²+z²)', () {
      final data = AccelerometerData(x: 3, y: 4, z: 0, timestamp: DateTime.now());
      expect(data.magnitude, closeTo(5.0, 0.01));
    });

    test('netMagnitude removes gravity', () {
      // Stationary phone: ~9.81 m/s² on one axis
      final data = AccelerometerData(x: 0, y: 0, z: 9.81, timestamp: DateTime.now());
      expect(data.netMagnitude, closeTo(0.0, 0.01));
    });

    test('netMagnitude detects impact', () {
      // Significant impact: 20 m/s² net above gravity
      final data = AccelerometerData(x: 20, y: 0, z: 9.81, timestamp: DateTime.now());
      // magnitude = sqrt(20² + 0² + 9.81²) = sqrt(400 + 96.24) ≈ 22.28
      // netMagnitude = |22.28 - 9.81| ≈ 12.47
      expect(data.netMagnitude, greaterThan(10.0));
    });

    test('magnitude is zero for zero input', () {
      final data = AccelerometerData(x: 0, y: 0, z: 0, timestamp: DateTime.now());
      expect(data.magnitude, 0.0);
    });
  });

  group('GyroscopeData', () {
    test('magnitude computes sqrt(x²+y²+z²)', () {
      final data = GyroscopeData(x: 100, y: 0, z: 0, timestamp: DateTime.now());
      expect(data.magnitude, closeTo(100.0, 0.01));
    });

    test('magnitude handles multiple axes', () {
      final data = GyroscopeData(x: 3, y: 4, z: 0, timestamp: DateTime.now());
      expect(data.magnitude, closeTo(5.0, 0.01));
    });

    test('magnitude is zero for zero input', () {
      final data = GyroscopeData(x: 0, y: 0, z: 0, timestamp: DateTime.now());
      expect(data.magnitude, 0.0);
    });
  });

  group('GpsData', () {
    test('speedKmh converts m/s to km/h', () {
      final data = GpsData(
        latitude: 28.6139,
        longitude: 77.2090,
        speed: 10.0, // 10 m/s
        timestamp: DateTime.now(),
      );
      expect(data.speedKmh, closeTo(36.0, 0.01));
    });

    test('speedKmh is zero when speed is zero', () {
      final data = GpsData(
        latitude: 28.6139,
        longitude: 77.2090,
        speed: 0.0,
        timestamp: DateTime.now(),
      );
      expect(data.speedKmh, 0.0);
    });

    test('default values for optional fields', () {
      final data = GpsData(
        latitude: 28.6139,
        longitude: 77.2090,
        speed: 5.0,
        timestamp: DateTime.now(),
      );
      expect(data.accuracy, 0.0);
      expect(data.rawSpeedKmh, 0.0);
      expect(data.groundSpeedKmh, 0.0);
      expect(data.isStationary, false);
    });

    test('toJson contains all fields', () {
      final data = GpsData(
        latitude: 28.6139,
        longitude: 77.2090,
        speed: 10.0,
        timestamp: DateTime(2024, 1, 15, 10, 30, 0),
        accuracy: 5.0,
        rawSpeedKmh: 35.0,
        groundSpeedKmh: 37.0,
        isStationary: false,
      );
      final json = data.toJson();
      expect(json['latitude'], 28.6139);
      expect(json['longitude'], 77.2090);
      expect(json['speed_kmh'], closeTo(36.0, 0.01));
      expect(json['accuracy'], 5.0);
      expect(json['is_stationary'], false);
    });
  });

  group('FusedSensorState', () {
    test('hasAllSensors returns true when all present', () {
      final state = FusedSensorState(
        accelerometer: AccelerometerData(x: 0, y: 0, z: 9.81, timestamp: DateTime.now()),
        gyroscope: GyroscopeData(x: 0, y: 0, z: 0, timestamp: DateTime.now()),
        gps: GpsData(latitude: 0, longitude: 0, speed: 0, timestamp: DateTime.now()),
        timestamp: DateTime.now(),
      );
      expect(state.hasAllSensors, true);
    });

    test('hasAllSensors returns false when missing', () {
      final state = FusedSensorState(
        accelerometer: null,
        gyroscope: GyroscopeData(x: 0, y: 0, z: 0, timestamp: DateTime.now()),
        gps: GpsData(latitude: 0, longitude: 0, speed: 0, timestamp: DateTime.now()),
        timestamp: DateTime.now(),
      );
      expect(state.hasAllSensors, false);
    });
  });

  group('EmergencyEvent', () {
    test('severity classification', () {
      final critical = EmergencyEvent(
        id: '1', timestamp: DateTime.now(), emergencyScore: 85,
        activityType: ActivityType.emergency, status: EmergencyStatus.possibleEmergency,
      );
      expect(critical.severity, Severity.critical);

      final high = EmergencyEvent(
        id: '2', timestamp: DateTime.now(), emergencyScore: 70,
        activityType: ActivityType.emergency, status: EmergencyStatus.possibleEmergency,
      );
      expect(high.severity, Severity.high);

      final medium = EmergencyEvent(
        id: '3', timestamp: DateTime.now(), emergencyScore: 50,
        activityType: ActivityType.emergency, status: EmergencyStatus.possibleEmergency,
      );
      expect(medium.severity, Severity.medium);

      final low = EmergencyEvent(
        id: '4', timestamp: DateTime.now(), emergencyScore: 20,
        activityType: ActivityType.normal, status: EmergencyStatus.safe,
      );
      expect(low.severity, Severity.low);
    });

    test('copyWith preserves existing fields', () {
      final event = EmergencyEvent(
        id: '1', timestamp: DateTime.now(), emergencyScore: 50,
        activityType: ActivityType.driving, status: EmergencyStatus.safe,
        speedKmh: 60.0,
      );
      final updated = event.copyWith(status: EmergencyStatus.confirmed);
      expect(updated.status, EmergencyStatus.confirmed);
      expect(updated.speedKmh, 60.0);
      expect(updated.id, '1');
    });
  });

  group('TrustedContact', () {
    test('isValid returns true when name and phone present', () {
      final contact = TrustedContact(name: 'Mom', phoneNumber: '+911234567890');
      expect(contact.isValid, true);
    });

    test('isValid returns false when name is empty', () {
      final contact = TrustedContact(name: '', phoneNumber: '+911234567890');
      expect(contact.isValid, false);
    });

    test('isValid returns false when phone is empty', () {
      final contact = TrustedContact(name: 'Mom', phoneNumber: '');
      expect(contact.isValid, false);
    });

    test('toJson round-trip', () {
      final contact = TrustedContact(
        name: 'Dad', phoneNumber: '+919876543210', isPrimary: true,
      );
      final json = contact.toJson();
      final restored = TrustedContact.fromJson(json);
      expect(restored.name, 'Dad');
      expect(restored.phoneNumber, '+919876543210');
      expect(restored.isPrimary, true);
    });

    test('copyWith preserves defaults', () {
      final contact = TrustedContact(name: 'Friend', phoneNumber: '+911111111111');
      final updated = contact.copyWith(isPrimary: true);
      expect(updated.isPrimary, true);
      expect(updated.name, 'Friend');
      expect(updated.isTestContact, false);
    });

    test('test contact flag preserved', () {
      final contact = TrustedContact(
        name: 'Test', phoneNumber: '+919999999999', isTestContact: true,
      );
      expect(contact.isTestContact, true);
    });
  });
}
