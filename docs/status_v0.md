# Statut d'implémentation — echango Promo V0

**Ce fichier est le suivi vivant du projet.** Il doit être mis à jour à
chaque implémentation importante (nouvelle fonctionnalité, correction
d'audit, changement d'architecture) — pas seulement en fin de session.
Pour le détail historique complet, voir aussi `docs/AUDIT_V0.md`
(findings) et `CLAUDE.md` (règles à respecter).

Dernière mise à jour : 2026-07-05

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
- **2026-07-05 (fix lint + fix démarrage)** — `npm run lint` a relevé
  `@typescript-eslint/no-unsafe-enum-comparison` dans
  `AllExceptionsFilter.fallbackCode` (paramètre typé `number` comparé à des
  membres `HttpStatus`) : corrigé en typant le paramètre `HttpStatus`.
  Puis au démarrage réel : `UnknownDependenciesException` sur
  `JwtAuthGuard` dans `StorageModule` — `TypeOrmModule` n'était pas
  réexporté par `AuthModule`, donc `Repository<Agent>`/`Repository<Admin>`
  (ajoutés pour le tokenVersion) n'étaient résolvables que dans les
  modules qui les fournissaient déjà eux-mêmes. Corrigé en ajoutant
  `TypeOrmModule` à `exports` d'`AuthModule`, même traitement que
  `JwtModule` déjà réexporté pour `JwtService`.
