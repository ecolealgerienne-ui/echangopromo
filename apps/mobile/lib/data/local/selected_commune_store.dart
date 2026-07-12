import 'package:shared_preferences/shared_preferences.dart';

/// Communes sélectionnées par le client (specs §3.1, extension multi-communes
/// 2026-07-12 pour les grandes villes où les communes sont accolées) :
/// stockées en local, pas de compte, modifiables à tout moment. Plafonné à 4
/// (`kMaxSelectedCommunes`), imposé côté écran ET côté backend (DTO).
class SelectedCommuneStore {
  SelectedCommuneStore(this._prefs);

  static const _key = 'selected_commune_ids';

  final SharedPreferences _prefs;

  List<String> get() => _prefs.getStringList(_key) ?? const [];

  Future<void> set(List<String> communeIds) => _prefs.setStringList(_key, communeIds);
}
