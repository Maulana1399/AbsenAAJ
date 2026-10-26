import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/presentation/auth_gate.dart';
import 'core/navigation/app_navigator.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: AbsenApp()));
}

class AbsenApp extends StatelessWidget {
  const AbsenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Absen AAJ',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1A5CFF),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}