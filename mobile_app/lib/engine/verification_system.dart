import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/thresholds.dart';
import '../models/emergency_event.dart';

/// Callback type for verification state changes
typedef VerificationCallback = void Function(EmergencyStatus status);

/// Manages the emergency verification flow:
/// - Shows countdown timer
/// - Handles user response (OK / Send Alert)
/// - Auto-confirms on timeout
class VerificationSystem extends ChangeNotifier {
  Timer? _timer;
  int _remainingSeconds = EmergencySpeedThresholds.verificationTimeout;
  EmergencyStatus _status = EmergencyStatus.safe;
  EmergencyEvent? _currentEvent;
  VerificationCallback? _onStatusChange;

  int get remainingSeconds => _remainingSeconds;
  EmergencyStatus get status => _status;
  EmergencyEvent? get currentEvent => _currentEvent;
  bool get isVerifying => _status == EmergencyStatus.verifying;

  /// Set callback for status changes
  void setStatusCallback(VerificationCallback callback) {
    _onStatusChange = callback;
  }

  /// Start verification flow for a possible emergency
  void startVerification(EmergencyEvent event) {
    _currentEvent = event;
    _remainingSeconds = EmergencySpeedThresholds.verificationTimeout;
    _status = EmergencyStatus.verifying;
    notifyListeners();
    _onStatusChange?.call(_status);

    // Start countdown
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _remainingSeconds--;
      notifyListeners();

      if (_remainingSeconds <= 0) {
        _confirmEmergency();
      }
    });
  }

  /// User confirms they are OK — cancel emergency
  void userOk() {
    _timer?.cancel();
    _status = EmergencyStatus.cancelled;
    _currentEvent = _currentEvent?.copyWith(status: EmergencyStatus.cancelled);
    notifyListeners();
    _onStatusChange?.call(_status);
    _reset();
  }

  /// User manually sends alert — confirm emergency
  void sendAlert() {
    _timer?.cancel();
    _confirmEmergency();
  }

  /// Internal: confirm the emergency
  void _confirmEmergency() {
    _timer?.cancel();
    _status = EmergencyStatus.confirmed;
    _currentEvent = _currentEvent?.copyWith(status: EmergencyStatus.confirmed);
    notifyListeners();
    _onStatusChange?.call(_status);
  }

  /// Reset to safe state
  void _reset() {
    _timer?.cancel();
    _currentEvent = null;
    _remainingSeconds = EmergencySpeedThresholds.verificationTimeout;
    Future.delayed(const Duration(seconds: 2), () {
      _status = EmergencyStatus.safe;
      notifyListeners();
      _onStatusChange?.call(_status);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
