# Plan de test — echango Promo

Instanciation de `docs/METHODE_TEST.md` sur ce produit. Le document générique
dit *comment* éprouver ; celui-ci dit *quoi*, *où*, et *dans quel ordre* — avec
les valeurs réelles de ce dépôt.

Tout ce qui est chiffré ici a été **mesuré le 2026-08-04** sur `main`
(`77e788a`), pas estimé. Chaque règle métier porte son `fichier:ligne`.

---

## 1. État des lieux mesuré

### Le backend

| | Valeur | Comment c'est su |
|---|---|---|
| Contrôleurs | 11 | `apps/backend/src/**/*.controller.ts` |
| Routes | **62** | `docs/methode-test/banc-refus-http.py --list` |
| Routes ouvertes | **14** | idem, mode `par_route` |
| Polarité de protection | **garde par route** | `@UseGuards(JwtAuthGuard, RolesGuard)` par contrôleur ; seul `ThrottlerGuard` est global (`app.module.ts:63`) |
| Codes d'erreur | **42** | `common/errors/error-code.enum.ts` |
| Fichiers de test | **5** | `pagination-query.dto`, `jwt-auth.guard`, `image-signature`, `highlight.service`, `app-links.controller` |

> ⚠️ **La polarité est le fait le plus important de ce tableau.** Avec un garde
> posé route par route, **la route qu'on oublie est ouverte** — et l'oubli ne se
> voit ni à la compilation, ni à l'exécution, ni dans les journaux. C'est ce qui
> rend l'étape 1 prioritaire ici, davantage que sur un projet à garde global.

### L'application

| | Valeur |
|---|---|
| `flutter analyze` (Flutter 3.35.7) | **1 avertissement** — import inutilisé, `commercant_login_screen.dart:4` |
| Tests unitaires Dart | **5** — `api_exception`, `promo_lifecycle_status`, `promo`, `enum_labels`, `pin_validator` |
| Tests d'intégration écran | **0** — `integration_test/` n'existe pas |
| Langues | FR / EN / AR (RTL) |

### La base locale (WSL)

`postgres://echango:echango@localhost:5433/echango_promo`

| Table | Lignes |
|---|---|
| `commune` | 35 |
| `commercant` | 1 |
| `promo` | 1 — **expirée** (`dateFin` = 2026-07-09) |
| `admin` | 1 |
| `agent` | 0 |
| `highlight` | 0 |

> Conséquence directe : **il n'existe aujourd'hui aucun décor exploitable.** Les
> écrans client affichent « aucune promo active », ce qui est le rendu correct
> d'une réponse vide — donc indiscernable d'une panne. C'est l'étape 3 qui
> traite ce manque.

---

## 2. Les défauts déjà trouvés

Trouvés **en instanciant la méthode**, avant même d'avoir écrit un banc.

### D1 — Cinq codes d'erreur servis et jamais traduits ⚠️ ouvert

`dart run docs/methode-test/check-sync.dart` sur `main` :

| Code | Émis par | Traduit en FR | EN | AR |
|---|---|---|---|---|
| `PROMO_DATE_FIN_EXCEEDS_MAX` | `promo.service.ts:103` | ❌ | ❌ | ❌ |
| `PROMO_ACTIVE_CAP_REACHED` | `promo.service.ts:126` | ❌ | ❌ | ❌ |
| `PROMO_DAILY_CREATION_CAP_REACHED` | `promo.service.ts:154` | ❌ | ❌ | ❌ |
| `PROMO_REPUBLISH_TOO_SOON` | `promo.service.ts:174` | ❌ | ❌ | ❌ |
| `HIGHLIGHT_CAP_REACHED` | `highlight.service.ts:222` | ❌ | ❌ | ❌ |

**Ce que ça produit.** Un commerçant qui atteint le plafond de 5 promos actives
reçoit le message brut du backend — **toujours en français**, y compris sur un
téléphone en arabe ou en anglais. Aucune erreur de compilation d'aucun côté ne
le signale. C'est exactement le défaut que la **règle 26** de `CLAUDE.md` existe
pour empêcher, et elle n'était tenue par rien d'autre qu'une consigne écrite.

