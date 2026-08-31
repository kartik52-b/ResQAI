import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/emergency_event.dart';

/// Service for communicating with the ResQ AI backend.
class ApiService {
  // Change this to your backend URL
  static const String baseUrl = 'http://10.0.2.2:8000';

  /// Report an emergency to the backend
  Future<Map<String, dynamic>?> reportEmergency({
    required double latitude,
    required double longitude,
    required double speedKmh,
    required double impactMagnitude,
    required int emergencyScore,
    required String severity,
    required List<ReplayEvent> timeline,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/emergency'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'location': {
            'latitude': latitude,
            'longitude': longitude,
          },
          'speed_kmh': speedKmh,
          'impact_magnitude': impactMagnitude,
          'emergency_score': emergencyScore,
          'severity': severity,
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

  /// Create an incident record
  Future<Map<String, dynamic>?> createIncident(Incident incident) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/incident'),
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
      final response = await http.get(
        Uri.parse('$baseUrl/incident/$incidentId'),
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
      final response = await http.get(
        Uri.parse('$baseUrl/incidents'),
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
      final response = await http.post(
        Uri.parse('$baseUrl/location'),
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
