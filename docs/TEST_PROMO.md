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

### D1 — Un code d'erreur sans décision, et quatre exclusions illisibles

⚠️ **Ce constat a été corrigé le 2026-08-04 après vérification.** La première
version annonçait « cinq codes servis et jamais traduits », donc cinq défauts.
C'était faux pour quatre d'entre eux, et la raison de l'erreur est le vrai
enseignement — voir plus bas.

`dart run tool/check_error_codes.dart` sur `main` :

| Code | Émis par | Dans les 3 tables | Verdict |
|---|---|---|---|
| `PROMO_DATE_FIN_EXCEEDS_MAX` | `promo.service.ts:103` | ❌ | **exclusion volontaire** |
| `PROMO_ACTIVE_CAP_REACHED` | `promo.service.ts:126` | ❌ | **exclusion volontaire** |
| `PROMO_DAILY_CREATION_CAP_REACHED` | `promo.service.ts:154` | ❌ | **exclusion volontaire** |
| `PROMO_REPUBLISH_TOO_SOON` | `promo.service.ts:174` | ❌ | **exclusion volontaire** |
| `HIGHLIGHT_CAP_REACHED` | `highlight.service.ts:222` | ❌ | ⚠️ **sans décision écrite** |

**Les quatre exclusions sont légitimes et documentées.** L'en-tête de
`error_messages_fr.dart` explique que le message backend de ces codes
**interpole une valeur** (le plafond, la durée, le délai restant) et qu'un
mapping statique la perdrait. `ApiException.displayMessage` retombe alors sur
le message brut (`messages[code] ?? message`, `api_exception.dart:52`). C'est un
arbitrage assumé, pas un oubli.

**Le prix de cet arbitrage doit rester conscient** : le message backend est
**toujours en français**. Un commerçant arabophone qui atteint le plafond de 5
promos voit donc une phrase en français. Si ce prix devient inacceptable, la
sortie n'est pas d'ajouter un mapping statique — il reperdrait la valeur — mais
de faire porter les paramètres par la réponse serveur pour que l'app compose la
phrase elle-même.

**Ce qui reste un vrai défaut** : `HIGHLIGHT_CAP_REACHED` n'est ni traduit, ni
inscrit dans la liste des exclusions. Son message interpole lui aussi une
valeur, il appartient donc probablement à la même famille — mais **rien ne le
dit**, et une exclusion non écrite est indiscernable d'un oubli. Quelqu'un doit
trancher : le traduire, ou l'épingler avec sa raison.

**Pourquoi je me suis trompé, et c'est le vrai enseignement.** Les exclusions
vivaient dans un **commentaire d'en-tête**. Aucun outil ne peut lire un
commentaire : le vérificateur les a donc toutes signalées comme des défauts, et
j'ai conclu trop vite. C'est le mode **M5** du générique — *un invariant
s'applique, il ne se documente pas* — appliqué à une liste d'exceptions plutôt
qu'à une règle. La liste vit désormais **en donnée**, dans
`apps/mobile/tool/check_error_codes.dart`, chaque entrée portant sa raison, et
l'auto-test refuse une exclusion sans justification.

**Et l'enseignement inverse, qui vaut autant** : un contrôle peut mentir en
disant **non**. Un faux positif qui accuse à tort se paie en confiance perdue —
c'est ainsi que les contrôles finissent désactivés.

**État** :

1. ✅ **`HIGHLIGHT_CAP_REACHED` traduit** dans les 3 tables (décision du
   2026-08-04). ⚠️ **Sans recopier le plafond** : le message backend interpole
   `HIGHLIGHT_MAX_SLIDES`, et reproduire ce nombre côté app dupliquerait une
   constante serveur — l'app mentirait le jour où elle change (règle 7 de
   `CLAUDE.md`). La formulation retenue porte le **geste à faire**, qui ne
   dépend pas du nombre : « supprimez une mise en avant pour en ajouter une
   nouvelle ». Le contrôle est vert : 38 clés dans chaque table.
