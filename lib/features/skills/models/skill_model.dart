class SkillModel {
  final String id;
  final String name;
  final String? slug;
  final List<String> aliases;
  final bool? isActive;

  const SkillModel({
    required this.id,
    required this.name,
    this.slug,
    this.aliases = const [],
    this.isActive,
  });

  factory SkillModel.fromJson(Map<String, dynamic> json) {
    return SkillModel(
      id: (json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      slug: json['slug']?.toString(),
      aliases: (json['aliases'] is List)
          ? (json['aliases'] as List).map((e) => e.toString()).toList()
          : const [],
      isActive: json['isActive'] is bool ? json['isActive'] as bool : null,
    );
  }
}
