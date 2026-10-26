import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/presentation/login_page.dart';
import '../../../features/shell/presentation/main_shell.dart';
import '../session_controller.dart';

/// Routes between the login page and the main shell based on session state.
/// Triggers session restoration once on app start.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sessionControllerProvider.notifier).restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);

    if (session.isAuthenticated) {
      return const MainShell();
    }

    if (session.status == SessionStatus.initial ||
        session.status == SessionStatus.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return const LoginPage();
  }
}