2. ⬜ Faire pointer le commentaire d'en-tête de `error_messages_fr.dart` vers
   `tool/check_error_codes.dart`, pour qu'il n'y ait **qu'une seule** source de
   vérité sur les exclusions. ⚠️ Modification d'un fichier existant — arbitrage
   A1.

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

### Les personas, et leur surface mesurée

Mesuré le 2026-08-04 en lisant les `@Roles` de chaque route. ⚠️ Les routes
partagées (`/notifications`, `/storage/upload`, `/promo/:id`) comptent pour
**chaque** profil qui y a droit — le total par colonne dépasse donc 62.

| Persona | Auth. | Routes | Écrans | Particularité pour les tests |
|---|---|---|---|---|
| **Admin** | mot de passe | **35** | **13** | Compte **unique** en V0. Accès par URL directe `/admin`, non découvrable dans l'app. **La plus grande surface des quatre, de loin.** |
| **Agent** | mot de passe | **26** | 3 | Rattaché à N communes. ⚠️ **14 de ses routes sont sous `/admin/*`** : il suspend, supprime, valide un registre, réinitialise un PIN, modère. Rôle appelé à disparaître à l'extension multi-wilaya — mais bien présent aujourd'hui. |
| **Commerçant** | PIN | 17 | 7 | Cycle de vie : inscription → validation registre → actif → suspendu → supprimé. Peut **s'auto-supprimer** (`DELETE /commercant/me`). |
| **Client** | **aucune** — anonyme | 14 (ouvertes) | 4 + 4 onboarding | C'est ce qui rend 14 routes légitimement ouvertes. Identifié par un `X-Device-Id` **déclaratif, jamais vérifié** — d'où le throttle par IP sur `/report`. |

> ⚠️ **Le fait qui doit orienter tout le plan** : l'**agent** cumule un pouvoir
> quasi administratif (14 routes `/admin/*`) et la plus faible couverture. La
> question « un agent hors de ses communes peut-il suspendre *ce* commerçant ? »
> porte sur une surface **sept fois plus grande** que l'IDOR promo corrigé à
> l'audit V0 — et elle n'est posée nulle part aujourd'hui.

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

Chaque ligne est un couple qui doit rester d'accord. État au 2026-08-04 :

| Couple | Serveur | Application | Tenu par |
|---|---|---|---|
| Codes d'erreur | `common/errors/error-code.enum.ts` (42) | `error_messages_{fr,en,ar}.dart` (38 clés) | ✅ `tool/check_error_codes.dart` |
| Catégories (7) | `common/enums/categorie.enum.ts` | `domain/enums/categorie.dart` | ✅ `tool/check_enums.dart` |
| Cycle de vie promo (5) | `promo.entity.ts` | `promo_lifecycle_status.dart` | ✅ idem |
| Modération promo (4) | `promo.entity.ts` | `promo_moderation_status.dart` | ✅ idem |
| État de compte commerçant (2) | `commercant.entity.ts` | `commercant_account_state.dart` | ✅ idem |
| Vérification d'origine (2) | `commercant.entity.ts` | `commercant_origin_verification.dart` | ✅ idem |
| Statut du registre (3) | `commercant.entity.ts` | `registre_status.dart` | ✅ idem |
| Motif de signalement (4) | `report.entity.ts` | `report_reason.dart` | ✅ idem |
| Type d'acteur (audit) (2) | `audit-log.entity.ts` | `audit_actor_type.dart` | ✅ idem |
| **Bornes de validation** | décorateurs des DTO | constantes de formulaire | ⬜ **rien** |

> ⚠️ **Ce que ces contrôles ne couvrent PAS, et c'est la règle 19 qui reste
> ouverte.** Ils garantissent que les *valeurs* d'un miroir sont les bonnes ;
> ils ne garantissent pas que les écrans **utilisent** le miroir. Plusieurs
> comparent encore `CommercantAccountState` par **chaîne littérale**
> (`status == 'autonome'`) : le miroir existe, il est juste, et il est
> contourné. Un contrôle du même esprit — refuser une comparaison littérale sur
> une valeur d'enum connue — reste à écrire.

