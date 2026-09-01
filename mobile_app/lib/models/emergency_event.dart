/// Activity classification
enum ActivityType {
  normal,
  walking,
  running,
  cycling,
  driving,
  phoneDrop,
  suspicious,
  emergency,
}

/// Status of the emergency verification
enum EmergencyStatus {
  safe,
  possibleEmergency,
  verifying,
  confirmed,
  cancelled,
  falseAlarm,
}

/// Severity levels for incidents
enum Severity {
  low,
  medium,
  high,
  critical,
}

/// An emergency event detected by the system
class EmergencyEvent {
  final String id;
  final DateTime timestamp;
  final int emergencyScore;
  final ActivityType activityType;
  final EmergencyStatus status;
  final double? impactMagnitude;
  final double? speedKmh;
  final double? rotationSpeed;
  final Map<String, dynamic>? location;

  EmergencyEvent({
    required this.id,
    required this.timestamp,
    required this.emergencyScore,
    required this.activityType,
    required this.status,
    this.impactMagnitude,
    this.speedKmh,
    this.rotationSpeed,
    this.location,
  });

  EmergencyEvent copyWith({
    EmergencyStatus? status,
    int? emergencyScore,
    ActivityType? activityType,
  }) {
    return EmergencyEvent(
      id: id,
      timestamp: timestamp,
      emergencyScore: emergencyScore ?? this.emergencyScore,
      activityType: activityType ?? this.activityType,
      status: status ?? this.status,
      impactMagnitude: impactMagnitude,
      speedKmh: speedKmh,
      rotationSpeed: rotationSpeed,
      location: location,
    );
  }

  Severity get severity {
    if (emergencyScore >= 85) return Severity.critical;
    if (emergencyScore >= 70) return Severity.high;
    if (emergencyScore >= 50) return Severity.medium;
    return Severity.low;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'emergency_score': emergencyScore,
        'activity_type': activityType.name,
        'status': status.name,
        'severity': severity.name,
        'impact_magnitude': impactMagnitude,
        'speed_kmh': speedKmh,
        'rotation_speed': rotationSpeed,
        'location': location,
      };
}

/// A Life Replay event entry
class ReplayEvent {
  final DateTime timestamp;
  final String description;
  final ActivityType activityType;
  final int score;

  ReplayEvent({
    required this.timestamp,
    required this.description,
    required this.activityType,
    required this.score,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'description': description,
        'activity_type': activityType.name,
        'score': score,
      };
}

/// Complete incident record
class Incident {
  final String id;
  final String incidentId;
  final DateTime time;
  final double? latitude;
  final double? longitude;
  final double speedKmh;
  final double impactMagnitude;
  final int emergencyScore;
  final Severity severity;
  final String status;
  final List<ReplayEvent> timeline;

  Incident({
    required this.id,
    required this.incidentId,
    required this.time,
    this.latitude,
    this.longitude,
    required this.speedKmh,
    required this.impactMagnitude,
    required this.emergencyScore,
    required this.severity,
    required this.status,
    required this.timeline,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'incident_id': incidentId,
        'time': time.toIso8601String(),
        'location': {
          'latitude': latitude,
          'longitude': longitude,
        },
        'speed_kmh': speedKmh,
        'impact_magnitude': impactMagnitude,
        'emergency_score': emergencyScore,
        'severity': severity.name,
        'status': status,
        'timeline': timeline.map((e) => e.toJson()).toList(),
      };
}
