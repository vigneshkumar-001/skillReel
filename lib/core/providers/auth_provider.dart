import 'package:flutter/foundation.dart';

class AuthProvider extends ChangeNotifier {
  bool _isAuthenticated = false;
  String? _token;

  bool get isAuthenticated => _isAuthenticated;
  String? get token => _token;

  void setAuthenticated({required bool value, String? token}) {
    _isAuthenticated = value;
    _token = token;
    notifyListeners();
  }

  void signOut() {
    _isAuthenticated = false;
    _token = null;
    notifyListeners();
  }
}
