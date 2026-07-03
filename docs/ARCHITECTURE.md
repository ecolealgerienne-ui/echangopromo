# echango Promo — Stack technique & organisation du dépôt

Ce document tranche le point ouvert §7.3 des specs (choix technique) et décrit
l'organisation du monorepo. Décisions validées avec le porteur de projet le
2026-07-03.

## 1. Décisions de stack

Le porteur de projet utilise NestJS + Flutter sur ses autres modules
(notamment `echango` / Vendure Mobile). echango Promo reprend la **même
stack technique**, avec les adaptations suivantes propres à son domaine
(pas de catalogue produit, pas de panier, pas de commande) :

| Sujet | Décision | Raison |
|---|---|---|
| Moteur backend | **NestJS "nu"**, sans le framework e-commerce Vendure | Vendure modélise catalogue/commandes/paiement — inadapté au domaine promo (commerçant/promo/zone/signalement). Reprendre uniquement NestJS + TypeScript + PostgreSQL évite de détourner un moteur e-commerce pour un besoin différent. |
| Style d'API | **REST** | Le domaine ne justifie pas la complexité GraphQL (pas de requêtes imbriquées type catalogue). REST est plus rapide à mettre en place et à faire évoluer pour ce périmètre. |
| Base de données | **PostgreSQL** + TypeORM | Cohérent avec l'écosystème echango existant. |
| Stockage images | **S3 OVH** (compatible API S3), via `@aws-sdk/client-s3` | Décision explicite des specs (§5.8), même SDK que le projet Vendure. |
| Apps mobiles | **Une seule app Flutter multi-rôles** (Client / Commerçant / Agent) | Miroir de l'app "mobile" de Vendure qui combine déjà client + vendeur. Le routing conditionnel selon l'état de connexion (anonyme / commerçant / agent) évite de dupliquer l'infra (thème, navigation, l10n) sur 2-3 apps pour un pilote à ~30 commerces. |
| État / navigation mobile | **flutter_riverpod** + **go_router** | Même choix que Vendure Mobile. |
| Auth mobile | `flutter_secure_storage` (PIN commerçant / session agent), `shared_preferences` (ville/commune sélectionnée, favoris locaux, device ID anonyme) | Cohérent avec le stockage 100% local exigé côté client (§3.1). |
| Admin / Modérateur | **Différé pour le pilote** — pas d'UI dédiée en V0, actions via API (endpoints REST protégés, appelés directement) | Échelle du pilote (~30 commerces) ne justifie pas encore un dashboard web ; à réévaluer dès l'extension à d'autres quartiers/communes. |
| Déploiement | Docker + docker-compose (Postgres, backend), même logique que `packages/backend` du dépôt Vendure | Réutilise les pratiques d'infra déjà en place côté porteur de projet. |

## 2. Organisation du dépôt (monorepo)

```
echangopromo/
├── docs/
│   ├── SPECS_ECHANGO_PROMO_V0.md   # spécifications fonctionnelles (source de vérité produit)
│   └── ARCHITECTURE.md            # ce document
├── apps/
│   ├── backend/                   # API NestJS + PostgreSQL (TypeORM)
│   └── mobile/                    # App Flutter unique (client / commerçant / agent)
├── package.json                   # workspace racine (scripts communs)
└── README.md
```

### Backend (`apps/backend`)

Modules NestJS calqués sur les entités des specs (§4) :

- `commune` — référentiel administratif (wilaya → commune), lecture seule côté client.
- `zone` — découpage opérationnel agent, distinct de `commune` (§5.2, ne pas fusionner).
- `commercant` — fiche, cycle de vie du compte, niveau de vérification, auth téléphone+PIN+OTP.
- `promo` — CRUD promo, plafond de 5 actives (§5.3), job d'expiration (§5.1).
- `agent` — compte agent, auth email+mot de passe, rattachement à une zone.
- `admin` — auth email+mot de passe, modération, gestion zones/agents.
- `report` — signalements anti-fraude par device_id (§5.4).
- `audit-log` — traçabilité des actions agent/admin.
- `storage` — intégration S3 OVH, compression déléguée au client, cron de purge à 1 mois (§5.8).
- `auth` — OTP SMS, sessions PIN, JWT.

Tâches planifiées (`@nestjs/schedule`) : expiration des promos (J+fin de validité) et purge des images S3 à 1 mois — deux jobs indépendants (§5.1 et §5.8).

### Mobile (`apps/mobile`)

Une seule app Flutter, structurée par rôle sous `features/`, avec état
d'authentification déterminant le rôle actif (anonyme → client ;
téléphone+PIN validés → commerçant ; email+mot de passe → agent) :

```
lib/
├── app/            # bootstrap, thème, routing racine (go_router)
├── config/         # env, endpoints API
├── data/
│   ├── api/        # clients REST (dio/http)
│   └── local/      # device ID, favoris, ville/commune sélectionnée
├── domain/         # modèles (Promo, Commercant, Zone, ...)
└── features/
    ├── client/     # liste promos, fiche promo, favoris, signalement
    ├── commercant/ # auth PIN, gestion promos, dashboard stats
    └── agent/      # liste commerces de zone, création fiche, capture photo obligatoire
```

## 3. Points laissés ouverts (non traités par ce document)

Les points ouverts fonctionnels du §7 des specs (mode hors-ligne agent, tri
par défaut, durée par défaut ajustable, seuil anti-fraude auto-inscription)
restent à trancher — ce document ne couvre que le choix de stack et
l'organisation du code, pas les règles métier encore en discussion.
