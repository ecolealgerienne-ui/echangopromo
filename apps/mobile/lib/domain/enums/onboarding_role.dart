/// Rôle choisi au premier lancement (écran "Bienvenue"). Purement local et
/// réversible : il oriente l'écran d'accueil, ne crée aucun compte et ne
/// remplace jamais l'authentification (`AuthSession.role`, qui elle vient du
/// JWT). Un client peut donc devenir commerçant sans réinstaller l'app.
///
/// Pas d'équivalent backend : cette valeur ne quitte jamais l'appareil.
enum OnboardingRole {
  client,
  commercant;

  static OnboardingRole? fromName(String? name) {
    if (name == null) return null;
    for (final role in OnboardingRole.values) {
      if (role.name == name) return role;
    }
    return null;
  }
}
