import 'package:absen_aaj/features/attendance/domain/attendance_outbox_time.dart';
import 'package:test/test.dart';

void main() {
  test('formats a fixed-width UTC timestamp with microseconds', () {
    expect(
      formatOutboxTimestamp(DateTime.utc(2026, 10, 6, 8, 30, 0, 123, 456)),
      '2026-10-06T08:30:00.123456Z',
    );
    expect(
      formatOutboxTimestamp(DateTime.utc(2026, 10, 6, 8, 30)),
      '2026-10-06T08:30:00.000000Z',
    );
  });

  test('normalizes parsed timestamps to UTC', () {
    final parsed = parseOutboxTimestamp('2026-10-06T15:30:00.123456+07:00');
    expect(parsed, DateTime.utc(2026, 10, 6, 8, 30, 0, 123, 456));
    expect(parsed.isUtc, isTrue);
  });
}
