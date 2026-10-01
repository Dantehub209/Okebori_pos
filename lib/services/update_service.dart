import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks the `app_version` table in Supabase and tells the user when a
/// newer APK is available. Builds below `min_build` cannot be dismissed.
class UpdateService {
  static bool _dialogOpen = false;

  static Future<void> check(GlobalKey<NavigatorState> navigatorKey) async {
    if (_dialogOpen) return;
    try {
      final row = await Supabase.instance.client
          .from('app_version')
          .select('latest_build, min_build, apk_url, release_notes')
          .eq('id', 1)
          .maybeSingle();
      if (row == null) return;

      final info = await PackageInfo.fromPlatform();
      // Split APKs add 1000/2000/4000 per phone type (e.g. build 2 becomes 2002 on arm64)
      final currentBuild = (int.tryParse(info.buildNumber) ?? 0) % 1000;
      final latestBuild = row['latest_build'] as int;
      final minBuild = row['min_build'] as int;
      if (currentBuild >= latestBuild) return;

      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;

      final forced = currentBuild < minBuild;
      final apkUrl = row['apk_url'] as String;
      final notes = row['release_notes'] as String?;

      _dialogOpen = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: !forced,
        builder: (context) => PopScope(
          canPop: !forced,
          child: AlertDialog(
            title: Text(forced ? 'Update Required' : 'Update Available'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(forced
                    ? 'This version of Okebori POS is no longer supported. Please install the latest version to continue.'
                    : 'A new version of Okebori POS is available.'),
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text("What's new:", style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(notes),
                ],
                const SizedBox(height: 12),
                Text('Installed: ${info.version} (build $currentBuild)', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            actions: [
              if (!forced)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Later'),
                ),
              ElevatedButton.icon(
                onPressed: () => launchUrl(Uri.parse(apkUrl), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.download),
                label: const Text('Download Update'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      // No network or table not set up yet: let the app carry on.
      debugPrint('Update check failed: $e');
    } finally {
      _dialogOpen = false;
    }
  }
}
