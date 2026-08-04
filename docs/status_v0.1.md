# Statut d'implémentation — echango Promo V0.1

**Ce fichier est le suivi vivant du projet à partir du 2026-08-04.** Il doit
être mis à jour à chaque implémentation importante — nouvelle fonctionnalité,
correction d'audit, changement d'architecture, décision produit — et pas
seulement en fin de session.

Dernière mise à jour : **2026-08-04**

---

## Rapport aux autres documents

| Document | Rôle | État |
|---|---|---|
| `docs/status_v0.md` | journal de la V0 | **figé** — dernière entrée 2026-07-12 |
| **`docs/status_v0.1.md`** *(ce fichier)* | **journal courant** | actif |
| `docs/METHODE_TEST.md` | la méthode de test, générique à la stack Echango | référence |
| `docs/TEST_PROMO.md` | son instanciation sur ce produit, avec les valeurs réelles | référence |
| `CLAUDE.md` | les 27 règles à respecter | référence |
| `docs/AUDIT_V0.md`, `AUDIT_V1.md` | findings détaillés, fichier:ligne | historique |

> ⚠️ **Un trou de journal existe entre le 2026-07-12 et le 2026-08-04.** Les
> 42 commits des 29–31 juillet (parcours de premier lancement, carte « autour de
> moi », refonte visuelle, bandeau Top promos, préparation à la publication, CI
> Codemagic) **ne figurent dans aucun journal**. Ils sont dans l'historique git
> et dans la PR #13, rien de plus. Ce document ne les reconstitue pas
> rétroactivement — une reconstitution de mémoire serait une donnée d'appui
> fausse en puissance. Il en prend acte et repart d'un état **mesuré**.

---

## État mesuré au 2026-08-04

Mesuré, pas estimé. La méthode et les commandes sont dans `docs/TEST_PROMO.md` §1.

