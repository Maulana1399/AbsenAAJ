import 'dart:async';

import 'package:absen_aaj/core/auth/session_controller.dart';
import 'package:absen_aaj/core/storage/device_identity.dart';
import 'package:absen_aaj/features/attendance/application/attendance_controller.dart';
import 'package:absen_aaj/features/attendance/application/attendance_sync_policy.dart';
import 'package:absen_aaj/features/attendance/application/attendance_sync_providers.dart';
import 'package:absen_aaj/features/attendance/application/attendance_sync_worker.dart';
import 'package:absen_aaj/features/attendance/data/attendance_repository.dart';
import 'package:absen_aaj/features/attendance/data/local/local_attendance_providers.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_models.dart';
import 'package:absen_aaj/features/attendance/services/camera_service.dart';
import 'package:absen_aaj/features/attendance/services/location_service.dart';
import 'package:absen_aaj/features/home/presentation/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  testWidgets('attendance button is disabled while a request is in progress', (
    tester,
  ) async {
    final gate = Completer<void>();
    final writer = FakeOutboxWriter();
    final runner = FakeSyncRunner()..gate = gate;
    runner.onSync = (_, __) {
      final queued = writer.events.last;
      return AttendanceSyncRunResult(
        acknowledged: [
          makeEvent(
            clientEventId: queued.clientEventId,
            eventType: queued.eventType.key,
          ),
        ],
      );
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(FakeLocationService()),
          cameraServiceProvider.overrideWithValue(FakeCameraService()),
          attendanceRepositoryProvider.overrideWithValue(
            _SetEventRepo(const []),
          ),
          attendanceLocalReaderProvider.overrideWithValue(
            FakeLocalAttendanceReader(),
          ),
          attendanceOutboxWriterProvider.overrideWithValue(writer),
          attendanceSyncRunnerProvider.overrideWithValue(runner),
          sessionControllerProvider.overrideWith(
            (ref) => FakeSessionController(ref),
          ),
          deviceIdentityProvider.overrideWithValue(FakeDeviceIdentity()),
        ],
        child: const MaterialApp(home: Scaffold(body: HomePage())),
      ),
    );

    // Let the initial device registration + home reload finish.
    await tester.pumpAndSettle();

    // Before submitting, the button must be enabled.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isTrue,
    );

    // Trigger submission through the controller that the page uses.
    ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    ).read(attendanceSubmissionProvider.notifier).submitCheckIn();
    await tester.pump();

    // While in flight the button is replaced by a spinner and disabled.
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(
      button.enabled,
      isFalse,
      reason: 'double-tap while in flight must be impossible',
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('home shows server-provided today status', (tester) async {
    final readyRepo = _SetEventRepo([
      makeEvent(id: 1, eventType: 'CHECK_IN', status: 'ON_TIME'),
      makeEvent(id: 2, eventType: 'CHECK_OUT', status: 'NORMAL'),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attendanceRepositoryProvider.overrideWithValue(readyRepo),
          attendanceLocalReaderProvider.overrideWithValue(
            FakeLocalAttendanceReader(),
          ),
          deviceIdentityProvider.overrideWithValue(FakeDeviceIdentity()),
          locationServiceProvider.overrideWithValue(FakeLocationService()),
          cameraServiceProvider.overrideWithValue(FakeCameraService()),
        ],
        child: const MaterialApp(home: Scaffold(body: HomePage())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('SELESAI'), findsOneWidget);
    expect(find.text('Absensi Selesai'), findsOneWidget);
  });

  testWidgets('offline submit is only claimed as saved after enqueue succeeds', (
    tester,
  ) async {
    final writer = FakeOutboxWriter();
    final runner = FakeSyncRunner()
      ..onSync = ((_, __) => const AttendanceSyncRunResult(
            failure: AttendanceSyncFailure(
              kind: AttendanceSyncFailureKind.retryable,
              code: 'NETWORK_ERROR',
              message: 'offline',
            ),
          ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attendanceRepositoryProvider.overrideWithValue(_SetEventRepo(const [])),
          attendanceLocalReaderProvider.overrideWithValue(
            FakeLocalAttendanceReader(),
          ),
          attendanceOutboxWriterProvider.overrideWithValue(writer),
          attendanceSyncRunnerProvider.overrideWithValue(runner),
          deviceIdentityProvider.overrideWithValue(FakeDeviceIdentity()),
          locationServiceProvider.overrideWithValue(FakeLocationService()),
          cameraServiceProvider.overrideWithValue(FakeCameraService()),
          sessionControllerProvider.overrideWith(
            (ref) => FakeSessionController(ref),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: HomePage())),
      ),
    );

    await tester.pumpAndSettle();

    ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    ).read(attendanceSubmissionProvider.notifier).submitCheckIn();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(writer.events, hasLength(1));
    expect(
      find.text(AttendanceSubmissionController.localQueuedMessage),
      findsOneWidget,
    );
  });

  testWidgets('local enqueue failure is shown as a local save failure', (
    tester,
  ) async {
    final writer = FakeOutboxWriter()..onEnqueue = () => throw StateError('disk');
    final runner = FakeSyncRunner();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attendanceRepositoryProvider.overrideWithValue(_SetEventRepo(const [])),
          attendanceLocalReaderProvider.overrideWithValue(
            FakeLocalAttendanceReader(),
          ),
          attendanceOutboxWriterProvider.overrideWithValue(writer),
          attendanceSyncRunnerProvider.overrideWithValue(runner),
          deviceIdentityProvider.overrideWithValue(FakeDeviceIdentity()),
          locationServiceProvider.overrideWithValue(FakeLocationService()),
          cameraServiceProvider.overrideWithValue(FakeCameraService()),
          sessionControllerProvider.overrideWith(
            (ref) => FakeSessionController(ref),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: HomePage())),
      ),
    );

    await tester.pumpAndSettle();

    // Capture the call count after init (which triggers one background sync).
    final callsBeforeSubmit = runner.calls;

    ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    ).read(attendanceSubmissionProvider.notifier).submitCheckIn();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(writer.events, isEmpty);
    // Sync runner must NOT have been called by the failed submit itself.
    expect(runner.calls, callsBeforeSubmit);
    expect(find.textContaining('gagal disimpan di perangkat'), findsOneWidget);
    expect(
      find.text(AttendanceSubmissionController.localQueuedMessage),
      findsNothing,
    );
  });
}

class _SetEventRepo implements AttendanceRepository {
  _SetEventRepo(this.events);

  final List<AttendanceEvent> events;

  @override
  Future<List<AttendanceEvent>> history({DateTime? from, DateTime? to}) async {
    return events;
  }

  @override
  Future<AttendanceEvent> submitEvent({
    required String clientEventId,
    required String deviceUuid,
    required AttendanceEventType eventType,
    required DateTime eventAt,
    required GpsReading gps,
    required DateTime capturedAt,
    required List<int> photoBytes,
  }) {
    throw StateError('not used');
  }

  @override
  Future<DeviceInfo> registerDevice({
    required String deviceUuid,
    String? manufacturer,
    String? model,
    String? appVersion,
  }) async {
    return DeviceInfo(id: 1, deviceUuid: deviceUuid, status: 'ACTIVE');
  }
}
