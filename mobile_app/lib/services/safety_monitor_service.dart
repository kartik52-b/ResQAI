import 'dart:async';
import 'package:flutter/foundation.dart';
import '../sensors/sensor_manager.dart';
import '../engine/sensor_fusion.dart';
import '../engine/context_engine.dart';
import '../engine/accident_detector.dart';
import '../engine/speed_drop_detector.dart';
import '../engine/life_replay.dart';
import '../models/emergency_event.dart';
import '../models/sensor_data.dart';
import 'api_service.dart';
import 'contact_service.dart';
import 'native_service_bridge.dart';
import 'emergency_orchestrator.dart';
import 'voice_emergency_detector.dart';

/// The core monitoring service that owns the safety detection lifecycle.
///
/// This service:
/// - Starts/stops sensors and detection engines
/// - Processes GPS + accelerometer + gyroscope data
/// - Detects emergencies via SpeedDropDetector (GPS speed drop)
/// - Feeds multi-sensor data (accel + gyro) to SpeedDropDetector
/// - Manages voice emergency detection
/// - Coordinates the EmergencyOrchestrator for SMS/call/backend
/// - Shows emergency notification when app is in background
/// - Exposes observable state for the UI layer
///
/// The UI (HomeScreen, MonitoringScreen) reads from this service.
/// The service does NOT depend on any widget or screen.
class SafetyMonitorService extends ChangeNotifier {
  final SensorManager _sensorManager;
  final NativeServiceBridge _nativeBridge;
  final ApiService _apiService;
  final ContactService _contactService;

  // Detection engines
  final SensorFusion _fusion = SensorFusion();
  final ContextEngine _contextEngine = ContextEngine();
  final SpeedDropDetector _speedDropDetector = SpeedDropDetector();
  final AccidentDetector _accidentDetector = AccidentDetector();
  final LifeReplay _lifeReplay = LifeReplay();
  late final EmergencyOrchestrator _orchestrator;
  late final VoiceEmergencyDetector _voiceDetector;

  // Stream subscriptions
  StreamSubscription? _fusedSubscription;
  StreamSubscription? _gpsSubscription;

  // --- Observable state ---
  bool _isProtecting = false;
  String _safetyStatus = 'STANDBY';
  String _emergencyStatus = 'SAFE';
  int _emergencyScore = 0;
  String _lastIncident = 'None';
  String _orchestratorMessage = '';
  String _voiceTranscript = '';

  // GPS
  double _currentSpeedKmh = 0.0;
  double _currentLatitude = 0.0;
  double _currentLongitude = 0.0;
  String _gpsStatus = 'INACTIVE';
  String _detectionPhase = 'IDLE';
  double _gpsAccuracy = 0.0;
  bool _gpsIsStationary = false;
  String _movementDiagnostics = '';

  // Voice
  bool _voiceDetectionOn = false;
  String _voiceMicStatus = 'INACTIVE';
  String _voiceDetectionStatus = 'OFF';
  String _voiceDetectedPhrase = '';

  // --- Getters ---
  bool get isProtecting => _isProtecting;
  String get safetyStatus => _safetyStatus;
  String get emergencyStatus => _emergencyStatus;
  int get emergencyScore => _emergencyScore;
  String get lastIncident => _lastIncident;
  String get orchestratorMessage => _orchestratorMessage;
  String get voiceTranscript => _voiceTranscript;

  double get currentSpeedKmh => _currentSpeedKmh;
  double get currentLatitude => _currentLatitude;
  double get currentLongitude => _currentLongitude;
  String get gpsStatus => _gpsStatus;
  String get detectionPhase => _detectionPhase;
  double get gpsAccuracy => _gpsAccuracy;
  bool get gpsIsStationary => _gpsIsStationary;
  String get movementDiagnostics => _movementDiagnostics;

  bool get voiceDetectionOn => _voiceDetectionOn;
  String get voiceMicStatus => _voiceMicStatus;
  String get voiceDetectionStatus => _voiceDetectionStatus;
  String get voiceDetectedPhrase => _voiceDetectedPhrase;

  EmergencyOrchestrator get orchestrator => _orchestrator;
  LifeReplay get lifeReplay => _lifeReplay;
  SpeedDropDetector get speedDropDetector => _speedDropDetector;
  AccidentDetector get accidentDetector => _accidentDetector;
  SensorManager get sensorManager => _sensorManager;

