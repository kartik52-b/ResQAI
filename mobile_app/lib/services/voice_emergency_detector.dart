import 'dart:async';
import 'package:flutter/foundation.dart';
import 'native_service_bridge.dart';

/// States for the voice emergency detection system.
enum VoiceDetectionState {
  off,
  initializing,
  listening,
  phraseDetected,
  confirming,
  cancelled,
  triggered,
  error,
}

/// Configurable emergency voice phrases.
/// These are the trigger words the system listens for.
/// Matching uses whole-word boundary checks to avoid false positives
/// (e.g., "help" should not trigger on "helpful").
const List<String> _emergencyPhrases = [
  'help',
  'help me',
  'bachao',
  'bachaao',
  'madad',
  'madad karo',
  'save me',
  'emergency',
  'rescue',
];

/// Phrases that CANCEL an emergency if detected during confirmation.
const List<String> _cancelPhrases = [
  'cancel',
  'i am fine',
  "i'm fine",
  'i am ok',
  "i'm ok",
  'i am okay',
  "i'm okay",
  'okay',
  'ok',
  'alright',
  'all right',
  'safe',
  'no emergency',
  'no problem',
];

/// Detects emergency voice phrases in real-time using Android SpeechRecognizer.
///
/// When Protection is ON and voice detection is enabled:
/// 1. Continuously listens via Android's SpeechRecognizer
/// 2. Matches recognized text against emergency phrases
/// 3. When a phrase is detected, enters PENDING state
/// 4. Gives user a configurable cancellation window (default 5 seconds)
/// 5. If not cancelled, triggers the EmergencyOrchestrator
///
/// Android background limitation:
/// SpeechRecognizer only works while the Activity is in the foreground.
/// When the screen is locked or app is backgrounded, speech recognition
/// will stop. The foreground service notification will reflect this.
class VoiceEmergencyDetector extends ChangeNotifier {
  final NativeServiceBridge _bridge;

  VoiceDetectionState _state = VoiceDetectionState.off;
  Timer? _cancelWindowTimer;
  int _triggerCount = 0; // Prevents duplicate triggers

  // Configuration
  bool _enabled = false;
  bool _audioPermissionGranted = false;
  int _cancelWindowSeconds = 5;

  // Callbacks
  Function()? onEmergencyTriggered;
  Function(String phrase)? onPhraseDetected;
  Function(String)? onPartialTranscript;
  Function(String)? onError;
  Function(VoiceDetectionState)? onStateChanged;

  VoiceDetectionState get state => _state;
  bool get isEnabled => _enabled;
  bool get isListening => _state == VoiceDetectionState.listening;
  bool get isPending => _state == VoiceDetectionState.phraseDetected;
  int get triggerCount => _triggerCount;
  int get cancelWindowSeconds => _cancelWindowSeconds;

  static const List<String> emergencyPhrases = _emergencyPhrases;
  static const List<String> cancelPhrases = _cancelPhrases;

  VoiceEmergencyDetector(this._bridge);

  /// Enable or disable voice emergency detection.
  Future<void> setEnabled(bool enabled) async {
    if (enabled == _enabled) return;

    if (enabled) {
      // Step 1: Check if permission is already granted
      _audioPermissionGranted = await _bridge.checkPermission('audio');

      if (!_audioPermissionGranted) {
        // Step 2: Request permission and WAIT for the user's response
        debugPrint('VoiceEmergencyDetector: Requesting audio permission...');
        _setState(VoiceDetectionState.initializing);
        notifyListeners();

        _audioPermissionGranted = await _bridge.requestAudioPermissionAndWait(
          timeoutSeconds: 60, // Give user time to respond to dialog
        );
      }

      if (!_audioPermissionGranted) {
        // Step 3: Permission denied — check if permanently denied
        _setState(VoiceDetectionState.error);
        onError?.call(
          'Microphone permission denied. '
          'Please enable it in Android Settings > Apps > ResQ AI > Permissions.',
        );
        debugPrint('VoiceEmergencyDetector: Audio permission denied by user');
        _enabled = false;
        notifyListeners();
        return;
      }

      // Step 4: Permission granted — start listening
      debugPrint('VoiceEmergencyDetector: Audio permission GRANTED');
      _setState(VoiceDetectionState.initializing);
      _enabled = true;
      _setupCallbacks();
      _startListening();
    } else {
      _enabled = false;
      _cancelWindowTimer?.cancel();
      _bridge.stopContinuousListening();
      _setState(VoiceDetectionState.off);
    }

    notifyListeners();
  }

  /// Open Android app settings so the user can manually grant microphone permission.
  Future<void> openSettings() async {
    await _bridge.openAppSettings();
  }

  /// Configure the cancellation window duration (seconds).
  void setCancelWindow(int seconds) {
    _cancelWindowSeconds = seconds.clamp(3, 30);
  }

  /// Cancel a pending emergency (user said "I'm OK" during confirmation window).
  void cancelPendingEmergency() {
    debugPrint('VoiceEmergencyDetector: Emergency cancelled by user');
    _cancelWindowTimer?.cancel();
    _setState(VoiceDetectionState.cancelled);
    _triggerCount = 0;

    // Resume listening after a brief pause
    Future.delayed(const Duration(seconds: 2), () {
      if (_enabled && _state == VoiceDetectionState.cancelled) {
        _startListening();
      }
    });
  }

