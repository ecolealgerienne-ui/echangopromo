# Méthode de test — stack Echango

Comment on éprouve un produit Echango : backend Node/NestJS propriétaire d'une
base SQL, application Flutter unique à plusieurs personas, développement en
WSL avec émulateur côté Windows.

Extrait de la pratique réelle d'`echango-delivery` (26 bancs de scénarios,
3 fichiers de parcours écran, 6 vérificateurs statiques), généralisé pour être
appliqué aux autres produits de la suite. Première instanciation :
`echangopromo`.

---

## Ce que ce document est, et ce qu'il n'est pas

**Ce n'est pas une liste de bonnes pratiques.** Chaque section décrit un **mode
de défaillance** — un symptôme reconnaissable dans votre propre projet, la
raison pour laquelle il échappe à la relecture, et le remède. La forme est
délibérée : une prescription (« écrivez des tests ») ne se reconnaît pas dans un
cas nouveau, un mode de défaillance oui.

**Ce n'est pas un plan de couverture.** Il ne dit pas « testez tout ». Il dit
par quoi commencer quand on part de rien, et quel artefact rend visible ce qui
n'est **pas** couvert.

**Ce n'est pas transposable tel quel hors de cette stack.** Les squelettes
supposent NestJS + `class-validator` côté serveur et Flutter côté app. Les modes
de défaillance, eux, se transposent ; les commandes non.

---

## Lexique

Ces mots reviennent partout. Les fixer évite que deux personnes appellent
« test » deux choses différentes.

| Terme | Sens précis |
|---|---|
| **Banc** | Un scénario métier complet joué en HTTP contre le serveur réel et sa base réelle. Ni test unitaire, ni test d'intégration au sens framework : un enchaînement d'appels qui reproduit une situation qu'un utilisateur peut produire. |
| **Décor** | L'état posé **avant** un test et qu'il ne peut pas poser lui-même (comptes activés, données de référence, ressources à consommer). Il ne vérifie rien. Le séparer est une règle, pas un confort — voir M8. |
| **Témoin** | Le cas symétrique qui doit **réussir** quand le cas testé doit échouer, et inversement. Sans témoin, un banc qui refuse tout passe au vert. |
| **Mutation** | Un fichier réel volontairement cassé, sur lequel on fait tourner un contrôle pour vérifier qu'il **refuse**. Différent d'un cas fabriqué : la mutation porte sur le vrai fichier, avec sa vraie structure. |
| **Auto-test** (`--self-test`) | La batterie interne d'un vérificateur, comportant autant de cas qui doivent échouer que de cas qui doivent passer. Bloquante : elle tourne avant le contrôle réel. |
| **Frontière** | La surface HTTP exposée : l'ensemble des routes, leur exigence d'authentification, de rôle, et d'appartenance. |
| **Projection** | Ce que le serveur consent à servir à un persona donné pour une ressource donnée. Deux personas peuvent lire la même commande et n'en voir pas les mêmes champs. |
| **Persona** | Un rôle applicatif avec son propre parcours et sa propre projection (client, commerçant, agent, admin…). |

---

## Le principe fondateur

> **Une donnée mal câblée ne casse presque jamais — elle disparaît.**

Et une disparition n'a pas de trace : pas d'exception, pas de pile d'appels,
rien à lire dans les journaux. Le serveur répond **HTTP 200** avec une liste
vide, un champ absent, un montant à zéro.

C'est pour cette raison que la méthode repose sur des bancs qui **comparent à un
témoin** plutôt que sur des tests qui vérifient qu'on n'a pas planté. « Ça n'a
pas levé » n'est pas un résultat.

Corollaire, qui gouverne tout le reste :

> **Un contrôle au vert n'a montré qu'une chose : sa capacité à dire oui.**

Tant qu'on ne l'a pas vu refuser, on ne sait pas s'il regarde.

---

## Les quatre étages

Chacun voit quelque chose que les trois autres ne peuvent pas voir. Aucun ne
remplace un autre.