**Ce que ça confirme sur la méthode** : ces cinq codes appartiennent aux
fonctionnalités les plus récentes (anti-abus promo, bandeau Top promos). La
règle a été respectée pendant des mois, puis oubliée exactement là où le rythme
s'est accéléré. Un contrôle exécuté ne se fatigue pas.

**Correction** : ajouter les 5 entrées dans les 3 tables
`apps/mobile/lib/features/shared/errors/error_messages_{fr,en,ar}.dart`.
⚠️ C'est une **modification** de fichiers existants — à arbitrer avec la règle
« ajout seulement », ou à faire dans un commit isolé et minimal.

### D2 — Huit clés d'environnement absentes du `.env` local ⚠️ à vérifier

`ANDROID_PACKAGE_NAME`, `ANDROID_SHA`, `IOS_TEAM_ID`, `IOS_BUNDLE_ID`,
`PLAY_STORE_URL`, `APP_STORE_URL`, `CORS_ORIGINS`, **`PROMO_MAX_DURATION_DAYS`**.

Aucune n'est bloquante au démarrage, mais la dernière **pilote une règle métier
éprouvée par un banc** (`PROMO_DATE_FIN_EXCEEDS_MAX`). Un banc qui tourne sans
elle éprouve la valeur par défaut du code, pas la valeur de production — et
conclurait juste sur le mauvais nombre.

> **Règle qui en découle, et qui vaut au-delà de ce cas** : tout banc qui teste
> une borne configurable **imprime la valeur qu'il a effectivement utilisée**.
> Une borne lue depuis l'environnement est une donnée d'entrée du banc, pas une
> constante.

---

## 3. Ce qu'il y a à éprouver

### Les personas

| Persona | Authentification | Particularité pour les tests |
|---|---|---|
| **Client** | **aucune** — anonyme | C'est ce qui rend 14 routes légitimement ouvertes. Identifié par un `X-Device-Id` **déclaratif, jamais vérifié** — d'où le throttle par IP sur `/report`. |
| **Commerçant** | PIN | Cycle de vie : inscription → validation registre → actif → suspendu → supprimé |
| **Agent** | mot de passe | Rattaché à N communes. ⚠️ Rôle appelé à disparaître à l'extension multi-wilaya |
| **Admin** | mot de passe | Compte **unique** en V0. Accès par URL directe `/admin`, non découvrable dans l'app |

### Les règles métier, avec leur valeur et leur emplacement

C'est la liste de départ des bancs de l'étape 4 : **une règle, un banc**.

| Règle | Valeur | Emplacement | Configurable |
|---|---|---|---|
| Plafond de promos actives | **5** | `promo.service.ts:43` | non |
| Plafond de créations par jour | **5** | `promo.service.ts:80` | `PROMO_DAILY_CREATION_CAP` |
| Délai avant republication | **24 h** | `promo.service.ts:85` | `PROMO_REPUBLISH_COOLDOWN_HOURS` |
| Durée maximale d'une promo | — | `promo.service.ts:103` | `PROMO_MAX_DURATION_DAYS` |
| Commerces rendus par la carte | **300** | `promo.service.ts:51` | non |
| Seuil de masquage par signalements | **3** | `report.service.ts:17` | non |
| Fenêtre d'ignore d'un signalement | **30 j** | `report.service.ts:18` | non |
| Mises en avant du bandeau | **10** (`HIGHLIGHT_MAX_SLIDES`) | `highlight/highlight.constants.ts` | non |
| Repli du bandeau | **8** (`HIGHLIGHT_FALLBACK_LIMIT`) | idem | non |

### Les plafonds de requêtes — à connaître avant d'écrire un banc

`common/throttle.ts` :

| Plafond | Valeur | Portée |
|---|---|---|
| global | 60 / min / IP | toutes les routes |
| `STRICT_THROTTLE` | **5 / min / IP** | les 3 logins, `/commercant/register`, `/report` |
| `SENSITIVE_ACTION_THROTTLE` | 20 / min / IP | actions d'écriture sensibles |
| `MAP_THROTTLE` | 180 / min / IP | `/promo/map` |

> ⚠️ **`STRICT_THROTTLE` = 5/min est la contrainte qui dimensionne toute la
> suite** (mode M9 du générique). Un banc qui se connecte quatre fois de suite
> consomme presque tout le budget d'une minute. Deux conséquences : la
> temporisation entre bancs n'est pas optionnelle, et **une session obtenue se
> réutilise** au lieu de se reconnecter.