> ⚠️ **Et 5 miroirs sur 8 avalent une valeur inconnue** (`orElse` dans
> `fromValue`) : catégorie, cycle de vie, modération, état de compte, motif de
> signalement. Une valeur ajoutée côté serveur y devient silencieusement autre
> chose — pour le cycle de vie, une promo inconnue serait traitée comme
> **expirée**. `check_enums.dart` le signale sans bloquer : c'est un choix à
> rendre, pas un défaut à corriger d'office.

---

## 4. Registre de couverture

Ce qui est couvert, ce qui ne l'est pas, et **pourquoi**. Un total sans sa
décomposition ne se vérifie pas.

### Trois couvertures, trois cibles différentes

Les confondre conduit à annoncer un pourcentage qui ne veut rien dire. Elles ne
répondent pas à la même question et n'ont pas le même plafond atteignable.

| Couverture | Question | Cible | Pourquoi cette cible |
|---|---|---|---|
| **Accès** | qui a le droit d'appeler quoi | **100 %** | Atteinte **par construction** : le banc énumère les routes depuis la source, donc une route ajoutée demain est couverte sans que personne y pense |
| **Usage** | chaque route est-elle appelée au moins une fois en cas nominal | **100 %** | Atteignable et bornée : 62 routes, une passe chacune. Attrape les 500, les sérialisations cassées, les réponses vides — la famille de défauts qui ne lève jamais |
| **Comportement** | chaque règle métier fait-elle ce qu'elle doit | **piloté par le risque** | **Non bornée** : les combinaisons, l'ordre et la concurrence sont infinis. Un pourcentage y serait un chiffre inventé |

> **Pourquoi la couverture d'usage mérite 100 % et pas moins.** C'est la seule
> qui se compte honnêtement, et elle coûte peu par route une fois le décor
> posé. Surtout, elle traite le mode de défaillance central de ce projet : une
> donnée mal câblée ne casse pas, elle **disparaît** — en HTTP 200. Une route
> jamais appelée peut servir une liste vide depuis des semaines sans que rien
> ne le dise.

### État au 2026-08-04

```
Couverture d'ACCÈS                    0 / 62 routes      ← étape 1, cible 100 %
  protégées, à éprouver .......      48
  ouvertes, à épingler (§5) ...      14

Couverture d'USAGE                    0 / 62 routes      ← étape 4, cible 100 %
  admin ......................       35
  agent ......................       26   dont 14 sous /admin/*
  commerçant .................       17
  client (ouvertes) ..........       14
  (somme > 62 : les routes partagées comptent par profil)

Couverture COMPORTEMENTALE            0 / 8 règles chiffrées   ← étape 4
  (le plafond de 5 est protégé par un verrou consultatif
   Postgres, jamais éprouvé en concurrence)

Couples serveur ↔ app                10 / 10 tenus       ← étape 2 CLOSE
  codes d'erreur .............   ✅ éprouvé par 5 mutations
  8 enums miroirs ............   ✅ éprouvé par 4 mutations
  bornes de validation .......   ✅ éprouvé par 5 mutations
  (une seule commande : dart run tool/check_all.dart)

Écrans (*_screen.dart)                0 / 34 ouverts     ← étape 3
  admin 13 · commercant 7 · client 4 · onboarding 4
  agent 3 · shared 2 · dev 1
```

### Exclusions épinglées

Aucune exclusion **définitive** à ce jour. Les quatre points ci-dessous
coûtent plus cher que les autres, mais **aucun n'est un obstacle** — les
nommer sert à ce qu'ils ne deviennent pas des oublis silencieux.

