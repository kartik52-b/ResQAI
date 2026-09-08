import '../models/sensor_data.dart';

/// Movement state determined by multi-sensor fusion.
enum MovementState {
  stationary,
  walking,
  running,
  cycling,
  driving,
}

/// Diagnostic info for debugging movement classification.
class MovementDiagnostics {
  final double rawGpsSpeedKmh;
  final double filteredGpsSpeedKmh;
  final double accelMagnitude;
  final double accelNetMagnitude;
  final double gyroMagnitude;
  final MovementState state;
  final String reason;

  const MovementDiagnostics({
    required this.rawGpsSpeedKmh,
    required this.filteredGpsSpeedKmh,
    required this.accelMagnitude,
    required this.accelNetMagnitude,
    required this.gyroMagnitude,
    required this.state,
    required this.reason,
  });

  @override
  String toString() =>
      'GPS:${rawGpsSpeedKmh.toStringAsFixed(1)}→${filteredGpsSpeedKmh.toStringAsFixed(1)} '
      'A:${accelNetMagnitude.toStringAsFixed(1)} '
      'G:${gyroMagnitude.toStringAsFixed(1)} '
      '${state.name.toUpperCase()} [$reason]';
}

/// Multi-sensor movement classifier with noise filtering.
///
/// Uses:
/// - GPS speed (EMA smoothed, dead-zone filtered)
/// - Accelerometer (net acceleration after gravity removal)
/// - Gyroscope (angular velocity magnitude)
///
/// State transitions require sustained readings (hysteresis).
class MovementClassifier {
  // --- GPS speed smoothing ---
  // Exponential moving average over the last N readings
  static const int _speedBufferSize = 5;
  final List<double> _speedBuffer = [];
  double _filteredSpeed = 0;
  bool _hasFirstReading = false;

  // --- State machine with hysteresis ---
  MovementState _currentState = MovementState.stationary;
  MovementState _candidateState = MovementState.stationary;
  int _consecutiveCount = 0;
  static const int _hysteresisCount = 3; // consecutive readings to confirm change

  // --- Accelerometer smoothing ---
  static const int _accelBufferSize = 5;
  final List<double> _accelBuffer = [];
  double _filteredAccelNet = 0;

  // --- Gyroscope smoothing ---
  static const int _gyroBufferSize = 5;
  final List<double> _gyroBuffer = [];
  double _filteredGyroMag = 0;

  MovementState get currentState => _currentState;
  double get filteredSpeedKmh => _filteredSpeed;
  MovementDiagnostics? _lastDiagnostics;
  MovementDiagnostics? get lastDiagnostics => _lastDiagnostics;

  /// Classify the current movement state from fused sensor data.
  ///
  /// Returns the stable movement state after smoothing and hysteresis.
  MovementState classify(FusedSensorState state) {
    // 1. Extract raw values
    final rawGpsSpeed = state.gps?.speedKmh ?? 0;
    final rawAccelMag = state.accelerometer?.magnitude ?? 9.81;
    final rawAccelNet = state.accelerometer?.netMagnitude ?? 0;
    final rawGyroMag = state.gyroscope?.magnitude ?? 0;

    // 2. Check GPS stationary flag — this is the strongest signal
    final gpsStationary = state.gps?.isStationary ?? false;

    // 3. Smooth GPS speed via EMA buffer
    final filteredSpeed = _smoothGpsSpeed(rawGpsSpeed);

    // 4. Smooth accelerometer net magnitude
    final filteredAccelNet = _smoothBuffer(_accelBuffer, _accelBufferSize,
        rawAccelNet, _filteredAccelNet);
    _filteredAccelNet = filteredAccelNet;

    // 5. Smooth gyroscope magnitude
    final filteredGyroMag = _smoothBuffer(_gyroBuffer, _gyroBufferSize,
        rawGyroMag, _filteredGyroMag);
    _filteredGyroMag = filteredGyroMag;

    // 6. Determine candidate movement state
    final candidate = _determineCandidate(
      filteredSpeed,
      filteredAccelNet,
      filteredGyroMag,
      rawAccelMag,
      gpsStationary,
    );

    // 7. Apply hysteresis (require consecutive readings)
    final (newState, reason) = _applyHysteresis(candidate);

    // 8. Store diagnostics
    _lastDiagnostics = MovementDiagnostics(
      rawGpsSpeedKmh: rawGpsSpeed,
      filteredGpsSpeedKmh: filteredSpeed,
      accelMagnitude: rawAccelMag,
      accelNetMagnitude: filteredAccelNet,
      gyroMagnitude: filteredGyroMag,
      state: newState,
      reason: reason,
    );

    return newState;
  }

