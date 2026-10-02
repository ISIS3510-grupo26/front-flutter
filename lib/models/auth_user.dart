class AuthUser {
  final String userId;
  final String email;
  final String accessToken;

  const AuthUser({
    required this.userId,
    required this.email,
    required this.accessToken,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        userId: json['userId'] as String,
        email: json['email'] as String,
        accessToken: json['accessToken'] as String,
      );
}
