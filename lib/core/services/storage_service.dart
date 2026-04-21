import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static StorageService? _instance;
  static StorageService get instance {
    _instance ??= StorageService._();
    return _instance!;
  }
  StorageService._();

  final _secure = const FlutterSecureStorage();

  Future<void> saveToken(String token) =>
      _secure.write(key: 'jwt_token', value: token);

  Future<String?> getToken() => _secure.read(key: 'jwt_token');

  Future<void> clearToken() => _secure.delete(key: 'jwt_token');

  Future<void> saveUserId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', id);
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  Future<void> clear() async {
    await _secure.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}