| Étage | Outil | Ce qu'il voit | Ce qu'il ne peut pas voir |
|---|---|---|---|
| **1. Vérificateurs statiques** | scripts autonomes lisant deux fichiers et les comparant | les désynchronisations silencieuses entre serveur et app (codes d'erreur, bornes, listes fermées) | tout ce qui dépend de l'exécution |
| **2. Tests unitaires** | jest côté serveur, `flutter test` côté app | la logique pure : calculs, prédicats, formatage | tout ce qui dépend de la base, du réseau ou de l'écran |
| **3. Bancs HTTP** | shell/python + `curl` contre le serveur réel | les règles métier de bout en bout, les refus d'accès, les courses de concurrence | **l'application** : un écran peut être absent, muet ou planter à l'ouverture sans qu'un banc passe au rouge |
| **4. Parcours écran** | `flutter drive` sur émulateur, app réelle + serveur réel | ce qu'un utilisateur **voit** et peut **faire** : une valeur affichée, deux messages distincts, un aller-retour serveur | les cas de bord non atteignables à l'écran, la concurrence, la charge |

**Le piège classique** est de croire que l'étage 3 couvre l'étage 4. Il ne le
couvre pas : dans `echango-delivery`, deux formulaires d'inscription ont été
livrés, compilés, analysés — et **jamais ouverts**. Aucun banc n'était rouge.

**Le piège inverse** est de croire que l'étage 4 couvre l'étage 3. Un parcours
écran ne peut faire que ce qu'un utilisateur peut faire : il ne peut pas
appeler une route avec le jeton d'autrui, ni lancer deux acceptations
simultanées.

---

## Les modes de défaillance

Le cœur du document. Chaque mode : le **symptôme**, pourquoi il **échappe à la
relecture**, le **remède**, et comment savoir que le remède marche.

### M1 — Le contrôle qui n'a jamais dit non

**Symptôme.** Un vérificateur, un banc ou un test est au vert depuis sa
création. Personne ne l'a jamais vu refuser quoi que ce soit.

**Pourquoi ça échappe.** Un contrôle qui ne regarde pas la bonne chose est au
vert exactement comme un contrôle qui regarde la bonne chose. Les deux sont
indiscernables tant qu'on ne leur soumet pas un cas qui doit échouer. Relire le
contrôle ne suffit pas : les erreurs de ce type ne se voient pas à la lecture —
une ancre de regex trop laxiste, un champ dont la déclaration n'est pas
reconnue, un décimal lu comme un entier.

**Remède.** Deux niveaux, cumulatifs :

1. Un **`--self-test`** intégré, avec autant de cas qui doivent échouer que de
   cas qui doivent passer, exécuté **avant** le contrôle réel et **bloquant**.
2. Une **mutation du vrai fichier** : casser volontairement le fichier réel et
   vérifier que le contrôle refuse. C'est elle qui attrape ce que les cas
   fabriqués laissent passer, parce qu'elle porte la vraie structure.

**Comment savoir que ça marche.** Le compte des cas de refus est affiché :
« auto-test : 14 cas, dont 9 refus ». Un auto-test sans cas de refus n'est pas
un auto-test.

### M2 — Le test qui recopie ce qu'il vérifie

**Symptôme.** Un test contient sa propre version de la règle qu'il éprouve —
souvent pour contourner une dépendance lourde (base, client généré, framework).

**Pourquoi ça échappe.** Le test et le code sont d'accord **au moment où on
l'écrit**. Ils divergent ensuite en silence : le test reste vert pendant que le
code réel dérive. Deux copies d'accord ne prouvent rien.

**Remède.** Un test **importe** ce que le code exécute, ou il ne sert à rien. Si
la dépendance rend l'import impossible, c'est la dépendance qu'il faut isoler
(extraire le prédicat pur dans un module sans dépendance), pas la règle qu'il
faut recopier.

**Variante à connaître.** Une vérification qui partage un composant avec ce
qu'elle vérifie ne dit rien de ce composant : l'erreur s'annule elle-même.

### M3 — Le repli qui rassure

**Symptôme.** Une valeur par défaut là où la donnée peut manquer : `|| 0`,
`?? false`, `catchError(() => [])`, une chaîne vide, un identifiant technique
affiché faute de mieux.

**Pourquoi ça échappe.** Le repli **détruit l'information d'absence** — et
l'absence est presque toujours l'information qui compte. Un conducteur dont
l'état est inconnu passe pour hors ligne ; des coordonnées manquantes valant
`0` désignent un point au large du golfe de Guinée ; une liste vidée par une
erreur réseau s'affiche « aucun résultat », c'est-à-dire une **affirmation
fausse** présentée avec l'aplomb d'un fait.

**Remède.** Le critère : *si cette valeur est fausse, est-ce que quelque chose
le dira ?* Si non, il ne faut pas de valeur — `null`, et deux messages distincts
pour « vide » et « illisible ».

**⚠️ Le pire endroit pour un repli est un test.** Il y produit exactement ce
qu'on redoute : un contrôle qui rassure. Un script de décor qui annonce
« ✅ compte créé » sans l'avoir obtenu fait échouer trois étapes plus loin, en
accusant la mauvaise.

### M4 — La capacité servie et jamais appelée

**Symptôme.** Une route existe, est testée, est documentée — et aucun écran ne
l'appelle. Ou l'inverse : un champ servi par le serveur et jamais lu par l'app.

**Pourquoi ça échappe.** Ça ne produit **aucune erreur**. Ça produit une
fonctionnalité absente que personne ne cherche, puisque le code existe. C'est le
défaut le plus répété observé sur `echango-delivery`, et de loin.

**Remède.** Trois règles :

- Une route neuve n'est pas finie tant qu'un écran ne l'appelle pas.
- Une réponse serveur se lit **en entier** : un champ servi et non lu est soit un
  manque côté app, soit un champ à retirer du serveur — jamais « pas grave ».
- Réciproquement, ce qui n'a plus d'appelant se supprime.

**Comment savoir que ça marche.** C'est l'étage 4 qui l'attrape, et lui seul :
un parcours écran qui n'atteint jamais une capacité prouve qu'elle est
inatteignable.

### M5 — Les deux copies d'accord entre elles

**Symptôme.** Un commentaire dit « doit rester identique à X », « le pendant
exact de X », « même règle que X ».

**Pourquoi ça échappe.** La phrase est l'aveu que **rien ne tient l'invariant à
notre place**, et un commentaire ne peut pas échouer. Pire : on vérifie que les
deux copies s'accordent entre elles, jamais qu'elles ont raison. Deux copies
d'accord peuvent être fausses ensemble.

**Le critère**, parce qu'il ne s'agit pas de tout fusionner : la question n'est
pas *« ces deux bouts se ressemblent-ils »* mais **« si l'un change, l'autre
doit-il changer ? »**

- **Oui ⇒ un seul endroit.**
- **Non ⇒ deux endroits, et un commentaire qui dit pourquoi.**
- **Quand la fusion coûte plus qu'elle ne rapporte ⇒ un contrôle exécuté**, pas
  une phrase. C'est l'étage 1.

**Cas typiques dans cette stack.** Registre de codes d'erreur serveur ↔ tables
de traduction app (une par langue) ; bornes de validation (`@MinLength`, `@Min`,
`@Max`) ↔ constantes de formulaire ; listes fermées (`@IsIn`) ↔ options
proposées à l'écran ; enums serveur ↔ enums Dart miroirs.

### M6 — Le test lié à la langue

**Symptôme.** Un test d'écran cherche un widget par son **libellé**.

**Pourquoi ça échappe.** Il passe au vert sur la machine de son auteur et
échoue sur un appareil configuré dans une autre langue, **pour une raison sans
rapport avec le défaut**. Le diagnostic coûte alors plus cher que le test ne
rapporte. Sur un produit multilingue (FR/EN/AR), c'est garanti.

**Remède.** Désigner les widgets par ce qu'ils **sont**, jamais par ce qu'ils
**disent** :

- leur **icône** (`find.byIcon`) — indépendante de la langue ;
- leur **type** (`find.byType`) ;
- leur **rang** dans une barre d'onglets ;
- une **donnée que le décor a posée** (un prix, un nom propre).

**L'exception, et sa condition.** Quand la distinction testée **est** une
différence de texte (deux messages qui doivent différer), on calcule les deux
attendus **par le traducteur de l'application, pour sa locale courante**. Le
test tient alors dans toutes les langues. Le défaut visé par la règle est un
littéral figé dans une langue, pas une lecture du traducteur.

### M7 — La liste virtuelle

**Symptôme.** Un test d'écran ne trouve pas une ligne dont on sait que le
serveur la sert.

**Pourquoi ça échappe.** `ListView.builder` **ne construit que ce qui est à
l'écran**. Une ligne plus bas dans la liste n'existe pas dans l'arbre de
widgets, donc elle est invisible à `find` — et le test conclut que le décor ne
l'a pas publiée. Le diagnostic part alors dans la mauvaise direction (« le
serveur ne sert rien ») et peut coûter plusieurs tours.

