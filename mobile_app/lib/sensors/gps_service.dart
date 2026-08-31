import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/sensor_data.dart';

/// Result of attempting to start GPS
class GpsStartResult {
  final bool success;
  final String? error;

  const GpsStartResult.success()
      : success = true,
        error = null;
  const GpsStartResult.failure(this.error)
      : success = false;

  @override
  String toString() => success ? 'GPS: OK' : 'GPS: $error';
}

/// Robust GPS service with:
/// - Ground speed calculation from consecutive positions (Haversine)
/// - GPS accuracy validation
/// - Rolling median + EMA filtering
/// - Stationary stability detection
/// - Outlier rejection
///
/// The goal: a stationary phone MUST NOT report moving.
class GpsService {
  StreamSubscription<Position>? _subscription;
  final _controller = StreamController<GpsData>.broadcast();
  GpsData? _latest;

  // --- Position history for ground speed calculation ---
  Position? _previousPosition;
  DateTime? _previousTimestamp;

  // --- Rolling speed buffer (for median filter) ---
  static const int _speedBufferSize = 7; // odd number for clean median
  final List<double> _speedBuffer = [];

  // --- EMA filter (after median) ---
  double _emaSpeed = 0;
  bool _hasEmaInitialized = false;
  static const double _emaAlpha = 0.35;

  // --- Stationary stability ---
  // Track positions within this radius (meters) over consecutive updates
  static const double _stationaryRadius = 15.0; // meters
  static const int _stationaryRequiredUpdates = 5; // consecutive within radius
  final List<_PositionRecord> _positionHistory = [];
  int _stationaryCount = 0;
  bool _isStationary = false;

  // --- Accuracy thresholds ---
  static const double _maxAccuracyMeters = 30.0; // reject poor-accuracy readings

  // --- Outlier rejection ---
  static const double _maxSingleSpeedJump = 15.0; // km/h max change per reading

  // --- Raw speed cross-validation ---
  // Android position.speed can be inaccurate. We compare with ground speed.
  static const double _maxSpeedDiscrepancy = 20.0; // km/h discrepancy threshold

  /// Most recent reading
  GpsData? get latest => _latest;

  /// Stream of GPS data points
  Stream<GpsData> get stream => _controller.stream;

