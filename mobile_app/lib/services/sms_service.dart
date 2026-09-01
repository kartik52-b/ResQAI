import 'package:flutter/foundation.dart';
import '../models/trusted_contact.dart';
import 'native_service_bridge.dart';

/// Result of sending an SMS
class SmsSendResult {
  final String contactName;
  final String phoneNumber;
  final bool success;
  final String? error;

  SmsSendResult({
    required this.contactName,
    required this.phoneNumber,
    required this.success,
    this.error,
  });
}

/// Sends real emergency SMS to trusted contacts via Android SmsManager.
class SmsService {
  final NativeServiceBridge _bridge;

  SmsService(this._bridge);

  /// Build the emergency SMS message with real GPS data.
  ///
  /// The message contains:
  /// 1. A live emergency tracking page link (Leaflet + OpenStreetMap)
  /// 2. A direct Google Maps fallback link
  /// 3. Real coordinates and timestamp
  String buildEmergencyMessage({
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    double? speedKmh,
    int? emergencyScore,
    String? emergencyPageUrl,
  }) {
    final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
    final dateStr = '${timestamp.day}/${timestamp.month}/${timestamp.year}';

    // Google Maps fallback link
    final mapsLink = 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';

    final buffer = StringBuffer();
    buffer.writeln('RESQ AI EMERGENCY ALERT');
    buffer.writeln('I may need help.');
    buffer.writeln('');

    // Live emergency tracking link (Leaflet + OpenStreetMap)
    if (emergencyPageUrl != null && emergencyPageUrl.isNotEmpty) {
      buffer.writeln('Live Location:');
      buffer.writeln(emergencyPageUrl);
      buffer.writeln('');
    }

    buffer.writeln('Last known coordinates:');
    buffer.writeln('Latitude: ${latitude.toStringAsFixed(6)}');
    buffer.writeln('Longitude: ${longitude.toStringAsFixed(6)}');
    buffer.writeln('');

    // Google Maps fallback
    buffer.writeln('Map: $mapsLink');
    buffer.writeln('');
    buffer.writeln('Time: $dateStr at $timeStr');
    buffer.writeln('Please check my live location and contact me immediately.');

    if (speedKmh != null && speedKmh > 0) {
      buffer.writeln('Speed at incident: ${speedKmh.toStringAsFixed(1)} km/h');
    }
    if (emergencyScore != null) {
      buffer.writeln('Emergency score: $emergencyScore/100');
    }

    return buffer.toString();
  }

  /// Send emergency SMS to ALL non-test trusted contacts.
  /// Returns results for each contact.
  Future<List<SmsSendResult>> sendEmergencyToAll({
    required List<TrustedContact> contacts,
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    double? speedKmh,
    int? emergencyScore,
    String? emergencyPageUrl,
  }) async {
    if (contacts.isEmpty) {
      debugPrint('SmsService: No contacts to notify');
      return [];
    }

    final message = buildEmergencyMessage(
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp,
      speedKmh: speedKmh,
      emergencyScore: emergencyScore,
      emergencyPageUrl: emergencyPageUrl,
    );

    debugPrint('SmsService: Sending emergency SMS to ${contacts.length} contacts');

    final results = <SmsSendResult>[];

    for (final contact in contacts) {
      // Skip test contacts in production SMS flow
      if (contact.isTestContact) {
        debugPrint('SmsService: Skipping test contact ${contact.name}');
        results.add(SmsSendResult(
          contactName: contact.name,
          phoneNumber: contact.phoneNumber,
          success: true,
          error: 'Test contact - SMS skipped',
        ));
        continue;
      }

      try {
        final smsResult = await _bridge.sendSms(contact.phoneNumber, message);
        final success = smsResult['success'] == true;
        final error = smsResult['error'] as String?;

        debugPrint('SmsService: ${contact.name} (${contact.phoneNumber}): '
            '${success ? "SUCCESS" : "FAILED"} ${error != null ? "- $error" : ""}');

        results.add(SmsSendResult(
          contactName: contact.name,
          phoneNumber: contact.phoneNumber,
          success: success,
          error: error,
        ));
      } catch (e) {
        debugPrint('SmsService: Exception sending to ${contact.name}: $e');
        results.add(SmsSendResult(
          contactName: contact.name,
          phoneNumber: contact.phoneNumber,
          success: false,
          error: e.toString(),
        ));
      }
    }

    return results;
  }
}