**Remède.**

1. **Attendre la liste, jamais la ligne cherchée.** On attend qu'une ligne —
   n'importe laquelle — soit rendue : c'est la preuve que le chargement a
   abouti. Puis on défile.
2. **Défiler depuis une coordonnée d'écran**, pas depuis un `Scrollable` désigné
   par son type : un `TabBarView` en expose plusieurs et rien ne distingue celui
   qui est visible de celui qui dort à côté.
3. **`hitTestable()`** pour ne désigner que ce qui est réellement frappable —
   les onglets non visibles sont construits mais pas frappables.

### M8 — Le décor mêlé au test

**Symptôme.** Un test commence par créer ses comptes, ses données de référence,
ses ressources — ou pire, dépend de l'état laissé par le test précédent.

**Pourquoi ça échappe.** Deux tests qui se passent un état **échouent
ensemble**, et le second accuse le premier. Le diagnostic devient un travail
d'archéologie. Et un test qui échoue en route laisse un décor à moitié posé, qui
fait échouer le suivant pour une troisième raison.

**Remède.** Un **script de décor séparé**, qui ne vérifie rien, et dont c'est le
seul travail. Il pose ce que le test **ne peut pas poser lui-même** :

- ce qui demande un rôle d'administration (activer un compte en attente) ;
- ce qui serait fragile à piloter à l'écran (choisir un point sur une carte) ;
- les ressources que le parcours va consommer.

