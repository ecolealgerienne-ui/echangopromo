import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Identifiant device anonyme (specs §3.1 / §5.4) : généré une fois à
/// l'installation, jamais lié à un compte, utilisé uniquement pour la
/// limitation des signalements et le comptage de vues par device unique.
class DeviceIdStore {
  DeviceIdStore(this._prefs);

  static const _key = 'device_id';

  final SharedPreferences _prefs;

  String getOrCreate() {
    final existing = _prefs.getString(_key);
    if (existing != null) return existing;

    final generated = const Uuid().v4();
    _prefs.setString(_key, generated);
    return generated;
  }
}
