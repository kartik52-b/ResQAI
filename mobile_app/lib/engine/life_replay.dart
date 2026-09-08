import 'dart:collection';
import '../models/emergency_event.dart';
import '../config/thresholds.dart';

/// Maintains a rolling buffer of recent sensor events.
/// When an emergency is confirmed, the relevant timeline is preserved.
class LifeReplay {
  final Queue<ReplayEvent> _buffer = Queue<ReplayEvent>();
  List<ReplayEvent>? _snapshot;
  DateTime? _lastEventTime;

  /// Get current buffer as a list
  List<ReplayEvent> get events => _buffer.toList();

  /// Get the snapshot taken at emergency confirmation
  List<ReplayEvent>? get snapshot => _snapshot;

  /// Get the preserved timeline (for incident record)
  List<ReplayEvent> get timeline => _snapshot ?? _buffer.toList();

  /// Add a new event to the buffer
  void addEvent({
    required String description,
    required ActivityType activityType,
    required int score,
  }) {
    final now = DateTime.now();

    // Avoid duplicate events within 2 seconds
    if (_lastEventTime != null &&
        now.difference(_lastEventTime!).inSeconds < 2) {
      return;
    }

    final event = ReplayEvent(
      timestamp: now,
      description: description,
      activityType: activityType,
      score: score,
    );

    _buffer.addLast(event);
    _lastEventTime = now;

    // Remove old events beyond buffer limit
    while (_buffer.length > EmergencyThresholds.replayBufferMaxEvents ||
        (_buffer.isNotEmpty &&
            _buffer.first.timestamp
                    .difference(now)
                    .abs() >
                const Duration(seconds: EmergencyThresholds.replayBufferMaxSeconds))) {
      _buffer.removeFirst();
    }
  }

  /// Take a snapshot of current events (called when emergency is confirmed)
  void takeSnapshot() {
    _snapshot = _buffer.toList();
  }

  /// Clear snapshot (after incident is resolved)
  void clearSnapshot() {
    _snapshot = null;
  }

  /// Clear the entire buffer
  void clear() {
    _buffer.clear();
    _snapshot = null;
    _lastEventTime = null;
  }

  /// Convert timeline to a displayable format
  List<Map<String, String>> getDisplayTimeline() {
    final timeline = _snapshot ?? _buffer.toList();
    return timeline.map((e) {
      final hour = e.timestamp.hour.toString().padLeft(2, '0');
      final minute = e.timestamp.minute.toString().padLeft(2, '0');
      final second = e.timestamp.second.toString().padLeft(2, '0');
      return {
        'time': '$hour:$minute:$second',
        'description': e.description,
        'severity': e.activityType == ActivityType.emergency
            ? 'critical'
            : e.score > 50
                ? 'high'
                : e.score > 30
                    ? 'medium'
                    : 'low',
      };
    }).toList();
  }
}