Le décor **imprime la commande de test** avec ses paramètres — c'est lui qui sait
quels identifiants il a posés.

**⚠️ Il doit être idempotent, et pour une raison de plafond.** Les identifiants
sont **stables**, jamais aléatoires : les endpoints d'inscription et de connexion
sont rate-limités, et un décor à identifiants aléatoires devient inutilisable
au second passage de la journée.

### M9 — Le plafond pris pour un bug métier

**Symptôme.** Une suite qui passait échoue soudainement, et le message d'erreur
parle de mot de passe, de compte introuvable, ou de refus générique.

**Pourquoi ça échappe.** Le rate-limiting sort déguisé. Un plafond de connexion
atteint peut se présenter comme « identifiants incorrects » — ce qui envoie
chercher un bug d'authentification, voire supprimer des lignes en base, pour un
problème qui se résout en attendant soixante secondes.

**Remède.**

- **Temporiser entre bancs**, par défaut et non en option, à une cadence
  déduite du plafond réel (`PACE=65` pour 5 connexions/minute).
- **Nommer le plafond dans le tableau final** : détecter `429` /
  `ThrottlerException` dans le journal du banc et l'annoter
  « throttle — rejouer dans une heure » au lieu de le compter comme un échec
  métier.
- **Documenter le budget** : « la suite consomme 8 inscriptions sur les 10 par
  heure » est une information de premier ordre pour qui la rejoue.

### M10 — Le pipe qui masque le code de sortie

**Symptôme.** Une commande de vérification affiche toujours « code 0 ».

**Pourquoi ça échappe.** `commande | tail -20 && echo "code $?"` relève le code
de `tail`, jamais celui de `commande`. Le faux vert est parfaitement crédible.

