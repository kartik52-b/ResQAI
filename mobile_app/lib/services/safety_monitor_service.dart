import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/thresholds.dart';
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
  // Countdown ticks from the orchestrator — every tick rebuilds the UI so the
  // on-screen "ARE YOU ALRIGHT?" timer actually counts down.
  StreamSubscription<int>? _countdownSubscription;

  // GPS initialization timeout
  Timer? _gpsTimeoutTimer;

  // --- Test mode (developer only) ---
  bool _testMode = false;
  bool get testMode => _testMode;

  // --- Demo mode (shorter timeout for judge presentation) ---
  bool _demoMode = false;
  bool get demoMode => _demoMode;
  static const int _demoTimeoutSeconds = 15;
  int get demoCountdownSeconds => _demoMode ? _demoTimeoutSeconds : EmergencySpeedThresholds.verificationTimeout;

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
  double _rawSpeedKmh = 0.0;
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
  double get rawSpeedKmh => _rawSpeedKmh;
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

  // === TEST / DEMO MODE ===

  /// Enable/disable developer test mode.
  /// When enabled, the user can inject simulated sensor data via [injectTestData].
  void toggleTestMode(bool enable) {
    _testMode = enable;
    if (enable) {
      debugPrint('[TestMode] ENABLED — simulated data will feed real detection engines');
    } else {
      debugPrint('[TestMode] DISABLED');
      _accidentDetector.reset();
      _speedDropDetector.reset();
    }
    notifyListeners();
  }

  /// Enable/disable demo mode for judge presentation.
  /// Uses a shorter countdown (15s) so the demo doesn't take 2 minutes.
  void toggleDemoMode(bool enable) {
    _demoMode = enable;
    debugPrint('[DemoMode] ${enable ? 'ENABLED' : 'DISABLED'} — timeout: ${_demoMode ? _demoTimeoutSeconds : 120}s');
    notifyListeners();
  }

  /// Inject simulated sensor data into the REAL detection engines.
  /// Uses the EXACT SAME code path as real GPS + sensor data.
  ///
  /// [speedKmh] — simulated speed in km/h
  /// [accelNet] — simulated net accelerometer magnitude (m/s², gravity removed)
  /// [gyroMag] — simulated gyroscope magnitude (degrees/s)
  /// [latitude] / [longitude] — simulated GPS coordinates (optional, defaults to current)
  void injectTestData({
    required double speedKmh,
    required double accelNet,
    required double gyroMag,
    double? latitude,
    double? longitude,
  }) {
    if (!_testMode || !_isProtecting) return;

    final now = DateTime.now();
    final lat = latitude ?? (_currentLatitude != 0 ? _currentLatitude : 28.6139);
    final lon = longitude ?? (_currentLongitude != 0 ? _currentLongitude : 77.2090);

    // Create a GpsData with the simulated speed (convert km/h to m/s for GpsData)
    final gpsData = GpsData(
      latitude: lat,
      longitude: lon,
      speed: speedKmh / 3.6, // GpsData stores m/s internally
      timestamp: now,
      accuracy: 5.0, // Perfect accuracy for test
      rawSpeedKmh: speedKmh,
      groundSpeedKmh: speedKmh,
      isStationary: speedKmh < 2.0,
    );

    // Update observable state (exactly like _onGpsData does)
    _currentSpeedKmh = speedKmh;
    _rawSpeedKmh = speedKmh;
    _currentLatitude = lat;
    _currentLongitude = lon;
    _gpsStatus = 'ACTIVE';
    _gpsAccuracy = 5.0;
    _gpsIsStationary = speedKmh < 2.0;

    // Feed to GPS update handlers — SAME PATH as real GPS
    _speedDropDetector.onGpsUpdate(gpsData);
    _accidentDetector.onGpsUpdate(gpsData);

    // Feed accelerometer + gyroscope to detection engines — SAME PATH as real sensors
    _speedDropDetector.updateSensorData(accelNet, gyroMag);
    _accidentDetector.updateSensorData(accelNet, gyroMag);

    // Update orchestrator location
    _orchestrator.updateLocation(lat, lon, speedKmh);

    // Update detection phase display
    _detectionPhase = _accidentDetector.phase.name.toUpperCase();

    final accidentPhase = _accidentDetector.phase;
    if (accidentPhase == AccidentPhase.suddenDeceleration ||
        accidentPhase == AccidentPhase.possibleImpact ||
        accidentPhase == AccidentPhase.postEventInactivity) {
      _safetyStatus = 'ACCIDENT DETECTED';
    } else if (accidentPhase == AccidentPhase.normalMoving) {
      _safetyStatus = speedKmh > 30 ? 'DRIVING' : speedKmh > 12 ? 'CYCLING' : 'MOVING';
    } else {
      _safetyStatus = speedKmh < 2.0 ? 'STATIONARY' : 'MOVING';
    }

    debugPrint('[TestMode] Injected: speed=${speedKmh.toStringAsFixed(1)} km/h, '
        'accel=${accelNet.toStringAsFixed(1)} m/s², '
        'gyro=${gyroMag.toStringAsFixed(1)} deg/s, '
        'phase=${_accidentDetector.phase.name}');

    notifyListeners();
  }

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
      gpsService: _sensorManager.gps,
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

    // Wire up native Android emergency popup callbacks
    _nativeBridge.onEmergencyUserOk = (eventId) {
      debugPrint('[SafetyMonitorService] Native popup: user pressed OK — event: $eventId');
      _orchestrator.userConfirmedOk();
    };
    _nativeBridge.onEmergencyUserHelp = (eventId) {
      debugPrint('[SafetyMonitorService] Native popup: user pressed HELP — event: $eventId');
      _orchestrator.userConfirmedHelp();
    };
    _nativeBridge.onEmergencyTimeout = (eventId) {
      debugPrint('[SafetyMonitorService] Native popup: timeout — event: $eventId');
      _orchestrator.userConfirmedHelp(); // Auto-confirm emergency
    };

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

    // Tick the UI every second of the emergency countdown. Without this the
    // overlay timer stays frozen at 02:00 (stream existed but had no listener).
    _countdownSubscription = _orchestrator.countdownStream.listen((_) {
      notifyListeners();
    });
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
      debugPrint('[SafetyMonitor] GPS stream started — SEARCHING for fix');

      // Start 60-second GPS timeout
      _gpsTimeoutTimer?.cancel();
      _gpsTimeoutTimer = Timer(const Duration(seconds: 60), () {
        if (_isProtecting && _gpsStatus == 'SEARCHING') {
          debugPrint('[SafetyMonitor] ⚠️ GPS timeout — no fix after 60s');
          _movementDiagnostics = 'GPS: No fix after 60s. Go outdoors or check device GPS.';
          notifyListeners();
        }
      });
    } else {
      // Permission denied or location service off — show the specific error
      final error = gpsResult.error ?? 'Unknown GPS error';
      debugPrint('[SafetyMonitor] ❌ GPS start failed: $error');
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

    // === AUTO-START VOICE EMERGENCY DETECTION ===
    // Voice monitoring starts automatically with Protection.
    // The user does NOT need to manually enable it.
    // If microphone permission is denied, voice detection gracefully
    // falls back to OFF and sensor-only detection continues.
    _autoStartVoiceDetection();

    return gpsResult.success;
  }

  void stopProtection() {
    _isProtecting = false;
    _safetyStatus = 'STANDBY';

    _fusedSubscription?.cancel();
    _fusedSubscription = null;
    _gpsSubscription?.cancel();
    _gpsSubscription = null;

    _gpsTimeoutTimer?.cancel();
    _gpsTimeoutTimer = null;

    _sensorManager.stopAll();
    _fusion.reset();
    _contextEngine.resetImpact();
    _speedDropDetector.reset();
    _accidentDetector.reset();
    // resetForReuse() — NOT dispose(). The orchestrator and its voice alert
    // service must stay alive so protection can be stopped and restarted.
    // dispose() would permanently kill the countdown stream + voice alert.
    _orchestrator.resetForReuse();

    // Always stop voice detection when protection stops
    _voiceDetector.setEnabled(false);
    _voiceDetectionOn = false;
    _voiceMicStatus = 'INACTIVE';
    _voiceDetectionStatus = 'OFF';

    _nativeBridge.stopForegroundService();

    _emergencyScore = 0;
    _emergencyStatus = 'SAFE';
    _gpsStatus = 'INACTIVE';
    _currentSpeedKmh = 0;
    _rawSpeedKmh = 0;
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

  /// Automatically start voice emergency detection.
  /// Called from startProtection() — the user does NOT need to manually enable it.
  /// If microphone permission is denied, voice detection gracefully degrades
  /// to OFF while sensor-only detection continues normally.
  Future<void> _autoStartVoiceDetection() async {
    debugPrint('[SafetyMonitor] Auto-starting voice emergency detection...');
    try {
      await _voiceDetector.setEnabled(true);
      _voiceDetectionOn = _voiceDetector.isEnabled;
      if (_voiceDetectionOn) {
        debugPrint('[SafetyMonitor] ✅ Voice detection AUTO-STARTED — listening for emergency phrases');
      } else {
        debugPrint('[SafetyMonitor] ⚠️ Voice detection not started — microphone permission may be denied');
      }
    } catch (e) {
      debugPrint('[SafetyMonitor] ⚠️ Voice auto-start failed: $e — sensor detection continues');
      _voiceDetectionOn = false;
    }
    notifyListeners();
  }

  /// Restart voice detection after an emergency cycle completes.
  /// Called when the emergency is cancelled (I'M OK) or completed.
  Future<void> _restartVoiceAfterEmergency() async {
    if (!_isProtecting) return; // Don't restart if protection is off
    debugPrint('[SafetyMonitor] Restarting voice detection after emergency...');
    try {
      if (!_voiceDetector.isEnabled) {
        await _voiceDetector.setEnabled(true);
        _voiceDetectionOn = _voiceDetector.isEnabled;
      } else {
        // Detector is enabled but was paused during emergency — resume it
        _voiceDetector.cancelPendingEmergency();
      }
    } catch (e) {
      debugPrint('[SafetyMonitor] Voice restart after emergency failed: $e');
    }
    notifyListeners();
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

    // Allow accident detector to advance state machine via sensor inactivity
    // (critical for Path B: direct impact detection when GPS is unavailable)
    _accidentDetector.checkSensorInactivity();

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
      _gpsTimeoutTimer?.cancel();
      _gpsTimeoutTimer = null;
      debugPrint('[SafetyMonitor] ✅ GPS first valid fix received — now ACTIVE');
    }
    _currentSpeedKmh = gpsData.speedKmh;
    _rawSpeedKmh = gpsData.rawSpeedKmh;
    _currentLatitude = gpsData.latitude;
    _currentLongitude = gpsData.longitude;
    _detectionPhase = _speedDropDetector.phase.name.toUpperCase();
    _gpsAccuracy = gpsData.accuracy;
    _gpsIsStationary = gpsData.isStationary;

    debugPrint('[SafetyMonitor] GPS: speed=${gpsData.speedKmh.toStringAsFixed(1)} km/h, '
        'raw=${gpsData.rawSpeedKmh.toStringAsFixed(1)} km/h, '
        'acc=${gpsData.accuracy.toStringAsFixed(1)}m, '
        'stationary=${gpsData.isStationary}');

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
    _orchestrator.setCountdownTimeout(_demoMode ? 15 : EmergencySpeedThresholds.verificationTimeout);
    _orchestrator.onPossibleEmergency(event);
    notifyListeners();
  }

  void _onAccidentDetected(EmergencyEvent event) {
    _emergencyStatus = 'VERIFYING';
    _emergencyScore = event.emergencyScore;
    _orchestrator.setCountdownTimeout(_demoMode ? 15 : EmergencySpeedThresholds.verificationTimeout);
    _orchestrator.onPossibleEmergency(event);
    notifyListeners();
  }

  void _showEmergencyNotification() {
    // Launch the native Android emergency popup over the lock screen
    final eventId = _orchestrator.currentEvent?.id ?? 'emergency-${DateTime.now().millisecondsSinceEpoch}';
    debugPrint('[SafetyMonitorService] Launching native emergency popup — event: $eventId');

    _nativeBridge.launchEmergencyPopup(
      eventId: eventId,
      countdownSeconds: EmergencySpeedThresholds.verificationTimeout,
    );

    // Also show high-priority notification as fallback (for Android 14+ restrictions)
    _nativeBridge.showEmergencyNotification(
      title: '🚨 EMERGENCY DETECTED',
      body: 'Are you alright? Tap to respond.',
    );
  }

  void _onOrchestratorStateChanged(OrchestratorState state) {
    switch (state) {
      case OrchestratorState.voiceVerifying:
        _emergencyStatus = 'VOICE VERIFICATION';
      case OrchestratorState.userConfirmedOk:
        _emergencyStatus = 'SAFE';
        _safetyStatus = 'MONITORING';
        _nativeBridge.dismissEmergencyNotification();
      case OrchestratorState.emergencyConfirmed:
        _emergencyStatus = 'CONFIRMED';
        _lastIncident = _formatTime(DateTime.now());
        _nativeBridge.dismissEmergencyNotification();
      case OrchestratorState.smsSending:
        _emergencyStatus = 'SENDING SMS';
      case OrchestratorState.callingContact:
        _emergencyStatus = 'CALLING CONTACT';
      case OrchestratorState.complete:
        _emergencyStatus = 'CONFIRMED';
        // Restart voice monitoring after emergency cycle ends
        _restartVoiceAfterEmergency();
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
    _countdownSubscription?.cancel();
    _countdownSubscription = null;
    stopProtection();
    _voiceDetector.dispose();
    _orchestrator.dispose();
    super.dispose();
  }
}
