class AuthModel {
  final String token;
  final UserProfile user;

  AuthModel({required this.token, required this.user});

  factory AuthModel.fromJson(Map<String, dynamic> json) => AuthModel(
        token: json['token'],
        user: UserProfile.fromJson(json['user']),
      );
}

class UserProfile {
  final String id;
  final String mobile;
  final String? name;
  final String? email;
  final String? avatar;
  final String role;
  final bool isProvider;

  UserProfile({
    required this.id,
    required this.mobile,
    this.name,
    this.email,
    this.avatar,
    required this.role,
    required this.isProvider,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['_id'] ?? json['id'],
        mobile: json['mobile'],
        name: json['name'],
        email: json['email'],
        avatar: json['avatar'],
        role: json['role'] ?? 'user',
        isProvider: json['isProvider'] ?? false,
      );
}