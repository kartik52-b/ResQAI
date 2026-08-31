import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/sensor_data.dart';
import 'accelerometer_service.dart';
import 'gyroscope_service.dart';
import 'gps_service.dart';

/// Central manager that coordinates all sensor services.
/// Provides a unified interface and fused sensor state stream.
class SensorManager extends ChangeNotifier {
  final AccelerometerService _accelerometer = AccelerometerService();
  final GyroscopeService _gyroscope = GyroscopeService();
  final GpsService _gps = GpsService();

  final _fusedController = StreamController<FusedSensorState>.broadcast();
  Timer? _fusionTimer;

  FusedSensorState? _currentState;
  bool _isRunning = false;

  // Sensor health status
  bool _accelerometerActive = false;
  bool _gyroscopeActive = false;
  bool _gpsActive = false;
  GpsStartResult? _gpsStartResult;

  /// Stream of fused sensor states (updated at ~10Hz)
  Stream<FusedSensorState> get fusedStream => _fusedController.stream;

  /// Current fused state
  FusedSensorState? get currentState => _currentState;
  bool get isRunning => _isRunning;

  // Individual sensor accessors
  AccelerometerService get accelerometer => _accelerometer;
  GyroscopeService get gyroscope => _gyroscope;
  GpsService get gps => _gps;

  // Health status
  bool get accelerometerHealthy => _accelerometerActive;
  bool get gyroscopeHealthy => _gyroscopeActive;
  bool get gpsHealthy => _gpsActive;

  /// Result of the last GPS start attempt
  GpsStartResult? get gpsStartResult => _gpsStartResult;

  /// Start all sensors and begin fusion loop.
  /// Returns the GPS start result so the caller can handle GPS failures.
  Future<GpsStartResult> startAll() async {
    if (_isRunning) return const GpsStartResult.success();

    // Start accelerometer and gyroscope (these don't need permissions)
    _accelerometer.start();
    _accelerometerActive = true;
    _gyroscope.start();
    _gyroscopeActive = true;

    // Start GPS — this may fail if permissions are denied or GPS is off
    _gpsStartResult = await _gps.requestPermissionAndStart();
    _gpsActive = _gpsStartResult!.success;

    debugPrint('SensorManager: GPS start result: $_gpsStartResult');

    // Fusion timer: combine readings at ~10Hz
    _fusionTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _fuse(),
    );

    _isRunning = true;
    notifyListeners();
    return _gpsStartResult!;
  }

  /// Stop all sensors
  void stopAll() {
    _fusionTimer?.cancel();
    _accelerometer.stop();
    _gyroscope.stop();
    _gps.stop();

    _accelerometerActive = false;
    _gyroscopeActive = false;
    _gpsActive = false;
    _isRunning = false;
    notifyListeners();
  }

  /// Create a fused state from latest individual readings
  void _fuse() {
    final state = FusedSensorState(
      accelerometer: _accelerometer.latest,
      gyroscope: _gyroscope.latest,
      gps: _gps.latest,
      timestamp: DateTime.now(),
    );
    _currentState = state;
    _fusedController.add(state);
  }

  /// Get peak values and reset
  Map<String, double> getAndResetPeaks() {
    return {
      'acceleration_peak': _accelerometer.getAndResetPeak(),
      'rotation_peak': _gyroscope.getAndResetPeak(),
      'speed_change_peak': _gps.getAndResetMaxSpeedChange(),
    };
  }

  @override
  void dispose() {
    stopAll();
    _fusedController.close();
    _accelerometer.dispose();
    _gyroscope.dispose();
    _gps.dispose();
    super.dispose();
  }
}
