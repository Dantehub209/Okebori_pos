import 'package:flutter/material.dart';
import '../config.dart';
import '../screens/login_screen.dart';
import 'admin_shell.dart';
import 'admin_theme.dart';

/// Web admin for managers, opened in a laptop browser.
/// Build with: flutter build web -t lib/admin/admin_main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(MaterialApp(
    title: 'Okebori Admin',
    debugShowCheckedModeBanner: false,
    theme: buildAdminTheme(),
    home: AuthGate(
      title: 'Okebori Admin',
      subtitle: 'Sign in with your manager account',
      homeBuilder: (onSignedOut) => AdminShell(onSignedOut: onSignedOut),
    ),
  ));
}
