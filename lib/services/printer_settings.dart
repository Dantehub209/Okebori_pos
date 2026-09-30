import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which paired Bluetooth printer this device prints to.
class PrinterSettings {
  static const _macKey = 'printer_mac';
  static const _nameKey = 'printer_name';

  static Future<({String mac, String name})?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final mac = prefs.getString(_macKey);
    if (mac == null) return null;
    return (mac: mac, name: prefs.getString(_nameKey) ?? mac);
  }

  static Future<void> save(String mac, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_macKey, mac);
    await prefs.setString(_nameKey, name);
  }
}
