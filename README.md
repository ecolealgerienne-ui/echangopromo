# echango Promo

Module de la suite **echango** (echango, echango POS, echango Pay) : application
mobile mettant en relation commerçants et clients autour des promotions
commerciales. Pilote V0 sur un quartier de Djelfa.

## Documentation

- [`docs/SPECS_ECHANGO_PROMO_V0.md`](docs/SPECS_ECHANGO_PROMO_V0.md) — spécifications fonctionnelles (source de vérité produit).
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — stack technique retenue et organisation du dépôt.

## Structure du dépôt

```
echangopromo/
├── docs/            # specs fonctionnelles + architecture
├── apps/
│   ├── backend/     # API NestJS + PostgreSQL (TypeORM)
│   └── mobile/      # App Flutter unique (client / commerçant / agent)
├── docker-compose.yml
└── package.json
```

## Démarrage rapide

### Backend

```bash
cp apps/backend/.env.example apps/backend/.env
docker compose up -d postgres
npm run backend:dev
```

### Mobile

```bash
cd apps/mobile
flutter create . --project-name echango_promo --org com.echango   # une seule fois
flutter pub get
flutter run
```

Voir [`apps/mobile/README.md`](apps/mobile/README.md) pour le détail.
