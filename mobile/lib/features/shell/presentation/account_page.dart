import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final user = session.user;
    final employee = user?.employee;

    return Scaffold(
      appBar: AppBar(title: const Text('Akun')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CircleAvatar(
            radius: 40,
            child: Text(
              (user?.name.isNotEmpty ?? false)
                  ? user!.name.substring(0, 1).toUpperCase()
                  : '?',
              style: const TextStyle(fontSize: 28),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(user?.name ?? '-',
                style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                _tile(Icons.badge_outlined, 'Email', user?.email ?? '-'),
                _tile(Icons.person_outline, 'Role', _roleLabel(user?.role)),
                _tile(
                  Icons.tag,
                  'No. Karyawan',
                  employee?.employeeNumber ?? '-',
                ),
                _tile(
                  Icons.business_outlined,
                  'Status Karyawan',
                  employee?.status ?? '-',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => ref.read(sessionControllerProvider.notifier).logout(),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Widget _tile(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(label),
      subtitle: Text(value),
    );
  }

  String _roleLabel(String? role) => switch (role) {
        'ADMIN' => 'Admin',
        'HR' => 'HR',
        'EMPLOYEE' => 'Karyawan',
        _ => role ?? '-',
      };
}