/// Raw accelerometer data point
class AccelerometerData {
  final double x;
  final double y;
  final double z;
  final DateTime timestamp;

  AccelerometerData({
    required this.x,
    required this.y,
    required this.z,
    required this.timestamp,
  });

  /// Net acceleration magnitude (excluding gravity)
  double get magnitude => _sqrt(x * x + y * y + z * z);

  /// Net acceleration with gravity removed
  double get netMagnitude {
    final raw = magnitude;
    const gravity = 9.81;
    return (raw - gravity).abs();
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'z': z,
        'magnitude': magnitude,
        'net_magnitude': netMagnitude,
        'timestamp': timestamp.toIso8601String(),
      };

  static double _sqrt(double value) {
    if (value <= 0) return 0;
    double guess = value / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + value / guess) / 2;
    }
    return guess;
  }
}

/// Raw gyroscope data point
class GyroscopeData {
  final double x;
  final double y;
  final double z;
  final DateTime timestamp;

  GyroscopeData({
    required this.x,
    required this.y,
    required this.z,
    required this.timestamp,
  });

  /// Angular velocity magnitude in degrees/s
  double get magnitude => _sqrt(x * x + y * y + z * z);

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'z': z,
        'magnitude': magnitude,
        'timestamp': timestamp.toIso8601String(),
      };

  static double _sqrt(double value) {
    if (value <= 0) return 0;
    double guess = value / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + value / guess) / 2;
    }
    return guess;
  }
}

/// GPS location data point
class GpsData {
  final double latitude;
  final double longitude;
  final double speed; // m/s — filtered/robust speed
  final DateTime timestamp;
  final double accuracy; // meters — GPS accuracy
  final double rawSpeedKmh; // km/h — Android-reported speed
  final double groundSpeedKmh; // km/h — calculated from consecutive positions
  final bool isStationary; // true if position history shows no movement

  GpsData({
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.timestamp,
    this.accuracy = 0,
    this.rawSpeedKmh = 0,
    this.groundSpeedKmh = 0,
    this.isStationary = false,
  });

  /// Filtered speed in km/h
  double get speedKmh => speed * 3.6;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'speed': speed,
        'speed_kmh': speedKmh,
        'raw_speed_kmh': rawSpeedKmh,
        'ground_speed_kmh': groundSpeedKmh,
        'accuracy': accuracy,
        'is_stationary': isStationary,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Fused sensor state combining all sensor readings
class FusedSensorState {
  final AccelerometerData? accelerometer;
  final GyroscopeData? gyroscope;
  final GpsData? gps;
  final DateTime timestamp;

  FusedSensorState({
    this.accelerometer,
    this.gyroscope,
    this.gps,
    required this.timestamp,
  });

  bool get hasAllSensors =>
      accelerometer != null && gyroscope != null && gps != null;

  Map<String, dynamic> toJson() => {
        'accelerometer': accelerometer?.toJson(),
        'gyroscope': gyroscope?.toJson(),
        'gps': gps?.toJson(),
        'timestamp': timestamp.toIso8601String(),
      };
}
