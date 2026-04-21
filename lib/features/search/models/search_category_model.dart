class SearchCategoryModel {
  final String id;
  final String category;
  final String? imageUrl;
  final int skills;

  const SearchCategoryModel({
    required this.id,
    required this.category,
    this.imageUrl,
    required this.skills,
  });

  factory SearchCategoryModel.fromJson(Map<String, dynamic> j) {
    return SearchCategoryModel(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      category: (j['category'] ?? '').toString(),
      imageUrl: (j['imageUrl'] ?? '').toString().trim().isEmpty
          ? null
          : (j['imageUrl'] ?? '').toString(),
      skills: (j['skills'] is num)
          ? (j['skills'] as num).toInt()
          : int.tryParse((j['skills'] ?? 0).toString()) ?? 0,
    );
  }
}
