import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/format/attendance_format.dart';
import '../../attendance/application/attendance_sync_providers.dart';
import '../../attendance/domain/attendance_models.dart';
import '../application/history_controller.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(historyControllerProvider.notifier).load();
      _triggerSync();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggerSync();
      ref.read(historyControllerProvider.notifier).load();
    }
  }

  void _triggerSync() {
    final session = ref.read(sessionControllerProvider);
    final user = session.user;
    final employee = user?.employee;
    if (!session.isAuthenticated || user == null || employee == null) return;
    Future.microtask(() {
      try {
        ref.read(attendanceSyncRunnerProvider).syncNow(
              ownerUserId: user.id,
              employeeId: employee.id,
            );
      } catch (_) {
        // Best-effort sync trigger.
      }
    });
  }

  Future<void> _pickFrom() async {
    final state = ref.read(historyControllerProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: state.from ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      ref.read(historyControllerProvider.notifier).load(from: picked);
    }
  }

  Future<void> _pickTo() async {
    final state = ref.read(historyControllerProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: state.to ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      ref.read(historyControllerProvider.notifier).load(to: picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Absensi')),
      body: Column(
        children: [
          if (history.usingLocalData)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  const Icon(Icons.offline_pin_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Menampilkan data tersimpan di perangkat.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: _dateButton(
                    label: 'Dari: ${formatDate(history.from ?? DateTime(2020, 1, 1))}',
                    onTap: _pickFrom,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _dateButton(
                    label: 'Sampai: ${formatDate(history.to ?? DateTime.now())}',
                    onTap: _pickTo,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(history)),
        ],
      ),
    );
  }

  Widget _dateButton({required String label, required VoidCallback onTap}) {
    return OutlinedButton(
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _buildBody(HistoryState history) {
    switch (history.phase) {
      case HistoryLoadPhase.loading:
        return const Center(child: CircularProgressIndicator());
      case HistoryLoadPhase.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(history.errorMessage ?? 'Gagal memuat riwayat.'),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => ref
                    .read(historyControllerProvider.notifier)
                    .load(from: history.from, to: history.to),
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        );
      case HistoryLoadPhase.ready:
        if (history.events.isEmpty) {
          return const Center(child: Text('Belum ada data absensi.'));
        }
        return _GroupedList(events: history.events);
    }
  }
}

/// Groups events by date and renders a row per event with the server's
/// status. Photo hash is intentionally not shown to the employee.
class _GroupedList extends StatelessWidget {
  const _GroupedList({required this.events});

  final List<AttendanceEvent> events;

  @override
  Widget build(BuildContext context) {
    final grouped = <DateTime, List<AttendanceEvent>>{};
    for (final event in events) {
      final local = event.eventAt?.toLocal();
      final day = local == null
          ? DateTime(1970)
          : DateTime(local.year, local.month, local.day);
      grouped.putIfAbsent(day, () => []).add(event);
    }

    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: dates.length,
      itemBuilder: (context, index) {
        final day = dates[index];
        final dayEvents = grouped[day]!;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDate(day),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...dayEvents.map((e) => _eventRow(context, e)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _eventRow(BuildContext context, AttendanceEvent event) {
    final isCheckIn = event.isCheckIn;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isCheckIn ? Icons.login : Icons.logout,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(isCheckIn ? 'Check In' : 'Check Out'),
          const Spacer(),
          Text(formatTime(event.eventAt)),
          const SizedBox(width: 12),
          Chip(label: Text(attendanceStatusLabel(event.status))),
        ],
      ),
    );
  }
}