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

Client (sélection commune, liste promos, détail, favoris, signalement),
Commerçant (inscription, activation d'un compte créé par agent (`claim`,
sans OTP), login PIN, dashboard, promos), Agent (login, zone, création
commerçant, promo avec caméra obligatoire). Pas d'écran admin en V0
(décision assumée). PIN oublié : plus d'écran self-service, seul l'admin
peut réinitialiser (voir l'entrée "suppression OTP/SMS" ci-dessous).

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

Voir `CLAUDE.md` pour les règles générales. Liste concrète des éléments
non traités par cette session de corrections :

1. Révocation JWT (tokenVersion ou refresh token) pour agent/admin.
2. Validation de `JWT_SECRET` au démarrage (rejeter les valeurs par défaut
   en production).
3. Migrations TypeORM versionnées (toujours en `synchronize: true` dev).
4. `flutter test` réel (jamais exécuté ; `flutter analyze` fait et propre).
5. Refactoring `AdminController` (extraire l'orchestration modération dans
   un service dédié).
6. Automatiser le `netsh interface portproxy` (IP WSL2 changeante) si le
   développement mobile via émulateur Android + backend WSL continue —
   sinon documenter clairement la procédure pour chaque nouvelle session.
7. Regex PIN 4-6 chiffres vs 4 fixes dans les specs — décision produit à
   trancher (pas un bug).

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
  **Non exécuté dans mon environnement** (pas de `npm install`/build ici,
  conformément aux instructions) : à valider avec `npm run build && npm
  run lint` côté backend, et `flutter analyze` côté mobile, avant de
  considérer ce changement testé.