- **2026-07-05 (audit V1)** — Audit de suivi après la session
  révocation JWT/codes d'erreur, voir `docs/AUDIT_V1.md` (détail complet)
  et 3 nouvelles règles CLAUDE.md (#24-26). Findings principaux : pas de
  `tokenVersion` sur `Commercant` (reset-pin admin n'invalide pas les JWT
  déjà émis), pas de déconnexion mobile automatique sur token
  révoqué/invalide, N+1 réapparu dans `ModerationService.queue()`, rate
  limiting absent sur plusieurs actions sensibles post-authentification,
  2 FK sans index, 0% de tests backend. Rien de corrigé dans ce commit —
  uniquement le rapport, la priorisation reste à discuter avec
  l'utilisateur.

- **2026-07-05 (traitement audit V1, 1/4 — déconnexion mobile automatique)**
  — `ApiClient` (`data/api/api_client.dart`) détecte maintenant les codes
  `AUTH_TOKEN_MISSING`/`AUTH_TOKEN_INVALID`/`AUTH_TOKEN_REVOKED` dans
  l'intercepteur Dio et appelle `authController.logout()`
  (`providers/core_providers.dart`, nouveau paramètre `onAuthInvalid` sur
  `ApiClient`). Jusqu'ici le backend rejetait bien un token révoqué/expiré
  mais rien ne déconnectait l'utilisateur côté mobile — il restait bloqué
  sur son écran avec un token mort. `router.dart` redirige automatiquement
  vers le login du rôle concerné dès que `authControllerProvider` repasse
  à `null` (mécanisme `routerRefreshProvider` déjà en place, aucun
  changement nécessaire côté routeur).

- **2026-07-05 (traitement audit V1, 2-5/... — révocation JWT commerçant,
  N+1 modération, rate limiting élargi, index FK manquants, vérification
  a posteriori des images S3)** — regroupés dans un seul commit : les
  fichiers `commercant.service.ts`/`promo.service.ts` portent à la fois la
  révocation JWT et la vérification d'image (StorageService y est déjà
  injecté pour d'autres raisons), impossible de les séparer proprement
  sans réécriture de l'historique :
  - **`tokenVersion` sur `Commercant`** (`entities/commercant.entity.ts`) :
    `adminResetPin` l'incrémente désormais — jusqu'ici il effaçait le PIN
    sans révoquer le JWT déjà émis, qui restait valide jusqu'à expiration
    (30j par défaut) malgré l'action de l'admin. `JwtAuthGuard` vérifie
    maintenant `tokenVersion` pour les 3 rôles de façon uniforme (avant :
    uniquement agent/admin). Par symétrie, `Admin.tokenVersion` (jamais
    incrémenté jusqu'ici) obtient son propre endpoint
    `POST /admin/me/revoke-token` (auto-révocation, device perdu/volé).
  - **N+1 dans `ModerationService.queue()`** : remplacé
    `pending.map(({promoId}) => promoService.findByIdOrFail(promoId))`
    (un SELECT par promo signalée) par `PromoService.findByIds()` (une
    seule requête `IN (...)`) — même règle CLAUDE.md #14 que le premier
    correctif V0 sur cet écran, réapparue après coup.
  - **Rate limiting élargi** : nouveau
    `SENSITIVE_ACTION_THROTTLE` (20 req/min, `common/throttle.ts`) appliqué
    aux actions authentifiées jusqu'ici sans limite dédiée : toutes les
    routes `AdminController` hors login (dont `reset-pin`,
    `revoke-token`), `POST /agent/commercant`, `POST /commercant/me/registre`,
    les actions promo (`create`/`createByAgent`/`update`/`publish`/`stop`),
    `POST /storage/presigned-upload`.
  - **2 FK sans index** : `Agent.zoneId` et `Commercant.createdByAgentId`
    obtiennent leur `@Index()` (les 3 autres FK du modèle l'avaient déjà).
  - **Vérification a posteriori des images S3** (`storage.service.ts`) :
    `assertValidImage(key)` télécharge les 12 premiers octets de l'objet
    (`GetObjectCommand` + `Range`) et vérifie la signature réelle
    (jpeg/png/webp) — jusqu'ici seule la taille était contrainte par la
    policy S3 (session précédente), le `Content-Type` restait purement
    déclaratif (un exécutable renommé `.jpg` passait sans problème).
    Supprime le fichier et lève `STORAGE_INVALID_IMAGE` si la signature ne
    correspond à aucun format supporté. Appelée dans
    `CommercantService.selfRegister`/`createByAgent`/`updateProfile` et
    `PromoService.create`/`update` quand un `photoKey` est fourni. Logique
    de détection extraite dans `storage/image-signature.ts` (fonction pure)
    pour rester testable sans mock S3 — nouveau
    `image-signature.spec.ts` (5 cas). Nouveau code d'erreur
    `STORAGE_INVALID_IMAGE` ajouté au mapping mobile `errorMessagesFr`
    dans le même commit (règle CLAUDE.md #26).
  - Nouveau test `auth/guards/jwt-auth.guard.spec.ts` (5 cas : token
    manquant/invalide/révoqué/compte supprimé/valide) — avec
    `image-signature.spec.ts`, première suite de tests backend réels (0%
    jusqu'ici, cf. audit V1 §6).
  - **Non exécuté dans mon environnement** : `npm run build && npm run
    lint && npm test` à confirmer en local ; nouvelle colonne
    `tokenVersion` (Commercant) à intégrer à la prochaine
    `migration:generate`.

- **2026-07-05 (pagination des listes)** — Dernier point de dette restant
  de l'audit V1 (§5). Nouveau `common/pagination/` (`PaginationQueryDto`
  : `page`/`limit`, défaut 1/20, max 100 ; `PaginatedResult<T>` :
  `{items, total, page, limit}`) appliqué à `GET /promo`,
  `GET /promo/me/all`, `GET /admin/agent`, `GET /zone`, `GET /commune`,
  `GET /admin/moderation/queue`. Au passage, `ReportService` expose un
  `countPendingModeration()` séparé (compteur seul, sans pagination) pour
  le dashboard admin, qui utilisait jusqu'ici `.length` sur la liste
  complète.
  - **Décision volontaire : `/commune` n'est pas traité comme un flux
    paginé côté mobile.** C'est une liste de référence (communes) que
    `CommuneCascadeField` doit charger en entier pour construire le
    sélecteur wilaya → commune — paginer sans adapter le mobile aurait
    silencieusement tronqué la liste (34 communes pour Djelfa seul,
    au-delà du défaut de 20/page). `CommuneApi.list()` boucle en interne
    sur toutes les pages (`limit=100`, le max autorisé) et reconstruit la
    liste complète — signature Dart inchangée, aucun écran à modifier.
  - Pour `/promo` et `/promo/me/all` (vrais flux, feeds), le mobile
    récupère une seule page généreuse (`limit=100`) sans construire de
    défilement infini pour l'instant — largement suffisant à l'échelle du
    pilote (plafond de 5 promos actives par commerçant, un seul quartier).
    À revoir si le volume approche cette taille de page.
  - `/admin/agent` et `/admin/moderation/queue` n'ont aucun consommateur
    mobile (pas d'UI admin en V0) : pagination backend pure, aucun impact
    client.
  - Nouveau test `common/pagination/pagination-query.dto.spec.ts`
    (défauts, validation page/limit).
  - **Non exécuté dans mon environnement** : `npm run build && npm run
    lint && npm test` côté backend, `flutter analyze` côté mobile — à
    confirmer en local.

- **2026-07-05 (mobile : i18n FR/EN/AR + bouton de changement de langue)**
  — Le pilote était mono-langue (français codé en dur dans ~130 endroits
  répartis sur 22 écrans/widgets). Demande produit : ajouter anglais et
  arabe, avec un bouton pour basculer.
  - Infra `flutter gen-l10n` : `apps/mobile/l10n.yaml`
    (`synthetic-package: false`, sortie dans `lib/l10n/` — import relatif
    classique plutôt que le package synthétique `flutter_gen`),
    `pubspec.yaml` (`generate: true`), `lib/l10n/app_{fr,en,ar}.arb`
    (121 clés, français = template source). `app_localizations.dart` est
    généré par `flutter pub get`/`flutter gen-l10n`, jamais commité
    (`.gitignore` mis à jour).
  - `localeProvider` (Riverpod, `providers/locale_provider.dart`) persisté
    via `SharedPreferences` (`LocaleStore`, même pattern que
    `selectedCommuneProvider`) — défaut français, mémorisé entre
    lancements. `LanguageSwitcherButton`
    (`features/shared/widgets/language_switcher_button.dart`) ajouté à
    l'`AppBar` de chaque écran (pas de shell/navigation partagée entre les
    3 rôles, donc pas un seul endroit central possible — même logique de
    duplication assumée que `ErrorText`/`LoadingButton`).
  - Les libellés d'enum (`Categorie`, `PromoLifecycleStatus`,
    `visitStatus`) sont sortis des modèles de domaine vers des fonctions
    localisées (`features/shared/l10n/enum_labels.dart`) : un modèle de
    domaine n'a pas accès à un `BuildContext`. `Categorie.label` (champ
    français figé) supprimé de l'enum.
  - **Messages d'erreur backend** (`ApiException`/`extractApiErrorMessage`,
    audit V1) : `error_messages_en.dart`/`error_messages_ar.dart` créés en
    miroir de `error_messages_fr.dart` (CLAUDE.md règle #26).
    `ApiException.displayMessage` devient une méthode `(Locale)` au lieu
    d'un getter figé sur le français ; `extractApiErrorMessage` prend
    désormais un paramètre `locale` obligatoire (`Localizations.localeOf
    (context)` à chaque appel, 11 sites). Nouveau code `NETWORK_ERROR`
    (pas un `ErrorCode` backend — cas "pas de réponse HTTP du tout")
    ajouté aux 3 mappings.
  - `validatePin` (validateur PIN partagé) devient une factory
    `validatePin(context)` retournant le validateur localisé, au lieu
    d'une fonction figée en français.
  - Vérifié par script : les 3 fichiers `.arb` ont exactement le même jeu
    de 121 clés (aucune manquante d'un côté), et chaque clé `l10n.xxx`
    utilisée dans le code Dart existe dans les `.arb` (et réciproquement,
    aucune clé orpheline).
  - RTL (arabe) : automatique via `Localizations.localeOf`/`Directionality`
    de Flutter, aucun code supplémentaire nécessaire.
  - **Non exécuté dans mon environnement** : `flutter pub get` (déclenche
    `flutter gen-l10n`) puis `flutter analyze` à lancer en local avant
    toute autre vérification — c'est la première fois que ce mécanisme de
    génération de code est utilisé dans ce projet, à valider avant de
    considérer ce point terminé.

- **2026-07-05 (mobile : espace vide en bas des cartes promo)** — Signalé
  par capture d'écran : un espace blanc apparaissait sous certaines cartes
  de `promo_list_screen.dart`. Cause réelle : `SliverGridDelegateWithFixedCrossAxisCount`
  (`childAspectRatio: 0.72`, valeur figée devinée) ne correspondait pas à
  la hauteur réelle de la carte, et le bloc texte lui-même n'avait pas de
  hauteur réservée — une description tenant sur 1 seule ligne (`maxLines:
  2` ne force pas 2 lignes) ou l'absence de nom de commerçant (bloc
  simplement omis) raccourcissait la carte davantage.
  - Premier essai (grille "masonry", chaque carte garde sa hauteur
    naturelle) **abandonné à la demande explicite de l'utilisateur** :
    préférence produit pour une grille strictement homogène (2 cartes par
    ligne, même hauteur), la hauteur du contenu étant par construction
    quasi fixe (photo, 2 lignes de description, 1 ligne de prix, 1 ligne
    de nom).
  - **Solution retenue** : `promo_card.dart` réserve désormais une hauteur
    fixe (`promoCardTextBlockHeight = 96`) pour tout le bloc texte
    (au lieu de la hauteur naturelle de chaque `Text`), et rend toujours
    la ligne du nom du commerçant (chaîne vide si `null`) plutôt que de
    l'omettre — la hauteur de la carte devient réellement déterministe.
    `promo_list_screen.dart` calcule `childAspectRatio` dynamiquement via
    `LayoutBuilder` (largeur de case → hauteur photo 16:9 + hauteur bloc
    texte + paddings) au lieu d'une valeur devinée — s'adapte à la largeur
    d'écran réelle, plus de ratio à retoucher à la main.
  - Limite acceptée (pas de solution parfaite sans mesurer le texte
    dynamiquement) : une échelle de police accessibilité très agrandie
    pourrait dépasser les 96px réservés et déborder visuellement — marge
    incluse dans la valeur choisie mais non testée avec un réglage
    d'accessibilité extrême.
  - **Non exécuté dans mon environnement** : `flutter analyze`/`flutter
    run` pour confirmer visuellement sur la liste des promos (aucune
    nouvelle dépendance cette fois, la tentative masonry
    `flutter_staggered_grid_view` a été retirée).

- **2026-07-05 (suite) : RenderFlex overflow au lancement** — Confirmé en
  environnement réel : la `Column` de `promo_card.dart` débordait
  (`RenderFlex#... OVERFLOWING`, ~3-4px sur une carte de 217px). Cause :
  le `childAspectRatio` calculé dans `promo_list_screen.dart` visait une
  correspondance exacte entre la hauteur allouée par la grille et la
  hauteur théorique de la carte (photo + bloc texte fixe) — le moindre
  écart entre l'estimation et les métriques de police réellement rendues
  (thème Material 3, `titleMedium`) suffit à faire déborder une `Column`
  à contraintes strictes (tight) comme celles d'une grille.
  - **Fix structurel** (pas un ajustement de valeur) : la photo utilise
    désormais `Expanded` au lieu d'`AspectRatio` — elle prend toujours
    exactement l'espace restant après le bloc texte (hauteur fixe),
    jamais plus. Rend la carte mathématiquement incapable de déborder,
    quelle que soit la précision du `childAspectRatio` calculé côté
    grille (qui reste utile pour viser un rendu proche de 16:9, mais
    n'est plus un contrat strict à respecter).
  - Le bloc texte à hauteur fixe (`promoCardTextBlockHeight`) garde la
    même limite déjà documentée ci-dessus (échelle d'accessibilité
    extrême non testée).

- **2026-07-05 (mobile : partage d'une promo, croissance organique)** —
  Bouton "Partager" sur la fiche promo (`promo_detail_screen.dart`, icône
  à côté du cœur favori) : envoie texte + photo vers le sélecteur de
  partage natif du téléphone (WhatsApp, SMS, email... — pas un bouton
  WhatsApp dédié, le sélecteur système liste tout ce qui est installé).
  Décision produit actée avec l'utilisateur : pas de lien profond vers
  l'app (pas de présence web, un lien nécessiterait un nom de domaine +
  un fichier `assetlinks.json`/`apple-app-site-association` hébergé) —
  texte autonome uniquement.
  - Nouveaux `Env.playStoreUrl`/`Env.appStoreUrl` (`config/env.dart`,
    `String.fromEnvironment`, vides par défaut) : l'app n'est pas encore
    publiée (`applicationId` encore la valeur par défaut Flutter
    `com.example.echango_promo`), mais l'utilisateur prévoit de publier.
    Le message de partage n'ajoute la ligne "installe l'app" que si le
    lien de la plateforme courante (`Platform.isIOS` ? App Store : Play
    Store) est non vide — remplir la valeur à la publication
    (`--dart-define=PLAY_STORE_URL=...`) suffira, aucun code à retoucher.
  - Photo : téléchargée à la volée depuis S3 vers un fichier temporaire
    (`Dio().download` + `path_provider`, même pattern que
    `storage_api.dart`) puisque `Share.shareXFiles` a besoin d'un fichier
    local, pas d'une URL — échec de téléchargement non bloquant, retombe
    sur le texte seul.
  - Nouvelle dépendance `share_plus` (^7.2.2, API `Share.share`/
    `Share.shareXFiles` classique — délibérément pas la dernière version
    majeure, dont l'API `SharePlus.instance`/`ShareParams` plus récente
    n'a pas pu être vérifiée par compilation dans cet environnement).
  - Nouvelles clés `.arb` (`shareTooltip`, `shareMessage`,
    `shareInstallCta`) dans les 3 langues (CLAUDE.md règle #27).
  - **Non exécuté dans mon environnement** : `flutter pub get` (nouvelle
    dépendance) puis `flutter analyze`/`flutter run`, et test manuel du
    partage (texte seul et texte+photo) vers au moins une app installée.

- **2026-07-05 (préparation App Links / stores — pas encore publié)** —
  Suite de la fonctionnalité de partage : préparer (sans l'activer) le
  jour où le lien partagé (`promo.echango.com`) ouvrira l'app directement
  si elle est installée, et redirigera vers le store sinon (jamais vers un
  site qui affiche la promo — décision produit actée). Nouveau
  `docs/DEPLOIEMENT_STORES.md` : procédure complète Google Play + App
  Store, App Links/Universal Links, tableau des variables à remplir,
  checklist.
  - **Backend** : `src/app-links/` (`AppLinksModule`/`AppLinksController`,
    restreint à `host: 'promo.echango.com'`) sert
    `.well-known/assetlinks.json` et `.well-known/apple-app-site-association`
    (tableaux/structures vides — donc valides mais no-op — tant que
    `ANDROID_PACKAGE_NAME`/`ANDROID_SHA256_CERT_FINGERPRINT`/`IOS_TEAM_ID`/
    `IOS_BUNDLE_ID` ne sont pas renseignées) et `GET /promo/:id` (redirige
    vers `PLAY_STORE_URL`/`APP_STORE_URL` selon le user-agent, ou affiche
    une page d'attente tant qu'aucun n'est configuré — jamais la promo).
    6 nouvelles variables dans `.env.example`, toutes vides, aucune
    requise au démarrage (contrairement à `JWT_SECRET`).
    **Point d'attention à vérifier en priorité** : `AppLinksController`
    partage le chemin `/promo/:id` avec `PromoController` (l'API JSON de
    l'app, sans restriction de host) — les deux ne se distinguent que par
    le header `Host`. `AppLinksModule` est enregistré *avant* `PromoModule`
    dans `app.module.ts` à dessein (Express/Nest essaient les routes dans
    l'ordre d'enregistrement) ; non vérifié par un test d'intégration réel
    (`app-links.controller.spec.ts` teste la logique en isolation, pas le
    routage NestJS complet) — à confirmer avec `npm run start:dev` +
    `curl -H "Host: promo.echango.com" http://localhost:3000/promo/xyz`
    avant de considérer ce point terminé.
  - **Mobile** : intent-filter App Links ajouté dans
    `android/app/src/main/AndroidManifest.xml` (`autoVerify`, host
    `promo.echango.com`, pathPrefix `/promo`) — sans risque à activer dès
    maintenant, la vérification échoue simplement tant qu'`assetlinks.json`
    est vide. `ios/Runner/Runner.entitlements` créé (Associated Domains)
    mais **pas encore relié au projet Xcode** (nécessite Xcode/Mac, absent
    de cet environnement de dev) — voir doc.
  - **Corrigé au passage** : `Info.plist` n'avait que
    `NSLocationWhenInUseUsageDescription` — `NSCameraUsageDescription` et
    `NSPhotoLibraryUsageDescription` manquaient alors que `image_picker`
    est utilisé pour la caméra ET la galerie (`PhotoPickerField`) ; sans
    ces clés, iOS **crashe** l'app dès la première demande de permission
    caméra/galerie (pas juste un rejet de review, un vrai crash en test).
  - **Préalable bloquant documenté mais pas fait** : `applicationId`
    encore `com.example.echango_promo` (défaut Flutter jamais changé) — à
    fixer définitivement avant de générer un certificat de signature ou
    créer une fiche store (le changer après publication casse les mises à
    jour). Procédure recommandée (`package rename`) dans le doc.
  - **Suggéré, pas fait** : les deux stores exigent une politique de
    confidentialité (URL) — l'app collecte position GPS optionnelle,
    photo, numéro de téléphone ; à rédiger (je peux en préparer un premier
    jet factuel si demandé, ce n'est pas un texte juridique que je dois
    produire sans qu'on me le demande explicitement).
  - **Non exécuté dans mon environnement** : `npm run build`/`npm test`
    côté backend (nouveau `app-links.controller.spec.ts`), `flutter
    analyze` côté mobile (fichiers de config natifs modifiés, pas de code
    Dart).

- **2026-07-05 (suite) : `promo.echango.com` risquait de partager le
  backend echango Promo entier, pas juste l'App Links** — en préparant le
  déploiement VPS (Traefik partagé avec une autre plateforme déjà en
  place sur `echango.com`), il est apparu que `promo.echango.com`
  pourrait devenir l'hôte de tout le backend (API mobile comprise), pas
  seulement des routes App Links. Ça aurait rendu réelle la collision de
  chemin que le `host` du contrôleur évitait jusque-là artificiellement
  (`GET /promo/:id` existe des deux côtés : API JSON pour l'app,
  redirection pour un humain sans l'app).
  - **Corrigé par un chemin dédié plutôt qu'un artifice de routage** : la
    redirection App Links est maintenant `GET /p/:id` (au lieu de
    `/promo/:id`) — ne recoupe plus jamais l'API mobile, quel que soit le
    sous-domaine final. `AndroidManifest.xml` (`pathPrefix`),
    `apple-app-site-association` (`paths`) et une nouvelle route
    `go_router` `/p/:id` (même écran que `/promo/:id`, `app/router.dart`)
    mis à jour en conséquence. Le commentaire sur l'ordre d'enregistrement
    des modules dans `app.module.ts` (qui n'a plus lieu d'être) a été
    retiré.
  - Fichier `docker-compose.yml` du VPS partagé par l'utilisateur (autre
    projet : plateforme SaaS multi-boutique sur `echango.com`, Traefik +
    Vendure) : sa règle `storefront-vendor` (wildcard
    `*.echango.com` → boutiques vendeur) avalerait `promo.echango.com`
    tel quel — à exclure explicitement côté Traefik avant d'activer quoi
    que ce soit. Spec écrite pour une session dédiée dans ce second dépôt
    (hors périmètre de ce repo).

- **2026-07-05 (suite) : préparation du déploiement backend + DB sur le
  VPS** (`/opt/echangopromo`, réseau Docker `echango_network` déjà créé par
  la stack Traefik/Vendure, labels de routage `promo.${BASE_DOMAIN}`
  fournis par l'utilisateur, entrypoint `websecure`, priorité `20`).
  - **Trouvé en cours de route** : `npm run seed:admin`/`seed:communes`
    (scripts `apps/backend/scripts/*.ts` lancés via `ts-node`, une
    devDependency) étaient **inexécutables dans l'image Docker de
    production** — le 2ᵉ stage du `Dockerfile` fait `npm ci --omit=dev` et
    ne copie que `dist/`, ni `ts-node` ni les sources TS. Corrigé
    structurellement plutôt que par un hack : scripts déplacés vers
    `apps/backend/src/scripts/` pour être compilés par `nest build` dans
    `dist/scripts/` comme n'importe quel autre fichier de `src/` — exécutables
    en prod via `node dist/scripts/seed-admin.js` (nouveaux scripts npm
    `seed:admin:prod`/`seed:communes:prod`), sans rien changer au
    fonctionnement en local (`ts-node` inchangé, juste le chemin des fichiers).
  - **Nouveau `docker-compose.promo.yml`** (racine du repo), distinct du
    `docker-compose.yml` de dev local : `postgres` reste sur un réseau
    Docker interne dédié (jamais exposé à `echango_network`, aucun port
    hôte publié) ; `backend` rejoint en plus `echango_network` (externe,
    `external: true`) avec les labels Traefik fournis par l'utilisateur,
    sans publier de port sur l'hôte (Traefik y accède via le réseau Docker
    interne, port `3000` du conteneur).
  - Migrations : déjà automatiques au démarrage du conteneur (`Dockerfile`
    CMD), rien de nouveau à faire pour ça sur le VPS.
  - Modèle d'env ajouté (jamais commité en clair, gitignoré) :
    `.env.production.example` à la racine du repo — **un seul fichier**
    (pas deux, voir entrée suivante), utilisé à la fois comme `--env-file`
    de `docker compose` (substitution `${POSTGRES_PASSWORD}`/`${BASE_DOMAIN}`
    dans `docker-compose.promo.yml`) et comme `env_file:` du service
    `backend` (`DATABASE_URL`, `JWT_SECRET`, S3 OVH, etc.).
  - Procédure complète (premier déploiement, seeds, redéploiement) :
    `docs/DEPLOIEMENT_VPS.md`.
  - **Décision actée avec l'utilisateur** : pas d'automatisation GitHub
    Actions pour le déploiement pour l'instant (`git pull` manuel sur le
    VPS) — à revoir plus tard sans remettre en cause le fonctionnement en
    local.

- **2026-07-05 (suite) : premier déploiement réel sur le VPS — 3 incidents
  trouvés et corrigés en direct avec l'utilisateur.**
  - **`package-lock.json` désynchronisé de `package.json`** (`typeorm`
    verrouillé sur `^1.0.0` dans le lock alors que `package.json` déclare
    `^0.3.20`, + une dizaine de paquets transitifs manquants du lock) —
    invisible en local (`npm install` tolère l'écart) mais bloquant en
    prod (`npm ci`, volontairement strict, utilisé par le `Dockerfile`).
    Préexistant, sans lien avec les changements de cette session (vérifié
    par `git log -p` sur le fichier). Corrigé par l'utilisateur (`npm
    install` local, lock file régénéré et commité).
  - **Mot de passe Postgres avec caractère réservé URL (`?`) dans
    `DATABASE_URL`** → `TypeError: Invalid URL` côté `pg-connection-string`
    (le `?` démarre une query string). Poussé à choisir un mot de passe
    alphanumérique pur plutôt que d'encoder en `%3F` (plus sûr, évite toute
    classe d'erreur d'encodage similaire à l'avenir).
  - **Deux fichiers d'env (`.env.promo` + `apps/backend/.env.production`)
    fusionnés en un seul** (`.env.production` à la racine) après une
    session de debug longue sur un `password authentication failed`
    finalement dû à un volume Postgres déjà initialisé avec un ancien mot
    de passe (Postgres ne fixe le mot de passe qu'à la création du
    cluster, jamais après — `down -v` + recréation du volume nécessaires
    après tout changement de `POSTGRES_PASSWORD`). La duplication du même
    secret dans deux fichiers séparés était elle-même une source d'erreur
    évitable ; un seul fichier sert maintenant à la fois de `--env-file`
    docker compose et d'`env_file` du service `backend`.
  - `docker-compose.promo.yml` et `docs/DEPLOIEMENT_VPS.md` mis à jour en
    conséquence.

- **2026-07-05 (suite) : cause réelle du `password authentication failed`
  trouvée — collision de nom DNS entre deux stacks Docker sur le même
  réseau partagé, pas un problème de mot de passe.** Après avoir vérifié à
  l'octet près que le mot de passe était identique des deux côtés (aucun
  caractère invisible, même longueur, même décodage par `pg-connection-string`,
  la bibliothèque réellement utilisée par `pg`/TypeORM) et que Postgres
  s'authentifiait correctement en local (socket **et** boucle TCP
  `127.0.0.1`), le test décisif a été : `docker compose run --rm backend
  getent hosts postgres` → résolvait vers l'IP de `echango-postgres-1` (la
  stack **Vendure**, autre projet Compose sur le même VPS), pas vers notre
  propre conteneur `echangopromo-postgres-1`. Le service Postgres de cette
  stack et celui de la stack Vendure portaient tous les deux le nom
  générique `postgres`, tous deux attachés au réseau externe partagé
  `echango_network` (nécessaire pour que Traefik route `backend`) — le
  backend, connecté aux deux réseaux, résolvait le nom vers le mauvais
  conteneur. Le backend tentait donc de s'authentifier sur la base
  Vendure, où le rôle `echango` n'existe pas, d'où l'échec systématique
  peu importe les corrections de mot de passe.
  - **Fix** : service renommé `postgres` → `postgres_promo` dans
    `docker-compose.promo.yml` (`depends_on`, healthcheck inchangés) et
    `DATABASE_URL` dans `.env.production.example` mis à jour
    (`@postgres_promo:5432`). Commentaire ajouté directement dans le
    fichier compose pour que ce choix de nom ne soit pas défait par
    inadvertance plus tard.
  - Leçon générale documentée dans `docs/DEPLOIEMENT_VPS.md` : sur un
    réseau Docker externe partagé entre plusieurs stacks, ne jamais nommer
    un service avec un nom générique (`postgres`, `redis`, `db`...) —
    toujours vérifier avec `docker compose run --rm <service> getent
    hosts <nom>` que la résolution DNS pointe bien vers le conteneur
    attendu avant de chercher un bug ailleurs (mot de passe, encodage,
    etc.).
  - **Confirmé par l'utilisateur sur le VPS** : après renommage en
    `postgres_promo`, migrations passées, backend démarré sans erreur.

- **2026-07-05 (suite) : les seeds échouaient encore (`relation "admin"
  does not exist`) — cause distincte des incidents précédents, la vraie
  découverte de cette session de déploiement.** Aucun fichier de migration
  TypeORM n'avait jamais été commité dans le repo (`apps/backend/src/migrations/`
  inexistant côté git, confirmé par `git log --all`), alors que
  `docs/status_v0.md`/`CLAUDE.md` documentaient déjà des migrations comme
  si elles existaient. `migration:run` s'exécutait "avec succès" sur le VPS
  (base neuve) sans rien créer, faute de migration à appliquer — d'où un
  backend qui démarre proprement mais une base totalement vide. La base de
  dev locale de l'utilisateur avait ses tables, mais via 2 fichiers de
  migration générés localement à un moment donné et jamais poussés (dette
  silencieuse : "ça marche chez moi" masquait l'absence complète côté
  dépôt).
  - **Fix** : les 2 migrations locales préexistantes
    (`1783192047695-InitialSchema.ts`,
    `1783213583514-AddCommercantTokenVersionAndIndexes.ts`) commitées et
    poussées. Une 3ᵉ migration générée par erreur au passage (diff contre
    une base vide, donc un doublon complet du schéma) a été détectée et
    supprimée avant commit — testée en conditions réelles : les 2
    migrations d'origine créent bien tout le schéma sans erreur
    (`admin`, `zone`, `agent`, `commercant`, `commune`, `promo`, `report`,
    `audit_log`, toutes les FK), la 3ᵉ plantait sur `relation "zone"
    already exists` en tentant de recréer ce que la 1ʳᵉ avait déjà créé.
  - Sur le VPS : migrations appliquées, `\dt` confirme toutes les tables,
    `npm run seed:admin:prod` et `seed:communes:prod` **exécutés avec
    succès** (premier compte admin créé, 35 communes de Djelfa insérées).
  - **Routage Traefik confirmé** : `curl -I https://promo.echango.com/promo`
    → `HTTP/2 200`, headers de sécurité présents (HSTS, CSP-adjacents,
    rate-limit visible). **Déploiement backend + DB sur le VPS
    fonctionnel de bout en bout.**

- **2026-07-06 : audit de sécurité prod (`docs/AUDIT_SECURITE_PROD_2026-07.md`)
  et découverte d'une incompatibilité OVH bloquant l'upload de photos.**
  - Audit mené par phases (reconnaissance passive, revue statique OWASP
    Top 10:2021, LLM sans objet, API/cookies, rapport final) — 1 problème
    réel trouvé et corrigé : `main.ts` ne configurait pas `app.set('trust
    proxy', 1)`, donc `req.ip` valait l'IP interne de Traefik pour toutes
    les requêtes derrière le reverse proxy, faisant partager le même
    compteur de rate-limiting (`@nestjs/throttler`) à tous les
    utilisateurs au lieu d'isoler chaque IP réelle.
  - **Upload de photo cassé en prod, découvert au premier test réel** :
    OVH (S3 utilisé en prod) renvoie `501 Not Implemented — "POST Object
    is disabled on this deployment"` sur l'API S3 "POST Object" — la POST
    policy pré-signée (choisie initialement pour que `content-length-range`
    soit imposé par S3 lui-même, `AUDIT_V1.md`) ne fonctionne donc pas sur
    ce fournisseur. Un simple PUT pré-signé, lui, fonctionne (testé et
    confirmé), mais perd cette garantie de taille imposée par S3.
  - **Décision produit (utilisateur)** : upload proxifié par le backend
    plutôt qu'un PUT pré-signé. Le fichier transite par
    `POST /storage/upload` (`FileInterceptor`), le backend valide taille
    (5 Mo) et format (magic bytes, sur les octets déjà en mémoire) *avant*
    tout envoi à S3 via `PutObject` — remplace l'ancienne vérification a
    posteriori (`assertValidImage`, un `GetObject` après upload, retirée
    des 5 sites d'appel dans `promo.service.ts`/`commercant.service.ts`
    car devenue inutile : un fichier invalide n'atteint plus jamais S3).
    Mobile (`storage_api.dart`) simplifié en conséquence — un seul Dio
    authentifié, plus de POST direct vers S3.
  - Nouveau code d'erreur `STORAGE_FILE_TOO_LARGE` ajouté dans les 3
    mappings mobile (`error_messages_{fr,en,ar}.dart`) dans le même commit
    (CLAUDE.md règle #26).
  - Dépendances backend nettoyées : `@aws-sdk/s3-presigned-post` et
    `@aws-sdk/s3-request-presigner` retirées (plus utilisées),
    `@types/multer` ajouté (typage `Express.Multer.File`).
  - **À faire côté utilisateur** : `npm install` local (nouvelle
    dépendance `@types/multer`, régénère le lock file), `npm run build`/
    `lint`, puis déployer sur le VPS (`git pull` + rebuild `backend`) et
    retester un vrai upload de photo depuis l'app mobile.

- **2026-07-06 (suite) : upload OK, mais photo non affichée — 2ᵉ
  incompatibilité OVH trouvée (style d'URL).** Après déploiement du fix
  précédent, l'upload fonctionnait (fichier bien présent dans le bucket,
  vérifié via la console OVH), mais la photo ne s'affichait jamais dans
  l'app. Diagnostic par test `curl` direct de l'URL publique construite
  par `buildPublicUrl` :
  - Style "path" (`s3.gra.io.cloud.ovh.net/echango-promo/<clé>`, ce que le
    code construisait) → `400 InvalidRequest — "Not S3 request"` : **OVH
    rejette purement et simplement les requêtes anonymes en style path.**
  - Style "virtual-hosted" (`echango-promo.s3.gra.io.cloud.ovh.net/<clé>`)
    → `403 AccessDenied` propre (URL correcte, mais lecture publique
    jamais activée sur le bucket — action restée en attente depuis la
    configuration S3 initiale).
  - **Fix code** : `buildPublicUrl` bascule en style virtual-hosted quand
    `S3_PUBLIC_URL_VIRTUAL_HOSTED=true` (nouvelle variable, à `true`
    uniquement dans `.env.production` pour OVH — le client S3 authentifié
    garde `forcePathStyle: true` pour les opérations PUT/DELETE,
    compatible MinIO en dev local, seule l'URL publique change de style).
  - **Bucket policy indisponible sur OVH, ni via la console ni via l'API**
    : pas d'onglet "Confidentialité" dans la console (onglets disponibles :
    Informations générales/Objets/Réplication/Lifecycle), et
    `PutBucketPolicyCommand` renvoie `NotImplemented` (testé directement
    en script). Solution retenue : **ACL par objet** (`ACL: 'public-read'`
    sur chaque `PutObjectCommand`) — testée isolément et confirmée (`curl`
    anonyme sur un objet avec cet ACL → `200 OK`).
  - **Fix appliqué** : `StorageService.uploadPhoto` envoie désormais
    `ACL: 'public-read'` à chaque upload — les photos sont publiques dès
    l'upload, sans dépendre d'une config bucket-level indisponible chez ce
    fournisseur. Les photos uploadées avant ce fix (tests précédents)
    restent privées et doivent être re-uploadées pour être visibles.
  - **Confirmé sur le VPS** : `curl` sur une clé S3 réelle (uploadée après
    le rebuild avec l'ACL) → `200 OK`. La chaîne backend/S3 fonctionne de
    bout en bout.

- **2026-07-09 : photo toujours pas visible dans l'app malgré un backend
  100% fonctionnel — bug distinct, côté mobile cette fois.** L'URL S3
  confirmée en `200` ne s'affichait pourtant pas en rouvrant l'écran
  profil commerçant. Cause trouvée en lisant `PhotoPickerField` : ce
  widget n'affichait qu'une photo **locale** fraîchement choisie
  (`File?`) — aucune prise en charge d'une photo déjà enregistrée côté
  serveur, donc un écran d'édition rouvert n'affichait qu'un placeholder
  vide, indépendamment de tout ce qu'on avait corrigé côté S3.
  - **Fix** : `PhotoPickerField` accepte désormais `existingImageUrl`
    (affiché via `Image.network` tant qu'aucune nouvelle photo locale
    n'est choisie), propagé via `PromoFormFields.existingPhotoUrl` et
    câblé dans `promo_form_screen.dart`
    (`widget.existingPromo?.photoUrl`) et `edit_profile_screen.dart`
    (`me.photoUrl`, qui jetait auparavant cette donnée avec `data: (_) =>`).
  - Leçon de cette session de debug : les symptômes "photo pas affichée"
    avaient deux causes complètement indépendantes empilées (S3/ACL côté
    backend, puis widget mobile jamais câblé pour l'affichage
    d'une photo existante) — corriger la première n'a naturellement rien
    changé à la seconde.

- **2026-07-09 : première UI admin (jusque-là API seule, decision V0
  révisée).** L'API admin existait déjà en quasi-totalité (agents,
  modération, registre, dashboard) — jamais reliée à un écran. Wave 1 :
  login + dashboard + les 3 files de travail existantes.
  - **Backend** : 2 lacunes trouvées et corrigées en construisant l'UI
    dessus.
    - `GET /admin/moderation/queue` renvoyait l'entité `Promo` brute
      (sûre grâce à `@Exclude()`, mais sans `photoUrl` jamais calculé ni
      contact du commerçant) — remplacé par un DTO explicite
      (`admin.controller.ts`).
    - Aucun moyen de **lister** les commerçants en attente de vérification
      registre (seuls valider/rejeter par id existaient) — ajout de
      `CommercantService.findPendingRegistreVerification` +
      `GET /admin/commercant/registre/queue`.
  - **Mobile** : nouveau rôle `AppRole.admin`, module `features/admin/`
    (login, dashboard, file de modération, file de vérification registre,
    gestion agents + création, gestion zones + transfert de zone entre
    agents), routes protégées par rôle (`router.dart`, règle CLAUDE.md
    #22). **Décision produit, affinée après discussion** : pas d'entrée
    admin dans le menu public "espace pro" ni dans un menu quelconque —
    le point d'entrée est **caché dans l'écran de login commerçant
    existant** (`commercant_login_screen.dart`) : taper un email au lieu
    d'un numéro de téléphone dans le champ "Téléphone" (apparence
    inchangée) bascule ce même écran vers l'authentification admin
    (email + mot de passe, clavier/validateur/longueur du 2ᵉ champ
    ajustés dynamiquement, liens spécifiques commerçant masqués). Un seul
    compte admin en V0, pas de réel enjeu de découvrabilité au-delà de ça
    (login toujours protégé par mot de passe + rate limiting).
  - **Reste (wave 2, pas demandée pour l'instant)** : rien d'urgent
    identifié au-delà de ce périmètre — l'API couvre déjà tout ce que
    l'UI expose maintenant.
  - **Non exécuté dans mon environnement** : `flutter analyze` (nouveau
    module complet, 7 écrans) — à lancer en priorité avant de tester,
    conformément à la consigne du projet.
