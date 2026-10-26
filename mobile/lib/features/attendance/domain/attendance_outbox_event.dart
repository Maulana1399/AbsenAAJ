import 'attendance_models.dart';
import 'attendance_outbox_time.dart';

enum AttendanceOutboxState {
  pending,
  syncing,
  synced,
  rejected;

  static AttendanceOutboxState fromDatabase(String value) =>
      AttendanceOutboxState.values.firstWhere(
        (state) => state.name == value,
        orElse: () => throw FormatException('Unknown outbox state: $value'),
      );
}

class AttendanceOutboxEvent {
  const AttendanceOutboxEvent({
    required this.clientEventId,
    required this.ownerUserId,
    required this.employeeId,
    required this.deviceUuid,
    required this.eventType,
    required this.eventAt,
    required this.capturedAt,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.photoFilename,
    required this.localSequence,
    required this.state,
    required this.attemptCount,
    required this.createdAt,
    required this.updatedAt,
    this.nextAttemptAt,
    this.syncStartedAt,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.serverEventId,
    this.serverStatus,
    this.serverReceivedAt,
    this.syncedAt,
  });

  factory AttendanceOutboxEvent.pending({
    required String clientEventId,
    required int ownerUserId,
    required int employeeId,
    required String deviceUuid,
    required AttendanceEventType eventType,
    required DateTime eventAt,
    required DateTime capturedAt,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required String photoFilename,
    required DateTime createdAt,
    int localSequence = 0,
  }) {
    return AttendanceOutboxEvent(
      clientEventId: clientEventId,
      ownerUserId: ownerUserId,
      employeeId: employeeId,
      deviceUuid: deviceUuid,
      eventType: eventType,
      eventAt: eventAt,
      capturedAt: capturedAt,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      photoFilename: photoFilename,
      localSequence: localSequence,
      state: AttendanceOutboxState.pending,
      attemptCount: 0,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  final String clientEventId;
  final int ownerUserId;
  final int employeeId;
  final String deviceUuid;
  final AttendanceEventType eventType;
  final DateTime eventAt;
  final DateTime capturedAt;
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final String photoFilename;
  final int localSequence;
  final AttendanceOutboxState state;
  final int attemptCount;
  final DateTime? nextAttemptAt;
  final DateTime? syncStartedAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final int? serverEventId;
  final String? serverStatus;
  final DateTime? serverReceivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? syncedAt;

  Map<String, Object?> toDatabase() {
    return {
      'client_event_id': clientEventId,
      'owner_user_id': ownerUserId,
      'employee_id': employeeId,
      'device_uuid': deviceUuid,
      'event_type': eventType.key,
      'event_at': formatOutboxTimestamp(eventAt),
      'captured_at': formatOutboxTimestamp(capturedAt),
      'latitude': latitude,
      'longitude': longitude,
      'accuracy_meters': accuracyMeters,
      'photo_filename': photoFilename,
      'local_sequence': localSequence,
      'state': state.name,
      'attempt_count': attemptCount,
      'next_attempt_at': formatNullableOutboxTimestamp(nextAttemptAt),
      'sync_started_at': formatNullableOutboxTimestamp(syncStartedAt),
      'last_error_code': lastErrorCode,
      'last_error_message': lastErrorMessage,
      'server_event_id': serverEventId,
      'server_status': serverStatus,
      'server_received_at': formatNullableOutboxTimestamp(serverReceivedAt),
      'created_at': formatOutboxTimestamp(createdAt),
      'updated_at': formatOutboxTimestamp(updatedAt),
      'synced_at': formatNullableOutboxTimestamp(syncedAt),
    };
  }

  factory AttendanceOutboxEvent.fromDatabase(Map<String, Object?> row) {
    return AttendanceOutboxEvent(
      clientEventId: row['client_event_id'] as String,
      ownerUserId: row['owner_user_id'] as int,
      employeeId: row['employee_id'] as int,
      deviceUuid: row['device_uuid'] as String,
      eventType: AttendanceEventType.fromKey(row['event_type'] as String),
      eventAt: parseOutboxTimestamp(row['event_at'] as String),
      capturedAt: parseOutboxTimestamp(row['captured_at'] as String),
      latitude: (row['latitude'] as num).toDouble(),
      longitude: (row['longitude'] as num).toDouble(),
      accuracyMeters: (row['accuracy_meters'] as num).toDouble(),
      photoFilename: row['photo_filename'] as String,
      localSequence: (row['local_sequence'] as num).toInt(),
      state: AttendanceOutboxState.fromDatabase(row['state'] as String),
      attemptCount: row['attempt_count'] as int,
      nextAttemptAt: parseNullableOutboxTimestamp(row['next_attempt_at']),
      syncStartedAt: parseNullableOutboxTimestamp(row['sync_started_at']),
      lastErrorCode: row['last_error_code'] as String?,
      lastErrorMessage: row['last_error_message'] as String?,
      serverEventId: row['server_event_id'] as int?,
      serverStatus: row['server_status'] as String?,
      serverReceivedAt: parseNullableOutboxTimestamp(row['server_received_at']),
      createdAt: parseOutboxTimestamp(row['created_at'] as String),
      updatedAt: parseOutboxTimestamp(row['updated_at'] as String),
      syncedAt: parseNullableOutboxTimestamp(row['synced_at']),
    );
  }
}
