import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/sensor_data.dart';

/// Service that collects gyroscope data from device sensors.
class GyroscopeService {
  StreamSubscription<GyroscopeEvent>? _subscription;
  final _controller = StreamController<GyroscopeData>.broadcast();
  GyroscopeData? _latest;
  double _peakMagnitude = 0;

  /// Stream of gyroscope data points
  Stream<GyroscopeData> get stream => _controller.stream;

  /// Most recent reading
  GyroscopeData? get latest => _latest;

  /// Peak angular velocity magnitude
  double get peakMagnitude => _peakMagnitude;

  /// Start listening to gyroscope events
  void start() {
    _subscription = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      // sensors_plus delivers gyroscope values in RAD/S.
      // Convert to DEG/S for use with detection thresholds.
      const double radToDeg = 180.0 / 3.141592653589793;
      final data = GyroscopeData(
        x: event.x * radToDeg,
        y: event.y * radToDeg,
        z: event.z * radToDeg,
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

  void dispose() {
    stop();
    _controller.close();
  }
}
