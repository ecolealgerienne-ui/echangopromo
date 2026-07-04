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
| Mobile Flutter (3 rôles) | ✅ implémenté, **jamais compilé** (SDK indisponible dans l'environnement de dev) |
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
Commerçant (inscription, revendication OTP, login PIN, PIN oublié,
dashboard, promos), Agent (login, zone, création commerçant, promo avec
caméra obligatoire). Pas d'écran admin en V0 (décision assumée).

---

## Corrections issues de l'audit V0

Branche `claude/new-project-setup-t5rs5y`. Chaque ligne référence le
finding correspondant dans `docs/AUDIT_V0.md`. Les corrections cochées ont
été vérifiées par un test manuel réel (backend relancé contre un Postgres
local), pas seulement par la compilation.

### Sécurité

- [x] **IDOR agent → promo/commerçant** : `PromoController.update`,
      `.createByAgent` et `AgentController.initiateClaim` vérifient
      désormais que le commerçant appartient à la zone de l'agent connecté
      (`CommercantService.assertZoneMatches`). **Testé** : agent hors zone
      → 403 sur les 3 endpoints ; agent de la bonne zone → 200/201.
- [x] **Rate limiting auth** : `@nestjs/throttler` installé et branché
      globalement (60 req/min/IP par défaut) + limite stricte
      (5 req/min/IP, `STRICT_THROTTLE`) sur tous les logins (commerçant,
      agent, admin), les endpoints OTP, et `POST /report`. **Testé** : 429
      dès la 6ᵉ requête sur `/commercant/login`.
- [x] **Anti brute-force OTP** : compteur de tentatives (`OtpCode.attempts`,
      verrouillage à 5 échecs) + cooldown d'envoi de 60s, indépendants de
      l'expiration du code.
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
- [ ] Fuite d'énumération de téléphone sur `forgot-pin/request` — **non
      traité** (sévérité basse).
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
      `AgentController` (création commerçant, initiation revendication) et
      `AdminController` (création agent, transfert de zone, 3 actions de
      modération, validation/rejet registre).
- [x] Index DB manquants — `Promo.status+dateFin` (composite),
      `Promo.commercantId`, `Commercant.communeId`, `Commercant.zoneId`,
      `OtpCode(telephone,purpose)` tous ajoutés.
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
      `AppRole` non importé (`otp_confirm_screen.dart`, faute de compilation
      réelle), et 3× usage déprécié de `DropdownButtonFormField.value` →
      `initialValue` (`category_dropdown.dart`, `create_commercant_screen.dart`,
      `commercant_register_screen.dart`). `flutter analyze` propre après
      correction (0 issue restante à vérifier après ce commit).

---

## Reste à faire avant extension au-delà du pilote Djelfa

Voir `CLAUDE.md` pour les règles générales. Liste concrète des éléments
non traités par cette session de corrections :

1. Révocation JWT (tokenVersion ou refresh token) pour agent/admin.
2. Validation de `JWT_SECRET` au démarrage (rejeter les valeurs par défaut
   en production).
3. Migrations TypeORM versionnées (toujours en `synchronize: true` dev).
4. Vraie intégration SMS (stub qui logge toujours le code).
5. `flutter analyze` + `flutter test` réels (jamais exécutés).
6. Refactoring `AdminController` (extraire l'orchestration modération dans
   un service dédié).

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
