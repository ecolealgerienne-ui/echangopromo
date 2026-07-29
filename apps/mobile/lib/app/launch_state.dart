/// État du lancement courant de l'app, partagé entre la redirection du
/// routeur et le splash.
///
/// Dans son propre fichier plutôt que dans `router.dart` : le splash a besoin
/// de marquer l'état, et le routeur a besoin de le lire tout en important le
/// splash — les mettre ensemble créerait un cycle d'imports entre les deux.
library;

/// Faux au démarrage du processus, passé à vrai par le splash une fois son
/// animation terminée. Le splash s'affiche donc à **chaque lancement à
/// froid** de l'app, et plus seulement au tout premier (retour terrain
/// 2026-07-29) — mais jamais à un simple retour depuis l'arrière-plan, où le
/// processus n'est pas relancé et où revoir le splash serait pénible.
///
/// Une variable de processus et non `SharedPreferences` : c'est exactement la
/// durée de vie voulue, sans rien à réinitialiser ni à nettoyer.
bool _splashShownThisLaunch = false;

bool get splashShownThisLaunch => _splashShownThisLaunch;

/// Appelé par `SplashScreen` avant de naviguer : sans ça, la redirection du
/// routeur le renverrait aussitôt sur lui-même.
void markSplashShown() => _splashShownThisLaunch = true;
