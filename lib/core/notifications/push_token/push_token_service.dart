import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../network/api_error_message.dart';
import '../../services/log.dart';
import '../../services/storage_service.dart';
import 'push_token_repository.dart';

class PushTokenService {
  static const _kLastToken = 'push_last_token';
  static const _kLastSentAt = 'push_last_sent_at';

  final PushTokenRepository _repo;

  PushTokenService({PushTokenRepository? repo})
      : _repo = repo ?? PushTokenRepository();

  Future<void> registerIfPossible({
    required String? pushToken,
    required String source,
  }) async {
    final token = (pushToken ?? '').trim();
    if (token.isEmpty) return;

    // Avoid doing anything if user is not authenticated yet.
    final jwt = await StorageService.instance.getToken();
    if (jwt == null || jwt.trim().isEmpty) {
      log.tag('PushToken').i('Skip push token register (no auth yet).');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastToken = prefs.getString(_kLastToken) ?? '';
      final lastSentAt = prefs.getInt(_kLastSentAt) ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // If token didn't change and it was sent recently, skip.
      if (lastToken == token &&
          (nowMs - lastSentAt) < const Duration(hours: 12).inMilliseconds) {
        return;
      }

      final deviceId = await StorageService.instance.getOrCreateDeviceId();
      final info = await PackageInfo.fromPlatform();

      final locale = PlatformDispatcher.instance.locale.toLanguageTag();
      final tz = _timezoneLabel();
      final platform = _platformLabel();

      final payload = <String, dynamic>{
        'token': token,
        'platform': platform,
        'deviceId': deviceId,
        'appVersion': '${info.version}+${info.buildNumber}',
        'locale': locale,
        'timezone': tz,
        'source': source,
      };

      await _repo.savePushToken(payload);

      await prefs.setString(_kLastToken, token);
      await prefs.setInt(_kLastSentAt, nowMs);

      log
          .tag('PushToken')
          .i('Push token saved (platform=$platform, source=$source)');
    } catch (e) {
      log
          .tag('PushToken')
          .w('Push token register failed: ${apiErrorMessage(e)}');
    }
  }

  static String _platformLabel() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  static String _timezoneLabel() {
    final name = DateTime.now().timeZoneName.trim();
    final off = DateTime.now().timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final hh = off.inHours.abs().toString().padLeft(2, '0');
    final mm = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final offset = 'GMT$sign$hh:$mm';
    if (name.isEmpty) return offset;
    if (name == offset) return name;
    return '$name ($offset)';
  }
}
