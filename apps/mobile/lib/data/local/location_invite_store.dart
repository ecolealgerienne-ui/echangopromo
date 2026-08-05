import 'package:shared_preferences/shared_preferences.dart';

/// Mémorise que l'utilisateur a écarté l'invitation à activer la localisation
/// affichée sur la carte.
///
/// ── Pourquoi ce drapeau existe ───────────────────────────────────────────
///
/// Sans lui, l'invitation reviendrait à **chaque** ouverture de la carte —
/// c'est-à-dire exactement le harcèlement que la règle 5.1.1(iv) d'Apple
/// interdit, et qui a valu un refus le 2026-08-05. Une proposition faite au
/// bon moment est légitime ; la même proposition répétée ne l'est plus.
///
/// ⚠️ Écarter n'est pas refuser : le refus, lui, se fait dans la boîte de
/// dialogue du système, et c'est le système qui le retient. Ce drapeau ne
/// note que « l'utilisateur a fermé cette invitation-ci ».
class LocationInviteStore {
  LocationInviteStore(this._prefs);

  static const _key = 'location_invite_dismissed';

  final SharedPreferences _prefs;

  bool isDismissed() => _prefs.getBool(_key) ?? false;

  Future<void> markDismissed() => _prefs.setBool(_key, true);
}
