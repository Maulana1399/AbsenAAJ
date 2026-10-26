import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/session_controller.dart';
import '../data/attendance_sync_api.dart';
import '../data/local/local_attendance_providers.dart';
import 'attendance_sync_worker.dart';

final attendanceSyncApiProvider = Provider<AttendanceSyncApi>(
  (ref) => ApiAttendanceSyncApi(ref.watch(apiClientProvider)),
);

final attendanceSyncWorkerProvider = Provider<AttendanceSyncWorker>(
  (ref) => AttendanceSyncWorker(
    ref.watch(attendanceOutboxRepositoryProvider),
    ref.watch(attendancePhotoStorageProvider),
    ref.watch(attendanceSyncApiProvider),
    isSessionActive: () => ref.read(sessionControllerProvider).isAuthenticated,
  ),
);

final attendanceSyncRunnerProvider = Provider<AttendanceSyncRunner>(
  (ref) => ref.watch(attendanceSyncWorkerProvider),
);