  SafetyMonitorService({
    required SensorManager sensorManager,
    required NativeServiceBridge nativeBridge,
    required ApiService apiService,
    required ContactService contactService,
  })  : _sensorManager = sensorManager,
        _nativeBridge = nativeBridge,
        _apiService = apiService,
        _contactService = contactService {
    _orchestrator = EmergencyOrchestrator(
      bridge: _nativeBridge,
      apiService: _apiService,
      contactService: _contactService,
      speedDropDetector: _speedDropDetector,
      lifeReplay: _lifeReplay,
    );

    _orchestrator.onStateChanged = _onOrchestratorStateChanged;
    _orchestrator.onStatusMessage = (msg) {
      _orchestratorMessage = msg;
      notifyListeners();
    };
    _orchestrator.onVoiceTranscript = (text) {
      _voiceTranscript = text;
      notifyListeners();
    };
    _orchestrator.onEmergencyNotification = _showEmergencyNotification;

    _voiceDetector = VoiceEmergencyDetector(_nativeBridge);
    _orchestrator.attachVoiceDetector(_voiceDetector);

    _voiceDetector.onStateChanged = (state) {
      _voiceMicStatus = (state == VoiceDetectionState.listening)
          ? 'ACTIVE'
          : (state == VoiceDetectionState.error) ? 'ERROR' : 'INACTIVE';
      _voiceDetectionStatus = state.name.toUpperCase();
      notifyListeners();
    };

    _voiceDetector.onPhraseDetected = (phrase) {
      _voiceDetectedPhrase = phrase;
      _voiceDetectionStatus = 'PHRASE DETECTED';
      notifyListeners();
    };

    _voiceDetector.onError = (error) {
      _voiceMicStatus = 'ERROR';
      _voiceDetectionStatus = 'ERROR';
      notifyListeners();
    };

    _speedDropDetector.setCallback(_onSpeedDropDetected);
    _accidentDetector.setCallback(_onAccidentDetected);
  }

  // === PROTECTION CONTROL ===

  Future<bool> startProtection() async {
    if (_isProtecting) return true;

    _safetyStatus = 'STARTING...';
    _gpsStatus = 'STARTING';
    notifyListeners();

    final gpsResult = await _sensorManager.startAll();

    _isProtecting = true;
    _safetyStatus = 'ACTIVE';

    // Set GPS status based on the start result
    if (gpsResult.success) {
      // Permission granted and GPS stream started — waiting for first fix
      _gpsStatus = 'SEARCHING';
    } else {
      // Permission denied or location service off — show the specific error
      final error = gpsResult.error ?? 'Unknown GPS error';
      if (error.contains('disabled')) {
        _gpsStatus = 'SERVICE OFF';
      } else if (error.contains('denied')) {
        _gpsStatus = 'PERMISSION DENIED';
      } else {
        _gpsStatus = 'ERROR';
      }
    }
    notifyListeners();

    _nativeBridge.startForegroundService();
    _nativeBridge.requestSmsPermission();
    _nativeBridge.requestCallPermission();
    _nativeBridge.requestNotificationPermission();

    _fusedSubscription?.cancel();
    _gpsSubscription?.cancel();

    _fusedSubscription = _sensorManager.fusedStream.listen(_onFusedData);
    _gpsSubscription = _sensorManager.gps.stream.listen(_onGpsData);

    return gpsResult.success;
  }

  void stopProtection() {
    _isProtecting = false;
    _safetyStatus = 'STANDBY';

    _fusedSubscription?.cancel();
    _fusedSubscription = null;
    _gpsSubscription?.cancel();
    _gpsSubscription = null;

    _sensorManager.stopAll();
    _fusion.reset();
    _contextEngine.resetImpact();
    _speedDropDetector.reset();
    _accidentDetector.reset();
    _orchestrator.dispose();

    if (_voiceDetectionOn) {
      _voiceDetector.setEnabled(false);
      _voiceDetectionOn = false;
      _voiceMicStatus = 'INACTIVE';
      _voiceDetectionStatus = 'OFF';
    }

    _nativeBridge.stopForegroundService();

    _emergencyScore = 0;
    _emergencyStatus = 'SAFE';
    _gpsStatus = 'INACTIVE';
    _currentSpeedKmh = 0;
    _currentLatitude = 0;
    _currentLongitude = 0;
    _detectionPhase = 'IDLE';
    _gpsAccuracy = 0;
    _gpsIsStationary = false;
    _movementDiagnostics = '';
    _orchestratorMessage = '';
    _voiceTranscript = '';
    _voiceDetectedPhrase = '';

    notifyListeners();
  }

  // === VOICE DETECTION ===

  Future<void> toggleVoiceDetection(bool enable) async {
    if (enable && !_isProtecting) return;

    // setEnabled() handles permission request internally —
    // no need to request permission separately here.
    await _voiceDetector.setEnabled(enable);
    _voiceDetectionOn = enable && _voiceDetector.isEnabled;
    notifyListeners();
  }

