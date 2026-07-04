# Audit V0 — echango Promo

**Statut** : les 6 audits sont terminés. Ce document reste le compte-rendu
figé des findings tels que trouvés — pour savoir ce qui a été corrigé
depuis, voir `docs/status_v0.md` (la plupart des findings critiques/hauts
de sécurité et les bugs d'architecture identifiés ici ont été traités dans
la foulée). `CLAUDE.md` tire les leçons générales pour la suite du
développement.

**Note (2026-07-04)** : l'OTP SMS mentionné dans plusieurs findings
ci-dessous (brute-force OTP, rate limiting d'envoi, index `OtpCode`) a
depuis été **supprimé du projet** (décision produit : jugé inutile et
coûteux) — ces findings n'ont plus d'objet, le code correspondant
n'existe plus. Détail dans `docs/status_v0.md`.
**Méthode** : 6 audits indépendants menés en parallèle par des agents en
lecture seule (aucune modification de code), sur la branche
`claude/new-project-setup-t5rs5y` (commit `e56c015`). L'audit fonctionnel
s'est lui-même décomposé en deux sous-analyses (mobile vs specs, backend
vs specs) vu le volume à couvrir.

| # | Audit | Statut |
|---|---|---|
| 1 | Fonctionnel (conformité specs) | ✅ terminé |
| 2 | Architecture technique | ✅ terminé |
| 3 | Sécurité | ✅ terminé |
| 4 | Qualité de code & dette technique | ✅ terminé |
| 5 | Vérifiabilité mobile / risque de compilation | ✅ terminé |
| 6 | Performance & scalabilité | ✅ terminé |

Les recommandations synthétisées à partir de ces findings sont dans
`CLAUDE.md` à la racine du dépôt.

---

## 1. Fonctionnel — ✅ terminé

Mené en deux sous-audits : mobile vs specs vs backend, puis backend vs
specs point par point (les 12 règles métier des specs V0).

### Mobile vs specs vs backend

**Verdict** : l'app mobile est réellement câblée de bout en bout à l'API
(0 mock, 0 écran vide, 14/14 écrans fonctionnels). Toutes les règles
vérifiées sont conformes : device ID anonyme, sélection commune, favoris
100% locaux, catégories fermées (pas de recherche texte libre), login
commerçant PIN sans OTP récurrent, OTP réservé à inscription/revendication/PIN
oublié, capture photo caméra-only pour l'agent (galerie autorisée pour le
commerçant), pas de géolocalisation, compression image avant upload
(1200px/qualité 80 conforme à la spec), statuts de zone agent corrects,
absence d'écran admin cohérente avec la décision assumée.

**Gaps mineurs identifiés :**
- Le plafond de 5 promos actives n'a pas de garde-fou proactif côté UI
  (le bouton "Nouvelle promo" reste actif au-delà du seuil) — l'utilisateur
  ne découvre le blocage qu'après soumission, via le message d'erreur
  backend. (`apps/mobile/lib/features/commercant/screens/my_promos_screen.dart:21-28`)
- La durée de validité par défaut de 5 jours n'est ni affichée ni éditable
  au moment de la création de la promo — le commerçant la découvre après
  coup dans la liste. (`apps/mobile/lib/features/commercant/screens/promo_form_screen.dart:11-13`)

**Constat documentaire** : `docs/ARCHITECTURE.md` §4 affirme encore
*« squelette de navigation seulement, aucun écran n'est encore relié à
l'API »* — cette phrase date du commit `54b3ec2` et n'a jamais été mise à
jour après l'implémentation complète du mobile (`e56c015`). **À corriger.**

### Backend vs specs (12 règles métier)

**Cycle de vie commerçant + vérification** : conforme, avec un écart
mineur assumé — `CommercantAccountState.REVENDIQUE` (`commercant.entity.ts:20`)
n'est **jamais assigné nulle part** (confirmé par grep), les deux parcours
sautent directement à `AUTONOME` (`commercant.service.ts:101-118`, justifié
en commentaire). État mort dans l'enum, pas un bug, mais trompeur pour un
futur lecteur. Les 2 niveaux de vérification (`auto_inscrit`/`confirme_agent`)
sont bien tous deux suffisants pour publier, `vérifié_registre` bien
indépendant et jamais bloquant.

