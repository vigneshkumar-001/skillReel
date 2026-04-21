import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../models/skill_model.dart';

class SkillsRepository {
  final _api = ApiClient.instance;

  Future<List<SkillModel>> getSkills({int page = 1, int limit = 50}) async {
    final res = await _api.get(
      ApiConstants.skills,
      params: {'page': page, 'limit': limit},
    );

    final data = res.data;
    final list = (data is Map) ? data['data'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => SkillModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
