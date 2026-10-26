import 'dart:async';

import 'package:absen_aaj/core/auth/session_controller.dart';
import 'package:absen_aaj/core/storage/device_identity.dart';
import 'package:absen_aaj/features/attendance/application/attendance_controller.dart';
import 'package:absen_aaj/features/attendance/application/attendance_sync_policy.dart';
import 'package:absen_aaj/features/attendance/application/attendance_sync_providers.dart';
import 'package:absen_aaj/features/attendance/application/attendance_sync_worker.dart';
import 'package:absen_aaj/features/attendance/data/local/local_attendance_providers.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_models.dart';
import 'package:absen_aaj/features/attendance/services/camera_service.dart';
import 'package:absen_aaj/features/attendance/services/location_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late ProviderContainer container;
  late FakeLocationService locationService;
  late FakeCameraService cameraService;
  late FakeDeviceIdentity identity;
  late FakeOutboxWriter writer;
  late FakeSyncRunner runner;

  setUp(() {
    locationService = FakeLocationService();
    cameraService = FakeCameraService();
    identity = FakeDeviceIdentity();
    writer = FakeOutboxWriter();
    runner = FakeSyncRunner();

    runner.onSync = (ownerUserId, employeeId) {
      final queued = writer.events.last;
      return AttendanceSyncRunResult(
        acknowledged: [
          makeEvent(
            id: 10,
            eventType: queued.eventType.key,
            status: 'ON_TIME',
            clientEventId: queued.clientEventId,
          ),
        ],
      );
    };

    container = ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(locationService),
        cameraServiceProvider.overrideWithValue(cameraService),
        deviceIdentityProvider.overrideWithValue(identity),
        attendanceOutboxWriterProvider.overrideWithValue(writer),
        attendanceSyncRunnerProvider.overrideWithValue(runner),
        sessionControllerProvider.overrideWith(
          (ref) => FakeSessionController(ref),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('AttendanceSubmissionController', () {
    test('successful check-in updates state with server event', () async {
      final controller = container.read(attendanceSubmissionProvider.notifier);
      await controller.submitCheckIn();

      final state = container.read(attendanceSubmissionProvider);
      expect(state.phase, AttendancePhase.success);
      expect(state.event?.id, 10);
      expect(state.event?.status, 'ON_TIME');
      expect(writer.events, hasLength(1));
      expect(runner.calls, 1);
    });

    test('enqueues durably before attempting the network', () async {
      final calls = <String>[];
      writer.onEnqueue = () => calls.add('enqueue');
      runner.onSync = (ownerUserId, employeeId) {
        calls.add('sync');
        final queued = writer.events.last;
        return AttendanceSyncRunResult(
          acknowledged: [
            makeEvent(
              id: 10,
              eventType: queued.eventType.key,
              clientEventId: queued.clientEventId,
            ),
          ],
        );
      };

      await container
          .read(attendanceSubmissionProvider.notifier)
          .submitCheckIn();

      expect(calls, ['enqueue', 'sync']);
    });

    test(
      'successful check-out uses CHECK_OUT and different event id',
      () async {
        final controller = container.read(
          attendanceSubmissionProvider.notifier,
        );

        await controller.submitCheckIn();
        final checkInId = writer.events.single.clientEventId;

        await controller.submitCheckOut();

        expect(writer.events.last.eventType, AttendanceEventType.checkOut);
        expect(writer.events.last.clientEventId, isNot(checkInId));
        expect(runner.calls, 2);
      },
    );

    test('the photo bytes are passed to the outbox', () async {
      cameraService.result = SelfieResult(
        bytes: const [9, 8, 7],
        capturedAt: DateTime(2026, 10, 6, 8, 30),
      );

      await container
          .read(attendanceSubmissionProvider.notifier)
          .submitCheckIn();

      expect(writer.events.single.photoBytes, [9, 8, 7]);
    });

    test(
      'server rejection does not pretend success and keeps the queue',
      () async {
        runner.onSync = (ownerUserId, employeeId) =>
            const AttendanceSyncRunResult(
              failure: AttendanceSyncFailure(
                kind: AttendanceSyncFailureKind.permanentRejection,
                code: 'OUTSIDE_GEOFENCE',
                message: 'Anda berada di luar area absensi cabang.',
              ),
            );

        final controller = container.read(
          attendanceSubmissionProvider.notifier,
        );
        await controller.submitCheckIn();

        final state = container.read(attendanceSubmissionProvider);
        expect(state.phase, AttendancePhase.error);
        expect(state.event, isNull);
        expect(state.errorCode, 'OUTSIDE_GEOFENCE');
        expect(state.isSuccess, isFalse);
        expect(writer.events, hasLength(1));
      },
    );

    test('network failure reports that the event is saved locally', () async {
      runner.onSync = (ownerUserId, employeeId) =>
          const AttendanceSyncRunResult(
            failure: AttendanceSyncFailure(
              kind: AttendanceSyncFailureKind.retryable,
              code: 'NETWORK_ERROR',
              message:
                  'Tidak dapat terhubung ke server. Absensi akan dicoba lagi.',
            ),
          );

      final controller = container.read(attendanceSubmissionProvider.notifier);
      await controller.submitCheckIn();

      final state = container.read(attendanceSubmissionProvider);
      expect(state.phase, AttendancePhase.queued);
      expect(state.isError, isFalse);
      expect(state.isQueued, isTrue);
      expect(state.errorCode, 'NETWORK_ERROR');
      expect(state.queuedEvent?.clientEventId, writer.events.single.clientEventId);
      expect(
        state.errorMessage,
        AttendanceSubmissionController.localQueuedMessage,
      );
      expect(writer.events, hasLength(1));
    });

    test('sync crash after enqueue still reports the local queue', () async {
      runner.onSync = (ownerUserId, employeeId) => throw StateError('boom');

      final controller = container.read(attendanceSubmissionProvider.notifier);
      await controller.submitCheckIn();

      final state = container.read(attendanceSubmissionProvider);
      expect(state.phase, AttendancePhase.queued);
      expect(state.queuedEvent?.clientEventId, writer.events.single.clientEventId);
      expect(writer.events, hasLength(1));
    });

    test('local enqueue failure is reported as a local save failure', () async {
      writer.onEnqueue = () => throw StateError('disk full');

      final controller = container.read(attendanceSubmissionProvider.notifier);
      await controller.submitCheckIn();

      final state = container.read(attendanceSubmissionProvider);
      expect(state.phase, AttendancePhase.error);
      expect(state.errorCode, 'LOCAL_STORAGE_ERROR');
      expect(state.errorMessage, contains('gagal disimpan di perangkat'));
      expect(state.isQueued, isFalse);
      expect(runner.calls, 0);
    });

    test('cancelling the selfie returns to idle without submitting', () async {
      cameraService.returnsNull = true;

      final controller = container.read(attendanceSubmissionProvider.notifier);
      await controller.submitCheckIn();

      expect(
        container.read(attendanceSubmissionProvider).phase,
        AttendancePhase.idle,
      );
      expect(writer.events, isEmpty);
      expect(runner.calls, 0);
    });

    test('missing employee link blocks submission before writing', () async {
      container = ProviderContainer(
        overrides: [
          locationServiceProvider.overrideWithValue(locationService),
          cameraServiceProvider.overrideWithValue(cameraService),
          deviceIdentityProvider.overrideWithValue(identity),
          attendanceOutboxWriterProvider.overrideWithValue(writer),
          attendanceSyncRunnerProvider.overrideWithValue(runner),
          sessionControllerProvider.overrideWith(
            (ref) => FakeSessionController(ref, user: testUserWithoutEmployee),
          ),
        ],
      );

      await container
          .read(attendanceSubmissionProvider.notifier)
          .submitCheckIn();

      final state = container.read(attendanceSubmissionProvider);
      expect(state.phase, AttendancePhase.error);
      expect(state.errorCode, 'EMPLOYEE_REQUIRED');
      expect(writer.events, isEmpty);
    });

    test(
      'double tap while submitting is guarded (isSubmitting disables action)',
      () async {
        final gate = Completer<void>();
        runner.gate = gate;

        final controller = container.read(
          attendanceSubmissionProvider.notifier,
        );
        final first = controller.submitCheckIn();
        final second = controller.submitCheckIn();
        expect(
          container.read(attendanceSubmissionProvider).isSubmitting,
          isTrue,
          reason: 'button should be disabled while submitting',
        );

        gate.complete();
        await Future.wait([first, second]);

        expect(
          writer.events,
          hasLength(1),
          reason: 'only one submission allowed',
        );
        expect(runner.calls, 1);
      },
    );
  });
}
