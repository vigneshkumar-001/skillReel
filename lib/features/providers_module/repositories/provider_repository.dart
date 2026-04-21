import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/constants/api_constants.dart';
import '../models/provider_model.dart';

class ProviderRepository {
  final _api = ApiClient.instance;

  Future<Map<String, dynamic>> getMyProviderProfileJson() async {
    try {
      final res = await _api.get(ApiConstants.myProvider);
      final root = res.data;
      final payload = (root is Map) ? root['data'] : null;
      if (payload is! Map) {
        throw StateError('Unexpected app/me/provider response');
      }
      return _normalizeProviderJson(Map<String, dynamic>.from(payload));
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      // Some backends expose provider profile via /app/me (legacy shape) and
      // keep /app/me/provider only for POST/PUT.
      if (code == 404 || code == 405) {
        final res = await _api.get(ApiConstants.appMe);
        final root = res.data;
        final data = (root is Map) ? root['data'] : null;
        if (data is! Map) {
          throw StateError('Unexpected app/me response');
        }
        final provider = data['provider'];
        if (provider is! Map) {
          throw StateError('Provider data not found in app/me response');
        }
        return _normalizeProviderJson(Map<String, dynamic>.from(provider));
      }
      rethrow;
    }
  }

  Future<ProviderModel> getMyProviderProfile() async {
    final payload = await getMyProviderProfileJson();
    return ProviderModel.fromJson(payload);
  }

  Future<ProviderModel> getProviderById(String id) async {
    // Public provider overview (expects providerId in path)
    //
    // GET /app/userproviders/:id
    // { success, data: { profile: {...}, stats: {...}, viewer: {...} } }
    final res = await _api.get('${ApiConstants.userProviderOverview}/$id');
    final root = res.data;
    final data = (root is Map) ? root['data'] : null;
    if (data is! Map) {
      throw StateError('Unexpected userproviders response');
    }

    final profileObj = data['profile'];
    if (profileObj is! Map) {
      throw StateError('Missing profile in userproviders response');
    }
    final profile = _normalizeProviderJson(
      Map<String, dynamic>.from(profileObj),
    );

    final verificationObj = profile['verification'];
    final verification = verificationObj is Map
        ? Map<String, dynamic>.from(verificationObj)
        : const <String, dynamic>{};

    final communicationObj = profile['communication'];
    final communication = communicationObj is Map
        ? Map<String, dynamic>.from(communicationObj)
        : const <String, dynamic>{};

    final statsObj = data['stats'];
    final stats =
        statsObj is Map ? Map<String, dynamic>.from(statsObj) : const <String, dynamic>{};
    final followersObj = stats['followers'];
    final followers =
        followersObj is Map ? Map<String, dynamic>.from(followersObj) : const <String, dynamic>{};

    final mapped = <String, dynamic>{
      '_id': profile['id'] ?? profile['_id'],
      'userId': profile['userId'],
      'displayName': profile['displayName'],
      // ProviderModel expects avatar key; API returns avatarUrl.
      'avatar': profile['avatarUrl'] ?? profile['avatar'],
      'skills': profile['skills'],
      'bio': profile['bio'],
      'location': profile['location'],
      'averageRating': verification['averageRating'],
      'totalReviews': verification['totalReviews'],
      'followerCount': followers['value'],
      // Not available in this API; default to 0.
      'enquiryCount': 0,
      'isVerified': verification['isVerified'],
      // Not available in this API; treat as active by default.
      'isActive': true,
      'trustScore': verification['trustScore'],
      'callEnabled': communication['callEnabled'],
    };

    return ProviderModel.fromJson(mapped);
  }

  Future<void> follow(String providerId) =>
      _api.post('${ApiConstants.follows}/$providerId');

  Future<void> unfollow(String providerId) =>
      _api.delete('${ApiConstants.follows}/$providerId');

  Future<ProviderModel> becomeProvider(Map<String, dynamic> data) async {
    Response res;
    try {
      // New API: POST /app/me/provider
      res = await _api.post(ApiConstants.myProvider, data: data);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      // Backward-compat: older API used /providers/become.
      if (code == 404 || code == 405) {
        res = await _api.post(ApiConstants.becomeProvider, data: data);
      } else {
        rethrow;
      }
    }

    final root = res.data;
    final payload = (root is Map) ? root['data'] : null;
    if (payload is! Map) {
      throw StateError('Unexpected provider create response');
    }
    return ProviderModel.fromJson(Map<String, dynamic>.from(payload));
  }

  Future<ProviderModel> updateMyProviderProfile(
      Map<String, dynamic> data) async {
    final res = await _api.put(ApiConstants.myProvider, data: data);
    final root = res.data;
    final payload = (root is Map) ? root['data'] : null;
    if (payload is! Map) {
      throw StateError('Unexpected provider update response');
    }
    return ProviderModel.fromJson(
      _normalizeProviderJson(Map<String, dynamic>.from(payload)),
    );
  }

  Map<String, dynamic> _normalizeProviderJson(Map<String, dynamic> raw) {
    final out = Map<String, dynamic>.from(raw);
    final locationObj = out['location'];
    if (locationObj is Map) {
      final loc = Map<String, dynamic>.from(locationObj);

      // Mongo geojson format: location.coordinates.coordinates = [lng, lat]
      final coordinatesObj = loc['coordinates'];
      if (coordinatesObj is Map) {
        final coordinates = coordinatesObj['coordinates'];
        if (coordinates is List && coordinates.length >= 2) {
          loc['lng'] ??= coordinates[0];
          loc['lat'] ??= coordinates[1];
        }
      }

      out['location'] = loc;
    }
    return out;
  }
}