### Les données à double vie — cibles de l'étape 2

Chaque ligne est un couple qui doit rester d'accord, aujourd'hui tenu par rien.

| Couple | Serveur | Application |
|---|---|---|
| Codes d'erreur | `common/errors/error-code.enum.ts` (42) | `error_messages_{fr,en,ar}.dart` |
| Catégories | `common/enums/categorie.enum.ts` (7, dont `restauration`) | `domain/enums/categorie.dart` |
| Cycle de vie promo | `lifecycleStatus` | `promo_lifecycle_status.dart` |
| Statut de modération | `moderationStatus` | — |
| État de compte commerçant | `CommercantAccountState` | ⚠️ comparé par **chaîne littérale** dans plusieurs écrans (règle 19 de `CLAUDE.md`) |
| Bornes de validation | décorateurs des DTO | constantes de formulaire |

---

## 4. Registre de couverture

Ce qui est couvert, ce qui ne l'est pas, et **pourquoi**. Un total sans sa
décomposition ne se vérifie pas.

```
Routes                                          62
  éprouvées par un banc de refus .............   0     ← étape 1
  ouvertes, épinglées (voir §5) ..............  14
  protégées, jamais éprouvées ................  48

Règles métier chiffrées                          8
  couvertes par un test .......................  0     ← étape 4
  (le plafond de 5 est protégé par un verrou
   consultatif Postgres, jamais éprouvé en
   concurrence)

Couples serveur ↔ app                            6
  tenus par un contrôle exécuté ...............  0     ← étape 2
  dont 1 DÉJÀ désynchronisé (D1)

Écrans (*_screen.dart)                          34
  ouverts par un test ..........................  0     ← étape 3
```

**Exclusions épinglées** — aucune à ce jour. Toute exclusion future s'écrit ici
avec sa raison : une exclusion anonyme est indiscernable d'un oubli.

---

## 5. Les 14 routes ouvertes, épinglées

À reporter dans `ROUTES_PUBLIQUES` du banc. Chacune est une décision ; aucune
n'est un oubli constaté au 2026-08-04.

| Route | Pourquoi ouverte |
|---|---|
| `GET /promo` | consultation client — le client est anonyme par conception |
| `GET /promo/:id` | idem |
| `GET /promo/map` | idem — protégée par `MAP_THROTTLE` (180/min) |
| `GET /commune` | sélecteur wilaya → commune, chargé **en entier** par `CommuneCascadeField`. ⚠️ Ne jamais paginer par défaut (règle 15 de `CLAUDE.md`) |
| `GET /highlight` | bandeau Top promos de l'accueil |
| `GET /commercant/:id/public` | fiche commerçant publique |
| `GET /p/:id` | redirection de partage vers le store |
| `GET /.well-known/assetlinks.json` | vérification App Links Android |
| `GET /.well-known/apple-app-site-association` | vérification Universal Links iOS |
| `POST /commercant/login` | authentification — `STRICT_THROTTLE` |
| `POST /agent/login` | idem |
| `POST /admin/login` | idem |
| `POST /commercant/register` | inscription — `STRICT_THROTTLE` |
| `POST /report` | signalement client anonyme — `STRICT_THROTTLE`, protégé **par IP** parce que le `X-Device-Id` est déclaratif (règle 7) |

> ⚠️ Les trois routes App Links (`/p/:id` et les deux `.well-known`) sont
> scopées au host `promo.echango.com` : elles répondent **404 sur localhost**,
> par conception documentée. Un banc qui les sonde sans en-tête `Host` conclurait
> à tort. Les sonder avec `-H "Host: promo.echango.com"`, ou les exclure
> nommément.

---

## 6. Plan d'adoption

### Étape 1 — Le banc de refus (48 routes protégées)

**Où** : `scripts/test-frontiere-http.sh` + `scripts/lib/frontiere_http.py`, copiés
de `docs/methode-test/banc-refus-http.py`.

**À écrire** :
- les trois fonctions de jeton — commerçant, agent, admin, plus un jeton révoqué
  (`POST /admin/me/revoke-token` existe, ainsi que
  `POST /admin/agent/:id/revoke-token`) ;
- les 14 routes ouvertes en `ROUTES_PUBLIQUES` (§5) ;
- les codes attendus, lus dans `error-code.enum.ts`.

