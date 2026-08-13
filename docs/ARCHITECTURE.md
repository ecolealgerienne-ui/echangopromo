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
| Moteur backend | **NestJS "nu"**, sans le framework e-commerce Vendure | Vendure modélise catalogue/commandes/paiement — inadapté au domaine promo (commerçant/promo/signalement). Reprendre uniquement NestJS + TypeScript + PostgreSQL évite de détourner un moteur e-commerce pour un besoin différent. |
| Style d'API | **REST** | Le domaine ne justifie pas la complexité GraphQL (pas de requêtes imbriquées type catalogue). REST est plus rapide à mettre en place et à faire évoluer pour ce périmètre. |
| Base de données | **PostgreSQL** + TypeORM | Cohérent avec l'écosystème echango existant. |
| Stockage images | **S3 OVH** (compatible API S3), via `@aws-sdk/client-s3` | Décision explicite des specs (§5.8), même SDK que le projet Vendure. |
| Apps mobiles | **Une seule app Flutter multi-rôles** (Client / Commerçant / Agent) | Miroir de l'app "mobile" de Vendure qui combine déjà client + vendeur. Le routing conditionnel selon l'état de connexion (anonyme / commerçant / agent) évite de dupliquer l'infra (thème, navigation, l10n) sur 2-3 apps pour un pilote à ~30 commerces. |
| État / navigation mobile | **flutter_riverpod** + **go_router** | Même choix que Vendure Mobile. |
| Auth mobile | `flutter_secure_storage` (PIN commerçant / session agent), `shared_preferences` (point de recherche + consentement, favoris locaux, device ID anonyme) | Cohérent avec le stockage 100% local exigé côté client (§3.1). |
| Admin / Modérateur | **Différé pour le pilote** — pas d'UI dédiée en V0, actions via API (endpoints REST protégés, appelés directement) | Échelle du pilote (~30 commerces) ne justifie pas encore un dashboard web ; à réévaluer dès l'extension à d'autres quartiers. |
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

- ~~`commune`~~ — ⚠️ **Le module a été supprimé le 2026-08-13**, avec le
  découpage administratif tout entier. Il avait déjà cessé d'être l'ancrage du
  client le 2026-08-12 (celui-ci cherche autour d'un point qu'il enregistre) ;
  il n'était plus que le territoire de l'agent et le filtre des écrans admin.
  Le lieu d'un commerce ne s'exprime désormais que de deux façons : sa
  **position** sur la carte, qui décide de tout, et son **adresse** en texte
  libre, facultative et purement indicative.
  ⚠️ La colonne `commercant."communeId"` survit jusqu'à la migration finale —
  nullable, plus écrite ni lue, conservée uniquement pour porter sa donnée
  jusqu'à une éventuelle recopie vers `adresse`.
- `commercant` — fiche, cycle de vie du compte, niveau de vérification, auth téléphone+PIN (pas d'OTP — décision produit, §3.2 des specs).
- `promo` — CRUD promo, plafond de 5 actives (§5.3), job d'expiration (§5.1). Détient la définition unique de « promo visible » (`findVisibleByIds`, `findActiveForClient`), réutilisée par les autres modules plutôt que réécrite.
- `highlight` — bandeau « Top promos » de l'accueil, curé par l'admin (ordre, image importée, titres) avec repli automatique sur le classement calculé par plus forte réduction quand aucune mise en avant n'est exploitable. Lecture publique (`GET /highlight`), gestion admin (`/admin/highlight`, agent exclu : vitrine globale, pas outil de terrain).
- `agent` — compte agent, auth email+mot de passe. ⚠️ **Sans territoire depuis
  le 2026-08-13** : il était rattaché à zéro, une ou plusieurs `Commune`, et
  cette liste bornait tout ce qu'il pouvait voir et faire. Un agent agit
  désormais sur **tout le parc**. Ce que ça retire et que rien ne remplace : la
  garde d'appartenance de quatorze routes d'écriture (règle 1, levée par
  décision produit), la partition du travail de modération, et le seul moyen
  dont l'admin disposait pour **restreindre** un agent.
- `admin` — auth email+mot de passe, modération, gestion des agents (création,
  réinitialisation de mot de passe, révocation — plus d'assignation de
  territoire).
- `report` — signalements anti-fraude par device_id (§5.4).
- `audit-log` — traçabilité des actions agent/admin.
- `storage` — intégration S3 OVH, compression déléguée au client, cron de purge à 1 mois (§5.8). Préfixe de clé selon l'usage (`promo-photos/` purgé, `commercant-photos/`, `registre-documents/` et `highlight-images/` permanents).
- `auth` — hash/compare PIN, JWT (pas d'OTP SMS, supprimé du projet).

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
│   └── local/      # device ID, favoris, point de recherche + consentement
├── domain/         # modèles (Promo, Commercant, Agent, ...)
└── features/
    ├── client/     # liste promos, fiche promo, favoris, signalement
    ├── commercant/ # auth PIN, gestion promos, dashboard stats
    └── agent/      # liste des commerces (nationale), création de fiche, capture photo obligatoire
```

Position GPS optionnelle du commerce via `geolocator` (localisation native,
gratuit) ; lien "Itinéraire" côté client via `url_launcher` (ouvre l'app
Google Maps, pas d'intégration SDK/clé API payante).

## 3. Points laissés ouverts (non traités par ce document)

Les points ouverts fonctionnels du §7 des specs (mode hors-ligne agent, tri
par défaut, durée par défaut ajustable, seuil anti-fraude auto-inscription)
restent à trancher — ce document ne couvre que le choix de stack et
l'organisation du code, pas les règles métier encore en discussion.

## 4. État d'avancement backend

L'API REST (`apps/backend`) implémente l'ensemble des règles métier des
specs V0 : cycle de vie commerçant (auto-inscription et création agent,
PIN sans OTP, PIN oublié réinitialisé par l'admin), plafond et expiration
des promos, anti-fraude signalements avec fenêtre d'ignore 30 jours,
gestion des agents, modération et dashboard admin, upload S3. Vérifié de bout en
bout localement (build, lint, et parcours API réel via curl : inscription →
publication → signalement → seuil → résolution admin → plafond de 5 promos).

**Non couvert / à faire avant le pilote** :
- ~~Migrations TypeORM versionnées~~ — **fait** : `synchronize` est coupé
  depuis, le schéma est tenu par les seules migrations versionnées.
- ~~Vérifier la liste des 36 communes contre une source officielle~~ —
  **sans objet depuis le 2026-08-13** : le référentiel a été supprimé. Cette
  ligne mérite d'être conservée pour ce qu'elle enseigne — la liste avait été
  reconstituée par recherche web, son en-tête l'avertissait, et trois documents
  du dépôt en donnaient trois décomptes différents (36, 35, 35). Un référentiel
  qu'on ne peut pas vérifier finit par décider de ce qui est visible.
- Application mobile Flutter : squelette de navigation seulement, aucun
  écran n'est encore relié à l'API.
