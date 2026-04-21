import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

class AppLogger {
  static bool _initialized = false;

  static void init({Level? level}) {
    if (_initialized) return;
    _initialized = true;

    Logger.root.level = level ?? (kDebugMode ? Level.ALL : Level.WARNING);
    Logger.root.onRecord.listen((rec) {
      final ts = rec.time.toIso8601String();
      final msg = '$ts ${rec.level.name} ${rec.loggerName}: ${rec.message}';
      debugPrint(msg);
      if (rec.error != null) debugPrint('error: ${rec.error}');
      if (rec.stackTrace != null) debugPrint('${rec.stackTrace}');
    });
  }

  static String maskToken(String? token) {
    if (token == null || token.isEmpty) return '<null>';
    if (token.length <= 10) return '***';
    return '${token.substring(0, 6)}...${token.substring(token.length - 4)}';
  }

  static String safeJson(dynamic value, {int max = 2000}) {
    try {
      final s = jsonEncode(value);
      if (s.length <= max) return s;
      return '${s.substring(0, max)}... (truncated, ${s.length} chars)';
    } catch (_) {
      final s = value.toString();
      if (s.length <= max) return s;
      return '${s.substring(0, max)}... (truncated, ${s.length} chars)';
    }
  }
}

