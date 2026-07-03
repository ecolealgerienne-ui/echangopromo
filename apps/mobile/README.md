# echango Promo — Mobile (Flutter)

App unique multi-rôles (Client / Commerçant / Agent terrain) — voir
`docs/ARCHITECTURE.md` à la racine du dépôt pour les choix de stack.

## État d'avancement

Tous les parcours des specs V0 sont implémentés et branchés à l'API :

- **Client** : sélection de commune, liste des promos (filtre commune +
  catégorie, favoris en tête), fiche promo, favoris locaux, signalement.
- **Commerçant** : auto-inscription, revendication d'un compte créé par un
  agent, login téléphone+PIN, PIN oublié, dashboard (vues fiche), gestion
  des promos (max 5 actives, appliqué côté backend).
- **Agent** : login email+mot de passe, liste des commerces de la zone avec
  statut de tournée, création de fiche commerçant, initiation de la
  revendication, création/prise de photo obligatoirement via l'appareil
  photo (pas de galerie) pour une promo.

**⚠️ Non vérifié par compilation** : le SDK Flutter n'est pas installable
dans cet environnement de développement (le point de sortie standard,
`storage.googleapis.com`, est bloqué par le proxy réseau). Tout le code a
été relu statiquement (résolution des imports, cohérence des providers
Riverpod, signatures d'API) mais **n'a jamais été passé par
`flutter analyze` ni exécuté**. Premier réflexe en reprenant ce projet
localement : `flutter analyze` puis tester chaque parcours à la main.

## Mise en route

Ce dépôt contient uniquement le code Dart (`lib/`, `pubspec.yaml`). Les
projets natifs Android/iOS n'ont pas été générés dans cet environnement
(pas de SDK Flutter disponible pour ce scaffold). À faire une seule fois,
localement, avant le premier build :

```bash
cd apps/mobile
flutter create . --project-name echango_promo --org com.echango
flutter pub get
flutter analyze          # à faire en premier, jamais exécuté ici
flutter run --dart-define=API_BASE_URL=http://<ip-locale>:3000
```

`flutter create .` complète le dossier avec `android/`, `ios/` et les
fichiers de plateforme sans toucher à `lib/` ni `pubspec.yaml` déjà en place.

`API_BASE_URL` par défaut vaut `http://localhost:3000`, ce qui ne fonctionne
pas depuis un appareil/émulateur (localhost y désigne l'appareil lui-même) —
passer l'IP locale de la machine qui fait tourner le backend.

## Structure

```
lib/
├── app/            # MaterialApp.router + GoRouter (redirections par rôle)
├── config/         # env (API_BASE_URL)
├── data/
│   ├── api/        # clients REST par domaine (dio)
│   └── local/      # device ID, favoris, commune sélectionnée, session JWT
├── domain/         # modèles + enums (miroir du backend)
├── providers/      # providers Riverpod transverses (auth, api clients)
└── features/
    ├── client/     # promos, favoris, commune
    ├── commercant/ # auth, dashboard, promos
    ├── agent/      # zone, création commerçant, promo (caméra obligatoire)
    └── shared/     # widgets réutilisés (catégorie, sélecteur photo)
```