  Future<void> openMicSettings() async {
    await _voiceDetector.openSettings();
  }

  // === SENSOR DATA PROCESSING ===

  void _onFusedData(FusedSensorState state) {
    if (!_isProtecting) return;

    final analysis = _fusion.analyze(state);
    final result = _contextEngine.analyze(analysis);

    _lifeReplay.addEvent(
      description: result.description,
      activityType: result.activityType,
      score: result.score.totalScore.round(),
    );

    // Feed multi-sensor data to detection engines
    final accelNet = state.accelerometer?.netMagnitude ?? 0;
    final gyroMag = state.gyroscope?.magnitude ?? 0;
    _speedDropDetector.updateSensorData(accelNet, gyroMag);
    _accidentDetector.updateSensorData(accelNet, gyroMag);

    // Update detection phase display from AccidentDetector
    _detectionPhase = _accidentDetector.phase.name.toUpperCase();

    if (_accidentDetector.phase != AccidentPhase.verifying) {
      _emergencyScore = result.score.totalScore.round();
      _safetyStatus = result.activityType.name.toUpperCase();
    }

    _movementDiagnostics = analysis.diagnostics?.toString() ?? '';
    notifyListeners();
  }

  void _onGpsData(GpsData gpsData) {
    if (!_isProtecting) return;

    // First valid position received → transition from SEARCHING to ACTIVE
    if (_gpsStatus != 'ACTIVE') {
      _gpsStatus = 'ACTIVE';
      debugPrint('SafetyMonitorService: GPS first valid fix received — now ACTIVE');
    }
    _currentSpeedKmh = gpsData.speedKmh;
    _currentLatitude = gpsData.latitude;
    _currentLongitude = gpsData.longitude;
    _detectionPhase = _speedDropDetector.phase.name.toUpperCase();
    _gpsAccuracy = gpsData.accuracy;
    _gpsIsStationary = gpsData.isStationary;

    // Feed latest GPS location to orchestrator for voice-triggered emergencies
    _orchestrator.updateLocation(
      gpsData.latitude,
      gpsData.longitude,
      gpsData.speedKmh,
    );

    _speedDropDetector.onGpsUpdate(gpsData);
    _accidentDetector.onGpsUpdate(gpsData);

    // Update detection phase from AccidentDetector
    _detectionPhase = _accidentDetector.phase.name.toUpperCase();

    final accidentPhase = _accidentDetector.phase;
    if (accidentPhase == AccidentPhase.suddenDeceleration ||
        accidentPhase == AccidentPhase.possibleImpact ||
        accidentPhase == AccidentPhase.postEventInactivity) {
      _safetyStatus = 'ACCIDENT DETECTED';
      if (_accidentDetector.lastDetectedScore > 0) {
        _emergencyScore = _accidentDetector.lastDetectedScore;
      }
    } else if (accidentPhase == AccidentPhase.normalMoving) {
      // Don't overwrite safety status from fused data during normal movement
    }

    notifyListeners();
  }

  // === EMERGENCY CALLBACKS ===

  void _onSpeedDropDetected(EmergencyEvent event) {
    _emergencyStatus = 'VERIFYING';
    _orchestrator.onPossibleEmergency(event);
    notifyListeners();
  }

  void _onAccidentDetected(EmergencyEvent event) {
    _emergencyStatus = 'VERIFYING';
    _emergencyScore = event.emergencyScore;
    _orchestrator.onPossibleEmergency(event);
    notifyListeners();
  }

  void _showEmergencyNotification() {
    // Notify the Android foreground service to show a high-priority notification
    _nativeBridge.showEmergencyNotification(
      title: '🚨 EMERGENCY DETECTED',
      body: 'Are you alright? Open ResQ AI to respond.',
    );
  }

  void _onOrchestratorStateChanged(OrchestratorState state) {
    switch (state) {
      case OrchestratorState.voiceVerifying:
        _emergencyStatus = 'VOICE VERIFICATION';
      case OrchestratorState.userConfirmedOk:
        _emergencyStatus = 'SAFE';
        _safetyStatus = 'NORMAL';
      case OrchestratorState.emergencyConfirmed:
        _emergencyStatus = 'CONFIRMED';
        _lastIncident = _formatTime(DateTime.now());
      case OrchestratorState.smsSending:
        _emergencyStatus = 'SENDING SMS';
      case OrchestratorState.callingContact:
        _emergencyStatus = 'CALLING CONTACT';
      case OrchestratorState.complete:
        _emergencyStatus = 'CONFIRMED';
      default:
        break;
    }
    notifyListeners();
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    stopProtection();
    _voiceDetector.dispose();
    super.dispose();
  }
}
