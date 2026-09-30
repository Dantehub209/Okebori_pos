import 'package:flutter/material.dart';
import '../config.dart';
import '../screens/login_screen.dart';
import '../theme.dart';
import 'admin_shell.dart';

/// Web admin for managers, opened in a laptop browser.
/// Build with: flutter build web -t lib/admin/admin_main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(MaterialApp(
    title: 'Okebori Admin',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: AuthGate(
      title: 'Okebori Admin',
      subtitle: 'Settings and reports for managers',
      homeBuilder: (onSignedOut) => AdminShell(onSignedOut: onSignedOut),
    ),
  ));
}
