import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/api_constants.dart';
import '../services/log.dart';
import 'api_interceptor.dart';
import 'api_callsite.dart';

class ApiClient {
  static ApiClient? _instance;
  late final Dio _dio;

  ApiClient._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        contentType: Headers.jsonContentType,
        // Dev tunnels / cold servers can take longer to accept TCP connections.
        // Keep a slightly higher connect timeout to avoid frequent false failures.
        connectTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(minutes: 1),
        receiveTimeout: const Duration(minutes: 1),
      ),
    );
    _dio.interceptors.add(ApiInterceptor());
  }

  static ApiClient get instance {
    _instance ??= ApiClient._();
    return _instance!;
  }

  Dio get dio => _dio;

  Map<String, dynamic> _callsiteExtra() {
    if (!kDebugMode) return const <String, dynamic>{};
    final source = ApiCallsite.infer(stackTrace: StackTrace.current);
    if (source == null || source.isEmpty) return const <String, dynamic>{};
    return <String, dynamic>{'source': source};
  }

  Future<Response> get(String path, {Map<String, dynamic>? params}) => _wrap(
        () => _getWithRetry(path, params: params),
      );

  Future<Response> post(String path, {dynamic data}) => _wrap(
        () => _dio.post(
          path,
          data: data,
          options: Options(extra: _callsiteExtra()),
        ),
      );

  Future<Response> put(String path, {dynamic data}) => _wrap(
        () => _dio.put(
          path,
          data: data,
          options: Options(extra: _callsiteExtra()),
        ),
      );

  Future<Response> delete(String path) => _wrap(
        () => _dio.delete(
          path,
          options: Options(extra: _callsiteExtra()),
        ),
      );

  Future<Response> postFormData(
    String path,
    FormData data, {
    ProgressCallback? onSendProgress,
  }) =>
      _wrap(
        () => _dio.post(
          path,
          data: data,
          options: Options(
            sendTimeout: const Duration(minutes: 1),
            receiveTimeout: const Duration(minutes: 1),
            extra: _callsiteExtra(),
          ),
          onSendProgress: onSendProgress,
        ),
      );

  Future<Response> putFormData(
    String path,
    FormData data, {
    ProgressCallback? onSendProgress,
  }) =>
      _wrap(
        () => _dio.put(
          path,
          data: data,
          options: Options(
            sendTimeout: const Duration(minutes: 1),
            receiveTimeout: const Duration(minutes: 1),
            extra: _callsiteExtra(),
          ),
          onSendProgress: onSendProgress,
        ),
      );

  Future<Response<T>> _wrap<T>(Future<Response<T>> Function() fn) async {
    try {
      return await fn();
    } catch (e, st) {
      if (kDebugMode) {
        log.tag('ApiClient').e('API call threw: $e', e, st);
      }
      rethrow;
    }
  }

  Future<Response> _getWithRetry(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    final options = Options(extra: _callsiteExtra());
    try {
      return await _dio.get(path, queryParameters: params, options: options);
    } on DioException catch (e) {
      final isTimeout = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout;
      if (!isTimeout) rethrow;

      // One safe retry for GET only (idempotent).
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      return await _dio.get(
        path,
        queryParameters: params,
        options: options.copyWith(
          // Give a little extra time on retry.
          connectTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
    }
  }
}
