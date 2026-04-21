import '../../reels/models/reel_model.dart';
import '../../providers_module/models/provider_model.dart';

class FeedModel {
  final List<ReelModel> reels;
  final List<ProviderModel> providers;
  FeedModel({required this.reels, required this.providers});

  factory FeedModel.fromJson(Map<String, dynamic> j) => FeedModel(
        reels: (j['reels'] as List? ?? const [])
            .whereType<Map>()
            .map((r) => ReelModel.fromJson(Map<String, dynamic>.from(r)))
            .toList(),
        providers: (j['providers'] as List? ?? const [])
            .whereType<Map>()
            .map((p) => ProviderModel.fromJson(Map<String, dynamic>.from(p)))
            .toList(),
      );
}
