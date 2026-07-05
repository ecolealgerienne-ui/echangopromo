# Statut d'implémentation — echango Promo V0

**Ce fichier est le suivi vivant du projet.** Il doit être mis à jour à
chaque implémentation importante (nouvelle fonctionnalité, correction
d'audit, changement d'architecture) — pas seulement en fin de session.
Pour le détail historique complet, voir aussi `docs/AUDIT_V0.md`
(findings) et `CLAUDE.md` (règles à respecter).

Dernière mise à jour : 2026-07-04

---

## Vue d'ensemble

| Composant | Statut |
|---|---|
| Specs fonctionnelles | ✅ `docs/SPECS_ECHANGO_PROMO_V0.md` |
| Architecture & choix de stack | ✅ `docs/ARCHITECTURE.md` |
| Backend NestJS (tous modules) | ✅ implémenté, build+lint clean |
| Mobile Flutter (3 rôles) | ✅ implémenté, **compilé et exécuté** sur émulateur Android, connecté au backend |
| Audit 6 volets (fonctionnel/architecture/sécurité/qualité/mobile/perf) | ✅ terminé — `docs/AUDIT_V0.md` |
| Corrections critiques/hautes de l'audit | ✅ appliquées et testées manuellement (voir ci-dessous) |
| Corrections moyennes/basses restantes | 🔄 non traitées, listées ci-dessous |

---

## Backend — modules implémentés

`commune`, `zone`, `agent`, `admin`, `commercant`, `promo`, `report`,
`audit-log`, `storage`, `auth`. Toutes les règles métier V0 des specs sont
couvertes (cycle de vie commerçant, plafond/durée promo, anti-fraude
signalements, séparation Commune/Zone, actions admin, dashboard).

## Mobile — écrans implémentés

