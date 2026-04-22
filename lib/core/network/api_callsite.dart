class ApiCallsite {
  static String? infer({StackTrace? stackTrace}) {
    final raw = (stackTrace ?? StackTrace.current).toString().split('\n');
    for (final line in raw) {
      final t = line.trim();
      if (!t.contains('package:') && !t.contains('file://')) continue;
      if (t.contains('dart:')) continue;
      if (t.contains('package:dio/')) continue;
      if (t.contains('package:flutter/')) continue;
      if (t.contains('api_client.dart')) continue;
      if (t.contains('api_interceptor.dart')) continue;

      final candidate = _extractLocation(t);
      final normalized = candidate == null ? null : _normalizeLocation(candidate);
      if (normalized != null && normalized.isNotEmpty) return normalized;
    }
    return null;
  }

  static String? _extractLocation(String stackLine) {
    final open = stackLine.indexOf('(');
    final close = stackLine.lastIndexOf(')');
    if (open >= 0 && close > open) {
      final inside = stackLine.substring(open + 1, close).trim();
      if (inside.isNotEmpty) return inside;
    }

    final m = RegExp(
      r'(package:[^\s\)]+\.dart:\d+:\d+|file:\/\/[^\s\)]+\.dart:\d+:\d+)',
    ).firstMatch(stackLine);
    return m?.group(1);
  }

  static String? _normalizeLocation(String location) {
    var loc = location.trim();
    if (loc.isEmpty) return null;

    if (loc.startsWith('package:skilreel_app/')) {
      loc = 'lib/${loc.substring('package:skilreel_app/'.length)}';
    }

    final lower = loc.toLowerCase();
    final libIdx = lower.indexOf('/lib/');
    if (libIdx >= 0) {
      loc = 'lib/${loc.substring(libIdx + '/lib/'.length)}';
    }

    final winLibIdx = lower.indexOf('\\lib\\');
    if (winLibIdx >= 0) {
      loc = 'lib/${loc.substring(winLibIdx + '\\lib\\'.length)}';
    }

    return loc;
  }
}