**Plafond 5 promos + durée 5 jours** : valeurs conformes, mais **bug réel
de race condition** — `PromoService.create()` (`promo.service.ts:50-78`)
fait un `count()` puis un `save()` sans transaction ni verrou
(`SELECT ... FOR UPDATE`) : deux créations quasi simultanées pour le même
commerçant peuvent chacune lire `activeCount = 4` et passer, aboutissant à
6 promos actives. Impact réel faible à l'échelle du pilote (peu de
créations concurrentes), mais à corriger avant montée en charge.

**Anti-fraude signalements** : conforme, y compris la logique fine de la
fenêtre d'ignore de 30 jours (le bug classique "bloquer tous les
signalements pendant 30 jours" n'est **pas** présent — seuls les
signalements antérieurs à `verifiedOkAt` sont exclus, les nouveaux devices
comptent normalement). Comportement post-fenêtre (les anciens signalements
"recomptent" une fois les 30 jours passés) est une interprétation
raisonnable mais non explicitement spécifiée — à faire valider par le
porteur de projet.

**Commune vs Zone** : conforme, séparation stricte, `ZoneController`
intégralement réservé à l'admin.

**6 catégories** : conforme, enum PostgreSQL réel (pas juste une
contrainte applicative) + `@IsEnum` sur tous les DTOs concernés.

**Preuve de passage agent** : conforme sur l'absence de géolocalisation.
Écart non documenté : pas de champ dédié type `photoTakenAt` distinct de
`createdAt`/`updatedAt` — une mise à jour de photo par l'agent ne laisse
pas de trace d'horodatage spécifique à cette nouvelle capture.

**OTP SMS** : conforme — uniquement inscription/revendication/PIN oublié,
jamais à la connexion normale.