| Composant | État |
|---|---|
| Branche de référence | `main` = `77e788a` (merge PR #13) |
| Branche de travail | `claude/echango-promo-suite-2026-08-04` |
| Backend | 11 contrôleurs, **62 routes** dont 14 ouvertes, 42 codes d'erreur |
| Backend — build | ✅ 0 erreur TypeScript, démarre, migrations à jour |
| Mobile — `flutter analyze` | ✅ **1 avertissement** (import inutilisé) — première analyse par un vrai SDK |
| Mobile — build Android | ✅ compilé et exécuté sur émulateur, connecté au backend local |
| Tests backend | 5 fichiers `.spec.ts` |
| Tests unitaires mobile | 5 fichiers |
| Tests d'écran | **0** — `integration_test/` n'existe pas |
| Écrans | 34 `*_screen.dart` |

**Ce qui a changé dans la connaissance du projet** : le code mobile avait été
« relu statiquement mais jamais compilé » depuis le début du projet (consigne de
`CLAUDE.md`). Ce n'est plus vrai depuis le 2026-08-04 — il compile, tourne, et
`flutter analyze` ne remonte qu'un import inutilisé.

---

## Points ouverts

Classés par ce qu'ils coûtent s'ils restent ouverts. Chacun porte ce qui le
débloque.

### P1 — Un code d'erreur sans décision écrite 🔽 *revu à la baisse le 2026-08-04*

> ⚠️ **Ce point a été formulé, puis corrigé le même jour.** Première version :
> « cinq codes servis et jamais traduits », présentés comme cinq défauts
> visibles par l'utilisateur. **C'était faux pour quatre d'entre eux.**

**Ce qui est établi.** L'en-tête de `error_messages_fr.dart` documente que
`PROMO_DATE_FIN_EXCEEDS_MAX`, `PROMO_ACTIVE_CAP_REACHED`,
`PROMO_DAILY_CREATION_CAP_REACHED` et `PROMO_REPUBLISH_TOO_SOON` sont
**volontairement absents** : leur message backend interpole une valeur (plafond,
durée, délai restant) qu'un mapping statique perdrait.
`ApiException.displayMessage` retombe alors sur le message brut
(`api_exception.dart:52`). Arbitrage assumé, pas oubli.

**Ce qui reste ouvert** : `HIGHLIGHT_CAP_REACHED` (`highlight.service.ts:222`)
n'est **ni traduit, ni épinglé** comme exclusion. Son message interpole lui
aussi une valeur, il appartient donc probablement à la même famille — mais rien
ne le dit. Une exclusion non écrite est indiscernable d'un oubli.

**Le prix de ces exclusions, à garder conscient** : le message backend est
toujours en français. Un commerçant arabophone qui atteint le plafond de
5 promos voit une phrase en français. Si ce prix devient inacceptable, la sortie
n'est pas un mapping statique — il reperdrait la valeur — mais des paramètres
portés par la réponse serveur, l'app composant la phrase.

**Pourquoi l'erreur a été commise, et ce qu'elle a produit de bon.** Les
exclusions vivaient dans un **commentaire**, qu'aucun outil ne peut lire. Le
vérificateur les a donc toutes signalées, et j'ai conclu trop vite à cinq
défauts. La liste vit désormais **en donnée**, dans
`apps/mobile/tool/check_error_codes.dart`, chaque entrée portant sa raison, et
l'auto-test **refuse une exclusion sans justification**. C'est le mode M5 du
générique appliqué à une liste d'exceptions — et l'illustration qu'**un contrôle
peut aussi mentir en disant non**.

**✅ Fermé le 2026-08-04.** Décision : `HIGHLIGHT_CAP_REACHED` **traduit** dans
les 3 tables. ⚠️ **Sans recopier le plafond** — le message backend interpole
`HIGHLIGHT_MAX_SLIDES`, et reproduire ce nombre côté app dupliquerait une
constante serveur (règle 7). La formulation porte le **geste à faire**, qui ne
dépend pas du nombre. Le vérificateur est vert : 38 clés par table.

**Reste ouvert, mineur** : le commentaire d'en-tête de `error_messages_fr.dart`
décrit toujours les exclusions, alors que la liste fait foi dans
`tool/check_error_codes.dart`. Deux sources de vérité tant que le commentaire
ne pointe pas vers le vérificateur. ⚠️ Modification d'un fichier existant —
voir A1.

### P2 — Aucun contrôle exécuté ne tient les couples serveur ↔ app

Six couples doivent rester d'accord ; **aucun n'est tenu par autre chose qu'une
consigne** (`docs/TEST_PROMO.md` §3). P1 est la démonstration que ça ne suffit
pas.

Le plus exposé après les codes d'erreur : `CommercantAccountState`, comparé par
**chaîne littérale** dans plusieurs écrans (règle 19). Un renommage backend ne
produirait aucune erreur de compilation.

**Débloqué par** : étape 2 de `docs/TEST_PROMO.md` — le squelette
`check-sync.dart` tourne déjà sur les vrais fichiers, il reste à le déplacer
dans `apps/mobile/tool/` et à l'éprouver par mutation.

### P3 — `PROMO_MAX_DURATION_DAYS` absente du `.env`

Huit clés présentes dans `.env.example` manquent au `.env` local :
`ANDROID_PACKAGE_NAME`, `ANDROID_SHA`, `IOS_TEAM_ID`, `IOS_BUNDLE_ID`,
`PLAY_STORE_URL`, `APP_STORE_URL`, `CORS_ORIGINS`, `PROMO_MAX_DURATION_DAYS`.

Aucune n'empêche le démarrage. Mais la dernière **pilote une règle métier**
(`PROMO_DATE_FIN_EXCEEDS_MAX`) : un banc qui l'éprouve sans elle teste la valeur
par défaut du code, pas celle de production — et conclut juste sur le mauvais
nombre. `CORS_ORIGINS` mérite d'être fixée aussi.

> **Règle qui en découle** : tout banc qui éprouve une borne configurable
> **imprime la valeur qu'il a effectivement utilisée**. Une borne lue depuis
> l'environnement est une donnée d'entrée du banc, pas une constante.

### P4 — Le verrou du plafond de 5 promos n'a jamais été éprouvé en concurrence

La race condition sur `MAX_PROMOS_ACTIVES` (`promo.service.ts:43`) a été
corrigée par un `pg_advisory_xact_lock` scopé au commerçant. **La correction n'a
jamais été rejouée sous charge.** Un banc de concurrence est probabiliste : un
passage au vert ne prouve rien, il en faut plusieurs tours.

**Débloqué par** : étape 4 de `docs/TEST_PROMO.md`, banc `test-plafond-promos`.

### P5 — L'IDOR agent → promo n'a jamais été rejoué

La faille critique de l'audit V0 (un agent authentifié pouvait modifier les
promos de n'importe quel commerçant) a été corrigée par
`CommercantService.assertZoneMatches`. Rien ne garantit aujourd'hui qu'elle
n'est pas revenue — et la polarité de protection du projet (garde posé **route
par route**) fait que **la route qu'on oublie est ouverte**.