| Point coûteux | Pourquoi | Ce qui le débloque |
|---|---|---|
| `POST /storage/upload` de bout en bout | la POST policy S3 (`content-length-range`) ne s'éprouve pas contre un stub | **MinIO tourne déjà en local** (`echangopromo-minio-1`) — c'est faisable aujourd'hui |
| `POST /commercant/me/registre` | demande un décor **photographique** | un PNG 1×1 en base64 suffit |
| Les 3 routes App Links | scopées au host `promo.echango.com`, donc 404 sur localhost | les sonder avec `-H "Host: promo.echango.com"` |
| Les routes destructives (`DELETE /commercant/me`, `/admin/commercant/:id/delete`) | consomment un compte à chaque passage, et l'inscription est plafonnée | comptes dédiés à emails stables, remis d'aplomb par `reactivate` plutôt que recréés |

⚠️ `dev_profile_switcher_screen.dart` est le **seul écran exclu** de la cible :
c'est un outil de développement, pas une surface produit.

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

### Étape 2 — Les vérificateurs de synchronisation ✅ **close (2026-08-04)**

**Une seule commande**, qui lance les trois avec leur auto-test :

```bash
cd apps/mobile && dart run tool/check_all.dart
```

Elle ne s'arrête pas au premier échec — sortir tôt masquerait l'état des
suivants, or c'est ce qu'on veut savoir en rejouant une suite. Et si l'auto-test
d'un vérificateur échoue, **son contrôle réel n'est pas exécuté** : son verdict
ne vaudrait rien.

| Vérificateur | Ce qu'il tient | Auto-test | Mutations |
|---|---|---|---|
| `check_error_codes.dart` | 42 codes serveur ↔ 3 tables (38 clés) | 14 cas, **7 refus** | **5/5** |
| `check_enums.dart` | 8 enums miroirs, 29 valeurs | 11 cas, **6 refus** | **4/4** |
| `check_server_rules.dart` | 6 bornes + 2 motifs réguliers | 13 cas, **6 refus** | **5/5** |

**Ce que les mutations ont prouvé** — c'est ça le critère de sortie, pas le
vert. Quatorze mutations des **vrais** fichiers, quatorze refus : membre bidon
ajouté, clé retirée d'une seule table, doublon, clé inconnue, valeur d'enum
changée d'un seul côté, borne serveur relevée, copie app modifiée, motif de PIN
divergent, champ de DTO renommé, et surtout **fichier de source renommé** → le
contrôle échoue sur source introuvable au lieu de conclure à l'accord. C'est le
mode de panne le plus dangereux de cette famille.

**Ce que l'étape a rapporté** : un vrai défaut corrigé (`HIGHLIGHT_CAP_REACHED`
non traduit), un faux diagnostic évité de justesse (les quatre exclusions
volontaires, voir D1), et deux observations de conception qui n'étaient
demandées à personne — les replis silencieux (P7) et les comparaisons
littérales qui contournent les miroirs (P8).

**Ce qui n'est délibérément pas couvert** : les bornes serveur **sans copie côté
app**. L'absence ne ment pas, contrairement à une copie divergente — le serveur
refuse, l'app affiche le refus. Les épingler serait inventer une dette.

### Étape 3 — Le décor et les parcours écran (un par profil, au minimum)

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

**Puis un parcours minimal par profil** — trois des quatre n'en ont aucun (T7),
et l'admin est celui qui a le plus d'écrans (13) :

| Profil | Parcours minimal | Pourquoi celui-là |
|---|---|---|
| Commerçant | le plafond de 5 promos | ci-dessus |
| Admin | modérer une promo signalée depuis la file | 3 écrans traversés, une décision qui masque du contenu public |
| Agent | créer un commerçant, puis une promo pour lui | le seul parcours agent qui écrit, et il touche l'appartenance |
| Client | choisir une commune → liste → fiche → signaler | le parcours du seul utilisateur non authentifié |
| Onboarding | splash → choix de rôle → localisation (les 2 écrans) | 4 écrans, premier contact, conditionne l'accès à tout le reste (T6) |