**Ce que ça éprouve en priorité** : l'IDOR agent → promo/commerçant, corrigé en
juillet par `CommercantService.assertZoneMatches` et **jamais rejoué depuis**.
C'était la faille critique de l'audit V0 ; rien ne garantit aujourd'hui qu'elle
n'est pas revenue.

**⚠️ Le banc d'appartenance est le vrai enjeu ici, plus encore que le banc de
refus.** Sur ce produit, un agent authentifié qui agit sur la promo d'un
commerçant hors de ses communes est le scénario d'attaque réaliste — pas
l'appel sans jeton. Prévoir deux comptes agent rattachés à des communes
disjointes.

**Critère de sortie** : prouvé par mutation — retirer un `@UseGuards` fait passer
le banc au rouge, et retirer un `assertZoneMatches` aussi.

### Étape 2 — Les vérificateurs de synchronisation

**Où** : `apps/mobile/tool/check_error_codes.dart` et
`apps/mobile/tool/check_enums.dart`, copiés de `docs/methode-test/check-sync.dart`.

**Déjà fonctionnel** : le squelette tourne sur les vrais fichiers et trouve D1.
Il ne reste qu'à le déplacer dans `tool/` et à le brancher.

**À ajouter ensuite** : le miroir des catégories (7 valeurs) et de
`CommercantAccountState` — ce dernier étant aujourd'hui comparé par chaîne
littérale dans plusieurs écrans, un renommage backend ne produirait **aucune
erreur de compilation**.

**Critère de sortie** : `--self-test` bloquant (13 cas, dont 6 refus — déjà le
cas), plus une mutation du vrai fichier.

**C'est l'étape la plus rentable** : statique, instantanée, sans base ni
émulateur, et elle a déjà trouvé un défaut réel.

### Étape 3 — Le décor et le premier parcours écran

**Où** : `scripts/provision-decor.sh` et `apps/mobile/integration_test/`.

**Ce que le décor doit poser** — la base locale ne contient qu'une promo expirée :
- un commerçant **actif** (inscription + validation du registre par l'admin —
  un geste d'administration, pas un geste d'utilisateur) ;
- un agent rattaché à au moins une commune ;
- 3 à 5 promos **actives** avec des prix distinctifs, dont une proche du plafond ;
- une promo portant **2 signalements** (le seuil est à 3) — pour éprouver la
  bascule sans la déclencher.

**Le premier parcours**, choisi sur le critère « quelle valeur affichée
tromperait le plus si elle était fausse ? » :

> **Le commerçant atteint le plafond de 5 promos actives.** Il voit un refus
> **compréhensible et dans sa langue**, et son compteur affiche 5/5.

Ce parcours éprouve d'un coup la règle métier, le code d'erreur, sa traduction
(D1 !) et l'affichage du compteur. Il aurait attrapé D1 tout seul.

**Critère de sortie** : `flutter drive` tourne depuis une machine neuve en
suivant uniquement ce qu'imprime le décor.

### Étape 4 — Les bancs métier

Un par règle **qui a déjà produit un défaut** — la colonne « défaut d'origine »
vient de `docs/AUDIT_V0.md` et de l'historique git.

| Banc | Règle éprouvée | Défaut d'origine |
|---|---|---|
| `test-appartenance-agent` | un agent n'agit que dans ses communes | **IDOR critique** — un agent pouvait modifier les promos de n'importe quel commerçant |
| `test-plafond-promos` | 5 actives, **en concurrence** | race condition : deux créations simultanées passaient toutes deux. Corrigé par `pg_advisory_xact_lock`, **jamais éprouvé sous charge** |
| `test-seuil-moderation` | 3 signalements masquent | seuil ramené de 1 à 3 le 2026-08-04 — un aller-retour non couvert |
| `test-abus-signalement` | `X-Device-Id` ne suffit pas | masquer la promo d'un concurrent avec 3 requêtes changeant un en-tête |
| `test-visibilite-promo` | « visible » a **une seule** définition | deux services répliquaient la règle ; un dashboard surcomptait |
| `test-fuite-photokey` | aucune réponse ne porte `photoKey` | un spread `{...promo}` exposait l'UUID de l'agent |
| `test-revocation-jwt` | `tokenVersion` invalide les jetons | ajouté à l'audit V1, jamais rejoué |
| `test-cycle-commercant` | suspension ≠ suppression | la suspension doit **libérer le numéro de téléphone** |