**Débloqué par** : étape 1 de `docs/TEST_PROMO.md`, banc d'appartenance.

### P7 — Cinq miroirs d'enum avalent une valeur inconnue 🆕

**Trouvé le 2026-08-04** par `tool/check_enums.dart`, qui le signale sans
bloquer.

Cinq `fromValue` sur huit portent un `orElse` : **Catégorie**, **Cycle de vie
promo**, **Modération promo**, **État de compte commerçant**, **Motif de
signalement**. Une valeur ajoutée côté serveur y devient silencieusement autre
chose — sans erreur, sans journal.

Le cas le plus lourd : `PromoLifecycleStatus.fromValue` retombe sur
**`expiree`**. Un nouveau statut serveur ferait donc disparaître les promos
concernées de l'affichage client, et le diagnostic partirait chercher une
panne de données.

Les trois autres (`RegistreStatus`, `AuditActorType`,
`CommercantOriginVerification`) lèvent — comportement plus bruyant, donc plus
sûr.

**C'est un choix à rendre, pas un défaut à corriger d'office** : un repli peut
être délibéré. Mais aujourd'hui rien ne dit lequel l'est.

### P8 — La règle 19 est contournée dans les écrans 🆕

Les vérificateurs garantissent que les *valeurs* des miroirs sont justes ; ils
ne garantissent pas que les écrans **s'en servent**. Plusieurs comparent encore
`CommercantAccountState` par **chaîne littérale** (`status == 'autonome'`) : le
miroir existe, il est correct, et il est contourné.

**Débloqué par** un contrôle du même esprit — refuser une comparaison littérale
portant sur une valeur d'enum connue. Reste à écrire.

### P6 — Dette mineure, non bloquante

- `apps/mobile/lib/features/commercant/screens/commercant_login_screen.dart:4` —
  import inutilisé, seul avertissement de `flutter analyze`.
- ~~`apps/mobile/pubspec.lock` non versionné~~ — **fermé le 2026-08-04**
  (`1c1bf1d`). Il n'était ignoré nulle part, il n'avait jamais été ajouté.
  Versionné pour que la machine de développement et Codemagic résolvent le même
  graphe de dépendances.
- `npm install` backend signale **4 vulnérabilités** (1 modérée, 3 hautes), non
  examinées.
- Upload S3/MinIO **jamais éprouvé de bout en bout** contre un vrai bucket —
  dette héritée de l'audit V0, toujours ouverte.
- Aucun mécanisme de **backup** de la base — dette identifiée le 2026-07-12
  après l'incident de corruption, toujours ouverte.

---

## Trous de couverture

Relevés le **2026-08-04** en mesurant la surface réelle par profil (`@Roles` de
chaque route, écrans par dossier) et en la confrontant au plan de test. Le plan
d'alors prévoyait 8 bancs choisis par défaut historique : ils couvraient
**15 routes sur 62**, et le déséquilibre entre profils ne se voyait pas.

`docs/TEST_PROMO.md` §6 a été repris en conséquence : **27 bancs, 62 routes sur
62**.

| Profil | Routes | Écrans | Couvert par le plan d'alors |
|---|---|---|---|
| Admin | **35** | **13** | 3 bancs partiels |
| Agent | **26** | 3 | 1 banc |
| Commerçant | 17 | 7 | 1 banc + 1 parcours |
| Client | 14 (ouvertes) | 4 + 4 onboarding | 3 bancs |