**Remède.** Écrire dans un fichier puis relever `$?`, ou lire
`${PIPESTATUS[0]}`. Et se méfier de toute vérification dont on n'a jamais vu le
code de sortie non nul (c'est M1 appliqué au shell).

**Cousin à connaître.** Une vérification qui échoue sur le **fichier de
configuration** plutôt que sur un fichier source est la signature d'un outil qui
n'est pas celui du projet — typiquement `npx` qui va chercher la dernière
version publiée parce que les dépendances ne sont pas installées.

### M11 — La cible prise dans la donnée examinée

**Symptôme.** Un banc qui énumère ses cibles depuis la même source que celle
qu'il contrôle.

**Pourquoi ça échappe.** C'est subtil et ça a réellement passé une mutation :
un banc de refus d'accès qui énumérait les routes protégées **depuis les
décorateurs de protection**. Ouvrir une route la faisait quitter l'ensemble
testé — le total tombait, et **rien ne passait au rouge**. Le banc contrôlait
fidèlement un ensemble qui rétrécissait.

**Remède.** L'ensemble contrôlé est énuméré depuis une source **indépendante**
de ce qu'on contrôle (toutes les routes, quelle que soit leur protection), et
les exceptions sont **épinglées explicitement** — chaque route publique est une
décision qui doit s'écrire, avec sa justification.

**Et le corollaire.** Un total sans sa décomposition ne se vérifie pas.
« 66 routes protégées » ne veut rien dire sans « sur 74, dont 8 publiques
épinglées ».

---

## L'ordre d'adoption

Ne pas commencer par le plus impressionnant. L'ordre ci-dessous est classé par
**rapport valeur / coût de mise en route**, et chaque étape a un critère de
sortie.

### Étape 1 — Le banc de refus de la frontière (étage 3)

**Pourquoi en premier.** Il est **automatique** : il énumère les routes depuis
la source et n'a donc presque rien à écrire par route. Il trouve des failles
réelles (IDOR, route oubliée sans garde) et sa valeur ne dépend pas de la
maturité du reste.

**Ce qu'il fait.** Chaque route protégée est appelée sans jeton, avec le jeton
d'un **autre rôle**, et avec un jeton **révoqué**. Les trois doivent être
refusés — avec le bon statut **et** le bon code, parce qu'un refus sans code est
un refus que l'application ne sait pas traduire.

**Puis, second banc :** l'appartenance. Le jeton est valide, mais la ressource
nommée est celle de quelqu'un d'autre. Le pire cas attendu est
« introuvable », jamais « la ressource d'autrui ».

> **Authentifier n'est pas autoriser.** Le garde prouve *qui* vous êtes ; il ne
> prouve pas que la ressource que vous nommez est à vous. Cette seconde
> vérification vit dans chaque service, donc dans des dizaines d'endroits,
> chacun reposant sur le fait que son auteur y a pensé.

**⚠️ Repérer d'abord la polarité de protection du projet — elle change tout.**

| Polarité | Mécanique | La route qu'on oublie est… |
|---|---|---|
| **Garde global** | un `APP_GUARD` d'authentification, et `@Public()` pour se retirer | **fermée** — l'oubli se voit à l'écran |
| **Garde par route** | un `@UseGuards(...)` sur chaque contrôleur ou méthode | **OUVERTE** — l'oubli ne se voit nulle part : ni à la compilation, ni à l'exécution, ni dans les journaux |

La seconde polarité est celle d'`echangopromo` (mesuré au 04/08/2026 : 62 routes,
seul `ThrottlerGuard` est global). Elle n'est pas fautive en soi, mais elle
**déplace la charge de la preuve** : c'est alors le banc, et lui seul, qui peut
dire qu'aucun garde ne manque.

**Conséquence concrète pour le banc** : en polarité « par route », il ne suffit
pas de sonder les routes protégées — il faut **énumérer celles qui ne le sont
pas** et exiger que chacune figure dans la liste épinglée. Une route sans garde
et non épinglée est une régression, pas une donnée d'entrée.

**⚠️ Et un piège de lecture, trouvé en éprouvant le squelette sur du vrai code.**
L'ordre habituel en NestJS place les décorateurs de classe ainsi :

```ts
@UseGuards(JwtAuthGuard, RolesGuard)   // ← le garde
@Roles('admin')
@Controller('admin/highlight')         // ← le préfixe
export class AdminHighlightController {
```

