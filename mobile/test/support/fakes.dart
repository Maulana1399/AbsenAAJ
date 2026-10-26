import 'dart:async';

import 'package:absen_aaj/core/auth/cached_user_store.dart';
import 'package:absen_aaj/core/auth/session_controller.dart';
import 'package:absen_aaj/core/auth/token_store.dart';
import 'package:absen_aaj/core/models/user.dart';
import 'package:absen_aaj/core/storage/device_identity.dart';
import 'package:absen_aaj/features/attendance/application/attendance_sync_worker.dart';
import 'package:absen_aaj/features/attendance/data/attendance_repository.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_local_reader.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_repository.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_models.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_outbox_event.dart';
import 'package:absen_aaj/features/attendance/services/camera_service.dart';
import 'package:absen_aaj/features/attendance/services/location_service.dart';

class FakeTokenStore implements TokenStore {
  String? token;

  final writes = <String>[];
  int clears = 0;

  @override
  Future<void> clear() async {
    clears++;
    token = null;
  }

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async {
    writes.add(value);
    token = value;
  }
}

class FakeCachedUserStore implements CachedUserStore {
  User? user;
  int saves = 0;
  int clears = 0;

  @override
  Future<void> save(User value) async {
    user = value;
    saves++;
  }

  @override
  Future<User?> read() async => user;

  @override
  Future<void> clear() async {
    user = null;
    clears++;
  }
}

class FakeLocalAttendanceReader implements LocalAttendanceReader {
  final events = <AttendanceOutboxEvent>[];
  int calls = 0;

  @override
  Future<List<AttendanceOutboxEvent>> eventsForOwner(
    int ownerUserId, {
    DateTime? from,
    DateTime? to,
  }) async {
    calls++;
    return events.where((event) {
      if (event.ownerUserId != ownerUserId) return false;
      final eventAt = event.eventAt.toLocal();
      if (from != null && eventAt.isBefore(from)) return false;
      if (to != null && eventAt.isAfter(to)) return false;
      return true;
    }).toList(growable: false);
  }
}

class FakeDeviceIdentity implements DeviceIdentity {
  FakeDeviceIdentity({
    this.uuidValue = 'device-uuid-123',
    this.registered = false,
  });

  final String uuidValue;
  bool registered;
  bool marked = false;

  @override
  Future<bool> isRegistered() async => registered;

  @override
  Future<void> markRegistered() async {
    registered = true;
    marked = true;
  }

  @override
  Future<void> resetRegistration() async => registered = false;

  @override
  Future<String> uuid() async => uuidValue;
}

class FakeLocationService implements LocationService {
  FakeLocationService({
    this.reading = const GpsReading(
      latitude: -5.1477,
      longitude: 119.4326,
      accuracyMeters: 20,
    ),
    this.error,
  });

  GpsReading reading;
  Object? error;

  @override
  Future<GpsReading> getLocation() async {
    if (error != null) throw error!;
    return reading;
  }
}

class FakeCameraService implements CameraService {
  FakeCameraService({this.result, this.error, this.returnsNull = false});

  SelfieResult? result;
  Object? error;
  bool returnsNull;

  @override
  Future<SelfieResult?> capture() async {
    if (error != null) throw error!;
    if (returnsNull) return null;
    return result ??
        SelfieResult(
          bytes: [1, 2, 3],
          capturedAt: DateTime(2026, 10, 6, 8, 30),
        );
  }
}

class RecordingAttendanceRepository implements AttendanceRepository {
  RecordingAttendanceRepository({
    this.event,
    this.submitError,
    this.registerError,
    this.deviceInfo,
    this.historyError,
    this.historyEvents = const [],
  });

  AttendanceEvent? event;
  Object? submitError;
  Object? registerError;
  DeviceInfo? deviceInfo;
  Object? historyError;
  List<AttendanceEvent> historyEvents;

  final submitted = <Map<String, dynamic>>[];
  final registeredDevices = <String>[];

  @override
  Future<AttendanceEvent> submitEvent({
    required String clientEventId,
    required String deviceUuid,
    required AttendanceEventType eventType,
    required DateTime eventAt,
    required GpsReading gps,
    required DateTime capturedAt,
    required List<int> photoBytes,
  }) async {
    if (submitError != null) throw submitError!;
    if (event == null) {
      throw StateError('no event configured');
    }
    submitted.add({
      'client_event_id': clientEventId,
      'device_uuid': deviceUuid,
      'event_type': eventType.key,
      'event_at': eventAt,
      'gps': gps,
      'photo_bytes': photoBytes,
    });
    return event!;
  }

  @override
  Future<DeviceInfo> registerDevice({
    required String deviceUuid,
    String? manufacturer,
    String? model,
    String? appVersion,
  }) async {
    if (registerError != null) throw registerError!;
    registeredDevices.add(deviceUuid);
    return deviceInfo ??
        DeviceInfo(id: 1, deviceUuid: deviceUuid, status: 'ACTIVE');
  }

