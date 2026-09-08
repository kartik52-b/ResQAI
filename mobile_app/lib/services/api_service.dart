import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/emergency_event.dart';

/// Service for communicating with the ResQ AI backend.
class ApiService {
  // Configurable backend URL.
  // Android emulator: 10.0.2.2:8000
  // Physical device: use your PC's local IP (e.g. 192.168.1.x:8000)
  // To change: edit this value before building.
  static const String baseUrl = 'http://10.0.2.2:8000';

  /// HTTP client — injectable for tests (MockClient).
  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Update this at runtime to point to your actual backend.
  static String _runtimeUrl = baseUrl;
  static String get effectiveBaseUrl => _runtimeUrl;

  /// Set the backend URL dynamically (e.g. from settings).
  static void setBaseUrl(String url) {
    _runtimeUrl = url;
  }

  /// Report an emergency to the backend.
  /// Returns { incident_id, access_token, severity, ... } on success.
  Future<Map<String, dynamic>?> reportEmergency({
    required double latitude,
    required double longitude,
    double? accuracy,
    required double speedKmh,
    required double impactMagnitude,
    required int emergencyScore,
    required String severity,
    required String emergencyType,
    required List<ReplayEvent> timeline,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$effectiveBaseUrl/emergency'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'location': {
            'latitude': latitude,
            'longitude': longitude,
            if (accuracy != null) 'accuracy': accuracy,
          },
          'speed_kmh': speedKmh,
          'impact_magnitude': impactMagnitude,
          'emergency_score': emergencyScore,
          'severity': severity,
          'emergency_type': emergencyType,
          'timeline': timeline.map((e) => e.toJson()).toList(),
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Update live location for an active emergency incident.
  /// Called periodically by the phone while the emergency is active.
  Future<bool> updateIncidentLocation({
    required String incidentId,
    required double latitude,
    required double longitude,
    double? accuracy,
    double? speedKmh,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$effectiveBaseUrl/incident/$incidentId/location'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          if (accuracy != null) 'accuracy': accuracy,
          if (speedKmh != null) 'speed_kmh': speedKmh,
        }),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Mark an incident as resolved (emergency cancelled).
  Future<bool> resolveIncident(String incidentId) async {
    try {
      final response = await _client.post(
        Uri.parse('$effectiveBaseUrl/incident/$incidentId/resolve'),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Build the family emergency page URL from an access token.
  /// Example: http://192.168.1.5:8000/emergency/abc123def456
  String getEmergencyPageUrl(String accessToken) {
    return '$effectiveBaseUrl/emergency/$accessToken';
  }

  /// Create an incident record
  Future<Map<String, dynamic>?> createIncident(Incident incident) async {
    try {
      final response = await _client.post(
        Uri.parse('$effectiveBaseUrl/incident'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(incident.toJson()),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get incident by ID
  Future<Map<String, dynamic>?> getIncident(String incidentId) async {
    try {
      final response = await _client.get(
        Uri.parse('$effectiveBaseUrl/incident/$incidentId'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get all incidents
  Future<List<Map<String, dynamic>>?> getIncidents() async {
    try {
      final response = await _client.get(
        Uri.parse('$effectiveBaseUrl/incidents'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['incidents'] ?? []);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Update location
  Future<bool> updateLocation({
    required double latitude,
    required double longitude,
    required double speed,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$effectiveBaseUrl/location'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          'speed': speed,
        }),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
