import 'package:dio/dio.dart';
import 'dart:convert';
import '../../../core/network/api_client.dart';
import '../../../core/constants/api_constants.dart';
import '../models/reel_model.dart';

class ReelRepository {
  final _api = ApiClient.instance;

  Future<List<ReelModel>> getReels() async {
    final res = await _api.get(ApiConstants.reels);
    return (res.data['data'] as List)
        .map((r) => ReelModel.fromJson(r))
        .toList();
  }

  Future<void> uploadReel({
    required String title,
    required String caption,
    required String description,
    required String filePath,
    required String mediaType,
    required List<String> skillTags,
    required String visibility,
    required String audience,
    required bool commentsEnabled,
    String? thumbnailPath,
    String? previewClipPath,
    int? price,
    ProgressCallback? onSendProgress,
  }) async {
    final form = FormData.fromMap({
      'title': title,
      'caption': caption,
      'description': description,
      'mediaType': mediaType,
      'visibility': visibility,
      'audience': audience,
      'commentsEnabled': commentsEnabled,
      'schedule': 'now',
      'skillTags': jsonEncode(skillTags),
      if (price != null) 'price': price,
      'media': await MultipartFile.fromFile(filePath),
      if (thumbnailPath != null && thumbnailPath.trim().isNotEmpty)
        'thumbnail': await MultipartFile.fromFile(thumbnailPath),
      if (previewClipPath != null && previewClipPath.trim().isNotEmpty)
        'previewClip': await MultipartFile.fromFile(previewClipPath),
    });
    await _api.postFormData(
      ApiConstants.reels,
      form,
      onSendProgress: onSendProgress,
    );
  }
}
