# Audit V1 — echango Promo

**Statut** : audit de suivi, pas un audit à 6 volets complet comme
`docs/AUDIT_V0.md`. Objectif : vérifier ce qui a été corrigé pendant la
session récente (révocation JWT par `tokenVersion`, codes d'erreur
`AppException`/`ErrorCode` centralisés, extraction de `ModerationService`,
rôle porté par la route mobile, enums Dart miroirs, première suite de
tests mobile) et chercher les régressions ou nouveaux problèmes introduits
en même temps. Méthode : exploration en lecture seule, fichier:ligne
systématique, aucune modification de code pendant l'audit lui-même.

**Mise à jour (2026-07-05)** : les findings ci-dessous ont été traités un
par un, chacun avec commit + doc. Statuts après traitement dans le
tableau ; détail des corrections dans `docs/status_v0.md` (entrées
"traitement audit V1").

| # | Point vérifié | Verdict initial | Statut après traitement |
|---|---|---|---|
| 1 | Révocation JWT (tokenVersion) | ⚠️ Absent pour commerçant | ✅ `Commercant.tokenVersion` ajouté, `adminResetPin` l'incrémente ; `Admin.tokenVersion` obtient `POST /admin/me/revoke-token` |
| 2 | Couverture du rate limiting | ⚠️ Gaps sur actions sensibles post-auth | ✅ `SENSITIVE_ACTION_THROTTLE` appliqué (admin, agent→commerçant, promo, presigned-upload) |
| 3 | Cohérence `AppException`/`ErrorCode` | ✅ Déjà conforme | ✅ Toujours conforme (nouveau code `STORAGE_INVALID_IMAGE` mappé) |
| 4 | Index sur les clés étrangères | ⚠️ 2 oublis | ✅ `Agent.zoneId`/`Commercant.createdByAgentId` indexés |
| 5 | Pagination des listes | ❌ Absente | ❌ **Non traité** — dette V0 explicitement différée, hors périmètre de cette passe |
| 6 | Tests automatisés backend | ❌ 0% | ⚠️ 2 fichiers de test ajoutés (`jwt-auth.guard.spec.ts`, `image-signature.spec.ts`) — première suite, pas une couverture complète |
| 7 | Upload S3 (taille / type) | ⚠️ Type non vérifié | ✅ `assertValidImage` (magic bytes) après upload |
| 8 | Déconnexion mobile sur token révoqué/expiré | ❌ Aucune déconnexion automatique | ✅ `ApiClient` détecte les codes `AUTH_TOKEN_*` et appelle `logout()` |
| 9 | Règles CLAUDE.md à ajouter | 3 propositions | ✅ Ajoutées (#24-26) |

---

## 1. Révocation JWT — commerçant non couvert

**Sévérité : Élevée.**

La révocation par `tokenVersion` ajoutée cette session ne couvre que les
rôles `agent`/`admin` (`apps/backend/src/auth/role.ts:6-7`,
`apps/backend/src/auth/guards/jwt-auth.guard.ts:37-43`). `Commercant`
n'a pas de colonne `tokenVersion`
(`apps/backend/src/commercant/entities/commercant.entity.ts`), alors que
c'est le seul rôle pour lequel un mécanisme de récupération de compte
existe réellement : `adminResetPin`
(`apps/backend/src/commercant/commercant.service.ts:143-147`) se contente
d'effacer `pinHash`, sans rien à incrémenter.

**Conséquence concrète** : téléphone volé → JWT commerçant exfiltré →
l'admin exécute `POST /admin/commercant/:id/reset-pin` pour couper l'accès
→ le JWT déjà émis reste pleinement valide jusqu'à expiration naturelle
(`JWT_EXPIRES_IN=30d` par défaut, `apps/backend/.env.example:17`). L'admin
croit avoir coupé l'accès (le PIN est bien effacé, le commerçant doit
`claim` un nouveau PIN pour se reconnecter) mais **le token déjà en
circulation continue de fonctionner** (lecture/édition profil, gestion des
promos) pendant jusqu'à 30 jours.

En complément : `Admin.tokenVersion` existe
(`apps/backend/src/admin/entities/admin.entity.ts:26-27`) mais n'est
**jamais incrémenté** — seul `AgentService.revokeTokens`
(`apps/backend/src/agent/agent.service.ts:83`) appelle
`.increment(..., 'tokenVersion', 1)`. Aucune route de révocation pour un
compte admin. Risque moindre en V0 (admin unique, bootstrap manuel) mais
même angle mort structurel : le champ existe, le levier n'est câblé que
pour l'agent.

**Recommandation** : ajouter `tokenVersion` à `Commercant` et l'incrémenter
dans `adminResetPin` (et dans tout futur flux de changement de PIN) ; soit
ajouter un endpoint `POST /admin/revoke-token` pour l'admin lui-même
(même si un seul compte existe en V0, le code doit pouvoir le faire),
soit documenter explicitement pourquoi ce n'est pas nécessaire pour ce
rôle.

## 2. Couverture du rate limiting

**Sévérité : Moyenne.**

