import 'package:shared_preferences/shared_preferences.dart';

/// Langue choisie explicitement par l'utilisateur (bouton de changement de
/// langue). Stockée en local, indépendante du compte — les 3 rôles
/// partagent le même appareil et donc la même préférence.
class LocaleStore {
  LocaleStore(this._prefs);

  static const _key = 'app_locale_code';

  final SharedPreferences _prefs;

  String? get() => _prefs.getString(_key);

  Future<void> set(String languageCode) => _prefs.setString(_key, languageCode);
}