**Ordre** : les deux premiers d'abord. Ce sont les seuls dont l'échec est une
faille, pas un affichage faux.

---

## 7. L'environnement de test

Spécifique à ce poste, et sans quoi rien ne démarre.

### Le double environnement

**Backend en WSL, application en Windows.** Le décor tourne côté WSL, le test
écran côté Windows.

```bash
# WSL — le backend
cd ~/projects/echangopromo/apps/backend
npm run migration:run && npm run start:dev     # port 3000
```

```powershell
# Windows — l'application
cd apps\mobile
flutter run -d <émulateur> --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

### Quatre pièges, tous rencontrés le 2026-08-04

**⚠️ `10.0.2.2`, jamais `localhost`.** Depuis un émulateur Android, `localhost`
désigne l'émulateur lui-même. `10.0.2.2` est l'alias de la machine hôte, et
Windows relaie vers WSL.

**⚠️ Appeler `flutter` directement.** Lancé via un intermédiaire qui reconstruit
la ligne de commande (`Start-Process` en PowerShell, notamment), le
`--dart-define` **se perd silencieusement** : le build part avec la valeur par
défaut — `https://promo.echango.com`, c'est-à-dire la **production** — et le
test s'exécute contre les vraies données sans qu'aucune erreur ne le dise.
Constaté, et le diagnostic a demandé une capture du trafic de l'émulateur.

Vérification en dix secondes, à faire avant de croire un résultat :

```powershell
flutter build bundle --dart-define=API_BASE_URL=http://10.0.2.2:3000
# puis chercher "10.0.2.2:3000" dans build\flutter_assets\kernel_blob.bin
```

**⚠️ L'analyse HTTPS d'un antivirus casse Gradle.** AVG réémet les certificats
avec sa propre autorité racine, présente dans le magasin Windows mais **pas dans
le truststore Java** : le téléchargement de Gradle échoue en
`PKIX path building failed`. Symptôme reconnaissable — le navigateur et
PowerShell téléchargent sans problème, Java non.

**⚠️ La base locale ne contient qu'une promo expirée.** Une liste vide n'est pas
une panne. Ne jamais conclure sur l'absence de données sans avoir vérifié ce que
sert l'API — c'est le mode M3 appliqué au diagnostic.

### Les identifiants du décor

⚠️ **Stables, jamais aléatoires** : `STRICT_THROTTLE` plafonne l'inscription et
la connexion à 5/min/IP. Un décor à identifiants aléatoires devient inutilisable
au second passage.

```
decor-commercant@echango.local
decor-agent@echango.local
admin@echango.local            (seed:admin)
```

---

## 8. Ce que ce plan ne couvre pas

- **Aucune intégration continue.** Les étapes 1 et 2 sont statiques ou sans
  émulateur : elles pourraient tourner automatiquement. Les étapes 3 et 4 non,
  en l'état.
- **Aucune réinitialisation de base.** Les bancs salissent une base vivante ; le
  ménage est à faire dans chaque banc, en best-effort.
- **Le stockage S3/MinIO n'est pas éprouvé de bout en bout.** L'upload par POST
  policy a été écrit mais jamais testé contre un vrai bucket — c'est un manque
  hérité de l'audit V0, toujours ouvert.
- **iOS.** La chaîne Codemagic existe (`codemagic.yaml`) mais aucun test décrit
  ici ne tourne sur iOS.
- **La charge et les performances** ne sont couvertes par aucune étape, alors
  que `/promo/map` a un plafond explicite de 300 commerces et un throttle à
  180/min — deux nombres qui appellent une mesure.

---

## 9. À faire ensuite, dans l'ordre

1. **Corriger D1** — 5 codes × 3 tables. Le défaut est réel et visible par
   l'utilisateur aujourd'hui.
2. **Étape 2** — déplacer `check-sync.dart` dans `apps/mobile/tool/`, l'éprouver
   par mutation. C'est ce qui empêche D1 de revenir.
3. **Étape 1** — le banc de refus et le banc d'appartenance.
4. **Étape 3** — le décor, puis le parcours « plafond de 5 promos ».
5. **Étape 4** — les deux premiers bancs métier.
