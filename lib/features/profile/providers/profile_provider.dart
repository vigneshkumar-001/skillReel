import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/app_repository.dart';

final appRepoProvider = Provider((_) => AppRepository());

final myProfileProvider = FutureProvider<Map<String, dynamic>>((ref) {
  return ref.read(appRepoProvider).fetchMe().then((res) {
    return res.data.profile.toProfileMap();
  });
});
