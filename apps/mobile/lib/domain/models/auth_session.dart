enum AppRole { commercant, agent, admin }

/// Session authentifiée persistée — rôle et jeton, rien d'autre.
///
/// ⚠️ **`userId` a été retiré le 2026-08-05.** Il était écrit par les trois
/// écrans de connexion et **lu nulle part** (règle #31 : ce qui n'a plus
/// d'appelant se supprime). Il n'était pas seulement inutile, il coûtait :
/// pour le renseigner, `loginThenResolveId` enchaînait un `me()` après le
/// `login()`, et ce `me()` pouvait échouer — un 429 sur un seau de 5/min, une
/// coupure — **après** que la session ait déjà été persistée. L'utilisateur
/// lisait « connexion impossible » puis se retrouvait authentifié au
/// relancement suivant, sans avoir rien fait.
///
/// Le `sub` du JWT reste la seule source d'identité, côté serveur, où il est
/// vérifié.
class AuthSession {
  const AuthSession({required this.role, required this.token});

  final AppRole role;
  final String token;

  Map<String, String> toStorageMap() => {
        'role': role.name,
        'token': token,
      };

  static AuthSession? fromStorageMap(Map<String, String?> map) {
    final roleName = map['role'];
    final token = map['token'];
    if (roleName == null || token == null) return null;

    for (final role in AppRole.values) {
      if (role.name == roleName) {
        return AuthSession(role: role, token: token);
      }
    }
    return null;
  }
}
