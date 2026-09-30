# okebori_pos

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Releasing an update to clients

The app checks the `app_version` table in Supabase every time it opens (and
when it comes back to the foreground). If a newer build exists, cashiers see an
**Update Available** dialog with a download button.

One-time setup: run `supabase/app_version.sql` in the Supabase SQL editor.

For each release:

1. Bump `version` in `pubspec.yaml`, always increasing the number after `+`
   (e.g. `1.0.0+1` → `1.0.1+2`).
2. Build the APK: `flutter build apk --release`
   (output: `build/app/outputs/flutter-apk/app-release.apk`).
3. Upload the APK somewhere with a direct download link (e.g. Supabase Storage,
   a public bucket).
4. In the web admin, open **App updates** and enter the new build number
   (the number after `+` in `pubspec.yaml`) and the download link.
   To force everyone off an old version, also set **Minimum build allowed** to
   the new build number; older builds then can't close the dialog until they update.

Always build releases with the same signing key, or Android will refuse to
install the update over the existing app.

## Web admin (for managers on a laptop)

Settings are not in the phone app. Managers use the web admin in a browser:
reports, parcels, branches, pricing, staff and app updates. Super Admins see
every page; Branch Managers see reports and parcels; cashiers are turned away.

- Try it locally: `flutter run -d chrome -t lib/admin/admin_main.dart`
- Build the site: `flutter build web --release -t lib/admin/admin_main.dart`
  and upload the `build/web` folder to any static host (GitHub Pages, Netlify,
  Firebase Hosting, etc.). If it is served from a sub-folder, add
  `--base-href /folder-name/` to the build command.

Access control in the app is only cosmetic: make sure Supabase Row Level
Security only lets admins change branches, pricing, users and app_version.
