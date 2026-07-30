import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/local/theme_mode_store.dart';
import 'core_providers.dart';

/// Clair par défaut, et non `ThemeMode.system` (décision 2026-07-29).
///
/// Le thème clair — blanc franc, orange en accent — *est* l'identité de
/// l'app ; suivre le réglage du téléphone la faisait disparaître pour tout
/// utilisateur en mode sombre, sans qu'il puisse comprendre pourquoi ni
/// revenir en arrière. Le bouton laisse le choix, mais le défaut montre
/// l'app telle qu'elle est pensée.
const _defaultThemeMode = ThemeMode.light;

/// `system` volontairement absent des valeurs proposées : un bouton à trois
/// états dont l'un dépend d'un réglage invisible depuis l'app est plus
/// déroutant qu'utile à cette échelle.
const supportedThemeModes = [ThemeMode.light, ThemeMode.dark];

final themeModeStoreProvider =
    Provider((ref) => ThemeModeStore(ref.watch(sharedPreferencesProvider)));

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._store) : super(_initialMode(_store));

  final ThemeModeStore _store;

  static ThemeMode _initialMode(ThemeModeStore store) {
    final saved = store.get();
    return supportedThemeModes.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => _defaultThemeMode,
    );
  }

  Future<void> setMode(ThemeMode mode) async {
    await _store.set(mode.name);
    state = mode;
  }

  Future<void> toggle() => setMode(
        state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
      );
}

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(ref.watch(themeModeStoreProvider)),
);