⚠️ **Le parcours admin et le parcours agent partagent des écrans mais pas les
mêmes droits.** Les jouer tous les deux n'est pas une redondance : c'est là que
se voit, à l'écran, ce que `test-agent-appartenance` vérifie côté API.

**Critère de sortie** : `flutter drive` tourne depuis une machine neuve en
suivant uniquement ce qu'imprime le décor.

### Étape 4 — Les bancs, en couverture d'usage complète

**Le principe qui rend ce tableau vérifiable** : chaque route des 62 figure dans
**au moins un** banc. Il se lit donc dans les deux sens — de gauche à droite
pour savoir ce qu'un banc éprouve, de **droite à gauche** pour vérifier
qu'aucune route n'est orpheline. Une version antérieure de ce plan comptait
8 bancs choisis par défaut historique : ils couvraient 15 routes sur 62, et le
déséquilibre entre profils ne se voyait pas.

#### Transverse — les 3 profils authentifiés

| Banc | Routes exercées | Ce qu'il éprouve en propre |
|---|---|---|
| `test-auth-login` | `POST /{commercant,agent,admin}/login` | le refus après 5 tentatives (c'est aussi ce qui rend tous les autres bancs coûteux) |
| `test-revocation-jwt` | `POST /admin/me/revoke-token`, `POST /admin/agent/:id/revoke-token`, `GET /admin/me` | `tokenVersion` invalide les jetons — ajouté à l'audit V1, **jamais rejoué** |
| `test-notifications` | `GET /notifications`, `/notifications/unread`, `/unread/count`, `POST /notifications/:id/read`, `/read-all` | **module entier sans aucune couverture** (T3) |
| `test-storage-upload` | `POST /storage/upload` | la POST policy S3 (`content-length-range`, 5 Mo) **jamais éprouvée contre un vrai bucket** — MinIO tourne en local |

#### Client — 14 routes ouvertes

| Banc | Routes exercées | Ce qu'il éprouve en propre |
|---|---|---|
| `test-client-liste` | `GET /promo`, `GET /promo/:id` | « visible » a **une seule** définition ; **aucune réponse ne porte `photoKey`** (un spread exposait l'UUID de l'agent) |
| `test-client-carte` | `GET /promo/map` | plafond de 300 commerces, bornes de la zone visible, throttle 180/min (T5) |
| `test-client-commune` | `GET /commune` | liste **complète**, jamais tronquée — la paginer casserait `CommuneCascadeField` (règle 15) |
| `test-client-highlight` | `GET /highlight` | bandeau curé : 10 max, repli à 8 |
| `test-client-fiche` | `GET /commercant/:id/public` | la projection publique — que voit un anonyme, et surtout que ne voit-il pas |
| `test-client-applinks` | `GET /p/:id`, les 2 `.well-known` | host-scopées : à sonder avec `-H "Host: promo.echango.com"` |
| `test-abus-signalement` | `POST /report` | `X-Device-Id` déclaratif — masquer la promo d'un concurrent en changeant un en-tête |

#### Commerçant — 17 routes

| Banc | Routes exercées | Ce qu'il éprouve en propre |
|---|---|---|
| `test-promo-plafond` | `POST /promo` | 5 actives **en concurrence** : le `pg_advisory_xact_lock` n'a jamais été éprouvé sous charge. Probabiliste, plusieurs tours |
| `test-promo-cycle` | `PATCH /promo/:id`, `POST /promo/:id/publish`, `/stop`, `GET /promo/me/all` | plafond quotidien (5), cooldown de republication (24 h), durée maximale |
| `test-commercant-profil` | `GET`/`PATCH /commercant/me`, `PATCH /commercant/me/pin` | le PIN 4-6 chiffres |
| `test-commercant-registre` | `POST /commercant/register`, `POST /commercant/me/registre` | demande un décor **photographique** |
| `test-commercant-dashboard` | `GET /commercant/me/dashboard` | le surcompte de promos actives, défaut historique |
| `test-commercant-autosuppression` | `DELETE /commercant/me` | **action irréversible, aucun test aujourd'hui** (T4) |

#### Agent — 26 routes

| Banc | Routes exercées | Ce qu'il éprouve en propre |
|---|---|---|
| **`test-agent-appartenance`** ⚠️ | **les 14 routes `/admin/*`** + `PATCH /promo/:id` + `POST /promo/agent/:commercantId` | **Le banc le plus important du lot** (T1). Un agent hors de ses communes doit être refusé sur *chacune* — suspendre, supprimer, valider un registre, réinitialiser un PIN, modérer. L'IDOR corrigé à l'audit V0 ne portait que sur les promos : la surface réelle est **sept fois plus grande** |
| `test-agent-creation` | `POST /agent/commercant`, `GET /agent/me` | le commerçant créé tombe dans une commune de l'agent |
| `test-agent-promo` | `POST /promo/agent/:commercantId` | l'exemption agent/admin des plafonds anti-abus |

#### Admin — 35 routes

| Banc | Routes exercées | Ce qu'il éprouve en propre |
|---|---|---|
| `test-admin-registre` | `GET /admin/commercant`, `POST …/registre/{valider,rejeter}`, `…/profile/valider`, `…/reset-pin` | le cycle de validation |
| `test-admin-cycle-commercant` | `POST …/suspend`, `/reactivate`, `/delete` | suspension ≠ suppression, et la suspension **libère le numéro de téléphone** |
| `test-admin-moderation` | `GET /admin/moderation/queue`, `POST …/{masquer,verifier-ok,avertir}` | seuil de 3 signalements, fenêtre d'ignore de 30 jours |
| `test-admin-dashboard` | `GET /admin/dashboard`, `GET /admin/promo` | le surcompte, et les filtres wilaya/commune |
| `test-admin-agents` | `POST`/`GET /admin/agent`, `PATCH /admin/agent/:id/communes`, `POST /admin/agent/transfer-communes`, `…/reset-password` | le transfert de communes — **exactement ce que l'`AuditLogModule` devait tracer** (T2) |
| `test-admin-audit-log` | `GET /admin/audit-log` | module resté **non branché depuis le premier commit** ; les actions ci-dessus doivent y laisser une trace |
| `test-admin-highlight` | `GET`/`POST /admin/highlight`, `PATCH`/`DELETE /admin/highlight/:id`, `POST /admin/highlight/reorder` | plafond de 10, réordonnancement, image importée. **Livré fin juillet, jamais éprouvé**, et porte le `HIGHLIGHT_CAP_REACHED` non traduit de P1 (T2) |

**Total : 27 bancs, 62 routes sur 62.**

**Ordre d'écriture** — par ce dont l'échec est une **faille**, puis par ce dont
l'échec est une **perte de données**, puis le reste :

1. `test-agent-appartenance` — seul banc dont l'échec est une faille d'accès
   sur 16 routes à la fois.
2. `test-promo-plafond` — une correction jamais rejouée, sur une règle d'argent.
3. `test-admin-cycle-commercant` et `test-commercant-autosuppression` — les
   actions irréversibles.
4. Le reste, par profil, en commençant par `admin` (35 routes, 3 bancs partiels
   aujourd'hui).

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
3. **Étape 1** — le banc de refus (48 routes d'un coup, par construction).
4. **`test-agent-appartenance`** — hors ordre, et volontairement. C'est le seul
   banc dont l'échec serait une **faille d'accès sur 16 routes à la fois**, et
   la surface concernée n'a jamais été éprouvée (T1).
5. **Étape 3** — le décor, puis le parcours « plafond de 5 promos ».
6. **Étape 4** — le reste des 27 bancs, dans l'ordre du §6.

**La cible est 100 %** sur la couverture d'accès et sur la couverture d'usage
(§4). Ce n'est pas un objectif de principe : les deux se comptent honnêtement,
la première est atteinte par construction, et la seconde est bornée à 62 routes.
Seule la couverture comportementale reste pilotée par le risque, parce qu'elle
n'a pas de dénominateur.
