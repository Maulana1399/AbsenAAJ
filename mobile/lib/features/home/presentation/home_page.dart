import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/format/attendance_format.dart';
import '../../attendance/application/attendance_controller.dart';
import '../../attendance/application/attendance_sync_providers.dart';
import '../../attendance/application/device_registration_controller.dart';
import '../../attendance/domain/attendance_models.dart';
import '../application/home_controller.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deviceRegistrationProvider.notifier).ensureRegistered();
      ref.read(homeControllerProvider.notifier).reload();
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
      ref.read(homeControllerProvider.notifier).reload();
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

  @override
  Widget build(BuildContext context) {
    _listenForSubmissionEnd();

    final session = ref.watch(sessionControllerProvider);
    final home = ref.watch(homeControllerProvider);
    final submission = ref.watch(attendanceSubmissionProvider);
    final device = ref.watch(deviceRegistrationProvider);

    final user = session.user;
    final name = user?.name ?? 'Karyawan';
    final employeeNumber =
        home.employeeNumber ?? user?.employee?.employeeNumber;

    return RefreshIndicator(
      onRefresh: () async {
        _triggerSync();
        await ref.read(homeControllerProvider.notifier).reload();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Text('Absen AAJ', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Text(
            'Halo, $name',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (employeeNumber != null && employeeNumber.isNotEmpty)
            Text('NIP: $employeeNumber',
                style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          _StatusCard(today: home.today),
          const SizedBox(height: 24),
          _buildDeviceState(device),
          const SizedBox(height: 16),
          _buildAttendanceButton(home.today.status, submission.isSubmitting),
          const SizedBox(height: 16),
          if (home.usingLocalData)
            Text(
              'Menampilkan data tersimpan di perangkat. '
              'Sinkronisasi akan dicoba saat koneksi tersedia.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (home.phase == HomeLoadPhase.error)
            Text(
              home.errorMessage ?? 'Gagal memuat status.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }

  void _listenForSubmissionEnd() {
    ref.listen(attendanceSubmissionProvider, (previous, next) {
      if (next.isSuccess && previous?.isSuccess != true) {
        final event = next.event;
        if (event != null) _showSuccessDialog(event);
        return;
      }
      if (next.isQueued && previous?.isQueued != true) {
        _showQueued(next);
        return;
      }
      if (next.isError) {
        _showError(next);
      }
    });
  }

  void _showQueued(AttendanceSubmissionState next) {
    final message =
        next.errorMessage ?? AttendanceSubmissionController.localQueuedMessage;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    ref.read(homeControllerProvider.notifier).reload();
  }

  Future<void> _showSuccessDialog(AttendanceEvent event) async {
    final typeLabel = event.isCheckIn ? 'Check In' : 'Check Out';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: const Text('Absensi berhasil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(typeLabel),
            Text(formatTime(event.eventAt)),
            const SizedBox(height: 8),
            Text('Status: ${attendanceStatusLabel(event.status)}'),
            Text('Jarak: ${formatDistance(event.distanceMeters)}'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(attendanceSubmissionProvider.notifier).reset();
              ref.read(homeControllerProvider.notifier).reload();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showError(AttendanceSubmissionState next) {
    final message =
        next.errorMessage ?? 'Terjadi kesalahan. Silakan coba lagi.';
    final isForeverDenied = next.errorCode == 'LOCATION_PERMISSION_FOREVER';

    if (isForeverDenied) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Akses lokasi dibutuhkan'),
          content: const Text(
            'Akses lokasi ditolak secara permanen. Silakan izinkan akses lokasi melalui pengaturan agar absensi dapat berjalan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Nanti'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                Geolocator.openAppSettings();
              },
              child: const Text('Buka Pengaturan'),
            ),
          ],
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildDeviceState(DeviceRegistrationState device) {
    if (device.phase == DeviceRegistrationPhase.registering) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Mendaftarkan device...'),
        ],
      );
    }
    if (device.phase == DeviceRegistrationPhase.failed) {
      return Row(
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(device.message ?? 'Gagal mendaftarkan device.'),
          ),
          TextButton(
            onPressed: () => ref
                .read(deviceRegistrationProvider.notifier)
                .ensureRegistered(),
            child: const Text('Coba lagi'),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildAttendanceButton(
    TodayAttendanceStatus status,
    bool submitting,
  ) {
    final ButtonStyle? style;
    if (status == TodayAttendanceStatus.none) {
      style = FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        backgroundColor: Theme.of(context).colorScheme.primary,
      );
    } else if (status == TodayAttendanceStatus.checkedIn) {
      style = FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        backgroundColor: Theme.of(context).colorScheme.tertiary,
      );
    } else {
      style = FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        disabledBackgroundColor:
            Theme.of(context).colorScheme.surfaceContainerHighest,
      );
    }

    final label = switch (status) {
      TodayAttendanceStatus.none => 'CHECK IN',
      TodayAttendanceStatus.checkedIn => 'CHECK OUT',
      TodayAttendanceStatus.done => 'Absensi Selesai',
    };

    final onPressed = switch (status) {
      TodayAttendanceStatus.none => submitting
          ? null
          : () =>
              ref.read(attendanceSubmissionProvider.notifier).submitCheckIn(),
      TodayAttendanceStatus.checkedIn => submitting
          ? null
          : () =>
              ref.read(attendanceSubmissionProvider.notifier).submitCheckOut(),
      TodayAttendanceStatus.done => null,
    };

    return FilledButton(
      onPressed: onPressed,
      style: style,
      child: submitting
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            )
          : Text(label, style: const TextStyle(fontSize: 18)),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.today});

  final TodayAttendance today;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (today.status) {
      TodayAttendanceStatus.none => ('Belum Check In', Icons.schedule),
      TodayAttendanceStatus.checkedIn => (
          'CHECKED IN',
          Icons.check_circle_outline
        ),
      TodayAttendanceStatus.done => ('SELESAI', Icons.task_alt),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Status hari ini',
                    style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Check-in: ${formatTime(today.checkIn?.eventAt)}'),
            if (today.checkOut != null)
              Text('Check-out: ${formatTime(today.checkOut?.eventAt)}'),
          ],
        ),
      ),
    );
  }
}