`STRICT_THROTTLE` (`apps/backend/src/common/throttle.ts:7`, 5 req/min) est
bien appliqué aux endpoints d'authentification et à `POST /report`
(login admin/agent/commerçant, `register`, `claim` — corrige bien le
finding critique du V0 sur `/report`). En dehors de ce périmètre, plusieurs
actions authentifiées mais sensibles n'ont aucune limite dédiée (seule la
limite globale de 60/min s'applique, `app.module.ts:42`) :

- `POST /agent/commercant` (création de commerçant par un agent,
  `apps/backend/src/agent/agent.controller.ts:65-84`)
- `POST /commercant/me/registre` (`commercant.controller.ts:137-147`)
- `POST /promo`, `POST /promo/agent/:commercantId`, `PATCH /promo/:id`,
  `POST /promo/:id/publish`, `POST /promo/:id/stop`
  (`promo.controller.ts:102,127,141,155,168`)
- `POST /storage/presigned-upload` (`storage.controller.ts:21-30`)
- Tous les endpoints `AdminController` hors `login` : notamment
  `POST /admin/commercant/:id/reset-pin` (`:203`) et
  `POST /admin/agent/:id/revoke-token` (`:99`) — un JWT admin volé (cf. §1)
  peut vider les PIN de tous les commerçants ou révoquer tous les agents
  en boucle, sans aucun frein au-delà de la limite globale.

Ce ne sont pas des endpoits de credentials (pas de brute-force possible
sans compte déjà authentifié), donc moins critique que les findings OTP/PIN
du V0, mais la règle CLAUDE.md #2 ("tout endpoint d'authentification...
dès sa création") a un périmètre plus étroit que ce qui mériterait
protection : un compte compromis (agent, admin, ou commerçant) peut
aujourd'hui spammer ces routes sans limite spécifique.

## 3. Cohérence `AppException`/`ErrorCode` — ✅ conforme

Vérifié par recherche exhaustive : **zéro** `throw new
(BadRequestException|NotFoundException|UnauthorizedException|
ForbiddenException|ConflictException|HttpException)` brut restant dans
tout `apps/backend/src`, y compris les modules non touchés directement
dans les commits récents (`storage/`, `report/`, `zone/`, `commune/`,
`audit-log/`). La seule occurrence de `HttpException` est le filtre global
légitime (`common/errors/all-exceptions.filter.ts`). Les seuls `throw new
Error(...)` restants sont dans `config/env.validation.ts:13,20` — erreurs
de démarrage, hors du contrat HTTP `AppException`, à raison.

Migration complète, aucune régression trouvée.

## 4. Index manquants sur les clés étrangères

**Sévérité : Faible** (impact nul aujourd'hui, aucune requête ne filtre
encore dessus — mais incohérent avec le reste du modèle).

| FK | Entité:ligne | Index ? |
|---|---|---|
| `Promo.commercantId` | `promo/entities/promo.entity.ts:59-64` | ✅ |
| `Commercant.communeId` | `commercant/entities/commercant.entity.ts:62-68` | ✅ |
| `Commercant.zoneId` | `commercant/entities/commercant.entity.ts:71-77` | ✅ |
| `Commercant.createdByAgentId` | `commercant/entities/commercant.entity.ts:79-84` | ❌ |
| `Agent.zoneId` | `agent/entities/agent.entity.ts:32-37` | ❌ |

