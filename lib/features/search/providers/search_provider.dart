import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/search_repository.dart';
import '../../home/models/feed_model.dart';
import '../models/search_category_model.dart';

final searchRepoProvider = Provider((_) => SearchRepository());
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider<FeedModel?>((ref) async {
  final q = ref.watch(searchQueryProvider);
  if (q.isEmpty) return null;
  return ref.read(searchRepoProvider).search(q);
});

final searchCategoriesProvider =
    FutureProvider<List<SearchCategoryModel>>((ref) async {
  return ref.read(searchRepoProvider).fetchCategories();
});
