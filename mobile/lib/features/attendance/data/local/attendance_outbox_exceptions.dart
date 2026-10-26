class AttendanceOutboxConflictException implements Exception {
  const AttendanceOutboxConflictException(this.clientEventId);

  static const code = 'CLIENT_EVENT_ID_CONFLICT';

  final String clientEventId;

  @override
  String toString() => '$code: $clientEventId';
}

class AttendanceOutboxTransitionException implements Exception {
  const AttendanceOutboxTransitionException(
    this.clientEventId, {
    required this.operation,
  });

  static const code = 'INVALID_OUTBOX_TRANSITION';

  final String clientEventId;
  final String operation;

  @override
  String toString() => '$code: $operation ($clientEventId)';
}
