class Env {
  Env._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  /// Fiches store (Play Store / App Store) — vides tant que l'app n'est pas
  /// publiée. Le partage d'une promo (`promo_detail_screen.dart`) n'ajoute
  /// la ligne "installe l'app" que si le lien correspondant à la
  /// plateforme est non vide, donc renseigner ces valeurs à la publication
  /// (`--dart-define=PLAY_STORE_URL=...`) suffit, sans toucher au code.
  static const playStoreUrl = String.fromEnvironment('PLAY_STORE_URL', defaultValue: '');
  static const appStoreUrl = String.fromEnvironment('APP_STORE_URL', defaultValue: '');
}
