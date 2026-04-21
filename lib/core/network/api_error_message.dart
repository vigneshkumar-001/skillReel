import 'package:dio/dio.dart';

/// Returns a user-facing error message, preferring server-provided API messages.
String apiErrorMessage(Object error) {
  if (error is DioException) return _fromDio(error);
  if (error is StateError) return error.message;

  final s = error.toString().trim();
  if (s.startsWith('Exception: ')) return s.substring('Exception: '.length);
  return s;
}

String _fromDio(DioException e) {
  // 1) Prefer response body message when present.
  final res = e.response;
  final data = res?.data;
  final fromBody = _messageFromBody(data);
  if (fromBody != null && fromBody.isNotEmpty) return fromBody;

  // 2) Friendly messages for network/timeout issues.
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'Request timed out. Please try again.';
    case DioExceptionType.badCertificate:
      return 'Secure connection failed. Please try again.';
    case DioExceptionType.connectionError:
      return 'No internet connection. Check your network and try again.';
    case DioExceptionType.cancel:
      return 'Request cancelled.';
    case DioExceptionType.unknown:
    case DioExceptionType.badResponse:
      break;
  }

  // 3) Fallback to status code + generic.
  final status = res?.statusCode;
  if (status != null && status >= 500) {
    return 'Server error ($status). Please try again later.';
  }
  if (status != null && status >= 400) {
    return 'Request failed ($status). Please try again.';
  }

  final msg = e.message?.trim();
  if (msg != null && msg.isNotEmpty) return msg;
  return 'Something went wrong. Please try again.';
}

String? _messageFromBody(dynamic body) {
  if (body == null) return null;
  if (body is String) {
    final s = body.trim();
    return s.isEmpty ? null : s;
  }
  if (body is Map) {
    // Common shapes: {message: "..."} / {error: "..."} / {detail: "..."}
    for (final k in const ['message', 'error', 'detail', 'msg']) {
      final v = body[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }

    // Some APIs: {errors: ["..."]} or {errors: [{message: "..."}]}
    final errors = body['errors'];
    if (errors is List && errors.isNotEmpty) {
      final first = errors.first;
      if (first is String && first.trim().isNotEmpty) return first.trim();
      if (first is Map) {
        for (final k in const ['message', 'error', 'detail', 'msg']) {
          final v = first[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
      }
    }

    // Some APIs: {data: {message: "..."}}
    final data = body['data'];
    if (data is Map) {
      for (final k in const ['message', 'error', 'detail', 'msg']) {
        final v = data[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
  }

  return null;
}
