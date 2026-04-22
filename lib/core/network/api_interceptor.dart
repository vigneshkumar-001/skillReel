import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/log.dart';
import '../services/storage_service.dart';
import '../../crashlytics_api_logger.dart';
import 'api_callsite.dart';

class ApiInterceptor extends Interceptor {
  static final _l = log.tag('Api');

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.extra['__startTime'] = DateTime.now().toIso8601String();
    options.extra['source'] ??= ApiCallsite.infer();

    final token = await StorageService.instance.getToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    if (kDebugMode) {
      final url = options.uri.toString();
      final method = options.method;
      final headers = _ApiLog.sanitizedHeaders(options.headers);
      final tokenMasked = _ApiLog.maskedToken(token);
      final body = _ApiLog.stringifyBody(options.data);
      final source = options.extra['source']?.toString();

      _l.i(
        'API REQUEST (${source ?? '<unknown>'})\n'
        'url=$url\n'
        'method=$method\n'
        'headers=$headers\n'
        'token=$tokenMasked\n'
        'body=$body',
      );
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      final req = response.requestOptions;
      final url = req.uri.toString();
      final method = req.method;
      final status = response.statusCode;
      final headers = _ApiLog.sanitizedHeaders(response.headers.map);
      final durationMs = _ApiLog.durationMs(req);
      final body = _ApiLog.stringifyBody(response.data);
      final source = req.extra['source']?.toString();

      _l.i(
        'API RESPONSE (${source ?? '<unknown>'})\n'
        'url=$url\n'
        'method=$method\n'
        'status=$status (${durationMs}ms)\n'
        'headers=$headers\n'
        'response=$body',
      );
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Global error handling - 401 clears token.
    if (err.response?.statusCode == 401) {
      StorageService.instance.clearToken();
    }

    if (kDebugMode) {
      final req = err.requestOptions;
      final url = req.uri.toString();
      final method = req.method;
      final status = err.response?.statusCode;
      final durationMs = _ApiLog.durationMs(req);
      final resHeaders = err.response != null
          ? _ApiLog.sanitizedHeaders(err.response!.headers.map)
          : null;
      final resBody =
          err.response != null ? _ApiLog.stringifyBody(err.response!.data) : '';
      final source = req.extra['source']?.toString();

      _l.w(
        'API ERROR (${source ?? '<unknown>'})\n'
        'url=$url\n'
        'method=$method\n'
        'status=$status (${durationMs}ms)\n'
        'error=${err.type} ${err.message}\n'
        'headers=${resHeaders ?? '<null>'}\n'
        'response=${resBody.isNotEmpty ? resBody : '<empty>'}',
      );
    }

    // Report API errors to Crashlytics with safe context (no sensitive data).
    // Note: runs best-effort and won't block the request pipeline.
    final screen = err.requestOptions.extra['screen']?.toString();
    CrashlyticsApiLogger.logDioError(err, screen: screen);

    handler.next(err);
  }
}

class _ApiLog {
  static const int _maxChars = 4000;

  static String maskedToken(String? token) {
    if (token == null || token.isEmpty) return '<null>';
    if (token.length <= 12) return '***';
    final start = token.substring(0, 6);
    final end = token.substring(token.length - 4);
    return '$start...$end';
  }

  static Map<String, dynamic> sanitizedHeaders(Map headers) {
    final out = <String, dynamic>{};
    headers.forEach((k, v) {
      final key = k.toString();
      if (key.toLowerCase() == 'authorization') {
        out[key] = '<redacted>';
      } else {
        out[key] = v;
      }
    });
    return out;
  }

  static int durationMs(RequestOptions options) {
    final startIso = options.extra['__startTime'];
    if (startIso is! String) return -1;
    final start = DateTime.tryParse(startIso);
    if (start == null) return -1;
    return DateTime.now().difference(start).inMilliseconds;
  }

  static String stringifyBody(dynamic body) {
    try {
      if (body == null) return '<null>';

      if (body is FormData) {
        final fields = body.fields.map((e) => '${e.key}=${e.value}').toList();
        final files = body.files
            .map((e) => '${e.key}=${e.value.filename ?? '<file>'}')
            .toList();
        return _truncate({
          'type': 'FormData',
          'fields': fields,
          'files': files,
        }.toString());
      }

      if (body is String) return _truncate(body);
      if (body is Map || body is List) {
        const encoder = JsonEncoder.withIndent('  ');
        return _truncate(encoder.convert(body));
      }

      return _truncate(body.toString());
    } catch (_) {
      return '<unprintable body>';
    }
  }

  static String _truncate(String s) {
    if (s.length <= _maxChars) return s;
    return '${s.substring(0, _maxChars)}... (truncated, ${s.length} chars)';
  }
}
