import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/thresholds.dart';
import '../models/emergency_event.dart';
import '../models/trusted_contact.dart';
import '../engine/speed_drop_detector.dart';
import '../engine/life_replay.dart';
import 'api_service.dart';
import 'contact_service.dart';
import 'native_service_bridge.dart';
import 'voice_alert_service.dart';
import 'voice_emergency_detector.dart';
import 'sms_service.dart';

/// States of the emergency orchestration flow.
enum OrchestratorState {
  idle,
  possibleEmergency,
  voiceVerifying,
  userConfirmedOk,
  userConfirmedHelp,
  noResponseTimeout,
  emergencyConfirmed,
  smsSending,
  callingContact,
  complete,
}

/// Coordinates the full emergency detection → verification → response flow.
///
/// Architecture:
/// 1. SpeedDropDetector detects possible emergency → onPossibleEmergency()
/// 2. VoiceEmergencyDetector detects emergency phrase → onVoiceTriggeredEmergency()
/// 3. Orchestrator starts 120-second countdown + speaks "Are you alright?"
/// 4. Voice alerts are retried every ~25 seconds within the 120s window
/// 5. Any OK response → cancel; HELP → confirm immediately; timeout → auto-confirm
/// 6. On confirm: SMS to ALL contacts + call to PRIMARY only + backend report
///
/// CRITICAL: The orchestrator OWNS the countdown timer.
/// The VerificationSystem is used ONLY for UI countdown display.
class EmergencyOrchestrator {
  final NativeServiceBridge _bridge;
  final ApiService _apiService;
  final ContactService _contactService;
  final SpeedDropDetector _speedDropDetector;
  final LifeReplay _lifeReplay;

  late final VoiceAlertService _voiceAlert;
  late final SmsService _smsService;
  VoiceEmergencyDetector? _voiceEmergencyDetector;

  OrchestratorState _state = OrchestratorState.idle;
  EmergencyEvent? _currentEvent;
  bool _isProcessing = false;
  bool _voiceTriggered = false;

  // Latest GPS location — updated by SafetyMonitorService on each GPS fix
  Map<String, dynamic>? _currentLocation;
  double _currentSpeedKmh = 0;

  // --- Unified countdown timer (ORCHESTRATOR OWNS THIS) ---
  Timer? _countdownTimer;
  int _remainingSeconds = EmergencySpeedThresholds.verificationTimeout;
  final _countdownController = StreamController<int>.broadcast();
  int _voiceRetryCount = 0;
  static const int _maxVoiceRetries = 4;
  static const int _voiceRetryIntervalSeconds = 25;

  OrchestratorState get state => _state;
  EmergencyEvent? get currentEvent => _currentEvent;
  bool get isProcessing => _isProcessing;
  bool get isVoiceTriggered => _voiceTriggered;
  int get remainingSeconds => _remainingSeconds;

  /// Stream of countdown seconds remaining (for UI)
  Stream<int> get countdownStream => _countdownController.stream;

  // Callbacks
  Function(OrchestratorState)? onStateChanged;
  Function(String)? onVoiceTranscript;
  Function(String)? onStatusMessage;
  Function()? onEmergencyNotification;

  EmergencyOrchestrator({
    required NativeServiceBridge bridge,
    required ApiService apiService,
    required ContactService contactService,
    required SpeedDropDetector speedDropDetector,
    required LifeReplay lifeReplay,
  })  : _bridge = bridge,
        _apiService = apiService,
        _contactService = contactService,
        _speedDropDetector = speedDropDetector,
        _lifeReplay = lifeReplay {
    _voiceAlert = VoiceAlertService(bridge);
    _smsService = SmsService(bridge);

    _voiceAlert.onUserSaidOk = _onVoiceUserOk;
    _voiceAlert.onUserSaidHelp = _onVoiceUserHelp;
    _voiceAlert.onNoResponseDetected = _onVoiceNoResponse;
    _voiceAlert.onPartialTranscript = (text) {
      onVoiceTranscript?.call(text);
    };
  }

  void attachVoiceDetector(VoiceEmergencyDetector detector) {
    _voiceEmergencyDetector = detector;
    detector.onEmergencyTriggered = () {
      onVoiceTriggeredEmergency();
    };
  }

  /// Update current GPS location — called by SafetyMonitorService on each GPS fix.
  /// This ensures voice-triggered emergencies always have the latest real location.
  void updateLocation(double latitude, double longitude, double speedKmh) {
    _currentLocation = {'latitude': latitude, 'longitude': longitude};
    _currentSpeedKmh = speedKmh;
  }

  // ======================================================================
  // EMERGENCY ENTRY POINTS
  // ======================================================================

