import '../../domain/attendance_models.dart';
import '../../domain/attendance_outbox_event.dart';
import 'attendance_outbox_store.dart';

/// Read-only view over the durable outbox for offline-first screens.
///
/// The outbox is the local source of truth while the server is unreachable.
/// Synced rows are retained until an explicit purge, so they can also back the
/// offline history view.
abstract interface class LocalAttendanceReader {
  Future<List<AttendanceOutboxEvent>> eventsForOwner(
    int ownerUserId, {
    DateTime? from,
    DateTime? to,
  });
}

class OutboxLocalAttendanceReader implements LocalAttendanceReader {
  OutboxLocalAttendanceReader(this._store);

  final AttendanceOutboxStore _store;

  @override
  Future<List<AttendanceOutboxEvent>> eventsForOwner(
    int ownerUserId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final events = await _store.listForOwner(ownerUserId);
    return events.where((event) {
      final eventAt = event.eventAt.toLocal();
      if (from != null && eventAt.isBefore(from)) return false;
      if (to != null && eventAt.isAfter(to)) return false;
      return true;
    }).toList(growable: false);
  }
}

/// Adapts a queued local event into the display model used by home/history.
///
/// The server remains the source of truth for accepted events; local-only
/// rows use explicit pseudo statuses so the UI can show them as pending.
AttendanceEvent localAttendanceEvent(AttendanceOutboxEvent event) {
  final status = switch (event.state) {
    AttendanceOutboxState.synced => event.serverStatus ?? 'SYNCED',
    AttendanceOutboxState.rejected => 'REJECTED',
    _ => 'PENDING_SYNC',
  };

  return AttendanceEvent(
    id: event.serverEventId ?? 0,
    clientEventId: event.clientEventId,
    eventType: event.eventType.key,
    status: status,
    employeeId: event.employeeId,
    eventAt: event.eventAt,
    serverReceivedAt: event.serverReceivedAt,
    latitude: event.latitude,
    longitude: event.longitude,
    accuracyMeters: event.accuracyMeters,
  );
}

bool isLocallyPending(AttendanceOutboxEvent event) =>
    event.state == AttendanceOutboxState.pending ||
    event.state == AttendanceOutboxState.syncing;