  /// Smooth GPS speed using exponential moving average.
  double _smoothGpsSpeed(double rawSpeed) {
    _speedBuffer.add(rawSpeed);
    if (_speedBuffer.length > _speedBufferSize) {
      _speedBuffer.removeAt(0);
    }

    if (!_hasFirstReading) {
      _filteredSpeed = rawSpeed;
      _hasFirstReading = true;
      return _filteredSpeed;
    }

    // EMA with alpha = 0.3 (lower = smoother)
    _filteredSpeed = _filteredSpeed + 0.3 * (rawSpeed - _filteredSpeed);
    return _filteredSpeed;
  }

  /// Generic buffer-based smoothing.
  double _smoothBuffer(
      List<double> buffer, int maxSize, double newValue, double previousFiltered) {
    buffer.add(newValue);
    if (buffer.length > maxSize) {
      buffer.removeAt(0);
    }
    // Simple moving average
    double sum = 0;
    for (final v in buffer) {
      sum += v;
    }
    return sum / buffer.length;
  }

  /// Determine candidate movement state from smoothed sensor values.
  MovementState _determineCandidate(
    double speedKmh,
    double accelNet,
    double gyroMag,
    double accelMag,
    bool gpsStationary,
  ) {
    // === STRONGEST SIGNAL: GPS stationary flag ===
    // If GpsService detected the device hasn't moved (coordinates within
    // radius for multiple readings), trust this over speed alone.
    if (gpsStationary) {
      return MovementState.stationary;
    }

    // === STATIONARY DEAD-ZONE ===
    // If GPS speed is very low AND no accelerometer/gyro activity,
    // the device is stationary.
    final bool accelIndicatesStationary = accelNet < 1.5;
    final bool gyroIndicatesStationary = gyroMag < 15.0;
    final bool gpsIndicatesLowSpeed = speedKmh < 2.5;

    if (gpsIndicatesLowSpeed && accelIndicatesStationary && gyroIndicatesStationary) {
      return MovementState.stationary;
    }

    // === DRIVING ===
    // High sustained GPS speed (above 30 km/h)
    if (speedKmh > 30) {
      return MovementState.driving;
    }

    // === CYCLING ===
    // Moderate speed (12–30 km/h)
    if (speedKmh > 12 && speedKmh <= 30) {
      if (gyroMag < 50) {
        return MovementState.cycling;
      }
      if (speedKmh > 18) {
        return MovementState.cycling;
      }
    }

    // === RUNNING ===
    // Speed 5–12 km/h with significant body movement
    if (speedKmh > 5 && speedKmh <= 12) {
      if (accelNet > 3.0 || gyroMag > 30) {
        return MovementState.running;
      }
      if (speedKmh > 7) {
        return MovementState.running;
      }
    }

    // === WALKING ===
    // Speed 2.5–7 km/h with SOME accelerometer activity
    if (speedKmh > 2.5 && speedKmh <= 7) {
      if (accelNet > 1.0 || gyroMag > 10) {
        return MovementState.walking;
      }
      if (speedKmh > 3.5) {
        return MovementState.walking;
      }
    }

    // === STATIONARY (fallback) ===
    return MovementState.stationary;
  }

  /// Apply hysteresis: require consecutive readings to confirm state change.
  ///
  /// Returns (confirmed state, reason string).
  (MovementState, String) _applyHysteresis(MovementState candidate) {
    if (candidate == _currentState) {
      // Same state — reset candidate counter
      _consecutiveCount = 0;
      _candidateState = candidate;
      return (_currentState, 'sustained ${_currentState.name}');
    }

    if (candidate == _candidateState) {
      // Same candidate as before — increment counter
      _consecutiveCount++;
      if (_consecutiveCount >= _hysteresisCount) {
        // Confirmed state change
        final oldState = _currentState;
        _currentState = candidate;
        _consecutiveCount = 0;
        return (_currentState, 'confirmed from ${oldState.name}');
      }
      return (_currentState, 'candidate=${candidate.name} ($_consecutiveCount/$_hysteresisCount)');
    } else {
      // New candidate — restart counter
      _candidateState = candidate;
      _consecutiveCount = 1;
      return (_currentState, 'candidate=${candidate.name} (1/$_hysteresisCount)');
    }
  }

  /// Reset all internal state.
  void reset() {
    _speedBuffer.clear();
    _filteredSpeed = 0;
    _hasFirstReading = false;
    _accelBuffer.clear();
    _filteredAccelNet = 0;
    _gyroBuffer.clear();
    _filteredGyroMag = 0;
    _currentState = MovementState.stationary;
    _candidateState = MovementState.stationary;
    _consecutiveCount = 0;
    _lastDiagnostics = null;
  }
}