Un analyseur qui part du `@Controller` pour chercher le garde **ne le voit
pas** : il est trois lignes plus haut. Première version du squelette : six
routes d'administration annoncées « ouvertes » alors qu'elles étaient gardées.
Le défaut n'a pas été trouvé en relisant l'analyseur — il a été trouvé en le
faisant tourner sur le dépôt réel. C'est le mode M1 dans les deux sens : un
contrôle peut aussi mentir en disant **non**, et un faux positif qui accuse à
tort se paie en confiance perdue.

**Critère de sortie.** Le banc a été **prouvé par mutation du vrai code** :
ouvrir une route la fait passer au rouge. Et le registre de couverture nomme
les routes non couvertes avec la raison.

**Squelette.** `docs/methode-test/banc-refus-http.py`

### Étape 2 — Les vérificateurs de synchronisation (étage 1)

**Pourquoi ensuite.** Statiques, instantanés, sans infrastructure. Ils attrapent
une classe de défauts **totalement silencieuse** : rien ne compile en rouge,
rien ne lève, l'utilisateur voit juste le mauvais texte ou un refus
incompréhensible.

**Ce qu'ils comparent, dans cette stack :**

| Vérificateur | Source A | Source B |
|---|---|---|
| codes d'erreur | l'enum serveur | les tables de traduction app, **une par langue** |
| bornes | `@MinLength`/`@Min`/`@Max` des DTO | les constantes de formulaire côté app |
| listes fermées | `@IsIn(...)` serveur | les options proposées à l'écran |
| enums miroirs | l'enum TypeScript | l'enum Dart |

Les trois ensembles de clés doivent être **strictement identiques**, doublons
compris. Un code en trop côté app est refusé en 400 par le serveur ; un code
manquant n'est jamais proposé. Les deux sont des pannes silencieuses.

**Critère de sortie.** Chaque vérificateur a son `--self-test` bloquant avec des
cas de refus, **et** a été éprouvé sur une mutation du vrai fichier.

**Squelette.** `docs/methode-test/check-sync.dart`

### Étape 3 — Le décor + un seul parcours écran (étages 8 → 4)

**Pourquoi maintenant.** C'est ici qu'on découvre les écrans jamais ouverts. Un
seul parcours suffit à installer toute la mécanique : décor, harness, commande
de lancement.

**Choisir le premier parcours** sur ce critère : *quelle valeur affichée
tromperait le plus si elle était fausse ?* Un montant, un solde, un statut qui
engage. Pas un écran de réglages.

**Critère de sortie.** `flutter drive` tourne de bout en bout depuis une machine
neuve, en suivant uniquement ce qu'imprime le script de décor.

**Squelettes.** `docs/methode-test/provision-decor.sh` et
`docs/methode-test/harness.dart`

### Étape 4 — Les bancs métier, un par règle qui a déjà cassé (étage 3)

**Pourquoi en dernier.** C'est le plus coûteux à écrire et le plus spécifique.
Et surtout : on sait maintenant lesquels écrire.

**Le critère de sélection** est le seul qui compte : **une règle qui a déjà
produit un défaut**. Pas « couvrons le module X ». Chaque banc porte en tête ce
qu'il éprouve et **le défaut réel qui l'a fait naître** — c'est cette phrase qui
permettra à quelqu'un d'autre de reconnaître un cas de la même famille.

**Puis l'orchestrateur**, quand il y en a plus de trois.

**Critère de sortie.** L'orchestrateur rend un tableau lisible, et l'ordre des
bancs est justifié en commentaire à côté de chaque entrée.

**Squelette.** `docs/methode-test/run-all-scenarios.sh`

---

## Le registre de couverture

L'artefact le plus sous-estimé de la méthode : **un document qui dit ce qui
n'est pas couvert, et pourquoi.**

Sans lui, l'absence de test et la décision de ne pas tester sont indiscernables.
Avec lui, la question « est-ce qu'on couvre ça ? » a une réponse en dix
secondes.

Forme minimale — une section par famille, avec sa décomposition complète :

