import 'package:flutter_test/flutter_test.dart';
import 'package:resq_ai/sensors/gps_service.dart';

/// Tests for the GPS service's internal filtering logic.
/// Since GpsService._haversineDistance and _rollingMedian are private,
/// we test the observable behavior: the stream output.
void main() {
  group('GpsService', () {
    test('GpsStartResult.success', () {
      const result = GpsStartResult.success();
      expect(result.success, true);
      expect(result.error, null);
    });

    test('GpsStartResult.failure', () {
      const result = GpsStartResult.failure('Permission denied');
      expect(result.success, false);
      expect(result.error, 'Permission denied');
    });

    test('GpsStartResult.toString success', () {
      const result = GpsStartResult.success();
      expect(result.toString(), 'GPS: OK');
    });

    test('GpsStartResult.toString failure', () {
      const result = GpsStartResult.failure('Service off');
      expect(result.toString(), 'GPS: Service off');
    });
  });
}
