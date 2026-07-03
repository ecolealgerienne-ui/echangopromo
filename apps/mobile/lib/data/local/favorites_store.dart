import 'package:shared_preferences/shared_preferences.dart';

/// Commerçants favoris du client (specs §3.1) : stockage 100% local,
/// aucun compte, sert de raccourci d'affichage (pas d'alerte proactive).
class FavoritesStore {
  FavoritesStore(this._prefs);

  static const _key = 'favorite_commercant_ids';

  final SharedPreferences _prefs;

  Set<String> getAll() => _prefs.getStringList(_key)?.toSet() ?? {};

  Future<void> toggle(String commercantId) {
    final current = getAll();
    if (!current.remove(commercantId)) {
      current.add(commercantId);
    }
    return _prefs.setStringList(_key, current.toList());
  }

  bool isFavorite(String commercantId) => getAll().contains(commercantId);
}
