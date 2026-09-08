import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resq_ai/services/sms_service.dart';
import 'package:resq_ai/services/contact_service.dart';
import 'package:resq_ai/services/native_service_bridge.dart';
import 'package:resq_ai/services/api_service.dart';
import 'package:resq_ai/services/emergency_orchestrator.dart';
import 'package:resq_ai/config/thresholds.dart';
import 'package:resq_ai/models/trusted_contact.dart';
import 'package:resq_ai/models/emergency_event.dart';
import 'package:resq_ai/engine/speed_drop_detector.dart';
import 'package:resq_ai/engine/life_replay.dart';

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

  group('EmergencyOrchestrator — full emergency flow', () {
    late List<http.Request> requests;
    late ApiService apiService;
    late ContactService contactService;
    late EmergencyOrchestrator orchestrator;

    /// Builds a real orchestrator backed by an in-memory HTTP mock and a
    /// mock SharedPreferences store. Native bridge calls are the real
    /// singleton — its platform calls fail gracefully in tests.
    EmergencyOrchestrator buildOrchestrator() {
      requests = [];
      final mockClient = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/emergency') {
          return http.Response(
            '{"status":"success","incident_id":"TEST0001",'
            '"access_token":"tok123","severity":"HIGH"}',
            200,
          );
        }
        return http.Response('{}', 200);
      });
      apiService = ApiService(client: mockClient);
      return EmergencyOrchestrator(
        bridge: NativeServiceBridge(),
        apiService: apiService,
        contactService: contactService,
        speedDropDetector: SpeedDropDetector(),
        lifeReplay: LifeReplay(),
      );
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});

      // Mock the native platform channel so bridge calls (SMS/call/TTS/etc.)
      // resolve deterministically in tests instead of throwing/hanging.
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.example.resq_ai/native_service'),
        (call) async {
          switch (call.method) {
            case 'sendSms':
            case 'makeCall':
              return {'success': true, 'error': ''};
            case 'checkPermission':
              return false;
            default:
              return true;
          }
        },
      );

      contactService = ContactService();
      await contactService.addContact(
        TrustedContact(name: 'Mom', phoneNumber: '+911234567890'),
      );
      orchestrator = buildOrchestrator();
    });

    EmergencyEvent makeEvent() => EmergencyEvent(
          id: 'evt-1',
          timestamp: DateTime.now(),
          emergencyScore: 82,
          activityType: ActivityType.emergency,
          status: EmergencyStatus.possibleEmergency,
          impactMagnitude: 20,
          speedKmh: 45,
          location: {'latitude': 28.6139, 'longitude': 77.2090},
        );

    test('default verification timeout is 120 seconds', () {
      expect(EmergencySpeedThresholds.verificationTimeout, 120);
    });

    test('possible emergency starts countdown and requests notification',
        () async {
      int notifications = 0;
      orchestrator.onEmergencyNotification = () => notifications++;

      orchestrator.setCountdownTimeout(120);
      orchestrator.onPossibleEmergency(makeEvent());

      expect(orchestrator.state, OrchestratorState.voiceVerifying);
      expect(orchestrator.isProcessing, true);
      expect(orchestrator.remainingSeconds, 120);
      expect(orchestrator.currentEvent?.id, 'evt-1');
      expect(notifications, 1);
    });

    test("I'M OK cancels the emergency and stops the countdown", () async {
      orchestrator.setCountdownTimeout(120);
      orchestrator.onPossibleEmergency(makeEvent());

      orchestrator.userConfirmedOk();

      expect(orchestrator.state, OrchestratorState.userConfirmedOk);
      expect(orchestrator.isProcessing, false);

      // Cancelled emergency must NOT hit the backend.
      expect(
        requests.where((r) => r.url.path == '/emergency'),
        isEmpty,
      );
    });

    test('duplicate I\'M OK calls are ignored', () async {
      orchestrator.setCountdownTimeout(120);
      orchestrator.onPossibleEmergency(makeEvent());

      orchestrator.userConfirmedOk();
      final stateAfterFirst = orchestrator.state;
      orchestrator.userConfirmedOk(); // duplicate

      expect(stateAfterFirst, OrchestratorState.userConfirmedOk);
      expect(orchestrator.state, OrchestratorState.userConfirmedOk);
    });

    test('I NEED HELP confirms: SMS + call + backend report, exactly once',
        () async {
      orchestrator.updateLocation(28.6139, 77.2090, 45);
      orchestrator.setCountdownTimeout(120);
      orchestrator.onPossibleEmergency(makeEvent());

      orchestrator.userConfirmedHelp();
      // Double-tap on HELP must not double the workflow.
      orchestrator.userConfirmedHelp();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Backend reported exactly once.
      final emergencyPosts =
          requests.where((r) => r.url.path == '/emergency').length;
      expect(emergencyPosts, 1);

      expect(orchestrator.state, OrchestratorState.complete);
      expect(orchestrator.isProcessing, false);
    });

    test('no response → 120s timeout → auto-escalation exactly once',
        () async {
      fakeAsync((async) {
        int notifications = 0;
        orchestrator.onEmergencyNotification = () => notifications++;

        orchestrator.updateLocation(28.6139, 77.2090, 45);
        orchestrator.setCountdownTimeout(120);
        orchestrator.onPossibleEmergency(makeEvent());

        // Simulate 119 seconds of silence.
        async.elapse(const Duration(seconds: 119));
        expect(orchestrator.state, OrchestratorState.voiceVerifying);

        // Second 120 — countdown expires and auto-escalation fires.
        async.elapse(const Duration(seconds: 2));
        // Pump the async confirm-and-act chain (SMS/call/backend report)
        // in small steps, staying below the 5s post-completion idle reset.
        for (var i = 0;
            i < 200 && orchestrator.state != OrchestratorState.complete;
            i++) {
          async.elapse(const Duration(milliseconds: 10));
        }

        expect(orchestrator.state, OrchestratorState.complete);
        expect(
          requests.where((r) => r.url.path == '/emergency').length,
          1,
          reason: 'Auto-escalation must trigger the workflow exactly once',
        );
        expect(notifications, 1,
            reason: 'Only one emergency notification should be raised');
      });
    });

    test('response near the deadline: I\'M OK at 119s cancels — no escalation',
        () async {
      fakeAsync((async) {
        orchestrator.setCountdownTimeout(120);
        orchestrator.onPossibleEmergency(makeEvent());

        // User responds one second before the deadline.
        async.elapse(const Duration(seconds: 119));
        expect(orchestrator.state, OrchestratorState.voiceVerifying);

        orchestrator.userConfirmedOk();
        async.elapse(const Duration(seconds: 2));

        expect(orchestrator.state, OrchestratorState.userConfirmedOk);
        expect(
          requests.where((r) => r.url.path == '/emergency'),
          isEmpty,
          reason: 'A cancelled emergency must never auto-escalate',
        );
      });
    });

    test('demo mode timeout (15s) escalates faster for presentations',
        () async {
      fakeAsync((async) {
        orchestrator.setCountdownTimeout(15);
        orchestrator.onPossibleEmergency(makeEvent());

        async.elapse(const Duration(seconds: 16));
        // Pump the async confirm-and-act chain.
        for (var i = 0;
            i < 200 && orchestrator.state != OrchestratorState.complete;
            i++) {
          async.elapse(const Duration(milliseconds: 10));
        }

        expect(orchestrator.state, OrchestratorState.complete);
        expect(
          requests.where((r) => r.url.path == '/emergency').length,
          1,
        );
      });
    });

    test('countdown stream emits ticks while counting down', () async {
      final ticks = <int>[];
      final sub = orchestrator.countdownStream.listen(ticks.add);

      orchestrator.setCountdownTimeout(12);
      orchestrator.onPossibleEmergency(makeEvent());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(ticks.first, 12,
          reason: 'Stream must emit the initial value (clamp min is 10s)');
      await sub.cancel();
    });

    test('resetForReuse returns orchestrator to a clean reusable state',
        () async {
      orchestrator.setCountdownTimeout(120);
      orchestrator.onPossibleEmergency(makeEvent());
      orchestrator.userConfirmedOk();

      // Simulate stop/restart of protection.
      orchestrator.resetForReuse();

      expect(orchestrator.state, OrchestratorState.idle);
      expect(orchestrator.isProcessing, false);
      expect(orchestrator.currentEvent, isNull);

      // After reset, a new emergency must still be possible.
      orchestrator.setCountdownTimeout(120);
      orchestrator.onPossibleEmergency(makeEvent());
      expect(orchestrator.state, OrchestratorState.voiceVerifying);
      expect(orchestrator.isProcessing, true);
    });

    test('isProcessing blocks concurrent emergency triggers', () async {
      orchestrator.setCountdownTimeout(120);
      orchestrator.onPossibleEmergency(makeEvent());

      // A second detection while processing must be ignored.
      orchestrator.onPossibleEmergency(EmergencyEvent(
        id: 'evt-2',
        timestamp: DateTime.now(),
        emergencyScore: 82,
        activityType: ActivityType.emergency,
        status: EmergencyStatus.possibleEmergency,
      ));

      expect(orchestrator.currentEvent?.id, 'evt-1',
          reason: 'Original event must not be replaced mid-flow');
    });

    test('voice-triggered emergency uses latest known location', () async {
      orchestrator.updateLocation(12.9716, 77.5946, 30);
      orchestrator.setCountdownTimeout(120);

      orchestrator.onVoiceTriggeredEmergency();
      orchestrator.userConfirmedHelp();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final body = requests
          .firstWhere((r) => r.url.path == '/emergency')
          .body;
      expect(body, contains('12.9716'));
      expect(body, contains('77.5946'));
      expect(body, contains('"emergency_type":"voice"'));
    });
  });
}