Client (sélection commune, liste promos, détail avec photo/itinéraire
commerçant, favoris, signalement), Commerçant (inscription avec commune en
cascade wilaya/commune, confirmation du PIN, photo et géolocalisation
optionnelles ; activation d'un compte créé par agent (`claim`, sans OTP,
confirmation du PIN aussi) ; login PIN, dashboard, promos), Agent (login,
zone, création commerçant avec les mêmes options commune/photo/géoloc,
promo avec caméra obligatoire). Pas d'écran admin en V0 (décision assumée).
PIN oublié : plus d'écran self-service, seul l'admin peut réinitialiser
(voir l'entrée "suppression OTP/SMS" ci-dessous).

---

## Corrections issues de l'audit V0

Branche `claude/new-project-setup-t5rs5y`. Chaque ligne référence le
finding correspondant dans `docs/AUDIT_V0.md`. Les corrections cochées ont
été vérifiées par un test manuel réel (backend relancé contre un Postgres
local), pas seulement par la compilation.

### Sécurité

- [x] **IDOR agent → promo/commerçant** : `PromoController.update` et
      `.createByAgent` vérifient désormais que le commerçant appartient à
      la zone de l'agent connecté (`CommercantService.assertZoneMatches`).
      **Testé** : agent hors zone → 403 ; agent de la bonne zone → 200/201.
      (`AgentController.initiateClaim`, le 3ᵉ endpoint concerné par ce
      finding, a depuis été **supprimé** avec l'OTP — voir plus bas.)
- [x] **Rate limiting auth** : `@nestjs/throttler` installé et branché
      globalement (60 req/min/IP par défaut) + limite stricte
      (5 req/min/IP, `STRICT_THROTTLE`) sur tous les logins (commerçant,
      agent, admin), `POST /commercant/claim`, et `POST /report`. **Testé** :
      429 dès la 6ᵉ requête sur `/commercant/login`.
- [x] **OTP SMS supprimé du projet** (2026-07-04, décision produit : jugé
      inutile et coûteux pour ce marché). Le finding "anti brute-force
      OTP" et le point ouvert "fuite d'énumération sur `forgot-pin/request`"
      n'ont plus d'objet : `OtpCode`, `SmsService`, et tous les endpoints
      OTP/forgot-pin ont été retirés. Détail du remplacement dans la
      section dédiée plus bas.
- [x] **Upload S3 sans limite de taille** : remplacé le PUT pré-signé par
      une POST policy S3 (`content-length-range`, 5 Mo max) — mobile mis à
      jour pour envoyer un formulaire multipart au lieu d'un PUT brut
      (`storage_api.dart`). Non testé end-to-end (nécessite un vrai bucket
      S3, pas seulement le stub local).
- [x] **Spread `{...promo}` cassant `ClassSerializerInterceptor`** :
      remplacé par un DTO de sortie explicite (`toClientJson`) qui exclut
      `photoKey` (fuite d'UUID agent) ; `@Exclude()` ajouté sur l'entité en
      défense en profondeur. **Vérifié** : `photoKey` absent des réponses.
- [ ] JWT 30 jours sans révocation — **non traité**, nécessite un design de
      refresh token / tokenVersion (session dédiée recommandée).
- [ ] `JWT_SECRET` sans validation au démarrage — **non traité**.
- [ ] Regex PIN 4-6 chiffres vs 4 fixes dans les specs — **non traité**
      (décision produit à trancher, pas un bug).

### Architecture / bugs fonctionnels

- [x] **Dashboard admin surcompte les promos actives** (`countVisible()`
      ne filtrait pas `dateFin`) — corrigé.
- [x] **Statut de zone agent divergent** (`listByZoneWithVisitStatus`
      n'utilisait pas la même définition de "promo visible" que le
      client) — corrigé, `VISIBLE_PROMO_STATUSES` centralisé dans
      `promo.entity.ts` et importé des deux côtés.
- [x] **Race condition sur le plafond de 5 promos actives** — corrigé par
      un verrou consultatif Postgres (`pg_advisory_xact_lock`) scopé au
      commerçant dans une transaction.
- [x] **N+1 sur `listByZoneWithVisitStatus`** — remplacé par 2 requêtes
      agrégées (au lieu d'une par commerçant).
- [x] **N+1 sur `listPendingModeration`** — remplacé par une seule requête
      agrégée (JOIN + GROUP BY + HAVING).
- [x] **`AuditLogModule` jamais branché** — corrigé : `AuditLogService`
      implémenté (repository + `record()`) et appelé depuis
      `AgentController` (création commerçant) et `AdminController`
      (création agent, transfert de zone, réinitialisation PIN, 3 actions de
      modération, validation/rejet registre). (L'action `initiate_claim`
      loggée par `AgentController` a disparu avec la suppression de l'OTP.)
- [x] Index DB manquants — `Promo.status+dateFin` (composite),
      `Promo.commercantId`, `Commercant.communeId`, `Commercant.zoneId`
      tous ajoutés. (`OtpCode(telephone,purpose)` n'existe plus, l'entité a
      été supprimée avec l'OTP.)
- [x] `assertOwnedBy` orpheline — **supprimée** (remplacée par
      `assertZoneMatches`, plus adaptée au besoin réel).
- [ ] `AdminController` god-object (5 services injectés) — **non traité**
      (refactoring, pas un bug).

### Mobile

- [x] `intl` n'est plus épinglé en dur (`0.20.2` → plage `>=0.19.0 <1.0.0`)
      — risque de blocage `flutter pub get` levé.
- [x] `ref` utilisé après `await` sans `context.mounted` corrigé dans
      `my_promos_screen.dart` et `zone_commerces_screen.dart`.
- [x] `storage_api.dart` mis à jour pour le nouveau flux POST policy
      (multipart au lieu de PUT brut).
- [x] `shimmer` (dépendance jamais utilisée) retirée de `pubspec.yaml`.
- [x] Garde-fou UI proactif sur le plafond de 5 promos actives (bouton
      "Nouvelle promo" désactivé à 5/5 dans `my_promos_screen.dart`) —
      gap fonctionnel mineur relevé par l'audit, corrigé au passage.
- [ ] Durée de validité par défaut (5 jours) toujours invisible/non
      éditable dans `promo_form_screen.dart` — **non traité** (UX mineure).
- [x] **`flutter analyze` exécuté pour la première fois** (SDK installé en
      local par l'utilisateur, WSL) : 5 issues trouvées et corrigées —
      import mort (`commune_providers.dart` dans `promo_list_screen.dart`),
      `AppRole` non importé (dans l'ancien `otp_confirm_screen.dart`,
      supprimé depuis avec l'OTP — faute de compilation réelle à
      l'époque), et 3× usage déprécié de `DropdownButtonFormField.value` →
      `initialValue` (`category_dropdown.dart`, `create_commercant_screen.dart`,
      `commercant_register_screen.dart`). `flutter analyze` propre après
      correction (0 issue restante à vérifier après ce commit).
- [x] **Dossiers de plateforme absents depuis le début** (`android/`, `ios/`,
      `web/`, `windows/`, `linux/`, `macos/`) : le projet n'avait jamais eu
      de `flutter create` abouti — seuls `lib/` et `pubspec.yaml` existaient,
      ce qui rendait `flutter analyze` possible mais `flutter run`
      impossible (aucune cible détectée). Générés via `flutter create .`
      côté Windows natif et commités.
- [x] **Première exécution réelle de l'app** : lancée sur un émulateur
      Android (AVD), connectée au backend NestJS tournant dans WSL2. A
      nécessité un `netsh interface portproxy` (le `localhost forwarding`
      WSL2 n'écoute que sur la boucle locale, pas sur l'interface réseau
      virtuelle de l'émulateur) — l'IP WSL change à chaque redémarrage, donc
      le portproxy est à refaire à chaque session si le réseau ne répond
      plus. Écran "Choisissez votre commune" affiché et API jointe avec
      succès.

---

## Reste à faire avant extension au-delà du pilote Djelfa

Voir `CLAUDE.md` pour les règles générales. Tous les points identifiés par
l'audit à 6 volets (`docs/AUDIT_V0.md`) ont été traités un par un (voir
historique ci-dessous) ; aucun élément concret restant à cette date. Les
seules réserves sont l'exécution locale (jamais effectuée dans cet
environnement, faute de SDK Flutter/DB accessible) : `flutter test`,
`flutter analyze`, `npm run build`/`lint` côté backend, migration initiale
TypeORM — à confirmer par l'utilisateur sur sa machine.

---

## Historique des mises à jour de ce document

- **2026-07-04** — Création du document après l'audit à 6 volets.
  Corrections appliquées et testées manuellement dans la foulée : IDOR
  agent (3 endpoints), rate limiting global + strict, anti brute-force
  OTP, upload S3 en POST policy avec limite de taille, spread cassant
  `ClassSerializerInterceptor`, bug dashboard `countVisible`, bug statut
  de zone agent, race condition plafond promos, N+1 zone/modération,
  branchement `AuditLogModule`, index DB manquants, corrections mobile
  (intl, `context.mounted`, garde-fou plafond promos).
- **2026-07-04 (suite)** — Déploiement et premiers tests réels côté
  utilisateur (WSL + Windows). Fix port Postgres (5433), fix `workspaces`
  npm racine cassant l'override `multer`. Premier `flutter analyze` réel :
  5 issues corrigées (import mort, `AppRole` non importé — bug réel, 3×
  `DropdownButtonFormField.value` déprécié). Découverte que les dossiers
  de plateforme (`android/`, etc.) n'avaient jamais été générés ; générés
  et commités. Première exécution de l'app sur émulateur Android connecté
  au backend WSL2 (nécessite un `netsh portproxy`, IP WSL changeante).
  Création de la branche `main` (absente jusque-là, `claude/new-project-
  setup-t5rs5y` était la branche par défaut).
- **2026-07-04 (suppression OTP/SMS)** — Décision produit : le SMS est
  jugé inutile et coûteux pour ce marché. Suppression complète de l'OTP
  (backend : `OtpCode`, `SmsService`, `AuthService.sendOtp/verifyOtp`,
  endpoints `confirm-inscription`/`confirm-revendication`/`forgot-pin/*`,
  `AgentController.initiateClaim` ; mobile : `otp_confirm_screen.dart`,
  `forgot_pin_screen.dart`, routes associées). Nouveaux flux, sans preuve
  de possession du numéro de téléphone :
  - Auto-inscription : téléphone + PIN en un seul appel
    (`POST /commercant/register`), compte `autonome` immédiatement.
  - Compte créé par un agent : le commerçant définit lui-même son PIN
    (`POST /commercant/claim`, nouvel endpoint), passage direct
    `créé_agent` → `autonome`. L'agent n'a plus rien à initier ; l'écran
    zone affiche juste un indicateur "en attente d'activation".
  - PIN oublié : plus de flux self-service. Seul l'admin peut effacer le
    PIN (`POST /admin/commercant/:id/reset-pin`, nouvel endpoint) ; le
    commerçant en redéfinit un via `claim`.
  - `CommercantAccountState` simplifié à `CREE_AGENT`/`AUTONOME` (les
    états `EN_ATTENTE_REVENDICATION`/`REVENDIQUE`, qui n'existaient que
    pour l'attente OTP, disparaissent — `REVENDIQUE` était de toute façon
    déjà mort, voir dette connue ci-dessus dans les versions précédentes).
  - Colonne `telephoneVerifiedAt` supprimée (plus de vérification à
    horodater).
  Specs (`docs/SPECS_ECHANGO_PROMO_V0.md` §3.2/§3.3/§7), architecture et
  audit mis à jour dans le même commit. Risque assumé documenté : sans
  OTP, un numéro usurpé peut techniquement créer/activer un compte au nom
  d'un tiers — le signalement/modération reste la seule ligne de défense.
  **Testé côté utilisateur** : `flutter analyze` exécuté sur le clone
  Windows après bascule de branche — 2 issues (`use_build_context_synchronously`
  sur les deux usages de `context` dans `_claim`, faux positif du linter
  sur un `mounted` nu après plusieurs `await`) corrigées en remplaçant par
  `context.mounted` explicite (commit `a1395dd`). Reste à confirmer
  `flutter analyze` propre après re-pull, et valider `npm run build && npm
  run lint` côté backend.
- **2026-07-04 (améliorations inscription commerçant)** — Suite à une
  demande utilisateur de 4 points sur l'inscription commerçant :
  - **Commune en cascade wilaya → commune** : nouveau widget partagé
    `CommuneCascadeField` (`features/shared/widgets/`), utilisé dans
    `commercant_register_screen.dart` (auto-inscription) et
    `create_commercant_screen.dart` (agent) — remplace la liste plate de
    communes, sans changement backend (`GET /commune?wilaya=` existait
    déjà).
  - **Confirmation du PIN** : champ de ressaisie ajouté à l'inscription et
    au dialog `claim` (activation d'un compte créé par un agent), avec
    validation `Form` que les deux PIN correspondent.
  - **Photo optionnelle du commerce** : `Commercant.photoKey` (nullable,
    jamais exposé brut — `photoUrl` calculé côté contrôleur comme pour
    `Promo`), réutilise le flux d'upload S3 existant
    (`PhotoPickerField`/`StorageApi`, cette fois avec `purpose: 'commercant'`
    → préfixe `commercant-photos/`, distinct de `promo-photos/` pour ne pas
    entrer dans le cron de purge à 30 jours). Affichée en miniature dans la
    fiche commerçant côté client (`promo_detail_screen.dart`).
  - **Géolocalisation, décision produit** : après arbitrage utilisateur,
    approche "GPS gratuit" retenue plutôt qu'une intégration Google Maps
    payante — `Commercant.latitude`/`longitude` (nullable), capturés via le
    nouveau widget `LocationCaptureField` (package `geolocator`, aucune clé
    API). Côté client, bouton "Itinéraire" (`url_launcher`) ouvrant
    `https://www.google.com/maps/search/?api=1&query=lat,lng` — l'app
    Google Maps s'ouvre si installée, sinon le navigateur. Permissions
    ajoutées : `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` (Android),
    `NSLocationWhenInUseUsageDescription` (iOS).
  - Backend : `photoKey`/`latitude`/`longitude` ajoutés aux DTOs
    `register-commercant` et `create-commercant-by-agent` ; endpoint
    `POST /storage/presigned-upload` accepte un `purpose` optionnel
    (`'promo'` par défaut, rétrocompatible).
  - Specs (`docs/SPECS_ECHANGO_PROMO_V0.md` §3.1/§3.2) et architecture mis
    à jour dans le même commit.
  - **Non exécuté dans mon environnement** (pas de `npm install`/`flutter
    pub get` ici) : à valider avec `npm run build && npm run lint` côté
    backend, et `flutter pub get && flutter analyze` côté mobile (nouvelles
    dépendances `geolocator` et `url_launcher` à récupérer).
- **2026-07-04 (formulaire promo)** — 3 points remontés sur l'ajout d'une
  promo :
  - `Promo.produit` renommé `description` (`@Column({ length: 140 })`,
    `MaxLength(140)` sur les DTOs), champ multiligne côté mobile.
  - Catégorie pré-remplie avec celle du commerçant (modifiable) : côté
    commerçant via `commercantApiProvider.me()`, côté agent via la
    catégorie du commerçant passée en `extra` de route (évite un appel
    API supplémentaire). Fix au passage d'un piège Flutter sur
    `CategoryDropdown` (`initialValue` non réactif sans `key`).
  - Contrôle `prixApres < prixAvant` ajouté côté backend
    (`PromoService.assertPriceOrder`, create + update) et côté mobile
    (validateur croisé sur les 2 formulaires).
  - Ajout d'une section "Consignes de fonctionnement" dans `CLAUDE.md` à
    la demande de l'utilisateur (optimiser les tokens, ne rien exécuter
    dans cet environnement).
  - **Non exécuté dans mon environnement** : à valider avec `npm run
    build && npm run lint` côté backend, `flutter analyze` côté mobile.
- **2026-07-04 (MinIO local)** — Ajout d'un service MinIO au
  `docker-compose.yml` (+ init bucket lecture publique) pour tester
  l'upload S3 sans bucket OVH. Fix au passage : `forcePathStyle: true`
  ajouté au `S3Client`, requis par MinIO et la plupart des S3 non-AWS
  (dont OVH) — bug latent jamais détecté faute de test end-to-end réel.
- **2026-07-04 (adresse optionnelle)** — `Commercant.adresse` rendue
  nullable (backend : entité + 2 DTOs ; mobile : modèle + champ non requis
  + affichage conditionnel côté client/agent), cohérent avec la
  géolocalisation qui peut désormais suffire à situer un commerce.
- **2026-07-04 (workflow promo brouillon/publication/arrêt)** — Suite au
  constat qu'un commerçant ne pouvait pas modifier une promo déjà créée
  (`PATCH /promo/:id` était réservé à l'agent — dette connue de
  `CLAUDE.md`, maintenant levée) :
  - **`Promo.status` (enum unique) éclaté en deux champs indépendants**
    `lifecycleStatus` (`brouillon`/`publiee`/`arretee`/`expiree`) et
    `moderationStatus` (`normale`/`signalee`/`masquee`/`verifiee_ok`) —
    corrige enfin la règle CLAUDE.md #8 ("ne jamais combiner cycle de vie
    et modération dans un seul enum"), profitant de l'ajout des nouveaux
    états demandé par l'utilisateur pour le faire proprement plutôt que
    d'empiler `brouillon`/`arretee` dans l'ancien enum.
  - Nouveaux endpoints `POST /promo/:id/publish` (brouillon/arrêtée/
    expirée → publiée, `dateFin` toujours recalculée à neuf — c'est ce
    geste explicite qui constitue la "republication complète" des specs,
    pas une simple prolongation) et `POST /promo/:id/stop` (arrêt
    volontaire, libère un slot sur le plafond de 5 immédiatement).
  - `PATCH /promo/:id` (édition de contenu) ouvert au commerçant
    propriétaire en plus de l'agent — vérification d'appartenance
    (`assertCanManage`), même pattern que les corrections IDOR
    précédentes. Édition possible quel que soit le statut.
  - Plafond de 5 compté sur `lifecycleStatus = publiee` uniquement
    (brouillons et promos arrêtées/expirées ne comptent pas) — verrou
    consultatif Postgres conservé (create + publish).
  - Durée de validité : sélecteur 1-7 jours ajouté au formulaire mobile
    (`PROMO_MAX_DURATION_DAYS=7`, validée côté serveur — auparavant
    invisible et sans borne max, un point ouvert des specs §7).
  - Mobile : `promo_form_screen.dart` réutilisé pour créer (brouillon ou
    publication) et éditer une promo existante ; `my_promos_screen.dart`
    a maintenant des actions Modifier/Publier/Arrêter par promo.
  - Specs (`docs/SPECS_ECHANGO_PROMO_V0.md` §3.2/§5.3/§7) et `CLAUDE.md`
    (dette levée) mis à jour dans le même commit.
  - **Non exécuté dans mon environnement** : à valider avec `npm run
    build && npm run lint` côté backend, `flutter analyze` côté mobile —
    changement de schéma (colonne `status` → `lifecycleStatus` +
    `moderationStatus`, `dateFin` nullable) : `synchronize: true` en dev
    devrait s'en charger, mais si des promos existent déjà en base avec
    l'ancien enum, le même risque qu'avec l'enum `CommercantAccountState`
    (valeurs absentes du nouveau type) peut se reproduire — repartir d'une
    base vide si erreur `invalid input value for enum` au démarrage.
- **2026-07-04 (migrations TypeORM réelles)** — Traitement du finding
  sévérité **haute** de l'audit architecture (`synchronize` couplé à
  `NODE_ENV`, chemin de déploiement Docker fragile/dangereux selon le
  `.env` monté) :
  - `synchronize: false` **en permanence**, plus aucune bascule sur
    `NODE_ENV` — schéma géré uniquement par des migrations versionnées.
  - `src/data-source.ts` : config TypeORM partagée entre le bootstrap
    NestJS et la CLI de migrations (`typeOrmBaseOptions` réutilisé par
    `app.module.ts`, une seule source de vérité).
  - Scripts `npm run migration:generate|run|revert` ajoutés.
  - `Dockerfile` : lance `npx typeorm migration:run` avant `node
    dist/main` au démarrage du conteneur, au lieu de compter sur
    `synchronize`.
  - Fix au passage : `"typeorm": "^1.0.0"` dans `package.json` — version
    incohérente avec le peer dependency de `@nestjs/typeorm@^11`
    (attend `^0.3.x`) ; corrigée en `^0.3.20`. À vérifier après `npm
    install` (`npm ls typeorm`) au cas où le lockfile actuel résolvait
    déjà autre chose.
  - `CLAUDE.md` mis à jour (commandes, dette levée).
  - **Non exécuté dans mon environnement — étapes obligatoires côté
    utilisateur** avant que ça fonctionne (voir message de session pour
    le détail complet) : `npm install` (nouvelle version `typeorm` + script CLI),
    repartir d'une base vide, générer la migration initiale
    (`npm run migration:generate -- src/migrations/InitialSchema`) contre
    cette base vide, `npm run migration:run`, puis reseed.
- **2026-07-04 (fix schéma)** — `Commercant.adresse` (`string | null`)
  n'avait pas de `type` explicite sur `@Column()` : TypeORM ne peut pas
  inférer le type Postgres depuis un union type TS via reflect-metadata,
  et retombe sur `"Object"`, rejeté par Postgres au démarrage. Fix :
  `type: 'varchar'` explicite (même précaution déjà appliquée à
  `zoneId`/`registreKey`). À surveiller pour tout futur champ nullable
  typé `T | null` sans `type` explicite.
- **2026-07-04 (édition profil commerçant)** — Gap découvert en testant :
  aucun moyen de modifier nom/adresse/catégorie/photo/position GPS après
  l'inscription (aucun endpoint, aucun écran). Ajout de
  `PATCH /commercant/me` (téléphone volontairement exclu — identifiant de
  connexion, pas un champ de profil) et d'un écran `EditProfileScreen`
  accessible depuis le dashboard commerçant.
- **2026-07-04 (carte promo client)** — Suite à un retour visuel (espace
  vide sous le prix sur la carte) : description limitée à 2 lignes
  (`maxLines`/`ellipsis`, détail complet accessible au clic) et ajout du
  nom du commerçant sur la carte (absent jusqu'ici de la liste, seulement
  visible en détail). Backend : `findActiveForClient`/`findByIdOrFail`
  chargent maintenant la relation `commercant` (`innerJoinAndSelect`/
  `relations`), `toClientJson` expose `commercantNom`.
- **2026-07-04 (3 findings audit : healthcheck, scaffolding, duplication)**
  — Traitement de 3 points de dette identifiés par l'audit :
  - **Healthcheck Postgres** ajouté à `docker-compose.yml` (`pg_isready`),
    `backend` attend `service_healthy` au lieu d'un simple `depends_on`
    sans condition (pouvait démarrer avant que Postgres accepte les
    connexions).
  - **Scaffolding NestJS nettoyé** : suppression de `app.controller.ts`/
    `.spec.ts`, `app.service.ts`, `test/app.e2e-spec.ts` ("Hello World"
    jamais appelé par aucun client, seuls tests de tout le backend avant
    ce nettoyage) — retirés d'`app.module.ts`.
  - **Duplication mobile factorisée** :
    - Widgets partagés `LoadingButton`/`ErrorText` (bloc
      `_loading`/`_error` + `FilledButton`/`CircularProgressIndicator`
      répété dans 6+ écrans) — appliqués à `agent_login_screen.dart`,
      `commercant_login_screen.dart`, `commercant_register_screen.dart`,
      `create_commercant_screen.dart`, `edit_profile_screen.dart`,
      `promo_form_screen.dart`, `agent_promo_form_screen.dart`.
    - Widget `PromoFormFields` (photo, description, prix, catégorie,
      durée) factorisant `PromoFormScreen`/`AgentPromoFormScreen`.
    - Widget `CommercantFieldsForm` (photo, téléphone, nom, adresse,
      position GPS, catégorie, commune) factorisant
      `CommercantRegisterScreen`/`CreateCommercantScreen` — le PIN
      (uniquement à l'auto-inscription) reste géré par l'écran appelant.
  - `CLAUDE.md` et la liste "Reste à faire" mis à jour (3 items retirés).
  - **Non exécuté dans mon environnement** : à valider avec `npm run
    build && npm run lint` côté backend, `flutter analyze` côté mobile.
- **2026-07-04 (sélection commune client en 2 étapes)** — L'écran
  `CommuneSelectionScreen` (bouton localisation côté client) affichait une
  liste plate de communes ; il réutilise maintenant `CommuneCascadeField`
  (wilaya → commune) déjà utilisé côté commerçant/agent. Ne change rien au
  pilote (une seule wilaya) mais évite de reprendre l'écran à l'extension
  multi-wilaya. Persistance locale (`SelectedCommuneStore` /
  `selectedCommuneProvider`) inchangée : le choix reste préchargé à
  l'ouverture de l'écran et réutilisé aux prochains lancements.
- **2026-07-04 (révocation JWT agent/admin)** — Ajout d'un `tokenVersion`
  (colonne `int default 0`) sur `Agent` et `Admin`, inclus dans le payload
  JWT à l'émission (`AuthService.issueToken`). `JwtAuthGuard` recharge le
  compte (agent/admin uniquement) à chaque requête et compare son
  `tokenVersion` à celui du token — mismatch = 401 "Token révoqué". Accès
  direct aux entités `Agent`/`Admin` depuis `AuthModule` (pas leurs
  modules, pour éviter un cycle — commenté, règle #9). Nouvel endpoint
  `POST /admin/agent/:id/revoke-token` (admin) incrémente le
  `tokenVersion` d'un agent — cas d'usage : téléphone perdu/volé, départ
  d'un agent. Pas d'endpoint équivalent pour l'admin lui-même (compte
  unique en V0, pas de gestion multi-admin). Pas de migration à écrire à
  la main : le schéma initial n'a pas encore été généré côté utilisateur,
  `npm run migration:generate` capturera directement ces colonnes.
- **2026-07-04 (validation JWT_SECRET au démarrage)** — `ConfigModule.forRoot`
  reçoit désormais un `validate` (`src/config/env.validation.ts`) : le
  backend refuse de démarrer si `JWT_SECRET` est absent, et si en plus
  `NODE_ENV=production` il refuse aussi la valeur par défaut `change-me`
  ou un secret de moins de 32 caractères. En dev/pilote, `change-me` reste
  toléré (celui fourni par `.env.example`) pour ne pas casser le
  démarrage local existant.
- **2026-07-04 (CORS explicite)** — `main.ts` appelle désormais
  `app.enableCors()` avec une liste d'origines lue dans `CORS_ORIGINS`
  (nouvelle variable, `.env.example`, vide par défaut = aucune origine
  web autorisée). L'app mobile (Dio natif) n'est pas concernée par le
  CORS ; ce réglage ne sert qu'à préparer un futur frontend web (admin)
  sans laisser la config permissive par défaut de NestJS en attendant.
- **2026-07-04 (décision PIN 4-6 chiffres)** — Tranché en faveur du code
  existant (backend + specs disaient déjà 4-6 chiffres depuis la
  suppression de l'OTP ; seul `AUDIT_V0.md` gardait la mention obsolète
  "4 fixes"). Côté mobile, les 4 validateurs dupliqués
  (`v.length < 4`, ne vérifiait ni le max ni que ce sont bien des
  chiffres) sont remplacés par un validateur partagé
  `features/shared/validators/pin_validator.dart` (regex `^\d{4,6}$`,
  miroir exact de la regex backend) utilisé dans
  `commercant_register_screen.dart` et `commercant_login_screen.dart`
  (connexion, claim, PIN oublié → nouveau PIN).
- **2026-07-04 (refactoring AdminController)** — Nouveau
  `ModerationService` (`admin/moderation.service.ts`) qui regroupe la file
  d'attente de modération et les 3 résolutions (`masquer`/`verifierOk`/
  `avertir`), chacune avec son audit-log — logique auparavant dupliquée
  ligne par ligne dans `AdminController`. Le controller ne fait plus que
  déléguer (`this.moderationService.masquer(user.sub, promoId)`), le
  reste (agents, registre, dashboard) est inchangé.
- **2026-07-04 (rôle associé à la route dans router.dart)** — Les listes
  `_commercantProtectedPaths`/`_agentProtectedPaths` + le cas spécial
  `isAgentPromoForm` (3 techniques différentes de protection cohabitant)
  sont remplacées par une seule liste `_appRoutes` de déclarations
  `_AppRoute(path, builder, {requiredRole})` : le rôle requis est porté par
  la déclaration de route elle-même, la liste des `GoRoute` et la
  vérification dans `redirect` sont dérivées de cette même source. Un
  écran ajouté sans `requiredRole` est public par construction. Aucun
  changement de comportement (mêmes routes protégées qu'avant).
- **2026-07-04 (enums Dart miroirs lifecycle/moderation/accountState)** —
  Trois nouveaux enums `domain/enums/{promo_lifecycle_status,
  promo_moderation_status, commercant_account_state}.dart`, sur le modèle
  de `Categorie` (règle #19). `Promo.lifecycleStatus`/`.moderationStatus`
  et `Commercant.accountState` ne sont plus des `String` comparées par
  littéral mais ces enums ; les getters `isDraft`/`isPublished`/
  `isStopped`/`isExpired`/`lifecycleLabel` et la comparaison dans
  `zone_commerces_screen.dart` (`accountState == 'cree_agent'`)
  sont mis à jour en conséquence. Erreur de compilation garantie en cas de
  renommage backend au lieu d'un bug silencieux.
- **2026-07-04 (première suite de tests mobile)** — `apps/mobile/test/`
  n'existait pas du tout jusqu'ici. Ajout d'une première suite ciblée sur
  de la logique pure (pas de widget test, pas besoin d'émulateur) :
  `pin_validator_test.dart` (regex 4-6 chiffres), `promo_lifecycle_status_test.dart`
  (`fromValue`), `promo_test.dart` (`Promo.fromJson` + `isDraft`/
  `isPublished`/`isExpired`/`lifecycleLabel`, dont un cas non trivial :
  une promo `publiee` dont `dateFin` est déjà dépassée doit être considérée
  expirée côté mobile sans attendre le cron backend
  `expireOutdatedPromos`). **Non exécuté dans mon environnement** (pas de
  SDK Flutter) : lancer `flutter test` en local pour confirmer.
- **2026-07-04 (automatisation netsh portproxy)** — Nouveau script
  `scripts/windows/sync-wsl-portproxy.ps1` (PowerShell, à lancer côté
  Windows en administrateur) : détecte l'IP WSL2 courante (`wsl hostname -I`)
  et recrée les règles `netsh interface portproxy` pour les ports 3000
  (backend) et 9000 (MinIO) — jusqu'ici refait à la main à chaque session
  après un redémarrage WSL. Référencé depuis `apps/mobile/README.md`. Ne
  touche pas au pare-feu (règle entrante à créer une seule fois,
  manuellement). Dernier point de la liste "Reste à faire" — plus aucun
  élément concret restant issu de l'audit à 6 volets.
- **2026-07-05 (codes d'erreur backend + mapping mobile, préparation i18n)**
  — Jusqu'ici, aucun code d'erreur : chaque service levait un
  `BadRequestException('texte français en dur')` et le mobile affichait ce
  message tel quel (`ApiException`/`extractApiErrorMessage`, un seul point
  central côté mobile, mais qui ne faisait que relayer le texte backend).
  Périmètre choisi : codes d'erreur + mapping mobile **français
  uniquement** pour l'instant (pas de traduction des textes d'écran, pas
  d'arabe, pas de sélecteur de langue — voir échange avec l'utilisateur).
  - **Backend** : nouveau `common/errors/error-code.enum.ts` (`ErrorCode`,
    ~30 codes) + `AppException`/`BadRequestAppException`/
    `NotFoundAppException`/`UnauthorizedAppException`/
    `ForbiddenAppException`/`ConflictAppException` (`common/errors/app-exception.ts`)
    qui portent un `code` dans le corps JSON en plus du `message`. Les 33
    sites de `throw new XxxException(...)` de tout le backend (auth, admin,
    agent, commercant, promo, zone, commune, report, device-id decorator)
    sont passés sur ces nouvelles classes. Nouveau `AllExceptionsFilter`
    (`common/errors/all-exceptions.filter.ts`, `app.useGlobalFilters` dans
    `main.ts`) qui garantit `{statusCode, code, message}` même pour les
    erreurs qui n'en portaient pas par construction : `VALIDATION_ERROR`
    pour les 400 de `ValidationPipe` (message dynamique par champ, laissé
    tel quel), `RATE_LIMITED` pour `ThrottlerException`, `INTERNAL_ERROR`
    pour toute erreur non prévue (500, loggée server-side, jamais son vrai
    message renvoyé au client).
  - **Mobile** : `ApiException` porte maintenant `code` en plus de
    `message` ; nouveau `features/shared/errors/error_messages_fr.dart`
    (mapping code -> texte français, une seule langue pour l'instant,
    ajouter une langue = ajouter un fichier `error_messages_<locale>.dart`
    sur ce modèle sans toucher au backend). `ApiException.displayMessage`
    utilise le mapping si le code est connu, sinon retombe sur le message
    backend brut (cas `VALIDATION_ERROR` et des deux codes dont le message
    backend interpole une valeur dynamique : `PROMO_DATE_FIN_EXCEEDS_MAX`,
    `PROMO_ACTIVE_CAP_REACHED`, volontairement absents du mapping).
    `extractApiErrorMessage` (signature inchangée, tous les écrans
    existants continuent de fonctionner sans modification) délègue à
    `displayMessage`. Tests ajoutés : `test/data/api/api_exception_test.dart`.
  - **Non exécuté dans mon environnement** : `npm run build`/`lint` côté
    backend, `flutter test`/`flutter analyze` côté mobile — à confirmer en
    local.
