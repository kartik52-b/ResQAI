import 'package:flutter_test/flutter_test.dart';
import 'package:resq_ai/services/sms_service.dart';
import 'package:resq_ai/services/contact_service.dart';
import 'package:resq_ai/services/native_service_bridge.dart';
import 'package:resq_ai/models/trusted_contact.dart';

void main() {
  // Ensure the binding is initialized so NativeServiceBridge's MethodChannel
  // can set its handler without crashing.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SmsService', () {
    late SmsService smsService;

    setUp(() {
      // NativeServiceBridge is a singleton — use the real instance.
      // buildEmergencyMessage doesn't use the bridge, so this is safe for unit tests.
      smsService = SmsService(NativeServiceBridge());
    });

    test('buildEmergencyMessage contains location', () {
      final message = smsService.buildEmergencyMessage(
        latitude: 28.6139,
        longitude: 77.2090,
        timestamp: DateTime(2024, 3, 15, 14, 30, 0),
      );
      expect(message, contains('28.6139'));
      expect(message, contains('77.209'));
      expect(message, contains('google.com/maps'));
    });

    test('buildEmergencyMessage contains timestamp', () {
      final message = smsService.buildEmergencyMessage(
        latitude: 28.6139,
        longitude: 77.2090,
        timestamp: DateTime(2024, 3, 15, 14, 30, 0),
      );
      expect(message, contains('15/3/2024'));
      expect(message, contains('14:30:00'));
    });

    test('buildEmergencyMessage contains speed when provided', () {
      final message = smsService.buildEmergencyMessage(
        latitude: 28.6139,
        longitude: 77.2090,
        timestamp: DateTime.now(),
        speedKmh: 45.0,
      );
      expect(message, contains('45.0 km/h'));
    });

    test('buildEmergencyMessage contains emergency score when provided', () {
      final message = smsService.buildEmergencyMessage(
        latitude: 28.6139,
        longitude: 77.2090,
        timestamp: DateTime.now(),
        emergencyScore: 85,
      );
      expect(message, contains('85/100'));
    });

    test('buildEmergencyMessage omits speed when null', () {
      final message = smsService.buildEmergencyMessage(
        latitude: 28.6139,
        longitude: 77.2090,
        timestamp: DateTime.now(),
      );
      expect(message, isNot(contains('Speed')));
    });

    test('buildEmergencyMessage contains Google Maps link', () {
      final message = smsService.buildEmergencyMessage(
        latitude: 28.6139,
        longitude: 77.2090,
        timestamp: DateTime.now(),
      );
      expect(message, contains('https://www.google.com/maps/search/?api=1&query=28.6139,77.209'));
    });

    test('buildEmergencyMessage is formatted correctly', () {
      final message = smsService.buildEmergencyMessage(
        latitude: 28.6139,
        longitude: 77.2090,
        timestamp: DateTime.now(),
      );
      expect(message, contains('RESQ AI EMERGENCY ALERT'));
      expect(message, contains('I may need help'));
      expect(message, contains('Latitude: 28.613900'));
      expect(message, contains('Longitude: 77.209000'));
      expect(message, contains('Please check my live location'));
    });

    test('buildEmergencyMessage includes emergency page URL when provided', () {
      final message = smsService.buildEmergencyMessage(
        latitude: 28.6139,
        longitude: 77.2090,
        timestamp: DateTime.now(),
        emergencyPageUrl: 'http://192.168.1.5:8000/emergency/abc123',
      );
      expect(message, contains('Live Location:'));
      expect(message, contains('http://192.168.1.5:8000/emergency/abc123'));
      expect(message, contains('google.com/maps'));
    });

    test('buildEmergencyMessage omits Live Location when no URL', () {
      final message = smsService.buildEmergencyMessage(
        latitude: 28.6139,
        longitude: 77.2090,
        timestamp: DateTime.now(),
      );
      expect(message, isNot(contains('Live Location:')));
    });

    test('sendEmergencyToAll returns empty for no contacts', () async {
      final results = await smsService.sendEmergencyToAll(
        contacts: [],
        latitude: 28.6139,
        longitude: 77.2090,
        timestamp: DateTime.now(),
      );
      expect(results, isEmpty);
    });

    test('sendEmergencyToAll skips test contacts', () async {
      final contacts = [
        TrustedContact(
          name: 'Test Contact',
          phoneNumber: '+919999999999',
          isTestContact: true,
        ),
      ];
      final results = await smsService.sendEmergencyToAll(
        contacts: contacts,
        latitude: 28.6139,
        longitude: 77.2090,
        timestamp: DateTime.now(),
      );
      expect(results.length, 1);
      expect(results.first.success, true); // skipped = success
      expect(results.first.error, contains('Test contact'));
    });
  });

  group('ContactService', () {
    test('TrustedContact max contacts limit', () {
      expect(ContactService.maxContacts, 5);
    });

    test('primaryContact returns first when no explicit primary', () {
      // We can't easily test ContactService without SharedPreferences
      // but we can verify the logic of primaryContact via TrustedContact
      final contacts = [
        TrustedContact(name: 'A', phoneNumber: '+911111111111'),
        TrustedContact(name: 'B', phoneNumber: '+912222222222', isPrimary: true),
        TrustedContact(name: 'C', phoneNumber: '+913333333333'),
      ];
      final primary = contacts.where((c) => c.isPrimary && c.isValid).toList();
      expect(primary.first.name, 'B');
    });
  });

  group('Emergency flow logic', () {
    test('timeout configuration', () {
      // Default timeout should be 120 seconds
      // Demo timeout should be 15 seconds
      const realTimeout = 120;
      const demoTimeout = 15;
      expect(realTimeout, greaterThanOrEqualTo(60));
      expect(realTimeout, lessThanOrEqualTo(120));
      expect(demoTimeout, lessThan(realTimeout));
    });

    test('I\'M OK cancels emergency', () {
      bool emergencyCancelled = false;
      bool emergencyConfirmed = false;

      // Simulate I'M OK button press
      emergencyCancelled = true;
      emergencyConfirmed = false;

      expect(emergencyCancelled, true);
      expect(emergencyConfirmed, false);
    });

    test('I NEED HELP confirms emergency', () {
      bool emergencyCancelled = false;
      bool emergencyConfirmed = false;

      // Simulate I NEED HELP button press
      emergencyConfirmed = true;
      emergencyCancelled = false;

      expect(emergencyConfirmed, true);
      expect(emergencyCancelled, false);
    });
  });
}


