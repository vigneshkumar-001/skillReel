import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/auth_repository.dart';
import '../../../core/services/storage_service.dart';

final authRepoProvider = Provider((_) => AuthRepository());

final authActionProvider = Provider((ref) => AuthActions(ref));

class AuthActions {
  final Ref _ref;
  AuthActions(this._ref);

  Future<void> requestOtp(String mobile) =>
      _ref.read(authRepoProvider).requestOtp(mobile);

  Future<String> verifyOtp(String mobile, String otp) async {
    final repo = _ref.read(authRepoProvider);
    final model = await repo.verifyOtp(mobile, otp);
    await StorageService.instance.saveToken(model.token);
    await StorageService.instance.saveUserId(model.user.id);
    return model.user.role;
  }
}