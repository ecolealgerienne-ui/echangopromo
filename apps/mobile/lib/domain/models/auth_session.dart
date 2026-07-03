enum AppRole { commercant, agent }

class AuthSession {
  const AuthSession({required this.role, required this.token, required this.userId});

  final AppRole role;
  final String token;
  final String userId;

  Map<String, String> toStorageMap() => {
        'role': role.name,
        'token': token,
        'userId': userId,
      };

  static AuthSession? fromStorageMap(Map<String, String?> map) {
    final roleName = map['role'];
    final token = map['token'];
    final userId = map['userId'];
    if (roleName == null || token == null || userId == null) return null;

    for (final role in AppRole.values) {
      if (role.name == roleName) {
        return AuthSession(role: role, token: token, userId: userId);
      }
    }
    return null;
  }
}