  /// Called when SpeedDropDetector detects a possible emergency.
  void onPossibleEmergency(EmergencyEvent event) {
    if (_isProcessing) return;
    debugPrint('EmergencyOrchestrator: Possible emergency detected (GPS speed drop)');
    _startEmergencyFlow(event, voiceTriggered: false);
  }

  /// Called when VoiceEmergencyDetector detects an emergency voice phrase.
  /// Uses the latest real GPS location from updateLocation().
  void onVoiceTriggeredEmergency() {
    if (_isProcessing) return;
    debugPrint('EmergencyOrchestrator: Voice-triggered emergency');

    final event = EmergencyEvent(
      id: 'voice-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
      emergencyScore: 75,
      activityType: ActivityType.emergency,
      status: EmergencyStatus.possibleEmergency,
      impactMagnitude: 0,
      speedKmh: _currentSpeedKmh,
      location: _currentLocation,
    );
    _startEmergencyFlow(event, voiceTriggered: true);
  }

  // ======================================================================
  // CORE EMERGENCY FLOW
  // ======================================================================

  void _startEmergencyFlow(EmergencyEvent event, {required bool voiceTriggered}) {
    _currentEvent = event;
    _voiceTriggered = voiceTriggered;
    _isProcessing = true;
    _voiceRetryCount = 0;

    _setState(OrchestratorState.possibleEmergency);
    _statusMessage('Emergency detected — verifying...');

    // Request SMS permission for later
    _bridge.requestSmsPermission();

    // Start the unified countdown (120 seconds)
    _startCountdown();

    // Show emergency notification (for background scenarios)
    onEmergencyNotification?.call();

    // Begin voice verification cycle
    _startVoiceVerification();
  }

  // ======================================================================
  // COUNTDOWN MANAGEMENT
  // ======================================================================

