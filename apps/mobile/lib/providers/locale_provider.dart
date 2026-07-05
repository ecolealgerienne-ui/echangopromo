import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/local/locale_store.dart';
import 'core_providers.dart';

/// Langues supportées (bouton de changement de langue) — Français par
/// défaut (pilote Djelfa), Anglais et Arabe ajoutés à la demande.
const supportedAppLocales = [Locale('fr'), Locale('en'), Locale('ar')];

const _defaultLocale = Locale('fr');

final localeStoreProvider = Provider((ref) => LocaleStore(ref.watch(sharedPreferencesProvider)));

class LocaleController extends StateNotifier<Locale> {
  LocaleController(this._store) : super(_initialLocale(_store));

  final LocaleStore _store;

  static Locale _initialLocale(LocaleStore store) {
    final saved = store.get();
    return supportedAppLocales.firstWhere(
      (locale) => locale.languageCode == saved,
      orElse: () => _defaultLocale,
    );
  }

  Future<void> setLocale(Locale locale) async {
    await _store.set(locale.languageCode);
    state = locale;
  }
}

final localeProvider = StateNotifierProvider<LocaleController, Locale>(
  (ref) => LocaleController(ref.watch(localeStoreProvider)),
);
