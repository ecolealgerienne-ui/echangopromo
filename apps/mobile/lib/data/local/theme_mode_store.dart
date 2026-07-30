import 'package:shared_preferences/shared_preferences.dart';

/// Clair ou sombre, choisi explicitement par l'utilisateur (bouton en tête
/// de l'accueil). Stocké en local comme la langue, indépendamment du compte
/// — les 3 rôles partagent l'appareil et donc la préférence.
class ThemeModeStore {
  ThemeModeStore(this._prefs);

  static const _key = 'app_theme_mode';

  final SharedPreferences _prefs;

  String? get() => _prefs.getString(_key);

  Future<void> set(String name) => _prefs.setString(_key, name);
}