  void _startCountdown() {
    _remainingSeconds = EmergencySpeedThresholds.verificationTimeout;
    _countdownController.add(_remainingSeconds);

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _remainingSeconds--;
      _countdownController.add(_remainingSeconds);

      if (_remainingSeconds <= 0) {
        timer.cancel();
        debugPrint('EmergencyOrchestrator: Countdown expired — auto-confirming');
        _setState(OrchestratorState.noResponseTimeout);
        _confirmAndAct();
      }
    });
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  // ======================================================================
  // VOICE VERIFICATION (ORCHESTRATOR-MANAGED RETRIES)
  // ======================================================================

  void _startVoiceVerification() {
    _setState(OrchestratorState.voiceVerifying);
    _statusMessage('Asking "Are you alright?" — listening for response');
    _voiceAlert.startAlert();
  }

  void _onVoiceUserOk() {
    if (!_isProcessing) return;
    debugPrint('EmergencyOrchestrator: Voice — user said OK → CANCEL');
    _cancelEmergency();
  }

  void _onVoiceUserHelp() {
    if (!_isProcessing) return;
    debugPrint('EmergencyOrchestrator: Voice — user said HELP → CONFIRM');
    _stopCountdown();
    _setState(OrchestratorState.userConfirmedHelp);
    _confirmAndAct();
  }

  void _onVoiceNoResponse() {
    if (!_isProcessing) return;
    _voiceRetryCount++;

    if (_voiceRetryCount < _maxVoiceRetries && _remainingSeconds > 10) {
      debugPrint('EmergencyOrchestrator: No response, retrying voice alert '
          '(${_voiceRetryCount}/$_maxVoiceRetries, ${_remainingSeconds}s remaining)');
      _statusMessage('No response — asking again (${_remainingSeconds}s remaining)');

      // Pause briefly, then retry
      Future.delayed(const Duration(seconds: 5), () {
        if (_isProcessing && _state == OrchestratorState.voiceVerifying) {
          _voiceAlert.startAlert();
        }
      });
    } else {
      debugPrint('EmergencyOrchestrator: No response after $_voiceRetryCount attempts '
          '(${_remainingSeconds}s remaining) — will auto-confirm at timeout');
      _statusMessage('No response — emergency will auto-confirm at timeout');
      // Don't confirm here — let the countdown timer handle it
    }
  }

  // ======================================================================
  // UI BUTTON HANDLERS
  // ======================================================================

  void userConfirmedOk() {
    if (!_isProcessing) return;
    debugPrint('EmergencyOrchestrator: User confirmed OK via UI');
    _cancelEmergency();
  }

  void userConfirmedHelp() {
    if (!_isProcessing) return;
    debugPrint('EmergencyOrchestrator: User confirmed HELP via UI');
    _stopCountdown();
    _voiceAlert.stop();
    _voiceEmergencyDetector?.cancelPendingEmergency();
    _setState(OrchestratorState.userConfirmedHelp);
    _confirmAndAct();
  }

  void _cancelEmergency() {
    _stopCountdown();
    _voiceAlert.stop();
    _voiceEmergencyDetector?.cancelPendingEmergency();
    _setState(OrchestratorState.userConfirmedOk);
    _statusMessage('Emergency cancelled — you are safe');
    _speedDropDetector.onVerificationComplete();
    _complete();
  }

  // ======================================================================
  // EMERGENCY CONFIRMATION + ACTIONS
  // ======================================================================

  Future<void> _confirmAndAct() async {
    _stopCountdown();
    _voiceAlert.stop();

    _setState(OrchestratorState.emergencyConfirmed);
    _lifeReplay.takeSnapshot();

    // Use event location, falling back to latest known GPS coordinates
    final location = _currentEvent?.location ?? _currentLocation;
    final double latitude = (location?['latitude'] as num?)?.toDouble() ?? 0.0;
    final double longitude = (location?['longitude'] as num?)?.toDouble() ?? 0.0;
    final double speedKmh = _currentEvent?.speedKmh ?? _currentSpeedKmh;
    final int score = _currentEvent?.emergencyScore ?? 0;
    final timestamp = DateTime.now();

    // === Step 1: SMS to ALL trusted contacts ===
    _setState(OrchestratorState.smsSending);
    _statusMessage('Sending emergency SMS to contacts...');

    final contacts = _contactService.contacts;
    if (contacts.isNotEmpty) {
      final smsResults = await _smsService.sendEmergencyToAll(
        contacts: contacts,
        latitude: latitude,
        longitude: longitude,
        timestamp: timestamp,
        speedKmh: speedKmh,
        emergencyScore: score,
      );
      int successCount = 0;
      for (final result in smsResults) {
        if (result.success) successCount++;
        debugPrint('SMS to ${result.contactName}: '
            '${result.success ? "SUCCESS" : "FAILED"} '
            '${result.error != null ? "(${result.error})" : ""}');
      }
      _statusMessage('SMS sent to $successCount/${contacts.length} contacts');
    } else {
      _statusMessage('No trusted contacts configured — SMS not sent');
    }

    // === Step 2: Phone call to PRIMARY contact only ===
    _setState(OrchestratorState.callingContact);
    _statusMessage('Calling primary trusted contact...');

    final primaryPhone = _contactService.getEmergencyPhoneNumber();
    if (primaryPhone != null) {
      try {
        final callResult = await _bridge.makeCall(primaryPhone);
        final success = callResult['success'] == true;
        _statusMessage(success
            ? 'Calling $primaryPhone'
            : 'Call failed: ${callResult['error']}');
      } catch (e) {
        _statusMessage('Call failed: $e');
      }
    } else {
      _statusMessage('No primary contact configured — call not placed');
    }

    // === Step 3: Report to backend ===
    _statusMessage('Reporting to backend...');
    try {
      final timeline = _lifeReplay.snapshot ?? _lifeReplay.events;
      final String severity;
      if (score >= 85) {
        severity = 'CRITICAL';
      } else if (score >= 70) {
        severity = 'HIGH';
      } else if (score >= 50) {
        severity = 'MEDIUM';
      } else {
        severity = 'LOW';
      }

      final result = await _apiService.reportEmergency(
        latitude: latitude,
        longitude: longitude,
        speedKmh: speedKmh,
        impactMagnitude: _currentEvent?.impactMagnitude ?? 0.0,
        emergencyScore: score,
        severity: severity,
        timeline: timeline,
      );

      if (result != null) {
        final incidentId = result['incident_id'] ?? 'Unknown';
        _statusMessage('Emergency confirmed — Incident $incidentId created');
      } else {
        _statusMessage('Emergency confirmed — Server unreachable (will retry)');
      }
    } catch (e) {
      _statusMessage('Emergency confirmed — Network error');
    }

    _setState(OrchestratorState.complete);
    _complete();
  }

  void _complete() {
    _isProcessing = false;
    _voiceTriggered = false;
    Future.delayed(const Duration(seconds: 5), () {
      _setState(OrchestratorState.idle);
    });
  }

  void _setState(OrchestratorState newState) {
    _state = newState;
    onStateChanged?.call(newState);
  }

  void _statusMessage(String msg) {
    debugPrint('EmergencyOrchestrator: $msg');
    onStatusMessage?.call(msg);
  }

  void dispose() {
    _stopCountdown();
    _voiceAlert.dispose();
    _countdownController.close();
  }
}