  void _setupCallbacks() {
    // Handle continuous speech recognition results
    _bridge.onSpeechResult = (text) {
      _handleRecognizedText(text, isFinal: true);
    };

    _bridge.onSpeechPartialResult = (text) {
      onPartialTranscript?.call(text);
      _handleRecognizedText(text, isFinal: false);
    };

    _bridge.onSpeechError = (error) {
      debugPrint('VoiceEmergencyDetector: Speech error: $error');
      if (error == 'not_available') {
        _setState(VoiceDetectionState.error);
        onError?.call('Speech recognition not available on this device');
      } else if (error == 'permission_denied') {
        _setState(VoiceDetectionState.error);
        onError?.call('Microphone permission denied');
      }
      // For transient errors (timeout, no_match, network), the Android side
      // will automatically restart continuous listening
    };

    _bridge.onListeningStarted = () {
      if (_enabled && _state == VoiceDetectionState.initializing) {
        _setState(VoiceDetectionState.listening);
      }
    };
  }

  void _startListening() {
    if (!_enabled) return;
    _setState(VoiceDetectionState.initializing);
    _bridge.startContinuousListening();
  }

  void _handleRecognizedText(String text, {required bool isFinal}) {
    if (!_enabled) return;
    if (text.isEmpty) return;

    final lower = text.toLowerCase().trim();

    // If we're in the cancel window, check for cancellation phrases
    if (_state == VoiceDetectionState.phraseDetected ||
        _state == VoiceDetectionState.confirming) {
      if (_isCancelPhrase(lower)) {
        cancelPendingEmergency();
        return;
      }
      // If not cancel phrase, keep waiting (don't check emergency phrases again)
      return;
    }

    // Only check for emergency phrases when listening
    if (_state != VoiceDetectionState.listening) return;

    // Check if the recognized text contains an emergency phrase
    final detectedPhrase = _findEmergencyPhrase(lower);
    if (detectedPhrase != null) {
      debugPrint('VoiceEmergencyDetector: EMERGENCY PHRASE DETECTED: "$detectedPhrase"');
      onPhraseDetected?.call(detectedPhrase);
      _enterConfirmationWindow(detectedPhrase);
    }
  }

  void _enterConfirmationWindow(String phrase) {
    _setState(VoiceDetectionState.phraseDetected);
    _triggerCount++;

    debugPrint('VoiceEmergencyDetector: Starting $_cancelWindowSeconds second cancel window');

    // Pause continuous listening during cancel window to avoid self-triggering
    // The TTS "Are you alright?" will play, and the user can respond
    _bridge.stopContinuousListening();

    _cancelWindowTimer?.cancel();
    _cancelWindowTimer = Timer(
      Duration(seconds: _cancelWindowSeconds),
      () {
        if (_state == VoiceDetectionState.phraseDetected) {
          // Cancel window expired — trigger emergency
          _triggerEmergency(phrase);
        }
      },
    );

    notifyListeners();
  }

  void _triggerEmergency(String phrase) {
    debugPrint('VoiceEmergencyDetector: TRIGGERING EMERGENCY for phrase "$phrase"');
    _cancelWindowTimer?.cancel();
    _setState(VoiceDetectionState.triggered);

    onEmergencyTriggered?.call();
  }

  bool _isCancelPhrase(String text) {
    return _cancelPhrases.any((phrase) => text.contains(phrase));
  }

  /// Match emergency phrases using word-boundary-aware matching.
  /// Prevents false positives like "helpful" triggering "help".
  /// For single-word phrases, requires word boundaries.
  /// For multi-word phrases, requires the full phrase to be present.
  String? _findEmergencyPhrase(String text) {
    for (final phrase in _emergencyPhrases) {
      if (_matchesPhrase(text, phrase)) {
        return phrase;
      }
    }
    return null;
  }

  /// Check if [text] contains [phrase] as a whole phrase (not substring of another word).
  /// Single-word phrases require word boundaries on both sides.
  /// Multi-word phrases require the exact phrase to appear.
  bool _matchesPhrase(String text, String phrase) {
    if (!text.contains(phrase)) return false;

    // For single-word phrases, check word boundaries
    if (!phrase.contains(' ')) {
      // Check character before match
      final idx = text.indexOf(phrase);
      if (idx > 0) {
        final before = text[idx - 1];
        if (RegExp(r'\w').hasMatch(before)) return false; // stuck to another word
      }
      // Check character after match
      final endIdx = idx + phrase.length;
      if (endIdx < text.length) {
        final after = text[endIdx];
        if (RegExp(r'\w').hasMatch(after)) return false; // stuck to another word
      }
    }
    return true;
  }

  void _setState(VoiceDetectionState newState) {
    if (_state == newState) return;
    _state = newState;
    onStateChanged?.call(newState);
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelWindowTimer?.cancel();
    _bridge.stopContinuousListening();
    super.dispose();
  }
}