  @override
  Future<List<AttendanceEvent>> history({DateTime? from, DateTime? to}) async {
    if (historyError != null) throw historyError!;
    return historyEvents;
  }
}

AttendanceEvent makeEvent({
  int id = 1,
  String eventType = 'CHECK_IN',
  String status = 'ON_TIME',
  double? distanceMeters,
  String? clientEventId,
}) {
  return AttendanceEvent(
    id: id,
    clientEventId: clientEventId ?? 'client-$id',
    eventType: eventType,
    status: status,
    eventAt: DateTime(2026, 10, 6, 8, 30),
    distanceMeters: distanceMeters,
    locationValid: true,
  );
}

AttendanceOutboxEvent makeOutboxEvent({
  String clientEventId = 'local-event-1',
  int ownerUserId = 1,
  int employeeId = 10,
  AttendanceEventType eventType = AttendanceEventType.checkIn,
  DateTime? eventAt,
  AttendanceOutboxState state = AttendanceOutboxState.pending,
  String? serverStatus,
  int? serverEventId,
}) {
  final at = eventAt ?? DateTime.now();
  return AttendanceOutboxEvent(
    clientEventId: clientEventId,
    ownerUserId: ownerUserId,
    employeeId: employeeId,
    deviceUuid: 'device-uuid-123',
    eventType: eventType,
    eventAt: at,
    capturedAt: at,
    latitude: -5.1477,
    longitude: 119.4326,
    accuracyMeters: 20,
    photoFilename: '$clientEventId.jpg',
    localSequence: 1,
    state: state,
    attemptCount: 0,
    createdAt: at,
    updatedAt: at,
    serverEventId: serverEventId,
    serverStatus: serverStatus,
    serverReceivedAt: state == AttendanceOutboxState.synced ? at : null,
    syncedAt: state == AttendanceOutboxState.synced ? at : null,
  );
}

const testUser = User(
  id: 1,
  name: 'Karyawan',
  email: 'karyawan@example.com',
  role: 'EMPLOYEE',
  isActive: true,
  employee: EmployeeBrief(
    id: 10,
    employeeNumber: 'EMP-10',
    name: 'Karyawan',
    status: 'ACTIVE',
  ),
);

const testUserWithoutEmployee = User(
  id: 1,
  name: 'Karyawan',
  email: 'karyawan@example.com',
  role: 'EMPLOYEE',
  isActive: true,
);

class FakeSessionController extends SessionController {
  FakeSessionController(super._ref, {User? user}) {
    state = SessionState(
      status: SessionStatus.authenticated,
      user: user ?? testUser,
    );
  }
}

class FakeOutboxWriter implements AttendanceOutboxWriter {
  final events = <FakeQueuedEvent>[];
  void Function()? onEnqueue;

  @override
  Future<AttendanceOutboxEvent> enqueue({
    required String clientEventId,
    required int ownerUserId,
    required int employeeId,
    required String deviceUuid,
    required AttendanceEventType eventType,
    required DateTime eventAt,
    required DateTime capturedAt,
    required GpsReading gps,
    required List<int> photoBytes,
  }) async {
    onEnqueue?.call();
    final queued = FakeQueuedEvent(
      clientEventId: clientEventId,
      ownerUserId: ownerUserId,
      employeeId: employeeId,
      deviceUuid: deviceUuid,
      eventType: eventType,
      eventAt: eventAt,
      capturedAt: capturedAt,
      gps: gps,
      photoBytes: List<int>.of(photoBytes),
    );
    events.add(queued);
    return queued.toEvent();
  }
}

class FakeQueuedEvent {
  FakeQueuedEvent({
    required this.clientEventId,
    required this.ownerUserId,
    required this.employeeId,
    required this.deviceUuid,
    required this.eventType,
    required this.eventAt,
    required this.capturedAt,
    required this.gps,
    required this.photoBytes,
  });

  final String clientEventId;
  final int ownerUserId;
  final int employeeId;
  final String deviceUuid;
  final AttendanceEventType eventType;
  final DateTime eventAt;
  final DateTime capturedAt;
  final GpsReading gps;
  final List<int> photoBytes;

  AttendanceOutboxEvent toEvent() => AttendanceOutboxEvent.pending(
    clientEventId: clientEventId,
    ownerUserId: ownerUserId,
    employeeId: employeeId,
    deviceUuid: deviceUuid,
    eventType: eventType,
    eventAt: eventAt,
    capturedAt: capturedAt,
    latitude: gps.latitude,
    longitude: gps.longitude,
    accuracyMeters: gps.accuracyMeters,
    photoFilename: '$clientEventId.jpg',
    createdAt: DateTime.utc(2026, 10, 6, 8, 30),
  );
}

class FakeSyncRunner implements AttendanceSyncRunner {
  FutureOr<AttendanceSyncRunResult> Function(int, int)? onSync;
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<AttendanceSyncRunResult> syncNow({
    required int ownerUserId,
    required int employeeId,
  }) async {
    calls++;
    if (gate != null) await gate!.future;
    return onSync?.call(ownerUserId, employeeId) ??
        const AttendanceSyncRunResult();
  }
}
