import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'core/services/crashlytics_log_settings.dart';

class CrashlyticsApiLogger {
  static const int _keyMaxChars = 900;
  static const int _logMaxChars = 3500;
  static const int _infoMaxChars = 800;

  static const Set<String> _sensitiveKeys = {
    'password',
    'token',
    'accesstoken',
    'refreshtoken',
    'authorization',
    'otp',
    'secret',
    'cookie',
    'cookies',
  };

  static Future<void> logDioError(
    DioException err, {
    String? screen,
    bool forceSendNow = false,
  }) async {
    if (!CrashlyticsLogSettings.apiLoggingEnabled) return;
    try {
      final ro = err.requestOptions;
      final endpoint = ro.uri.toString();
      final method = ro.method;
      final statusCode = err.response?.statusCode;

      final requestHeaders = _safeHeadersString(ro.headers);
      final responseHeaders =
          _safeHeadersString(err.response?.headers.map ?? const {});

      final requestBody = _safeBodyString(ro.data);
      final responseBody = _safeBodyString(err.response?.data);
      final errorMessage = _extractBackendMessage(err.response?.data) ??
          err.message ??
          err.error?.toString() ??
          err.type.toString();

      final crash = FirebaseCrashlytics.instance;
      await crash.setCustomKey(
          'api_endpoint', _truncate(endpoint, _keyMaxChars));
      await crash.setCustomKey('api_method', method);
      await crash.setCustomKey('api_status_code', statusCode ?? -1);
      if ((screen ?? '').trim().isNotEmpty) {
        await crash.setCustomKey(
          'api_screen',
          _truncate(screen!.trim(), _keyMaxChars),
        );
      }
      await crash.setCustomKey(
        'api_error_message',
        _truncate(errorMessage, _keyMaxChars),
      );
      await crash.setCustomKey(
        'api_request_headers',
        _truncate(requestHeaders, _keyMaxChars),
      );
      await crash.setCustomKey(
        'api_response_headers',
        _truncate(responseHeaders, _keyMaxChars),
      );
      await crash.setCustomKey(
        'api_request_body',
        _truncate(requestBody, _keyMaxChars),
      );
      await crash.setCustomKey(
        'api_response_body',
        _truncate(responseBody, _keyMaxChars),
      );

      crash.log(
        _truncate(
          'API error: $method $endpoint ($statusCode) $errorMessage\n'
          'requestHeaders=$requestHeaders\n'
          'responseHeaders=$responseHeaders\n'
          'requestBody=$requestBody\n'
          'responseBody=$responseBody',
          _logMaxChars,
        ),
      );

      await crash.recordError(
        err,
        err.stackTrace,
        fatal: false,
        reason: 'api_error',
        information: [
          'api_endpoint=${_truncate(endpoint, _infoMaxChars)}',
          'api_method=$method',
          'api_status_code=${statusCode ?? -1}',
          if ((screen ?? '').trim().isNotEmpty)
            'api_screen=${_truncate(screen!.trim(), _infoMaxChars)}',
          'api_error_message=${_truncate(errorMessage, _infoMaxChars)}',
          'api_request_headers=${_truncate(requestHeaders, _infoMaxChars)}',
          'api_response_headers=${_truncate(responseHeaders, _infoMaxChars)}',
          'api_request_body=${_truncate(requestBody, _infoMaxChars)}',
          'api_response_body=${_truncate(responseBody, _infoMaxChars)}',
        ],
      );

      if (forceSendNow) {
        await crash.sendUnsentReports();
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('CrashlyticsApiLogger failed: $e');
        debugPrint('$st');
      }
    }
  }

  static String? _extractBackendMessage(dynamic body) {
    try {
      if (body is Map) {
        final msg = body['message'] ?? body['error'] ?? body['detail'];
        if (msg != null) return msg.toString();
      }
    } catch (_) {}
    return null;
  }

  static String _safeBodyString(dynamic body) {
    try {
      if (body == null) return '<null>';

      if (body is FormData) {
        final fields = <String, dynamic>{};
        for (final entry in body.fields) {
          fields[entry.key] = _maskIfSensitive(entry.key, entry.value);
        }
        final files = body.files
            .map(
              (e) => {
                'field': e.key,
                'filename': e.value.filename ?? '<file>',
              },
            )
            .toList(growable: false);

        return _truncate(
          jsonEncode({
            'type': 'FormData',
            'fields': fields,
            'files': files,
          }),
          _logMaxChars,
        );
      }

      if (body is String) {
        return _truncate(body, _logMaxChars);
      }

      if (body is Map || body is List) {
        final sanitized = _sanitize(body);
        return _truncate(jsonEncode(sanitized), _logMaxChars);
      }

      return _truncate(body.toString(), _logMaxChars);
    } catch (_) {
      return '<unprintable>';
    }
  }

  static String _safeHeadersString(Map headers) {
    try {
      final out = <String, dynamic>{};
      headers.forEach((k, v) {
        final key = k.toString();
        final maskedKey = key.trim().toLowerCase();
        if (_sensitiveKeys.contains(maskedKey) ||
            maskedKey == 'authorization' ||
            maskedKey == 'set-cookie' ||
            maskedKey == 'cookie') {
          out[key] = '<redacted>';
          return;
        }

        if (v is List) {
          out[key] = v.map((e) => e.toString()).join(', ');
        } else {
          out[key] = v?.toString();
        }
      });
      return _truncate(jsonEncode(out), _logMaxChars);
    } catch (_) {
      return '<unprintable headers>';
    }
  }

  static dynamic _sanitize(dynamic value) {
    if (value is Map) {
      final out = <String, dynamic>{};
      value.forEach((k, v) {
        final key = k.toString();
        out[key] = _maskIfSensitive(key, _sanitize(v));
      });
      return out;
    }
    if (value is List) {
      return value.map(_sanitize).toList(growable: false);
    }
    return value;
  }

  static dynamic _maskIfSensitive(String key, dynamic value) {
    final k = key.trim().toLowerCase();
    if (_sensitiveKeys.contains(k)) return '<redacted>';
    return value;
  }

  static String _truncate(String s, int maxChars) {
    if (s.length <= maxChars) return s;
    return '${s.substring(0, maxChars)}... (truncated, ${s.length} chars)';
  }
}
