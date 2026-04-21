import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/models/my_provider_photos_model.dart';
import 'profile_provider.dart';

class MyProviderPhotosQuery {
  final String? cursor;
  final int limit;

  const MyProviderPhotosQuery({this.cursor, this.limit = 12});

  @override
  bool operator ==(Object other) =>
      other is MyProviderPhotosQuery &&
      other.cursor == cursor &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(cursor, limit);
}

final myProviderPhotosProvider =
    FutureProvider.family<MyProviderPhotosResponse, MyProviderPhotosQuery>(
  (ref, q) async {
    await ref.watch(myProfileProvider.future);
    final repo = ref.read(appRepoProvider);
    return repo.fetchMyProviderPhotos(cursor: q.cursor, limit: q.limit);
  },
);

