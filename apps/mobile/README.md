# echango Promo — Mobile (Flutter)

App unique multi-rôles (Client / Commerçant / Agent terrain) — voir
`docs/ARCHITECTURE.md` à la racine du dépôt pour les choix de stack.

## Mise en route

Ce dépôt contient uniquement le code Dart (`lib/`, `pubspec.yaml`). Les
projets natifs Android/iOS n'ont pas été générés dans cet environnement
(pas de SDK Flutter disponible pour ce scaffold). À faire une seule fois,
localement, avant le premier build :

```bash
cd apps/mobile
flutter create . --project-name echango_promo --org com.echango
flutter pub get
flutter run
```

`flutter create .` complète le dossier avec `android/`, `ios/` et les
fichiers de plateforme sans toucher à `lib/` ni `pubspec.yaml` déjà en place.
