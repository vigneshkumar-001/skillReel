import 'package:shared_preferences/shared_preferences.dart';

class ReelsPlaybackPrefs {
  static const _mutedKey = 'reels_muted';

  static Future<bool> getMuted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_mutedKey) ?? false;
  }

  static Future<void> setMuted(bool muted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mutedKey, muted);
  }
}