*(les routes partagées comptent par profil, d'où un total supérieur à 62)*

### T1 — L'agent cumule le plus de pouvoir et la plus faible couverture ⚠️

**14 des 26 routes de l'agent sont sous `/admin/*`** : il suspend un commerçant,
le **supprime**, valide ou rejette son registre, réinitialise son PIN, modère
des promos. Le plan ne prévoyait qu'un banc d'appartenance **centré sur la
promo**.

La question « un agent hors de ses communes peut-il suspendre *ce* commerçant ? »
n'était posée nulle part. C'est la forme exacte de l'IDOR critique de l'audit
V0, sur une surface **sept fois plus grande** que celle qui avait été corrigée.

**Traité dans le plan** par `test-agent-appartenance`, étendu aux 16 routes
concernées et remonté en priorité 4 du §9.

### T2 — L'admin : plus grande surface, trois bancs partiels

Non couvert avant reprise : le module **highlight** (5 routes, livré fin
juillet, jamais éprouvé, et porteur du `HIGHLIGHT_CAP_REACHED` de P1), la
**gestion des agents** (6 routes dont `transfer-communes` — précisément ce que
l'`AuditLogModule` devait tracer), l'**audit-log** lui-même, le **dashboard**
(historique de surcompte).

**Traité** par `test-admin-highlight`, `test-admin-agents`,
`test-admin-audit-log`, `test-admin-dashboard`.

### T3 — Le module notifications n'était couvert nulle part

5 routes, partagées par les 3 profils authentifiés, 1 écran. Zéro banc, zéro
parcours. **Traité** par `test-notifications`.

### T4 — `DELETE /commercant/me` n'est éprouvé par rien

Un commerçant peut supprimer son propre compte. Action **irréversible**, aucun
test. **Traité** par `test-commercant-autosuppression`, en priorité 3.

### T5 — La carte client n'était pas couverte

`GET /promo/map` porte deux nombres explicites — **300 commerces**, **180
req/min** — et c'est la fonctionnalité client la plus récente. `GET /commune`
non plus, alors qu'elle porte le piège de pagination de la règle 15.
**Traité** par `test-client-carte` et `test-client-commune`.

### T6 — L'onboarding n'était couvert par rien

4 écrans (splash, choix de rôle, localisation ×2), premier contact, et ils
conditionnent l'accès à tout le reste. **Traité** dans l'étape 3.

### T7 — Trois profils sur quatre n'avaient aucun parcours écran

Le seul prévu était commerçant. **Traité** : un parcours minimal par profil,
plus l'onboarding (§6 étape 3).

> ⚠️ **T1-T7 sont « traités dans le plan », pas résolus.** Aucun de ces bancs
> n'est écrit. Ils ne se ferment qu'une fois le banc écrit **et prouvé par
> mutation**.

---

## Arbitrages en attente

### A1 — Corriger P1 impose de modifier des fichiers existants

**La tension.** La règle de travail posée le 2026-08-04 est **« on ajoute, on ne
modifie pas »**, pour éviter les conflits de merge entre branches et entre les
deux clones (Windows / WSL). Or corriger P1 demande d'éditer trois fichiers
existants.

**Ce qui est réellement en jeu** : 5 lignes ajoutées dans chacun des 3 fichiers,
sans reformatage, sans toucher aux entrées existantes. Le risque de conflit est
faible — un conflit ne surviendrait que si une autre branche ajoutait des
entrées **au même endroit** de la même table.

**En attente de décision.** Trois issues possibles : corriger dans un commit
isolé et minimal ; attendre un moment où aucune autre branche ne touche ces
fichiers ; ou laisser P1 ouvert et documenté jusqu'à un lot i18n dédié.

> **Le cas général vaut d'être tranché une fois** : certains ajouts ne peuvent
> pas être 100 % additifs — brancher un module NestJS suppose une ligne dans
> `app.module.ts`, un écran une entrée dans `router.dart`, un `ErrorCode` une
> ligne dans 3 mappings. La règle a besoin d'une clause pour ces cas, sinon elle
> s'applique mal ou pas du tout.

### A2 — Ordre d'attaque du plan de test

`docs/TEST_PROMO.md` §9 propose : corriger P1 → étape 2 → étape 1 → étape 3 →
étape 4. L'étape 2 avant l'étape 1 parce qu'elle est statique, instantanée, sans
base ni émulateur — et qu'elle a **déjà trouvé un défaut réel**.

**En attente de confirmation.**

---

## Avancement du plan de test

Le détail de chaque étape, avec son critère de sortie, est dans
`docs/TEST_PROMO.md` §6.

| Étape | Objet | État |
|---|---|---|
| — | Méthode générique + 5 squelettes | ✅ écrits, auto-tests au vert (16/16 et 13/13) |
| — | Plan spécifique Promo | ✅ écrit |
| **1** | Banc de refus (48 routes, par construction) | 🔶 **écrit, épinglage prouvé** (auto-test 14/14 dont 6 refus ; **4/4 mutations**, sans identifiants car la phase d'épinglage précède le réseau). Phase réseau en attente du décor — **0 agent en base** |
| **2** | Vérificateurs de synchronisation | ✅ **CLOSE** — 3 vérificateurs, **10 couples sur 10**, **14 mutations sur 14 refusées**. Une commande : `dart run tool/check_all.dart` |
| **3** | Décor + 4 parcours écran + onboarding | ⬜ non commencé |
| **4** | Bancs, couverture d'usage complète (**27 bancs, 62/62 routes**) | ⬜ non commencé |

**Couverture actuelle**, décomposée (`docs/TEST_PROMO.md` §4) — trois
couvertures distinctes, trois cibles :

| Couverture | État | Cible |
|---|---|---|
| **Accès** (qui a le droit d'appeler quoi) | 0 / 62 | **100 %** — atteinte par construction, le banc énumère depuis la source |
| **Usage** (chaque route appelée au moins une fois) | 0 / 62 | **100 %** — bornée à 62 routes |
| **Comportement** (chaque règle fait ce qu'elle doit) | 0 / 8 règles chiffrées | **piloté par le risque** — non bornée, un pourcentage y serait inventé |
| Couples serveur ↔ app | ✅ **10 / 10** — tous éprouvés par mutation | 10 |
| Écrans | 0 / 34 | 33 (`dev_profile_switcher` exclu, outil de développement) |

---

## Journal

### 2026-08-04 — Reprise, mise à niveau et outillage de test

**Synchronisation.** Le dépôt local (Windows) et le clone WSL étaient tous deux
en retard : HEAD au 2026-07-14 côté Windows, au 2026-07-06 côté WSL. `main`
contenait déjà tout, plus la PR #13 mergée le jour même. Les 18 fichiers
modifiés non commités du clone WSL se sont révélés être **du reformatage
Prettier pur** (vérifié en neutralisant espaces et virgules : zéro changement de
logique) — écartés sans perte. Les deux clones sont désormais sur
`claude/echango-promo-suite-2026-08-04`, poussée sur `origin`.

**Backend remis en service.** `npm install`, puis un mois de migrations en
retard appliquées — dont `CreateHighlight` (table du bandeau, contraintes et
index) et `AddCategorieRestauration` (7ᵉ valeur d'enum sur `commercant` et
`promo`). Démarre sans erreur, répond 200 sur `/commune`, `/promo`, `/promo/map`,
`/highlight`.

**Mobile compilé pour la première fois.** `flutter pub get` + `flutter analyze`
sur Flutter 3.35.7 → **1 seul avertissement** sur tout le projet. Le build
Android a d'abord échoué sur `PKIX path building failed` : **l'analyse HTTPS
d'AVG** réémet les certificats avec sa propre autorité racine, présente dans le
magasin Windows mais absente du truststore Java. Débloqué en désactivant
l'analyse HTTPS le temps du build.

**⚠️ Le piège qui a coûté le plus, et qui doit être connu.** L'app a d'abord
tourné **contre la production** alors qu'elle était censée viser le backend
local. Cause : `flutter run` lancé via `Start-Process` (PowerShell), qui perd
silencieusement le `--dart-define` — le build part alors avec la valeur par
défaut de `Env.apiBaseUrl`, c'est-à-dire `https://promo.echango.com`. Aucune
erreur, aucun message : l'app fonctionne parfaitement, sur les mauvaises
données. Diagnostiqué en capturant le trafic TCP de l'émulateur (0 connexion
vers `10.0.2.2:3000`, 57 vers l'IP du VPS), puis confirmé en cherchant la chaîne
dans le `kernel_blob.bin` de l'APK installé. **Appeler `flutter` directement**,
et vérifier le kernel en cas de doute (`docs/TEST_PROMO.md` §7).

**Méthode de test.** Étude du dépôt `echango-delivery` (26 bancs de scénarios,
3 fichiers de parcours écran, 6 vérificateurs statiques), puis extraction en
`docs/METHODE_TEST.md` — 11 modes de défaillance, un lexique, un ordre
d'adoption, cinq squelettes exécutables dans `docs/methode-test/`. Instancié sur
ce produit dans `docs/TEST_PROMO.md`.

**Les squelettes ont trouvé leurs propres défauts, et c'est le point.** Trois
défauts dans mon propre code de vérification, **aucun repéré à la relecture** :
un enum sur une seule ligne dont seul le premier membre était lu ; un décorateur
en commentaire compté comme une vraie route ; et surtout un analyseur qui
cherchait `@UseGuards` **après** `@Controller` alors que l'ordre NestJS habituel
le place avant — six routes d'administration annoncées « ouvertes » alors
qu'elles étaient gardées trois lignes plus haut. Ce dernier n'a été trouvé qu'en
faisant tourner l'outil sur le dépôt réel. Les trois sont désormais des cas
d'auto-test.

**Résultats de la première passe** : 62 routes, 14 ouvertes — toutes légitimes,
**aucun garde manquant**. Et P1, ci-dessus.

### 2026-08-04 (suite) — Étape 2, premier vérificateur en place et éprouvé

`apps/mobile/tool/check_error_codes.dart` compare le registre serveur
(42 codes) aux trois tables de traduction. Auto-test **14/14, dont 7 refus** ;
et surtout **5 mutations des vrais fichiers, 5 refus** :

| Mutation | Attendu | Obtenu |
|---|---|---|
| membre bidon ajouté à l'enum serveur | 3 manques | ✅ |
| clé retirée d'**une seule** table | 1 manque | ✅ |
| doublon dans une table | 1 doublon | ✅ |
| clé inconnue du serveur | 1 « en trop » | ✅ |
| table renommée (`_ar` → `_arabe`) | **échec sur source introuvable** | ✅ sortie 2 |

La cinquième est la plus importante : un contrôle qui **conclut à l'accord**
quand il ne trouve pas sa source est le mode de panne le plus dangereux de
cette famille.

> ⚠️ **Une leçon d'exploitation, apprise en se brûlant.** Le lanceur de
> mutations restaure par `git checkout -- .`, ce qui **balaie aussi le travail
> non commité**. Lancé sur un arbre sale, il a effacé les trois traductions qui
> venaient d'être écrites. L'ordre est donc : **committer d'abord, muter
> ensuite** — et un lanceur de mutations devrait refuser de démarrer sur un
> arbre sale, ou ne restaurer que les fichiers qu'il a lui-même touchés.

**Ce que ce vérificateur a coûté en confiance, et pourquoi c'est instructif.**
Sa première version a produit un faux positif à quatre entrées (voir P1) parce
que les exclusions volontaires vivaient dans un commentaire. Un contrôle qui
accuse à tort se paie plus cher qu'un contrôle absent : c'est ainsi qu'ils
finissent désactivés. La correction n'a pas été de désactiver le contrôle mais
de **déplacer la liste d'exclusions du commentaire vers la donnée**, avec
obligation de justification — l'auto-test refuse une exclusion sans raison.

### 2026-08-04 (fin) — Étape 2 quasi close, deux constats de conception

`tool/check_enums.dart` tient les **8 enums miroirs**, 29 valeurs, comparés sur
la **valeur réseau** et non sur le nom du membre — les deux langages nomment
différemment (`VETEMENTS_TEXTILE` / `vetementsTextile`). Tous d'accord.

Auto-test 11 cas dont 6 refus, et **4 mutations sur 4 refusées** : valeur
ajoutée côté serveur, valeur retirée du miroir, valeur changée d'un seul côté,
fichier de miroir renommé (→ sortie 2, jamais « tout est d'accord »).

**Le piège d'extraction, qui est devenu un cas d'auto-test** : le corps d'un
enum Dart amélioré s'arrête au premier `;`. Au-delà vivent le constructeur, les
champs et les méthodes — sans cette borne, les chaînes de `fromValue` seraient
comptées comme des valeurs d'énumération.

**Le lanceur de mutations refuse désormais de démarrer sur un arbre sale**, et
ne restaure que les fichiers qu'il a touchés — correction directe de la leçon
apprise plus haut dans la journée.

Deux constats sont sortis du contrôle sans qu'on les cherche : **P7** (cinq
miroirs avalent une valeur inconnue) et **P8** (la règle 19 est contournée dans
les écrans). Aucun des deux n'est traité : ce sont des décisions, pas des
corrections évidentes.

### 2026-08-04 (clôture) — Étape 2 terminée

`tool/check_server_rules.dart` tient les **6 bornes numériques** et **2 motifs
réguliers** que l'application recopie du serveur : description de promo (140),
titre et sous-titre de mise en avant (60/100), mot de passe agent (8, dans
3 écrans), et les deux motifs de PIN (`^\d{6,12}$` pour le fixer,
`^\d{4,12}$` pour le vérifier). Tous d'accord.

**Choix de conception** : il lit les **vrais** fichiers des deux côtés, sans
fichier de constantes intermédiaire. Un tel fichier, que les écrans
n'utiliseraient pas, aurait donné une fausse impression de couverture — c'est
le défaut « le serveur savait, l'app ignorait » appliqué à nos propres outils.

**Il a refusé de conclure au premier essai**, sur un chemin de DTO erroné de ma
part (`admin/dto` au lieu de `agent/dto`) : il a dit « introuvable » plutôt
qu'annoncer l'accord sur les bornes qu'il avait pu lire. C'est exactement le
comportement voulu, obtenu sans l'avoir cherché.

`tool/check_all.dart` donne le point d'entrée unique qui manquait : les trois
vérificateurs, auto-test d'abord, sans arrêt au premier échec. L'étage 1 est
donc le seul lot qui pourrait tourner à chaque commit — statique, instantané,
sans base ni émulateur.

**Bilan de l'étape 2** : 3 vérificateurs, **10 couples sur 10** tenus par un
contrôle exécuté (contre 0 le matin même), et **14 mutations des vrais fichiers,
14 refus**.

### 2026-08-04 (soir) — Étape 1, le banc de refus est écrit

`scripts/lib/frontiere_http.py` + son lanceur. 62 routes énumérées depuis la
source, 14 ouvertes épinglées avec leur justification, 48 protégées.

**Ce qui est déjà prouvé, et sans un seul identifiant.** La vérification de
l'épinglage s'exécute **avant le premier appel réseau** — c'est elle qui
attrape un garde oublié, donc la propriété la plus importante du banc dans un
projet où la protection est posée route par route. Quatre mutations, quatre
comportements attendus : garde retiré d'un contrôleur → refus immédiat avec les
5 routes nommées ; route ouverte devenue protégée → avertissement ; source
introuvable → sortie 2 sans verdict ; arbre propre → passe l'épinglage et
s'arrête faute d'identifiants.

**Ce qui bloque la phase réseau, et ce n'est pas du code** : la base locale a
1 admin, 1 commerçant et **0 agent**. Les ~140 sondes attendent que l'étape 3
pose ces comptes. Le banc le dit et s'arrête plutôt que de conclure sur ce
qu'il a pu lire.

**Trois pièges d'analyse rencontrés**, tous devenus des cas d'auto-test : les
décorateurs forment un bloc contigu **autour** de la méthode (`@Roles` peut
suivre `@Get`, et ne lire que ce qui précède décale les rôles d'une route) ;
l'en-tête de classe ne commence pas au `@Controller` ; les paramètres d'URL
doivent être remplacés par un identifiant **bien formé**, sinon on mesure la
validation du format et un 400 passe pour un refus.

**Deux limites nommées plutôt que tues** : la sonde « mauvais rôle » est
impossible sur les routes ouvertes aux 3 rôles (notifications) — comptée non
applicable ; les 3 routes App Links sont host-scopées et répondent 404 sur
localhost par conception.

Aucune modification du code source : les mutations sont transitoires et
restaurées dans la seconde, `git status` vide après coup.

---

## Comment tenir ce fichier

- **Une entrée de journal par session**, datée, qui dit ce qui a été fait **et
  ce qui a été appris** — un piège rencontré vaut plus qu'une liste de commits,
  qui est déjà dans git.
- **Les points ouverts se ferment explicitement**, avec la date et ce qui les a
  fermés. Un point qui disparaît sans un mot est indiscernable d'un oubli.
- **Ne rien reconstituer de mémoire.** Si un fait n'est pas mesuré, l'écrire
  comme non mesuré. Une donnée d'appui fausse coûte plus cher qu'une absence.
- **Les chiffres portent leur date**, parce qu'ils vieillissent.
