import 'package:flutter/material.dart';
import 'config.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/update_service.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initSupabase();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => UpdateService.check(navigatorKey));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Check again when the app returns to the foreground, since counters leave it open for days.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) UpdateService.check(navigatorKey);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Okebori POS',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: AuthGate(
        title: 'Okebori POS',
        subtitle: 'Courier Management System',
        homeBuilder: (onSignedOut) => HomeShell(onSignedOut: onSignedOut),
      ),
    );
  }
}