```
Routes à identifiant : 32
  couvertes par test-appartenance ......... 25
  exclues (l'appartenance n'y est pas la question) ... 5
      /health, /auth/login, ... — raison épinglée
  NON couvertes ........................... 2
      lecture des preuves — demande un décor photographique
```

**Deux règles :**

- **Un total sans sa décomposition ne se vérifie pas.** « 25 routes couvertes »
  se prouve, « bonne couverture » non.
- **Ce qui est exclu est épinglé nommément**, avec la raison. Une exclusion
  anonyme est indiscernable d'un oubli.

---

## Les squelettes fournis

Dans `docs/methode-test/`. Ce sont des **patrons à instancier**, pas des scripts
prêts à tourner sur ce projet — chacun porte des marqueurs `À ADAPTER`.

| Fichier | Étage | Ce qu'il donne |
|---|---|---|
| `banc-refus-http.py` | 3 | énumération des routes depuis la source NestJS, trois sondes de refus par route, `--self-test` avec cas de refus, `--list` |
| `check-sync.dart` | 1 | comparaison de deux fichiers hétérogènes (TS ↔ Dart), `--self-test`, mode mutation |
| `provision-decor.sh` | — | décor idempotent à identifiants stables, qui imprime la commande de test |
| `harness.dart` | 4 | désignation sans libellé, `pumpUntil`, `scrollUntilFound`, `resetDevice`, identifiants sans valeur par défaut |
| `run-all-scenarios.sh` | 3 | orchestrateur sans `set -e`, temporisation, détection du throttle, tableau final |

**Comment les instancier.** Copier dans `scripts/` ou `tool/` du projet cible,
puis traiter chaque `À ADAPTER`. Ne pas les laisser dans `docs/` : un squelette
qu'on modifie sur place cesse d'être un squelette.

---

## Ce que cette méthode ne couvre pas

Par honnêteté, et parce que taire ces limites ferait croire à une couverture qui
n'existe pas. Ce sont des **questions ouvertes**, pas des recommandations.

**L'intégration continue.** La pratique observée est entièrement **manuelle** :
l'orchestrateur existe précisément parce que « personne ne les rejoue tous ».
Aucun de ces étages ne tourne sur un serveur d'intégration. C'est le manque le
plus visible, et le plus facile à combler pour les étages 1 et 2 (statiques,
sans infrastructure).

**La rejouabilité.** Une suite qui consomme 8 inscriptions sur un plafond de 10
par heure n'est pas rejouable deux fois de suite. C'est subi, pas choisi — et
ça interdit de fait l'exécution automatique fréquente.

**Aucune commande « tout est vert ».** L'orchestrateur exclut délibérément
l'analyse statique, les tests unitaires et les vérificateurs. Il n'existe pas de
point d'entrée unique qui dise si le projet va bien.

**Aucune réinitialisation.** Les bancs tournent contre une base vivante qu'ils
salissent. Le ménage est fait à la main dans chaque banc, en best-effort — un
banc qui échoue en route laisse son décor derrière lui.

**La charge et les performances** ne sont couvertes par aucun étage.

**Les tests unitaires (étage 2) sont le parent pauvre** de cette méthode. Elle
privilégie les bancs de bout en bout parce que c'est là que se trouvaient les
défauts réels ; ce n'est pas un argument contre les tests unitaires, c'est une
observation sur un projet donné.

---

## Résumé en une page

1. **Une donnée mal câblée disparaît, elle ne casse pas.** Comparer à un témoin,
   pas vérifier qu'on n'a pas planté.
2. **Un contrôle au vert n'a montré que sa capacité à dire oui.** `--self-test`
   bloquant + mutation du vrai fichier.
3. **Quatre étages, aucun ne remplace un autre.** Vérificateurs, unitaires,
   bancs HTTP, parcours écran.
4. **Le décor n'est pas le test.** Script séparé, idempotent, identifiants
   stables, qui imprime la commande.
5. **Rien n'est cherché par son libellé** dans un parcours écran.
6. **Commencer par le banc de refus** : automatique, et il trouve des failles
   réelles.
7. **Ce qui n'est pas couvert doit être écrit**, avec sa décomposition et ses
   exclusions épinglées.
