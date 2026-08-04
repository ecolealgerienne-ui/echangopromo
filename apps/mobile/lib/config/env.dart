class Env {
  Env._();

  /// Défaut = production (2026-07-29). Auparavant `http://localhost:3000`,
  /// ce qui rendait un build de release inutilisable si le
  /// `--dart-define` était oublié — l'app publiée appelait alors la machine
  /// du téléphone lui-même. Le défaut inverse ce risque : c'est désormais le
  /// développement local qui exige le flag, et l'oublier se voit
  /// immédiatement (on tape sur la prod au lieu de sa base de test) au lieu
  /// de ne se voir qu'après publication.
  ///
  /// Pour pointer un backend local :
  /// `flutter run --dart-define=API_BASE_URL=http://<ip-locale>:3000`
  /// (`localhost` désigne l'appareil lui-même depuis un émulateur ou un
  /// téléphone — il faut l'IP de la machine qui fait tourner le backend).
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://promo.echango.com',
  );

  /// Fiches store (Play Store / App Store) — vides tant que l'app n'est pas
  /// publiée. Le partage d'une promo (`promo_detail_screen.dart`) n'ajoute
  /// la ligne "installe l'app" que si le lien correspondant à la
  /// plateforme est non vide, donc renseigner ces valeurs à la publication
  /// (`--dart-define=PLAY_STORE_URL=...`) suffit, sans toucher au code.
  static const playStoreUrl = String.fromEnvironment('PLAY_STORE_URL', defaultValue: '');
  static const appStoreUrl = String.fromEnvironment('APP_STORE_URL', defaultValue: '');
}