3 des 5 FK ajoutées/vérifiées cette session sont bien indexées (règle
CLAUDE.md #12 correctement appliquée), mais `Agent.zoneId` et
`Commercant.createdByAgentId` ont été oubliées. Aucune requête ne filtre
encore dessus (confirmé par recherche), donc impact réel nul dans l'état
actuel — à corriger avant qu'un écran ne les utilise en filtre (ex. "tous
les commerçants créés par tel agent").

## 5. Pagination — dette inchangée depuis le V0

**Sévérité : Moyenne**, connue et déjà documentée (`CLAUDE.md`, section
"Dette connue"), toujours vraie : `GET /promo`, `GET /admin/agent`,
`GET /zone`, `GET /commune` n'ont ni `page` ni `limit`.

**Nouveau finding associé** : `ModerationService.queue()`
(`apps/backend/src/admin/moderation.service.ts:16-22`) exécute
`Promise.all(pending.map(async ({ promoId }) =>
this.promoService.findByIdOrFail(promoId)))` — un `SELECT` par promo
signalée. C'est exactement le pattern que la règle CLAUDE.md #14 bannit ;
le N+1 *comptage* déjà corrigé en V0 sur ce même écran a été suivi d'un
second N+1, cette fois sur le *fetch* des promos de la file. Sans
pagination, une file de modération qui grossit (extension multi-wilaya)
amplifierait ce problème au lieu de le contenir.

## 6. Tests backend — 0% de couverture

**Sévérité : Moyenne.**

Aucun fichier `*.spec.ts` dans `apps/backend/src` ni `apps/backend/test`.
Le scaffolding NestJS par défaut (tests du `AppController` "Hello World")
a été supprimé cette session comme dette (règle CLAUDE.md #16) — bon
geste, mais la couverture est passée de "100% sur du code mort" à **0%
tout court**, sans qu'aucune règle métier réelle (plafond de 5 promos,
fenêtre d'ignore de 30 jours, IDOR zone agent, révocation `tokenVersion`)
ne soit couverte. Contraste avec le mobile, qui a désormais 4 fichiers de
test (`apps/mobile/test/...`).

## 7. Upload S3 — taille corrigée, type toujours déclaratif

**Sévérité : Moyenne** (dette V0 partiellement traitée).

`storage.service.ts:15,74` : `MAX_UPLOAD_BYTES = 5 Mo` appliqué via
`content-length-range` sur la policy POST pré-signée — **corrige bien**
le finding critique du V0 sur la taille (contrainte imposée par S3
lui-même, pas seulement déclarative côté client).

Le `Content-Type` reste en revanche purement déclaratif
(`storage.service.ts:75,77`) : le client doit soumettre le type exact
annoncé au moment de la signature, mais **rien ne vérifie a posteriori le
contenu réel du fichier uploadé** (pas de relecture des magic bytes, pas
de hook S3, pas d'endpoint de confirmation). Un fichier dont les octets ne
correspondent pas au `Content-Type` déclaré (ex. exécutable renommé
`.jpg`) passe la policy sans problème — le gap exact identifié en V0,
seule la partie taille a été corrigée depuis.

## 8. Mobile — pas de déconnexion automatique sur token révoqué/expiré

**Sévérité : Élevée** — ce gap annule une partie de l'intérêt de la
révocation JWT construite cette session : le backend rejette bien le
token (401 avec `code: AUTH_TOKEN_REVOKED`/`AUTH_TOKEN_INVALID`), mais rien
ne déclenche de déconnexion côté mobile.

- `apps/mobile/lib/data/api/api_client.dart:21-28` : l'intercepteur Dio
  `onError` enveloppe l'erreur en `ApiException` et relaie
  (`handler.next(...)`), sans jamais inspecter `statusCode`/`code`, ni
  appeler `authControllerProvider.notifier.logout()`.
- Les textes `error_messages_fr.dart:19-20` (*"Votre session a expiré/a
  été révoquée. Reconnectez-vous."*) s'affichent correctement dans un
  message d'erreur d'écran, mais rien ne redirige réellement l'utilisateur.
- `AuthController.logout()` (`providers/auth_provider.dart:38-41`) est
  bien implémentée mais **orpheline côté réseau** — seuls 2 boutons manuels
  l'appellent (`commercant_dashboard_screen.dart:22-28`,
  `zone_commerces_screen.dart:25-28`). C'est une application directe de la
  règle CLAUDE.md #10 ("toute méthode écrite mais jamais appelée est un
  signal d'alarme") plutôt qu'un pattern nouveau — traité ici comme bug,
  pas comme règle supplémentaire.

**Conséquence concrète** : un compte dont le token est révoqué
(`POST /admin/agent/:id/revoke-token`) ou expiré reste sur son écran, avec
un token mort en mémoire. Chaque appel échoue en boucle avec le bon
message ("reconnectez-vous") mais **sans jamais rediriger vers l'écran de
login** — contredit l'intention du message affiché.

**Recommandation** : dans l'intercepteur Dio, détecter les codes
`AUTH_TOKEN_MISSING`/`AUTH_TOKEN_INVALID`/`AUTH_TOKEN_REVOKED` (401) et
appeler `logout()` avant de relayer l'erreur, pour que `router.dart`
redirige automatiquement vers l'écran de login du rôle concerné.

## 9. Propositions de nouvelles règles CLAUDE.md

Voir `CLAUDE.md` pour le texte final retenu (règles #24-26). Résumé :

- **#24** — Un `CanActivate`/intercepteur global qui injecte un
  `Repository<X>` doit voir son module réexporter `TypeOrmModule` en plus
  du provider du guard — sinon `UnknownDependenciesException` au démarrage
  dans tout module import ant seulement le module du guard.
- **#25** — Toute exception métier doit être une sous-classe
  d'`AppException` avec un `ErrorCode` dédié, ajoutée dans le même commit
  que l'endpoint — jamais une exception NestJS brute.
- **#26** — Tout `ErrorCode` ajouté côté backend doit obtenir une entrée
  dans le mapping mobile (`errorMessagesFr` ou équivalent futur
  multi-langue) dans le même commit, ou être explicitement ajouté à la
  liste documentée des exclusions volontaires.

---

## Traité (2026-07-05)

Tous les points ci-dessus ont été traités sauf la pagination (§5,
explicitement différée — dette V0 assumée, pas un oubli de cette passe) et
la couverture de tests backend (§6, amorcée avec 2 fichiers mais loin
d'une couverture complète). Détail des commits dans `docs/status_v0.md`
("traitement audit V1, 1/4" à "2-5/...").

Dette restante après cette passe, à garder en tête pour l'extension
multi-wilaya : pagination des listes, couverture de tests backend encore
partielle, `Admin` reste un compte unique en V0 (pas de gestion
multi-admin pour la révocation).
