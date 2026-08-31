import 'dart:async';
import 'package:flutter/foundation.dart';
import 'native_service_bridge.dart';

/// Simplified voice alert for emergency verification.
/// Does a single speak + listen cycle.
/// Orchestrator manages retries and overall timeout.
class VoiceAlertService {
  final NativeServiceBridge _bridge;

  Function()? onUserSaidOk;
  Function()? onUserSaidHelp;
  Function()? onNoResponseDetected;
  Function(String)? onPartialTranscript;

  Timer? _listeningTimer;
  static const int listenTimeoutSeconds = 15;

  bool _isActive = false;

  VoiceAlertService(this._bridge);

  bool get isActive => _isActive;

  /// Speak "Are you alright?" and listen once for a response.
  /// Callbacks fire based on what the user says.
  void startAlert() {
    debugPrint('VoiceAlertService: Starting single speak+listen cycle');
    _isActive = true;
    _setupCallbacks();
    _speakAndListen();
  }

  /// Stop all voice activity.
  void stop() {
    debugPrint('VoiceAlertService: Stopping');
    _isActive = false;
    _listeningTimer?.cancel();
    _bridge.stopSpeaking();
    _bridge.stopListening();
  }

  void _setupCallbacks() {
    _bridge.onSpeechResult = (text) {
      if (!_isActive) return;
      debugPrint('VoiceAlertService: Final result: "$text"');
      _listeningTimer?.cancel();

      if (_isOkResponse(text)) {
        _bridge.stopListening();
        _bridge.speak("Emergency cancelled. You are safe.");
        onUserSaidOk?.call();
      } else if (_isHelpResponse(text)) {
        _bridge.stopListening();
        onUserSaidHelp?.call();
      } else {
        _bridge.stopListening();
        onNoResponseDetected?.call();
      }
    };

    _bridge.onSpeechPartialResult = (text) {
      if (!_isActive) return;
      onPartialTranscript?.call(text);
      // Fast-path: check partial results for OK response
      if (_isOkResponse(text)) {
        _listeningTimer?.cancel();
        _bridge.stopListening();
        _bridge.speak("Emergency cancelled. You are safe.");
        onUserSaidOk?.call();
      }
    };

    _bridge.onSpeechError = (error) {
      debugPrint('VoiceAlertService: Speech error: $error');
      if (error == 'no_match' || error == 'timeout') {
        _listeningTimer?.cancel();
        _bridge.stopListening();
        onNoResponseDetected?.call();
      }
    };
  }

  void _speakAndListen() {
    _bridge.speak("Are you alright? Please respond with I'm okay or I need help.");

    // Wait for TTS to finish, then start listening
    Future.delayed(const Duration(seconds: 3), () {
      if (!_isActive) return;
      _startListening();
    });
  }

  void _startListening() {
    _bridge.startListening();

    _listeningTimer?.cancel();
    _listeningTimer = Timer(
      const Duration(seconds: listenTimeoutSeconds),
      () {
        if (_isActive) {
          _bridge.stopListening();
          onNoResponseDetected?.call();
        }
      },
    );
  }

  bool _isOkResponse(String text) {
    final lower = text.toLowerCase().trim();
    const okPhrases = [
      "i'm okay", "i am okay", "okay", "ok", "i'm ok", "i am ok",
      "i'm alright", "i am alright", "alright", "all right",
      "i'm fine", "i am fine", "fine", "i am safe", "i'm safe",
    ];
    return okPhrases.any((p) => lower.contains(p));
  }

  bool _isHelpResponse(String text) {
    final lower = text.toLowerCase().trim();
    return lower.contains("need help") || lower.contains("help") ||
        lower.contains("emergency") || lower.contains("bachao") ||
        lower.contains("madad");
  }

  void dispose() {
    stop();
  }
}
