import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/provider_repository.dart';
import '../models/provider_model.dart';

final providerRepoProvider = Provider((_) => ProviderRepository());

final providerDetailProvider =
    FutureProvider.family<ProviderModel, String>((ref, id) {
  return ref.read(providerRepoProvider).getProviderById(id);
});

final providerActionProvider = Provider((ref) => ProviderActions(ref));

class ProviderActions {
  final Ref _ref;
  ProviderActions(this._ref);

  Future<Map<String, dynamic>> getMyProviderProfileJson() =>
      _ref.read(providerRepoProvider).getMyProviderProfileJson();

  Future<ProviderModel> getMyProviderProfile() =>
      _ref.read(providerRepoProvider).getMyProviderProfile();

  Future<ProviderModel> updateMyProviderProfile(Map<String, dynamic> data) =>
      _ref.read(providerRepoProvider).updateMyProviderProfile(data);

  Future<void> follow(String providerId) =>
      _ref.read(providerRepoProvider).follow(providerId);

  Future<void> unfollow(String providerId) =>
      _ref.read(providerRepoProvider).unfollow(providerId);

  Future<ProviderModel> becomeProvider(Map<String, dynamic> data) =>
      _ref.read(providerRepoProvider).becomeProvider(data);
}
