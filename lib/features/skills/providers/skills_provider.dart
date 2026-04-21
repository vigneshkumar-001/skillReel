import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/skill_model.dart';
import '../repositories/skills_repository.dart';

final skillsRepoProvider =
    Provider<SkillsRepository>((_) => SkillsRepository());

final skillsProvider = FutureProvider<List<SkillModel>>((ref) async {
  final skills = await ref.read(skillsRepoProvider).getSkills();
  skills.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return skills.where((s) => s.isActive != false).toList();
});
