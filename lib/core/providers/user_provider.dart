import 'package:flutter/foundation.dart';

class UserProvider extends ChangeNotifier {
  String? _userId;
  String? _displayName;

  String? get userId => _userId;
  String? get displayName => _displayName;

  void setUser({
    required String userId,
    String? displayName,
  }) {
    _userId = userId;
    _displayName = displayName;
    notifyListeners();
  }

  void clear() {
    _userId = null;
    _displayName = null;
    notifyListeners();
  }
}