  /// Check and request location permissions with proper user prompts.
  Future<GpsStartResult> requestPermissionAndStart() async {
    // Step 1: Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      try {
        await Geolocator.openLocationSettings();
      } catch (_) {}
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const GpsStartResult.failure(
            'Location services are disabled. Please enable GPS in device settings.');
      }
    }

    // Step 2: Check permission status
    LocationPermission permission = await Geolocator.checkPermission();

    // Step 3: If denied, request permission (shows system dialog)
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return const GpsStartResult.failure(
            'Location permission denied. Please grant location access in app settings.');
      }
    }

    // Step 4: If permanently denied, user must go to settings
    if (permission == LocationPermission.deniedForever) {
      try {
        await Geolocator.openAppSettings();
      } catch (_) {}
      return const GpsStartResult.failure(
          'Location permission permanently denied. Please enable it in app settings.');
    }

    // Step 5: Permission granted — reset state and start GPS stream
    debugPrint('GpsService: Permission granted, starting GPS stream...');
    _resetFilterState();

    _subscription?.cancel();
    _subscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1, // Update every 1 meter
      ),
    ).listen(
      _onPositionUpdate,
      onError: (error) {
        debugPrint('GpsService: Position stream error: $error');
      },
    );

    return const GpsStartResult.success();
  }

  /// Core position update handler — the heart of GPS speed filtering.
  void _onPositionUpdate(Position position) {
    final now = DateTime.now();

    // === STEP 1: Validate accuracy ===
    final accuracy = position.accuracy;
    if (accuracy > _maxAccuracyMeters) {
      debugPrint('GpsService: REJECTED reading — accuracy ${accuracy.toStringAsFixed(1)}m '
          '> ${_maxAccuracyMeters}m threshold');
      return; // Skip this reading entirely
    }

    // === STEP 2: Calculate ground speed from consecutive positions ===
    double groundSpeedKmh = 0;
    if (_previousPosition != null && _previousTimestamp != null) {
      final distanceMeters = _haversineDistance(
        _previousPosition!.latitude,
        _previousPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      final timeDeltaSeconds = now.difference(_previousTimestamp!).inMilliseconds / 1000.0;

      if (timeDeltaSeconds > 0.1) {
        groundSpeedKmh = (distanceMeters / timeDeltaSeconds) * 3.6;
      }
    }

    // === STEP 3: Get Android-reported speed ===
    final androidSpeedKmh = position.speed * 3.6;

    // === STEP 4: Cross-validate ground speed vs Android speed ===
    // If both are available and differ greatly, prefer ground speed
    double fusedSpeedKmh;
    if (_previousPosition != null && groundSpeedKmh > 0) {
      final discrepancy = (groundSpeedKmh - androidSpeedKmh).abs();
      if (discrepancy > _maxSpeedDiscrepancy && androidSpeedKmh > 0) {
        // Large discrepancy — trust ground speed more
        fusedSpeedKmh = groundSpeedKmh;
        debugPrint('GpsService: Speed discrepancy ${discrepancy.toStringAsFixed(1)} km/h '
            '(ground=${groundSpeedKmh.toStringAsFixed(1)}, android=${androidSpeedKmh.toStringAsFixed(1)}) '
            '→ using ground speed');
      } else {
        // Reasonable agreement — use Android speed (it has Doppler advantage)
        fusedSpeedKmh = androidSpeedKmh;
      }
    } else {
      // First reading or no ground speed available — use Android speed
      fusedSpeedKmh = androidSpeedKmh;
    }

    // === STEP 5: Stationary stability detection ===
    _updateStationaryDetection(position, now);

    // If stationary, force speed toward 0
    if (_isStationary) {
      fusedSpeedKmh = fusedSpeedKmh * 0.1; // Clamp to 10% of reported speed
      if (fusedSpeedKmh < 0.5) fusedSpeedKmh = 0; // Snap to zero below 0.5 km/h
    }

    // === STEP 6: Rolling median filter ===
    _speedBuffer.add(fusedSpeedKmh);
    if (_speedBuffer.length > _speedBufferSize) {
      _speedBuffer.removeAt(0);
    }
    final medianSpeed = _rollingMedian(_speedBuffer);

    // === STEP 7: EMA smoothing (after median) ===
    if (!_hasEmaInitialized) {
      _emaSpeed = medianSpeed;
      _hasEmaInitialized = true;
    } else {
      // Reject single-reading jumps
      final jump = (medianSpeed - _emaSpeed).abs();
      if (jump > _maxSingleSpeedJump) {
        // Clamp change to max allowed jump
        final clampedSpeed = _emaSpeed +
            (medianSpeed > _emaSpeed ? _maxSingleSpeedJump : -_maxSingleSpeedJump);
        _emaSpeed = clampedSpeed.clamp(0, 999);
      } else {
        _emaSpeed = _emaSpeed + _emaAlpha * (medianSpeed - _emaSpeed);
      }
    }

    // === STEP 8: Final output ===
    final filteredSpeedMs = _emaSpeed / 3.6;

    final data = GpsData(
      latitude: position.latitude,
      longitude: position.longitude,
      speed: filteredSpeedMs, // Filtered speed in m/s
      timestamp: now,
      accuracy: accuracy,
      rawSpeedKmh: androidSpeedKmh,
      groundSpeedKmh: groundSpeedKmh,
      isStationary: _isStationary,
    );

    _latest = data;
    _previousPosition = position;
    _previousTimestamp = now;

    // Debug logging
    debugPrint('GpsService: '
        'raw=${androidSpeedKmh.toStringAsFixed(1)} '
        'ground=${groundSpeedKmh.toStringAsFixed(1)} '
        'fused=${fusedSpeedKmh.toStringAsFixed(1)} '
        'median=${medianSpeed.toStringAsFixed(1)} '
        'filtered=${_emaSpeed.toStringAsFixed(1)} '
        'acc=${accuracy.toStringAsFixed(1)}m '
        '${_isStationary ? "STATIONARY" : "MOVING"}');

    _controller.add(data);
  }

  /// Update stationary detection based on position history.
  /// If coordinates stay within _stationaryRadius for _stationaryRequiredUpdates
  /// consecutive readings, the device is considered stationary.
  void _updateStationaryDetection(Position position, DateTime now) {
    // Add to history
    _positionHistory.add(_PositionRecord(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: now,
    ));

    // Keep only last 15 seconds of history
    _positionHistory.removeWhere(
      (r) => now.difference(r.timestamp).inSeconds > 15,
    );

    if (_positionHistory.length < 2) {
      _stationaryCount = 0;
      return;
    }

    // Check if ALL recent positions are within stationary radius of each other
    // Use the oldest position as reference point
    final reference = _positionHistory.first;
    bool allWithinRadius = true;

    for (final record in _positionHistory) {
      final distance = _haversineDistance(
        reference.latitude,
        reference.longitude,
        record.latitude,
        record.longitude,
      );
      if (distance > _stationaryRadius) {
        allWithinRadius = false;
        break;
      }
    }

    if (allWithinRadius) {
      _stationaryCount++;
      if (_stationaryCount >= _stationaryRequiredUpdates) {
        _isStationary = true;
      }
    } else {
      // Movement detected — reset stationary state
      _stationaryCount = 0;
      _isStationary = false;
    }
  }

  /// Calculate median of a list of doubles.
  double _rollingMedian(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[mid];
    }
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// Haversine distance between two GPS coordinates in meters.
  double _haversineDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  /// Reset all filter state.
  void _resetFilterState() {
    _previousPosition = null;
    _previousTimestamp = null;
    _speedBuffer.clear();
    _emaSpeed = 0;
    _hasEmaInitialized = false;
    _positionHistory.clear();
    _stationaryCount = 0;
    _isStationary = false;
  }

  /// Get and reset max speed change (for peak tracking).
  double getAndResetMaxSpeedChange() {
    // Not used in critical path — return 0
    return 0;
  }

  /// Stop listening
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _resetFilterState();
  }

  /// Get current position (one-shot)
  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    stop();
    _controller.close();
  }
}

/// Internal position record for stationary detection.
class _PositionRecord {
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  _PositionRecord({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });
}
