import 'package:absen_aaj/core/format/attendance_format.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_models.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_payload.dart';
import 'package:test/test.dart';

void main() {
  test('formats an instant using the device local timezone', () {
    final instant = DateTime.utc(2026, 10, 24, 6, 7);
    final local = instant.toLocal();

    expect(
      formatTime(instant),
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
    );
  });

  test('serializes event timestamps with an explicit UTC offset', () {
    final local = DateTime(2026, 10, 24, 14, 7);
    final fields = buildEventFields(
      clientEventId: 'round-trip',
      deviceUuid: 'device',
      eventType: AttendanceEventType.checkIn,
      eventAt: local,
      capturedAt: local,
      gps: const GpsReading(
        latitude: -5.1477,
        longitude: 119.4326,
        accuracyMeters: 20,
      ),
    );

    final serialized = fields['event_at'] as String;
    final parsed = DateTime.parse(serialized);

    expect(parsed.toUtc(), local.toUtc());
    expect(serialized.endsWith('Z'), isTrue);
  });

  test('round-trips a UTC instant through local WITA display', () {
    final utc = DateTime.utc(2026, 10, 24, 6, 7);
    final local = utc.toLocal();

    expect(local.difference(utc), Duration.zero);
    expect(
      formatTime(utc),
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
    );
    if (local.timeZoneOffset == const Duration(hours: 8)) {
      expect(formatTime(utc), '14:07');
    }
  });

  test('normalizes a timestamp without an offset before serialization', () {
    final withoutOffset = DateTime.parse('2026-10-24T14:07:00');
    final fields = buildEventFields(
      clientEventId: 'no-offset',
      deviceUuid: 'device',
      eventType: AttendanceEventType.checkIn,
      eventAt: withoutOffset,
      capturedAt: withoutOffset,
      gps: const GpsReading(
        latitude: -5.1477,
        longitude: 119.4326,
        accuracyMeters: 20,
      ),
    );

    expect((fields['event_at'] as String).endsWith('Z'), isTrue);
    expect(DateTime.parse(fields['event_at'] as String).toUtc(), withoutOffset.toUtc());
  });
}
