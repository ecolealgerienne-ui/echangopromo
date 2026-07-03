import 'package:shared_preferences/shared_preferences.dart';

/// Ville/commune sélectionnée par le client (specs §3.1) : stockée en local,
/// pas de compte, modifiable à tout moment.
class SelectedCommuneStore {
  SelectedCommuneStore(this._prefs);

  static const _key = 'selected_commune_id';

  final SharedPreferences _prefs;

  String? get() => _prefs.getString(_key);

  Future<void> set(String communeId) => _prefs.setString(_key, communeId);
}
