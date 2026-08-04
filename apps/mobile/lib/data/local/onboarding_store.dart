import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/enums/onboarding_role.dart';

/// État du parcours de premier lancement (splash → rôle → localisation),
/// stocké en local à côté des communes sélectionnées (`SelectedCommuneStore`)
/// — aucun compte, aucune donnée envoyée au backend.
class OnboardingStore {
  OnboardingStore(this._prefs);

  static const _completedKey = 'onboarding_completed';
  static const _roleKey = 'onboarding_role';

  final SharedPreferences _prefs;

  /// Lu à chaque redirection du routeur : `SharedPreferences` sert ici de
  /// source de vérité synchrone, ce qui évite d'avoir à invalider un
  /// provider après `markCompleted()` pour que la redirection voie la
  /// nouvelle valeur.
  bool isCompleted() => _prefs.getBool(_completedKey) ?? false;

  Future<void> markCompleted() => _prefs.setBool(_completedKey, true);

  OnboardingRole? getRole() => OnboardingRole.fromName(_prefs.getString(_roleKey));

  Future<void> setRole(OnboardingRole role) => _prefs.setString(_roleKey, role.name);
}
