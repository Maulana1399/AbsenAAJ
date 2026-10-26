import 'package:absen_aaj/features/attendance/application/attendance_sync_policy.dart';
import 'package:absen_aaj/features/attendance/data/attendance_sync_api.dart';
import 'package:test/test.dart';

void main() {
  AttendanceSyncFailure classify({
    int? status,
    String? code,
    bool network = false,
    bool protocol = false,
    Duration? retryAfter,
  }) {
    return classifyAttendanceSyncFailure(
      AttendanceSyncApiException(
        statusCode: status,
        code: code,
        message: 'x',
        isNetwork: network,
        isProtocol: protocol,
        retryAfter: retryAfter,
      ),
    );
  }

  group('classification', () {
    test('network and timeout failures are retryable', () {
      expect(
        classify(network: true, code: 'NETWORK_ERROR').kind,
        AttendanceSyncFailureKind.retryable,
      );
      expect(
        classify(status: 408, code: 'REQUEST_TIMEOUT').kind,
        AttendanceSyncFailureKind.retryable,
      );
    });

    test('429 and 5xx failures are retryable', () {
      expect(
        classify(status: 429, code: 'RATE_LIMITED').kind,
        AttendanceSyncFailureKind.retryable,
      );
      expect(
        classify(status: 500, code: 'PHOTO_STORE_FAILED').kind,
        AttendanceSyncFailureKind.retryable,
      );
      expect(
        classify(status: 503, code: 'SERVICE_UNAVAILABLE').kind,
        AttendanceSyncFailureKind.retryable,
      );
    });

    test('an invalid response body is retryable, not an ack', () {
      expect(
        classify(code: 'SYNC_BAD_RESPONSE', protocol: true).kind,
        AttendanceSyncFailureKind.retryable,
      );
    });

    test('401 is an authentication pause', () {
      final failure = classify(status: 401, code: 'UNAUTHENTICATED');

      expect(failure.kind, AttendanceSyncFailureKind.authentication);
      expect(failure.isAuthentication, isTrue);
      expect(failure.isPermanent, isFalse);
    });

    test('known backend rejections are permanent', () {
      const codes = [
        'OUTSIDE_GEOFENCE',
        'LOCATION_LOW_ACCURACY',
        'ALREADY_CHECKED_IN',
        'CHECK_IN_REQUIRED',
        'ALREADY_CHECKED_OUT',
        'BRANCH_NOT_CONFIGURED',
        'BRANCH_LOCATION_NOT_CONFIGURED',
        'DEVICE_REVOKED',
        'ATTENDANCE_EVENT_CONFLICT',
        'VALIDATION_ERROR',
      ];

      for (final code in codes) {
        expect(
          classify(status: 422, code: code).kind,
          AttendanceSyncFailureKind.permanentRejection,
          reason: code,
        );
      }
    });

    test('unknown device code requires a user action', () {
      final failure = classify(status: 404, code: 'DEVICE_NOT_FOUND');

      expect(failure.kind, AttendanceSyncFailureKind.userActionRequired);
      expect(failure.isUserActionRequired, isTrue);
    });

    test('unknown 4xx is not blanket-mapped to a permanent rejection', () {
      expect(
        classify(status: 418, code: 'UNKNOWN').kind,
        AttendanceSyncFailureKind.userActionRequired,
      );
      expect(
        classify(status: 403, code: 'FORBIDDEN').kind,
        AttendanceSyncFailureKind.userActionRequired,
      );
    });

    test('uses the backend code translation for known codes', () {
      final failure = classify(status: 422, code: 'OUTSIDE_GEOFENCE');

      expect(failure.message, contains('luar area'));
    });
  });

  group('retry delay', () {
    test('uses exponential backoff from 30 seconds', () {
      expect(attendanceSyncRetryDelay(1), const Duration(seconds: 30));
      expect(attendanceSyncRetryDelay(2), const Duration(seconds: 60));
      expect(attendanceSyncRetryDelay(3), const Duration(seconds: 120));
      expect(attendanceSyncRetryDelay(4), const Duration(seconds: 240));
    });

    test('caps the exponential delay at 30 minutes', () {
      expect(attendanceSyncRetryDelay(100), const Duration(minutes: 30));
    });

    test('honors Retry-After over local backoff', () {
      expect(
        attendanceSyncRetryDelay(1, retryAfter: const Duration(minutes: 2)),
        const Duration(minutes: 2),
      );
    });

    test('caps an excessive Retry-After', () {
      expect(
        attendanceSyncRetryDelay(1, retryAfter: const Duration(days: 2)),
        attendanceSyncMaxRetryAfter,
      );
    });
  });
}
