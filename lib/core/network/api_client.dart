import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/api_constants.dart';
import '../services/log.dart';
import 'api_interceptor.dart';

class ApiClient {
  static ApiClient? _instance;
  late final Dio _dio;

  ApiClient._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        contentType: Headers.jsonContentType,
        connectTimeout: const Duration(seconds: 20),
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

  Future<Response> get(String path, {Map<String, dynamic>? params}) =>
      _wrap(() => _dio.get(path, queryParameters: params));

  Future<Response> post(String path, {dynamic data}) =>
      _wrap(() => _dio.post(path, data: data));

  Future<Response> put(String path, {dynamic data}) =>
      _wrap(() => _dio.put(path, data: data));

  Future<Response> delete(String path) => _wrap(() => _dio.delete(path));

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
}
