import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges Flutter to the Android native platform channel.
/// Handles: foreground service, TTS, speech recognition, SMS, phone calls, permissions.
class NativeServiceBridge {
  static const _channel = MethodChannel('com.example.resq_ai/native_service');

  // Callbacks for native events
  Function(String)? onSpeechResult;
  Function(String)? onSpeechPartialResult;
  Function(String)? onSpeechError;
  Function()? onListeningStarted;
  Function()? onServiceStarted;
  Function()? onServiceStopped;
  Function(Map<String, dynamic>)? onPermissionResult;

  // --- Permission result tracking ---
  // Maps permission name to a Completer that resolves when Android responds
  final Map<String, Completer<bool>> _pendingPermissions = {};

  static final NativeServiceBridge _instance = NativeServiceBridge._();
  factory NativeServiceBridge() => _instance;
  NativeServiceBridge._() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Handle method calls from native Android
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onSpeechResult':
        onSpeechResult?.call(call.arguments as String? ?? '');
        break;
      case 'onSpeechPartialResult':
        onSpeechPartialResult?.call(call.arguments as String? ?? '');
        break;
      case 'onSpeechError':
        onSpeechError?.call(call.arguments as String? ?? 'unknown');
        break;
      case 'onListeningStarted':
        onListeningStarted?.call();
        break;
      case 'onServiceStarted':
        onServiceStarted?.call();
        break;
      case 'onServiceStopped':
        onServiceStopped?.call();
        break;
      case 'onPermissionResult':
        final args = call.arguments as Map?;
        if (args != null) {
          final result = Map<String, dynamic>.from(args);
          onPermissionResult?.call(result);
          // Resolve any pending permission request
          final permission = result['permission'] as String?;
          final granted = result['granted'] as bool? ?? false;
          if (permission != null && _pendingPermissions.containsKey(permission)) {
            _pendingPermissions[permission]!.complete(granted);
            _pendingPermissions.remove(permission);
          }
        }
        break;
    }
  }

  // --- Emergency Notification ---

  Future<void> showEmergencyNotification({required String title, required String body}) async {
    try {
      await _channel.invokeMethod('showEmergencyNotification', {
        'title': title,
        'body': body,
      });
    } catch (e) {
      debugPrint('NativeServiceBridge: showEmergencyNotification error: $e');
    }
  }

  // --- Foreground Service ---

  Future<bool> startForegroundService() async {
    try {
      final result = await _channel.invokeMethod<bool>('startForegroundService');
      return result ?? false;
    } catch (e) {
      debugPrint('NativeServiceBridge: startForegroundService error: $e');
      return false;
    }
  }

  Future<bool> stopForegroundService() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopForegroundService');
      return result ?? false;
    } catch (e) {
      debugPrint('NativeServiceBridge: stopForegroundService error: $e');
      return false;
    }
  }

  Future<bool> isServiceRunning() async {
    try {
      final result = await _channel.invokeMethod<bool>('isServiceRunning');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  // --- Text-to-Speech ---

  Future<void> speak(String text) async {
    try {
      await _channel.invokeMethod('speak', {'text': text});
    } catch (e) {
      debugPrint('NativeServiceBridge: speak error: $e');
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _channel.invokeMethod('stopSpeaking');
    } catch (e) {
      debugPrint('NativeServiceBridge: stopSpeaking error: $e');
    }
  }

  // --- Speech Recognition ---

  /// Start one-shot speech recognition (for voice verification during emergency).
  Future<void> startListening() async {
    try {
      await _channel.invokeMethod('startListening');
    } catch (e) {
      debugPrint('NativeServiceBridge: startListening error: $e');
    }
  }

  /// Stop speech recognition.
  Future<void> stopListening() async {
    try {
      await _channel.invokeMethod('stopListening');
    } catch (e) {
      debugPrint('NativeServiceBridge: stopListening error: $e');
    }
  }

  /// Check if currently listening.
  Future<bool> isListening() async {
    try {
      final result = await _channel.invokeMethod<bool>('isListening');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Start CONTINUOUS speech recognition for voice emergency trigger.
  /// After each recognition cycle ends, Android automatically restarts.
  Future<void> startContinuousListening() async {
    try {
      await _channel.invokeMethod('startContinuousListening');
    } catch (e) {
      debugPrint('NativeServiceBridge: startContinuousListening error: $e');
    }
  }

  /// Stop continuous speech recognition.
  Future<void> stopContinuousListening() async {
    try {
      await _channel.invokeMethod('stopContinuousListening');
    } catch (e) {
      debugPrint('NativeServiceBridge: stopContinuousListening error: $e');
    }
  }

  // --- SMS ---

  /// Send SMS and return result with success/error
  Future<Map<String, dynamic>> sendSms(String phone, String message) async {
    try {
      final result = await _channel.invokeMethod<Map>('sendSms', {
        'phone': phone,
        'message': message,
      });
      return Map<String, dynamic>.from(result ?? {'success': false, 'error': 'no result'});
    } catch (e) {
      debugPrint('NativeServiceBridge: sendSms error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // --- Phone Call ---

  Future<Map<String, dynamic>> makeCall(String phone) async {
    try {
      final result = await _channel.invokeMethod<Map>('makeCall', {
        'phone': phone,
      });
      return Map<String, dynamic>.from(result ?? {'success': false, 'error': 'no result'});
    } catch (e) {
      debugPrint('NativeServiceBridge: makeCall error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // --- Permissions ---

  Future<void> requestSmsPermission() async {
    try {
      await _channel.invokeMethod('requestSmsPermission');
    } catch (e) {
      debugPrint('NativeServiceBridge: requestSmsPermission error: $e');
    }
  }

  Future<void> requestCallPermission() async {
    try {
      await _channel.invokeMethod('requestCallPermission');
    } catch (e) {
      debugPrint('NativeServiceBridge: requestCallPermission error: $e');
    }
  }

  Future<void> requestLocationPermission() async {
    try {
      await _channel.invokeMethod('requestLocationPermission');
    } catch (e) {
      debugPrint('NativeServiceBridge: requestLocationPermission error: $e');
    }
  }

  Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (e) {
      debugPrint('NativeServiceBridge: requestNotificationPermission error: $e');
    }
  }

  /// Request RECORD_AUDIO permission for voice detection.
  Future<void> requestAudioPermission() async {
    try {
      await _channel.invokeMethod('requestAudioPermission');
    } catch (e) {
      debugPrint('NativeServiceBridge: requestAudioPermission error: $e');
    }
  }

  /// Request RECORD_AUDIO permission and WAIT for the user's response.
  /// Returns true if granted, false if denied.
  /// Times out after [timeoutSeconds] if the user doesn't respond.
  Future<bool> requestAudioPermissionAndWait({int timeoutSeconds = 30}) async {
    // First check if already granted
    if (await checkPermission('audio')) {
      return true;
    }

    // Create a completer that will be resolved by _handleMethodCall
    final completer = Completer<bool>();
    _pendingPermissions['audio'] = completer;

    // Request the permission (shows Android system dialog)
    await requestAudioPermission();

    // Wait for result with timeout
    try {
      final result = await completer.future.timeout(
        Duration(seconds: timeoutSeconds),
        onTimeout: () {
          _pendingPermissions.remove('audio');
          return false;
        },
      );
      return result;
    } catch (e) {
      _pendingPermissions.remove('audio');
      return false;
    }
  }

  /// Open the app's Android settings page (for when permission is permanently denied).
  Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod('openAppSettings');
    } catch (e) {
      debugPrint('NativeServiceBridge: openAppSettings error: $e');
    }
  }

  Future<bool> checkPermission(String permission) async {
    try {
      final result = await _channel.invokeMethod<bool>('checkPermission', {
        'permission': permission,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
