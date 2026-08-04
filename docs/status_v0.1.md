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

### P1 — Cinq codes d'erreur servis et jamais traduits ⚠️ visible par l'utilisateur

**Trouvé le 2026-08-04** par `docs/methode-test/check-sync.dart` sur `main`.

| Code | Émis par |
|---|---|
| `PROMO_DATE_FIN_EXCEEDS_MAX` | `promo.service.ts:103` |
| `PROMO_ACTIVE_CAP_REACHED` | `promo.service.ts:126` |
| `PROMO_DAILY_CREATION_CAP_REACHED` | `promo.service.ts:154` |
| `PROMO_REPUBLISH_TOO_SOON` | `promo.service.ts:174` |
| `HIGHLIGHT_CAP_REACHED` | `highlight.service.ts:222` |

Aucun n'a d'entrée dans `error_messages_fr.dart`, `_en.dart` ni `_ar.dart`.

**Effet.** Un commerçant qui atteint le plafond de 5 promos actives reçoit le
message brut du backend — **toujours en français**, y compris sur un téléphone
configuré en arabe ou en anglais. Aucune erreur de compilation d'aucun côté ne
le signale : c'est une panne silencieuse.

**Ce que ça dit de la règle 26 de `CLAUDE.md`.** Elle exige précisément
l'inverse, et elle a tenu pendant des mois. Les cinq codes appartiennent tous
aux fonctionnalités les plus récentes (anti-abus promo, bandeau Top promos) :
la règle a lâché exactement là où le rythme s'est accéléré. **Une consigne
écrite ne peut pas échouer ; un contrôle exécuté, si.** D'où P2.

**Débloqué par** : ajouter 5 entrées dans chacun des 3 fichiers.
⚠️ **Arbitrage à rendre** — voir A1.

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
| **1** | Banc de refus + banc d'appartenance | ⬜ non commencé |
| **2** | Vérificateurs de synchronisation | 🔶 squelette fonctionnel, à déplacer dans `tool/` et à éprouver par mutation |
| **3** | Décor + premier parcours écran | ⬜ non commencé |
| **4** | Bancs métier (8 identifiés) | ⬜ non commencé |

**Couverture actuelle**, décomposée (`docs/TEST_PROMO.md` §4) : 0 route sur 48
protégées éprouvée, 0 règle métier chiffrée sur 8 couverte, 0 couple sur 6 tenu
par un contrôle, 0 écran sur 34 ouvert par un test.

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
