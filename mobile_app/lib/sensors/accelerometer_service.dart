import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/sensor_data.dart';

/// Service that collects accelerometer data from device sensors.
class AccelerometerService {
  StreamSubscription<AccelerometerEvent>? _subscription;
  final _controller = StreamController<AccelerometerData>.broadcast();
  AccelerometerData? _latest;

  /// Stream of accelerometer data points
  Stream<AccelerometerData> get stream => _controller.stream;

  /// Most recent reading
  AccelerometerData? get latest => _latest;

  /// Peak acceleration over a recent window
  double _peakMagnitude = 0;

  /// Start listening to accelerometer events
  void start() {
    _subscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      final data = AccelerometerData(
        x: event.x,
        y: event.y,
        z: event.z,
        timestamp: DateTime.now(),
      );
      _latest = data;
      if (data.magnitude > _peakMagnitude) {
        _peakMagnitude = data.magnitude;
      }
      _controller.add(data);
    });
  }

  /// Stop listening
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Get and reset the peak magnitude
  double getAndResetPeak() {
    final peak = _peakMagnitude;
    _peakMagnitude = 0;
    return peak;
  }

  /// Peak magnitude in current window
  double get peakMagnitude => _peakMagnitude;

  /// Dispose resources
  void dispose() {
    stop();
    _controller.close();
  }
}
