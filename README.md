# Okebori POS

Courier booking app for branch cashiers (Android) plus a web admin for managers.
Backend: Supabase.

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
an Overview dashboard (today across all branches), parcels, branches, pricing,
staff and app updates. Super Admins see
every page; Branch Managers see the Overview and parcels for their branch;
cashiers are turned away.

- Try it locally: `flutter run -d chrome -t lib/admin/admin_main.dart`
- Online: every push to `main` rebuilds the admin and publishes it to GitHub
  Pages at https://dantehub209.github.io/Okebori_pos/ (see
  `.github/workflows/admin-web.yml`). To republish without a code change, run
  the "Deploy web admin" workflow from the repo's Actions tab.

Access control in the app is only cosmetic: make sure Supabase Row Level
Security only lets admins change branches, pricing, users and app_version.

## Supabase setup (run in the SQL editor, in this order)

1. **Save your current access rules first.** Run
   `select * from pg_policies where schemaname = 'public';` and download the result.
2. `supabase/security.sql`: access rules. Cashiers can book and take payments
   but cannot edit or delete money, prices, branches or staff. Inactive staff
   lose access. The public can read nothing.
3. `supabase/book_parcel.sql`: saves a booking (customers, parcel, payment,
   receipt) in one step, so a dropped connection can't leave half a booking.
   **Run this before giving cashiers an APK built from this version.**
4. `supabase/app_version.sql`: the update alert.

All three files are safe to run again. After step 2, sign in as a cashier and
make a test booking to confirm everything still works.

### Add staff function

"Add staff" in the web admin uses a server function so the admin stays signed in.
Deploy it once: Supabase dashboard > **Edge Functions** > **Deploy a new function**
> **Via Editor**, name it `create-staff`, paste the contents of
`supabase/functions/create-staff/index.ts`, and click **Deploy**.
(Or with the Supabase CLI: `supabase functions deploy create-staff`.)

## Signing key (do once, before the first APK you send out)

Phones only accept an update if it is signed with the same key as the installed
app. Create the key once and keep it safe; if it is lost, every phone has to
uninstall and reinstall.

1. On your computer (Windows PowerShell; `keytool` comes with Android Studio):
   ```
   keytool -genkey -v -keystore $env:USERPROFILE\okebori-upload.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
   Choose a strong password and write it down.
2. Create `android/key.properties` (it is ignored by git; never upload it):
   ```
   storePassword=YOUR_PASSWORD
   keyPassword=YOUR_PASSWORD
   keyAlias=upload
   storeFile=C:/Users/YOUR_NAME/okebori-upload.jks
   ```
3. Back up `okebori-upload.jks` and the password somewhere safe (not GitHub).

Without `key.properties`, release builds fall back to a temporary debug key and
print a warning; don't send those APKs to clients.

The app ID is `com.okebori.pos`. Phones with the old test build
(`com.example.okebori_pos`) should uninstall it once and install the new APK;
every update after that installs over the top.
