import '../constants/api_constants.dart';
import 'api_client.dart';
import 'package:dio/dio.dart';
import 'dart:typed_data';
import 'models/app_bootstrap_model.dart';
import 'models/app_me_model.dart';
import 'models/my_provider_reels_model.dart';
import 'models/my_provider_photos_model.dart';
import 'models/my_saved_reels_model.dart';

class AppRepository {
  final ApiClient _api;

  AppRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  Future<AppBootstrapResponse> fetchBootstrap() async {
    final res = await _api.get(ApiConstants.bootstrap);
    final root = res.data;
    if (root is! Map) {
      throw StateError('Unexpected bootstrap response: ${root.runtimeType}');
    }
    return AppBootstrapResponse.fromJson(Map<String, dynamic>.from(root));
  }

  Future<AppMeResponse> fetchMe() async {
    final res = await _api.get(ApiConstants.appMe);
    final root = res.data;
    if (root is! Map) {
      throw StateError('Unexpected app/me response: ${root.runtimeType}');
    }
    return AppMeResponse.fromJson(Map<String, dynamic>.from(root));
  }

  Future<AppMeResponse> updateMyProfile(Map<String, dynamic> data) async {
    // Backend expects multipart/form-data even for text-only profile updates.
    final form = FormData.fromMap(data);
    final res = await _api.putFormData(ApiConstants.appMeProfile, form);
    final root = res.data;
    if (root is! Map) {
      throw StateError(
          'Unexpected app/me/profile response: ${root.runtimeType}');
    }
    return AppMeResponse.fromJson(Map<String, dynamic>.from(root));
  }

  Future<AppMeResponse> updateMyProfileWithAvatar({
    required Map<String, dynamic> data,
    required Uint8List avatarBytes,
    required String filename,
  }) async {
    final form = FormData.fromMap({
      ...data,
      'avatar': MultipartFile.fromBytes(avatarBytes, filename: filename),
    });

    Response res;
    try {
      // Preferred API: /app/me/profile
      res = await _api.putFormData(ApiConstants.appMeProfile, form);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 404 || code == 405) {
        // Legacy fallback: /a/me/profile
        res = await _api.putFormData(ApiConstants.updateProfile, form);
      } else {
        rethrow;
      }
    }

    final root = res.data;
    if (root is! Map) {
      throw StateError(
        'Unexpected profile update response: ${root.runtimeType}',
      );
    }
    return AppMeResponse.fromJson(Map<String, dynamic>.from(root));
  }

  Future<AppMeResponse> switchMode(String mode) async {
    final res = await _api.post(ApiConstants.switchMode, data: {'mode': mode});
    final root = res.data;
    if (root is! Map) {
      throw StateError('Unexpected switch-mode response: ${root.runtimeType}');
    }
    return AppMeResponse.fromJson(Map<String, dynamic>.from(root));
  }

  Future<MyProviderReelsResponse> fetchMyProviderReels({
    String? cursor,
    int limit = 12,
  }) async {
    final res = await _api.get(
      ApiConstants.myProviderReels,
      params: <String, dynamic>{
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
    );
    final root = res.data;
    if (root is! Map) {
      throw StateError(
          'Unexpected my provider reels response: ${root.runtimeType}');
    }
    return MyProviderReelsResponse.fromJson(Map<String, dynamic>.from(root));
  }

  Future<MyProviderPhotosResponse> fetchMyProviderPhotos({
    String? cursor,
    int limit = 12,
  }) async {
    final res = await _api.get(
      ApiConstants.myProviderPhotos,
      params: <String, dynamic>{
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
    );
    final root = res.data;
    if (root is! Map) {
      throw StateError(
        'Unexpected my provider photos response: ${root.runtimeType}',
      );
    }
    return MyProviderPhotosResponse.fromJson(Map<String, dynamic>.from(root));
  }

  Future<MySavedReelsResponse> fetchMySavedReels({
    String? cursor,
    int limit = 12,
  }) async {
    final res = await _api.get(
      ApiConstants.myProviderSaved,
      params: <String, dynamic>{
        if (cursor != null) 'cursor': cursor,
        'limit': limit,
      },
    );
    final root = res.data;
    if (root is! Map) {
      throw StateError(
          'Unexpected my saved reels response: ${root.runtimeType}');
    }
    return MySavedReelsResponse.fromJson(Map<String, dynamic>.from(root));
  }
}