**Stockage image** : rétention conforme (suppression S3 à 1 mois,
métadonnées conservées indéfiniment). Écart confirmé : aucune validation
de taille côté backend sur l'upload S3 pré-signé (*converge avec l'audit
sécurité, finding critique #8*). Note mineure : le document de registre de
commerce est uploadé sous le même préfixe `promo-photos/{commercantId}/`
que les photos de promo — incohérence de nommage sans impact fonctionnel
(le cron de purge n'opère que sur la table `Promo`).

**Actions admin** : conforme sur le périmètre couvert. Le transfert de
zone est bien conçu (les fiches commerçant ne bougent pas, c'est
`Agent.zoneId` qui change, donc les commerces suivent automatiquement).
`resolveAvertir` ne notifie pas réellement le commerçant (aucun mécanisme
de notification n'existe) — cohérent avec l'absence de push en V0, mais
"avertir" reste silencieux en pratique.

**Dashboard commerçant, vues par device unique** : conforme, aucun
compteur brut, tout est dédupliqué par device via contrainte unique + `orIgnore()`.

**Cron d'expiration** : conforme, s'applique même aux promos `SIGNALEE`/
`VERIFIEE_OK` passées leur date (l'expiration prime sur la modération),
et l'agent ne peut pas modifier `dateFin` via `PATCH /promo/:id` — empêche
bien la "simple prolongation" interdite par les specs.

**Auth agent/admin** : conforme, aucune route de création d'agent/admin en
dehors du flux prévu (admin crée les agents, bootstrap manuel pour l'admin).

### Anomalie fonctionnelle non couverte par les autres audits

**Un commerçant auto-inscrit (`auto_inscrit`, sans agent assigné) n'a
aucun moyen de corriger une erreur de saisie sur une promo déjà publiée** :
`PATCH /promo/:id` est réservé au rôle `agent` (`promo.controller.ts:87-92`),
il n'existe aucune route équivalente côté commerçant. Potentiellement en
tension avec l'autonomie visée pour ce profil par les specs §3.2.

Et deux findings qui convergent fortement avec les audits sécurité/architecture
(4 audits indépendants sur le même point, voir section convergences en bas
de page) : `AuditLogModule` jamais branché, et absence de vérification de
zone sur `createByAgent`/`update`/`initiateClaim` côté agent.

---

## 2. Architecture technique — ✅ terminé

### Bugs concrets liés à la fusion cycle de vie / modération dans `Promo.status`

**Sévérité haute — `PromoService.countVisible()` surcompte les promos actives**
`apps/backend/src/promo/promo.service.ts:239-243`. Filtre par `status IN
(ACTIVE, VERIFIEE_OK)` sans jamais comparer `dateFin`, contrairement à
`findActiveForClient()` qui ajoute `AND dateFin > NOW()`. Une promo expirée
reste comptée comme "publiée" au dashboard admin jusqu'au passage du cron
quotidien (jusqu'à 24h de statistique fausse).

**Sévérité haute — Duplication de la règle de visibilité entre deux services**
`apps/backend/src/commercant/commercant.service.ts:232-242` vs
`apps/backend/src/promo/promo.service.ts:21`. `listByZoneWithVisitStatus`
(écran agent "ma zone") ne considère que `status: ACTIVE`, pas
`VISIBLE_STATUSES = [ACTIVE, VERIFIEE_OK]`. Un commerçant dont l'unique
promo a été validée `verifiee_ok` après un signalement infondé apparaît à
tort "à relancer" au lieu de "à jour" pour l'agent. Cause racine :
`CommercantModule` accède au repository `Promo` en direct plutôt que via
`PromoService`, donc la règle "qu'est-ce qu'une promo visible" a divergé.

### Dépendances entre modules

Pas de cycle NestJS détecté. Pattern DTO/guards/erreurs homogène sur tout
le backend (`@UseGuards(JwtAuthGuard, RolesGuard)` + `@Roles`, dossiers
`dto/` par module, exceptions Nest cohérentes) — point positif confirmé.

**Sévérité moyenne — `CommercantModule` importe l'entité `Promo` en direct**
`apps/backend/src/commercant/commercant.module.ts:4,12`. Contournement
volontaire d'un cycle réel (`PromoModule` importe déjà `CommercantModule`)
mais non documenté comme exception délibérée — cause directe du bug
ci-dessus.

**Sévérité moyenne — `AdminController` god-object**
`apps/backend/src/admin/admin.controller.ts:1-161`. Injecte 5 services de
domaine (`AgentService`, `CommercantService`, `PromoService`,
`ReportService`, `AuthService`) alors que tous les autres contrôleurs
n'injectent que leur propre service. Orchestration métier non testable
unitairement sans monter tout le contrôleur HTTP.

**Sévérité moyenne — `AuditLogModule`/`AuditLog` jamais utilisés**
`apps/backend/src/audit-log/audit-log.service.ts`. `AuditLogService` est
une classe vide, jamais appelée. Or les actions qu'elle est censée tracer
(transfert de zone, modération) existent bien et se produisent sans laisser
de trace — *finding confirmé indépendamment par l'audit sécurité*.

**Sévérité moyenne — Autorisation manquante sur `PATCH /promo/:id` (agent) + méthode morte**
`apps/backend/src/promo/promo.controller.ts:87-92`,
`promo.service.ts:245-253`. `assertOwnedBy` existe mais n'est appelée
nulle part — *finding confirmé et approfondi par l'audit sécurité (voir
§3, IDOR critique)*.

### Configuration TypeORM / Docker

**Sévérité haute — `synchronize` + absence de migrations + `NODE_ENV=production` figé dans le Dockerfile**
`apps/backend/src/app.module.ts:21-26`, `apps/backend/Dockerfile:10`.
Aucune migration TypeORM dans le repo. Sur un volume Postgres neuf avec le
Dockerfile tel quel, `synchronize` est désactivé (NODE_ENV=production) donc
aucune table n'est créée — sauf si le `.env` monté redéfinit
`NODE_ENV=development`, auquel cas c'est l'inverse qui devient dangereux
(synchronize actif sur un volume persistant nommé "production"). Le seul
chemin de déploiement défini dans le repo est fragile ou dangereux selon la
config `.env`.

**Sévérité faible** — pas de healthcheck Postgres dans `docker-compose.yml`
(le backend peut démarrer avant que Postgres accepte les connexions).

### Mobile (architecture uniquement)

**Sévérité moyenne — Listes de chemins protégés en dur dans le routeur**
`apps/mobile/lib/app/router.dart:21-26,45,53`. Trois techniques différentes
cohabitent (liste exacte, `startsWith` ad hoc, comparaison de rôle sur
route "hub") pour ~10 routes protégées. Ajouter un écran protégé sans
l'ajouter à la bonne liste ne provoque aucune erreur de compilation —
l'écran reste accessible sans authentification jusqu'à l'échec de l'appel
API en 401.

Point mineur : `features/commercant/providers/` et `features/agent/providers/`
existent sur disque mais sont vides (providers définis inline dans les
écrans), incohérent avec `features/client/providers/` qui centralise les
siens — à trancher.

Le pont `RouterRefreshNotifier` (StateNotifier → Listenable pour
`refreshListenable`) est une approche saine, pas fragile.

---

## 3. Sécurité — ✅ terminé

### CRITIQUE

**1. IDOR — un agent peut modifier n'importe quelle promo, hors de sa zone**
`apps/backend/src/promo/promo.controller.ts:87-92` → `promo.service.ts:204-212`.
`PATCH /promo/:id` (`@Roles('agent')`) ne vérifie ni le commerçant
propriétaire ni la zone de l'agent connecté. La méthode `assertOwnedBy`
existe (`promo.service.ts:245-253`) mais n'est appelée nulle part.
→ Correctif : vérifier `agent.zoneId === commercant.zoneId` avant `update`.

**2. IDOR — un agent peut créer une promo pour n'importe quel commerçant**
`apps/backend/src/promo/promo.controller.ts:77-85`. `POST /promo/agent/:commercantId`
transmet `commercantId` sans jamais comparer les zones.

**3. Brute-force en ligne du PIN commerçant — aucun throttling**
`POST /commercant/login`. PIN à 4-6 chiffres (10 000 à 1 000 000
combinaisons), comparé via bcrypt sans compteur de tentatives ni délai.
`@nestjs/throttler` **n'est même pas installé** (vérifié : absent de
`package.json`, du lockfile, et non utilisé nulle part dans le code).

**4. Brute-force de l'OTP à 6 chiffres — aucune limite de tentatives**
`apps/backend/src/auth/auth.service.ts:54-75`. Seule l'expiration à 5 min
borne la fenêtre ; dans cette fenêtre, 1 000 000 de combinaisons sont
accessibles en boucle. Exploitable notamment via `forgot-pin/confirm` pour
prendre le contrôle d'un compte commerçant en connaissant juste son
numéro.

### HAUTE

**5. Sabotage trivial d'une promo concurrente via signalements anonymes**
`POST /report` est public, protégé uniquement par un header `X-Device-Id`
non vérifié et jamais lié à un vrai device. Avec 3 requêtes HTTP changeant
juste ce header, n'importe qui peut faire passer une promo concurrente en
`signalee` et la masquer de la liste client.

**6. IDOR — un agent peut déclencher une revendication pour un commerçant hors zone**
`POST /agent/commercant/:id/initiate-claim` — même absence de vérification
de zone, permet en plus du spam d'OTP ciblé (cf. finding #10).

**7. JWT 30 jours sans aucun mécanisme de révocation**
`apps/backend/src/auth/auth.module.ts:20-25`. Pas de refresh token, pas de
tokenVersion/jti, pas de blacklist. Combiné aux IDOR ci-dessus, un token
agent volé reste exploitable 30 jours pleins sans recours (changer le mot
de passe agent ne révoque pas le token déjà émis).

**8. Upload S3 pré-signé sans limite de taille ni vérification réelle du contenu**
`apps/backend/src/storage/storage.service.ts:42-55`. Pas de
`Content-Length-Range`, pas de vérification a posteriori du type réel du
fichier uploadé — le `Content-Type` déclaré au moment de la demande d'URL
n'engage à rien au moment du PUT réel.

### MOYENNE

**9. Le spread `{...promo, photoUrl}` casse le `ClassSerializerInterceptor`**
`apps/backend/src/promo/promo.controller.ts:33-38,71-74`. Un objet
littéral construit par spread n'est plus une instance de classe — les
`@Exclude()` ne s'appliquent plus. Sans impact aujourd'hui (`Promo` n'a pas
de champ `@Exclude()`), mais expose déjà inutilement `photoKey`, qui pour
les promos créées par un agent contient l'UUID de l'**agent** (pas du
commerçant) — fuite d'identifiant interne évitable.

**10. Aucune limite de fréquence d'envoi OTP (spam SMS)**
`sendOtp()` appelable en boucle via 3 endpoints différents, sans cooldown
— *convergent avec l'audit architecture (finding OTP rate limiting)*.

**11. `AuditLogService` jamais utilisé** — voir audit architecture ci-dessus,
finding confirmé indépendamment par les deux audits.

**12. `JWT_SECRET` sans contrôle de robustesse au démarrage** — `.env.example`
propose `change-me`, rien n'empêche un déploiement de démarrer avec cette
valeur par défaut.

**13. Absence de configuration CORS explicite** — pas d'impact immédiat
(pas de frontend web), à traiter explicitement dès l'ajout d'une interface
web.

### BASSE

**14. Fuite d'énumération de numéros de téléphone** — `forgot-pin/request`
renvoie `NotFoundException` si le numéro n'existe pas, contrairement à
`login` qui renvoie un message générique.

**15. Regex PIN 4 à 6 chiffres au lieu de 4 fixes** — divergence mineure
avec les specs (pas un problème de sécurité en soi).

### Points vérifiés sans finding

`.env` réel jamais commité, hashing bcryptjs correct, `@Exclude()` présent
sur toutes les entités sensibles là où l'entité est retournée directement,
tous les DTOs validés par class-validator, `ValidationPipe` global
correct, JWT mobile stocké via `flutter_secure_storage`, device ID mobile
correctement anonyme et local.

---

## 4. Qualité de code & dette technique — ✅ terminé

Backend globalement propre (lint et `tsc --noUnusedLocals` sans erreur,
pas de TODO résiduel). Points relevés :

**Sévérité élevée — `AuditLogModule` confirmé mort** (4ᵉ audit indépendant
à le relever). Le module ne déclare même pas `TypeOrmModule.forFeature([AuditLog])`
— aucun repository disponible, donc même en le branchant il faudrait
d'abord corriger le module lui-même.

**Sévérité moyenne — Scaffolding NestJS CLI jamais nettoyé**
`apps/backend/src/app.controller.ts`/`.spec.ts`, `test/app.e2e-spec.ts` : le
"Hello World" par défaut n'est appelé par aucun client mobile. Conséquence
notable : ce sont **les deux seuls tests de tout le backend** — 100% de la
couverture de test porte sur du code mort, 0% sur les règles métier
réelles (plafond de promos, fenêtre de 30 jours, cycle de vie commerçant).

**Sévérité moyenne — Duplication massive du boilerplate loading/erreur côté mobile**
Le bloc `_loading`/`_error` + `FilledButton`/`CircularProgressIndicator`
est répété à l'identique dans au moins 8 écrans (`commercant_register_screen.dart`,
`create_commercant_screen.dart`, `promo_form_screen.dart`,
`agent_promo_form_screen.dart`, `commercant_login_screen.dart`,
`agent_login_screen.dart`, `forgot_pin_screen.dart`, `otp_confirm_screen.dart`).
Ironie relevée par l'agent : `CategoryDropdown`/`PhotoPickerField` ont bien
été extraits en widgets partagés, pas ce pattern-là.

**Sévérité moyenne — Écrans de formulaire quasi jumeaux non factorisés**
`CommercantRegisterScreen`/`CreateCommercantScreen` (mêmes champs,
mêmes validators) et `PromoFormScreen`/`AgentPromoFormScreen` (ne
diffèrent que par `cameraOnly` et l'endpoint appelé).

**Sévérité moyenne — `PromoStatus`/`CommercantAccountState` sont des
`String` côté Dart, pas des enums** contrairement à `Categorie` qui, lui,
a bien un miroir Dart. Comparaisons par chaîne littérale disséminées
(`p.status == 'active'`, `commercant.accountState == 'cree_agent'`) — pas
de vérification à la compilation en cas de renommage backend.

**Sévérité faible** : duplication du pattern login entre `AgentService` et
`AdminService` (quasi identiques) ; `RegisterCommercantDto`/
`CreateCommercantByAgentDto` identiques champ pour champ ; `Promo.assertOwnedBy`
orpheline (déjà relevé par architecture/sécurité) ; `shimmer` dans
pubspec.yaml jamais utilisé dans le code.

Points vérifiés cohérents : header `X-Device-Id` identique des deux côtés,
valeurs `visitStatus` alignées, modèles `Commune`/`Agent`/`Report` alignés
avec les entités backend, aucune route mobile orpheline.

---

## 5. Vérifiabilité mobile / risque de compilation — ✅ terminé

Relecture exhaustive des 44 fichiers `.dart` (pas un échantillonnage).
**Bonne nouvelle** : tous les imports relatifs résolvent correctement,
tous les providers Riverpod référencés ont une définition correspondante
sans faute de frappe — la crainte initiale d'erreurs de câblage massives
ne se confirme pas.

**Risque n°1 (bloquant probable au premier `flutter pub get`) —
`intl: 0.20.2` épinglé en version exacte** (`pubspec.yaml:41`), alors que
`flutter_localizations` (SDK) impose en interne une version d'`intl` liée
à la version exacte du SDK Flutter installé. La contrainte SDK du projet
(`>=3.2.0 <4.0.0`) est large et ne garantit pas quelle version sera
résolue — si elle diffère de `0.20.2`, la résolution de dépendances échoue
avant même la compilation. **Premier point à vérifier en reprenant le projet.**

**Risque n°2 (warning probable) — `DropdownButtonFormField(value: ...)`**
(`category_dropdown.dart:13`, `commercant_register_screen.dart:105`,
`create_commercant_screen.dart:127`) : le paramètre `value` est déprécié
au profit d'`initialValue` sur les SDK Flutter récents ; selon la version
réellement résolue, ça ne compile pas moins bien mais génère un warning de
dépréciation.

**Risque n°3 (runtime, confirmé, 2 occurrences) — `ref` utilisé après un
`await` sans garde `context.mounted`** dans des `ConsumerWidget` (pas
`ConsumerStatefulWidget`, donc pas de `mounted` disponible) :
`my_promos_screen.dart:24-27` et `zone_commerces_screen.dart:37-40`. Si
l'écran est démonté pendant l'attente (retour forcé, redirection d'auth),
`ref.invalidate(...)` après coup lève une exception Riverpod.

**Risque faible** : usage systématique de `response.data!` dans la couche
API (`agent_api.dart`, `commercant_api.dart`, `promo_api.dart`,
`storage_api.dart`) — pas un risque de crash en pratique (tous les appels
sont déjà encadrés par un `try/catch` ou un `FutureProvider.when`), mais
les messages d'erreur seraient génériques plutôt que précis si le backend
renvoyait un jour un corps vide. `shimmer` déclaré mais jamais utilisé.

Points vérifiés SANS problème (contrairement à ce qui était craint) :
`GoRouterState.matchedLocation`, `context.push<T>()`/`go()`, signatures
go_router ^14 toutes conformes ; `state.extra as Map<String, String>` et
tous ses appelants cohérents (aucun mélange de types) ; `FlutterImageCompress.compressAndGetFile(...).path`
fonctionne quel que soit le type retourné exact (`File`/`XFile`) ; aucun
`!` non justifié sur les champs métier ; aucune dépendance utilisée dans
le code mais absente du pubspec.

---

## 6. Performance & scalabilité — ✅ terminé

### Points critiques (à corriger avant l'extension multi-wilaya)

**1. N+1 sur `listByZoneWithVisitStatus`**
`apps/backend/src/commercant/commercant.service.ts:225-249`. 2 `COUNT` par
commerçant → 401 requêtes pour une zone de 200 commerces.
→ Remplacer par une seule requête agrégée (GROUP BY avec CASE WHEN, ou
sous-requête `LEFT JOIN LATERAL`).

**2. N+1 en cascade sur la modération**
`apps/backend/src/report/report.service.ts:74-93` +
`admin.controller.ts:86-95,144-160`. Plus grave que le précédent car non
borné par une zone, et recalculé deux fois par requête (dashboard + queue).
→ Une seule requête SQL avec JOIN + GROUP BY + HAVING, calculée une fois
et réutilisée.

**3. Absence d'index sur les colonnes de jointure/filtre fréquentes**
`Promo.status`+`dateFin` (aucun index composite), `Promo.commercantId`,
`Commercant.communeId`, `Commercant.zoneId` — toutes des FK sans
`@Index()` explicite. **Point clé à retenir : sous PostgreSQL, TypeORM/Postgres
n'indexe PAS automatiquement les colonnes de clé étrangère**, contrairement
à une intuition répandue (différent de MySQL/InnoDB).

**4. Pas de pagination** sur `GET /promo`, `/admin/agent`, `/zone`,
`/commune` — faible risque à 30 commerces, incompatible avec la vocation
multi-wilaya déclarée du produit.

### Points corrects (confirmés bons)

`expireOutdatedPromosCron` : UPDATE ensembliste, bon pattern.
`StorageService` : `S3Client` singleton correctement réutilisé.
`synchronize: process.env.NODE_ENV !== 'production'` correctement gardé
(mais voir le risque Docker soulevé par l'audit architecture, §2).

### Moyen à surveiller

`purgeOldPhotosCron` boucle séquentiellement sur chaque promo pour l'appel
S3 (pas de chunking) — deviendra un goulot d'étranglement si des milliers
de promos expirent le même jour. Pas de migrations TypeORM (repris de
l'audit architecture). `OtpCode` n'a pas d'index sur `(telephone, purpose)`
alors que `verifyOtp` filtre dessus à chaque connexion/inscription.

---

## Findings convergents (confirmés par plusieurs audits indépendants)

Ces points ont été identifiés séparément par des agents qui ne voyaient
pas les résultats des autres — signal de fiabilité maximal, à traiter en
priorité :

- **`AuditLogModule` jamais branché — confirmé par 4 audits sur 6**
  (architecture, sécurité, qualité de code, fonctionnel). Le module ne
  déclare même pas son repository TypeORM.
- **Absence de vérification de zone sur les actions agent
  (`createByAgent`, `PATCH /promo/:id`, `initiateClaim`) — confirmé par
  4 audits sur 6** (architecture, sécurité, qualité de code, fonctionnel),
  la sécurité l'élève à IDOR critique. `assertOwnedBy` existe mais n'est
  appelée nulle part.
- **Absence de rate limiting sur l'envoi d'OTP et sur le login PIN**
  (architecture + sécurité + fonctionnel via le constat `@nestjs/throttler`
  absent)
- **Absence de migrations TypeORM** (architecture + performance)
- **Aucune validation de taille sur l'upload S3 pré-signé** (sécurité +
  fonctionnel)

## Findings nouveaux à ne pas manquer

- **Race condition sur le plafond de 5 promos actives** (fonctionnel) —
  `count()` puis `save()` sans transaction ni verrou.
- **`intl: 0.20.2` épinglé en dur, risque de blocage de `flutter pub get`**
  (vérifiabilité mobile) — à vérifier en tout premier lors de la reprise
  du projet en local.
- **`ref` Riverpod utilisé après `await` sans `context.mounted`** dans 2
  écrans (vérifiabilité mobile).
