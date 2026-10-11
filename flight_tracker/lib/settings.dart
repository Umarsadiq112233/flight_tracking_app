import 'package:shared_preferences/shared_preferences.dart';

/// Optional API keys, stored on device.
class AppSettings {
  static const _kAeroDataBox = 'aerodatabox_key';
  static String? aeroDataBoxKey;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    aeroDataBoxKey = p.getString(_kAeroDataBox);
  }

  static Future<void> setAeroDataBoxKey(String? key) async {
    final p = await SharedPreferences.getInstance();
    final k = key?.trim();
    if (k == null || k.isEmpty) {
      await p.remove(_kAeroDataBox);
      aeroDataBoxKey = null;
    } else {
      await p.setString(_kAeroDataBox, k);
      aeroDataBoxKey = k;
    }
  }

  static bool get hasScheduleApi => aeroDataBoxKey?.isNotEmpty == true;
}
