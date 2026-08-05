# CLAUDE.md — echango Promo

Instructions pour Claude Code sur ce dépôt. Lire aussi `docs/SPECS_ECHANGO_PROMO_V0.md`
(specs fonctionnelles), `docs/ARCHITECTURE.md` (choix de stack),
`docs/AUDIT_V0.md` (audit initial complet, fichier:ligne),
`docs/AUDIT_V1.md` (audit de suivi — révocation JWT, codes d'erreur),
`docs/AUDIT_PERFORMANCE_V0.md` (audit optimisation — vignettes/CDN,
timeouts mobile, compression backend) et
`docs/BENCHMARK_CONCURRENTIEL.md` (comparatif fonctionnel face à 7
applications de promos locales dans le monde) —
ce fichier-ci en est la synthèse actionnable.

## Consignes de fonctionnement (utilisateur)

- **Optimiser l'usage des tokens** : éviter les tâches/vérifications
  inutiles (builds, greps de relecture, allers-retours de confirmation
  superflus), rester concis dans les réponses.
- ~~**Ne jamais lancer les tests/builds/l'app** dans cet environnement.~~
  ⚠️ **Faux depuis le 2026-08-04.** Le backend démarre, les migrations
  tournent, `flutter analyze` et un build Android aboutissent, l'app tourne
  sur émulateur, et cinq bancs de test s'exécutent — le tout depuis cette
  session. La consigne d'origine décrivait un environnement qui n'existe
  plus ; la garder ferait refuser un travail désormais possible.
  **Un état périmé est pire qu'aucun état : il fait conclure.**
- **Ce qui reste vrai** : ne pas lancer un build long ou une suite complète
  sans raison — les plafonds de requêtes (voir § Environnement) rendent les
  rejeux coûteux, et un banc lancé au mauvais moment rend un 429 déguisé en
  échec métier.

## Projet en un coup d'œil

Backend NestJS + TypeORM + PostgreSQL (`apps/backend`), app mobile Flutter
multi-rôles Client/Commerçant/Agent/Admin (`apps/mobile`). Pilote V0 sur un
quartier de Djelfa. UI admin ajoutée le 2026-07-09 (modération, registre,
agents) — pas d'entrée dans le menu public "espace pro" (accès direct par
URL `/admin`, décision produit : ne pas la rendre découvrable depuis l'app
grand public). Le concept de Zone opérationnelle (découpage interne dédié
aux tournées d'agent) a été abandonné le 2026-07-09 : un agent est
désormais rattaché directement à zéro, une ou plusieurs `Commune`
(relation many-to-many), "assigner toute la wilaya" n'étant qu'une
commodité d'UI qui sélectionne en masse les communes de cette wilaya —
un agent par commune n'étant pas soutenable et le rôle agent lui-même
étant amené à disparaître à l'extension multi-wilaya.

```
apps/backend/src/{commune,agent,admin,commercant,promo,report,audit-log,storage,auth}
apps/mobile/lib/{app,data,domain,providers,features/{client,commercant,agent,admin,shared}}
```

Commandes utiles :
- Backend : `cd apps/backend && npm run start:dev` / `build` / `lint` /
  `seed:admin -- <email> <password> <nom>` / `seed:communes` /
  `migration:run` / `migration:generate -- src/migrations/<Nom>` /
  `migration:revert`. Schéma géré uniquement par migrations
  (`synchronize: false` toujours, plus de bascule sur `NODE_ENV`) —
  lancer `npm run migration:run` avant le premier `start:dev` sur une
  base neuve, et avant les scripts seed.
- Mobile : `cd apps/mobile && flutter pub get && flutter analyze && flutter test`.
  ⚠️ **Le paragraphe qui suivait ici est faux depuis le 2026-08-04.** Il
  affirmait que le SDK Flutter n'avait jamais pu être installé et que le code
  mobile n'avait **jamais été compilé**. Flutter 3.35.7 compile désormais,
  `flutter analyze` rend **0 problème** et `flutter test` **14 tests verts**.
  Le « proxy bloquant » était en réalité l'analyse HTTPS d'un antivirus (voir
  § Environnement).
- Vérificateurs de synchronisation : `cd apps/mobile && dart run tool/check_all.dart`
  — statiques, instantanés, sans base ni émulateur. Le seul lot qui peut
  tourner à chaque commit.
- Bancs de test : `./scripts/provision-decor.sh` puis les `./scripts/test-*.sh`.
  Détail, verdicts et ordre de reprise dans `docs/status_v0.1.md`.

### ⚠️ Vérifier le formatage sans le réécrire

**`npm run lint` porte `--fix`** : la commande **modifie** le dépôt au lieu de
le juger. Elle a réécrit 46 fichiers le 2026-08-05, et c'était déjà elle
l'origine des « 18 fichiers Prettier » trouvés modifiés dans le clone WSL la
veille — écartés sans qu'on en comprenne la cause. Un outil de vérification qui
fabrique le diff qu'il devrait signaler ne peut pas servir de barrière.

Pour **constater** sans écrire, les deux commandes à utiliser :

```bash
cd apps/backend && npx eslint 'src/**/*.ts'                    # sans --fix
cd apps/mobile  && dart format --output=none --set-exit-if-changed lib test tool
```

Les deux sortent à **0** depuis le 2026-08-05, le dépôt ayant été formaté une
fois pour toutes (46 fichiers côté backend, 104 côté mobile). Elles peuvent donc
servir de garde : toute sortie non nulle signale une dérive, pas un état de
départ.

⚠️ **`dart format` est un formateur pur ; `eslint --fix` ne l'est pas.** Le
second applique aussi des règles de lint et peut **changer le code** — il a
retiré une assertion de type le 2026-08-05, laissant le commentaire qui la
justifiait décrire un code disparu. Relire son diff, pas seulement celui de
`dart format`.

⚠️ **Reformater peut réveiller un lint endormi.** `dart format` replie les
lignes longues, et `curly_braces_in_flow_control_structures` **tolère**
`if (cond) instruction;` sur une seule ligne mais **l'interdit** sur deux : le
reformatage a fait apparaître 9 avertissements d'un coup. Ce ne sont pas des
régressions — la forme sans accolades était simplement invisible tant qu'elle
tenait sur une ligne.

---

## Règles à respecter systématiquement

Issues d'un audit à 6 volets (fonctionnel, architecture, sécurité, qualité
de code, vérifiabilité mobile, performance) mené sur la V0. Chaque règle
référence le problème concret qui l'a fait remonter — pas une bonne
pratique générique, un bug ou une faille réellement trouvés dans ce repo.

### Sécurité — priorité la plus haute

1. **Le rôle JWT ne suffit jamais pour une action sur la ressource d'un
   tiers.** Tout endpoint agent/admin qui prend un `:id` de ressource
   appartenant à un commerçant (promo, fiche) doit vérifier explicitement
   la zone/l'appartenance avant d'agir. *Trouvé : un agent authentifié
   pouvait modifier/créer des promos pour n'importe quel commerçant, hors
   de sa zone (`PromoController.update`, `.createByAgent`,
   `AgentController.initiateClaim`) — IDOR critique. Une méthode
   `assertOwnedBy` existait déjà dans le code mais n'était appelée nulle
   part.* Écrire la vérification ET la brancher dans le même commit — ne
   jamais laisser une méthode de garde orpheline.

2. **Tout endpoint d'authentification (login PIN, login mot de passe,
   vérification OTP) doit être rate-limité dès sa création.** *Trouvé :
   `@nestjs/throttler` n'était même pas installé — un PIN à 4-6 chiffres
   et un OTP à 6 chiffres étaient brute-forçables en ligne sans aucune
   limite de tentatives.* Ajouter le throttling dans le même commit que
   l'endpoint, pas après coup.

3. **Tout flux OTP a besoin d'un compteur de tentatives ET d'un cooldown
   d'envoi**, indépendants de l'expiration du code — sinon un attaquant
   dispose de toute la fenêtre de validité pour brute-forcer, et peut
   spammer un numéro tiers en boucle.

4. **Ne jamais retourner une entité TypeORM via un spread (`{...entity,
   extra}`).** Ça transforme l'instance en objet plain et désactive
   silencieusement les `@Exclude()` du `ClassSerializerInterceptor`.
   *Trouvé : `{...promo, photoUrl}` exposait `photoKey`, qui contient
   l'UUID de l'agent (pas du commerçant) pour les promos créées par un
   agent.* Retourner l'instance de classe, ou une DTO de sortie dédiée.

5. **Tout upload via URL S3 pré-signée doit limiter la taille**
   (`Content-Length-Range` sur la policy) et idéalement vérifier le
   contenu réel a posteriori — un `Content-Type` déclaré au moment de la
   signature n'engage à rien lors du PUT réel.

6. **Un JWT de plus de 24h doit prévoir une révocation dès la
   conception** (tokenVersion en base, refresh token) si le rôle a des
   droits d'écriture larges (agent/admin) — sinon un token volé reste
   exploitable jusqu'à expiration, sans recours.

7. **Un endpoint public protégé uniquement par un identifiant déclaratif
   fourni par le client** (ex. header `X-Device-Id`, jamais vérifié
   serveur) **doit être rate-limité par IP.** *Trouvé : `POST /report`
   était trivialement exploitable pour faire masquer la promo d'un
   concurrent avec 3 requêtes changeant juste ce header.*

### Architecture & modèle de données

8. **Ne jamais combiner cycle de vie et statut de modération dans un seul
   enum.** *Trouvé : `Promo.status` (ACTIVE/EXPIREE mélangés à
   SIGNALEE/MASQUEE/VERIFIEE_OK) a produit deux bugs indépendants (un
   dashboard qui surcompte les promos actives, un statut de tournée agent
   faux) simplement parce que deux services ont dû répliquer séparément la
   règle "qu'est-ce qui est visible".* Deux champs orthogonaux
   (lifecycle / moderation) rendent chaque requête auto-descriptive.

9. **Quand un module accède à l'entité d'un autre module en direct**
   (`TypeOrmModule.forFeature`) **pour casser un cycle NestJS plutôt que
   d'importer son module, documenter ce choix en commentaire** à
   l'endroit de l'import, et pousser toute règle métier partagée (filtres
   de statut, calculs dérivés) dans le service propriétaire plutôt que de
   la réécrire localement.

10. **Toute méthode d'autorisation écrite mais jamais appelée est un
    signal d'alarme, pas un détail.** Avant de considérer une route
    "protégée" terminée, vérifier que chaque garde nécessaire est
    réellement branchée — pas seulement définie.

11. **Un module créé "pour suivre les specs" doit être branché dans le
    même commit que les actions qu'il est censé couvrir, ou ne pas être
    committé du tout.** *Trouvé : `AuditLogModule` existait, bien conçu,
    depuis le premier commit du backend — et n'a jamais tracé une seule
    action, alors que les transferts de zone et la modération (exactement
    ce qu'il devait couvrir) fonctionnaient déjà.* Un module non-branché
    donne une fausse impression de couverture, pire qu'une absence
    déclarée.

12. **PostgreSQL n'indexe jamais automatiquement une colonne `@ManyToOne`**
    (contrairement à l'intuition venue de MySQL/InnoDB). Ajouter un
    `@Index()` explicite dès qu'une clé étrangère sert de filtre ou de
    jointure fréquente, pas seulement de contrainte référentielle.
    **Et un `@Index()` d'entité ne crée rien par lui-même :** `synchronize`
    est coupé (schéma tenu par les seules migrations versionnées, voir
    `data-source.ts`), donc un décorateur non repris dans une migration
    `CREATE INDEX` est un commentaire, pas un index — la base tourne sans lui
    et le prochain `migration:generate` l'émettra dans une migration qu'on
    croira additive. Toute pose d'`@Index()` doit s'accompagner de sa
    migration ; vérifier l'écart entité↔base plutôt que de faire confiance au
    décorateur. *Trouvé : `Notification` déclare des `@Index()` sur
    `recipientId` et `promoId` que `1783680000000-CreateNotificationEntity`
    ne crée pas (seul l'index composite l'est).*

13. **Toute opération "vérifier puis insérer" sur une contrainte métier
    (plafond, unicité) doit être protégée par une transaction ou un
    verrou**, jamais un `count()` suivi d'un `save()` sans garde. *Trouvé :
    le plafond de 5 promos actives est vérifiable en race condition —
    deux créations quasi simultanées peuvent toutes deux passer.*

14. **Bannir `Promise.all(array.map(async (x) => await repo.count(...)))`
    dans les services** — c'est un signal quasi certain de N+1. Chercher
    l'équivalent en une requête SQL agrégée (GROUP BY / sous-requête /
    JOIN LATERAL) avant d'écrire ce pattern. *Trouvé à deux endroits
    indépendants (liste des commerces d'une zone, file de modération).*

15. **Tout nouvel endpoint `GET` de liste doit prévoir page/limit dès la
    conception**, même si le volume initial semble négligeable — ce
    produit vise explicitement une extension multi-communes puis
    multi-wilayas. **Exception à vérifier avant de paginer un endpoint
    existant** : si un client le consomme aujourd'hui comme une liste de
    référence complète (ex. `/commune` chargé en entier par
    `CommuneCascadeField` pour construire un sélecteur wilaya → commune),
    ajouter la pagination sans adapter ce client tronque silencieusement
    la liste dès que le total dépasse la taille de page par défaut —
    vérifier les consommateurs existants (mobile, autre service) avant
    d'activer une pagination par défaut sur un endpoint déjà en
    production.

16. **Nettoyer le scaffolding généré par un CLI (NestJS, etc.) dès l'ajout
    du premier vrai module métier.** *Trouvé : les seuls tests de tout le
    backend étaient ceux du `AppController` par défaut ("Hello World"),
    jamais appelé par aucun client — 100% de couverture sur du code mort,
    0% sur les règles métier réelles.*

### Mobile Flutter

17. **Avant de committer du code Flutter non testé, lancer au minimum
    `flutter pub get` et `flutter analyze`** dans un environnement où le
    SDK est installable (CI, container avec proxy ouvert) — même une
    relecture manuelle très rigoureuse ne peut que suspecter certains
    risques (résolution de dépendances, API dépréciées) sans certitude.

18. **Ne jamais épingler un package en version exacte (`x.y.z` sans `^`)
    quand une dépendance SDK impose déjà sa propre contrainte de
    version.** *Trouvé : `intl: 0.20.2` figé en dur alors que
    `flutter_localizations` impose une version d'`intl` liée à la version
    exacte du SDK Flutter installé — risque de blocage de `flutter pub get`
    avant même la compilation.*

19. ⚠️ **La justification ci-dessous est au passé — vérifié le 2026-08-05.**
    Le défaut décrit (`status == 'active'` comparé par chaîne) **ne se
    reproduit plus** : zéro comparaison littérale dans le dépôt, et tous les
    champs d'état des modèles sont typés en enum. La règle reste valable pour
    ce qu'elle prescrit ; c'est son exemple qui a vieilli. *Il a d'ailleurs
    servi de donnée d'appui fausse : un audit l'a recopié comme un écart réel
    sans le mesurer.* La règle est tenue par `tool/check_enums.dart`.

    **Créer un enum Dart miroir pour chaque enum backend** (sur le modèle
    de `Categorie` ↔ `categorie.enum.ts`), plutôt que de propager la
    valeur comme `String` brute côté mobile. *Trouvé : `PromoStatus` et
    `CommercantAccountState` sont comparés par chaîne littérale
    (`status == 'active'`) dans plusieurs écrans — aucune vérification à
    la compilation en cas de renommage backend.*

20. **Dans un `ConsumerWidget` (pas `ConsumerStatefulWidget`), toute
    utilisation de `ref` après un `await` doit être précédée d'un
    `if (context.mounted)`** — un `ConsumerWidget` n'a pas de `mounted`
    propre, seulement `context.mounted`.

21. **Extraire un widget partagé dès qu'un pattern UI est dupliqué une 2ᵉ
    fois**, pas au bout du 8ᵉ écran. *Trouvé : le bloc loading/erreur/bouton
    était répété à l'identique dans 8 écrans, alors que `CategoryDropdown`
    et `PhotoPickerField` avaient bien été extraits au bon moment — la
    discipline existe déjà dans ce projet, il faut juste l'appliquer plus
    systématiquement.*

22. **Associer le rôle requis directement à la déclaration de route**
    (go_router) plutôt qu'à une liste de chemins protégés maintenue à
    part — un écran ajouté sans être ajouté à la bonne liste compile sans
    erreur et reste accessible sans authentification jusqu'à l'échec de
    l'appel API.

### Documentation

23. **Mettre à jour la documentation d'architecture dans le même commit
    que le changement qu'elle décrit.** *Trouvé : `docs/ARCHITECTURE.md`
    affirmait encore "aucun écran relié à l'API" après l'implémentation
    complète du mobile — resté faux pendant tout un cycle de
    développement faute de mise à jour.*

### Depuis l'audit V1 (révocation JWT, codes d'erreur)

24. **Un `CanActivate`/intercepteur global qui injecte un `Repository<X>`
    doit voir son module réexporter `TypeOrmModule`**, pas seulement le
    provider du guard lui-même. *Trouvé : `JwtAuthGuard` (vérification du
    `tokenVersion`) dépend de `Repository<Agent>`/`Repository<Admin>`
    déclarés dans `AuthModule` — tout module n'important que `AuthModule`
    (ex. `StorageModule`) plantait au démarrage avec
    `UnknownDependenciesException`, jusqu'à ce que `TypeOrmModule` soit
    ajouté à `exports` à côté de `JwtModule`.*

25. **Toute exception métier levée dans un service/contrôleur doit être
    une sous-classe d'`AppException` avec un `ErrorCode` dédié**, ajoutée
    dans le même commit que l'endpoint — jamais un `throw new
    BadRequestException(...)` (ou équivalent NestJS) brut, qui casserait
    le contrat `{statusCode, code, message}` garanti par
    `AllExceptionsFilter` et sur lequel le mobile
    (`ApiException`/`error_messages_{fr,en,ar}.dart`) s'appuie pour
    afficher un texte localisé.

26. **Tout `ErrorCode` ajouté côté backend doit obtenir une entrée dans les
    3 mappings mobile** (`error_messages_fr.dart`/`_en.dart`/`_ar.dart`)
    **dans le même commit**, ou être explicitement documenté comme
    exclusion volontaire (cas des messages intrinsèquement dynamiques, ex.
    `VALIDATION_ERROR`). Sans ça, une désynchronisation entre l'enum
    backend et un mapping mobile est silencieuse : le message backend brut
    (toujours en français) s'affiche à la place du texte localisé prévu,
    sans erreur de compilation d'aucun côté pour le signaler.

27. **Toute chaîne d'interface mobile ajoutée doit passer par
    `AppLocalizations`** (`lib/l10n/app_{fr,en,ar}.arb`), jamais un littéral
    français codé en dur dans un widget — et la clé doit exister dans les
    **3** fichiers `.arb` dans le même commit, pas seulement le template
    français. *Contexte : l'app était mono-langue jusqu'à l'ajout de
    l'anglais et de l'arabe (2026-07-05, ~130 chaînes à migrer sur 22
    fichiers) — repartir d'un seul fichier `.arb` aurait recréé le même
    problème dès la première chaîne oubliée.* Un modèle de domaine (enum,
    entité) n'a pas accès à un `BuildContext` : un libellé qui dépend de la
    langue (`Categorie`, statut de cycle de vie...) se résout côté UI via
    une fonction localisée (`features/shared/l10n/enum_labels.dart`), pas
    via un champ figé sur l'enum.

### Depuis la reprise des tests (2026-08-04)

Sept règles adaptées de [`echango-delivery`](https://github.com/ecolealgerienne-ui/echango-delivery),
produit voisin de la suite. **Aucune n'est importée parce qu'elle existe
ailleurs** : chacune référence un défaut trouvé dans *ce* dépôt — c'est ce qui
permet de reconnaître un cas nouveau relevant de la même règle.

28. **Un contrôle doit prouver qu'il sait refuser.** Un vérificateur au vert
    n'a montré qu'une chose : sa capacité à dire oui. Tant qu'on ne l'a pas vu
    **refuser**, on ne sait pas s'il regarde. En pratique : un `--self-test`
    bloquant, avec autant de cas qui doivent échouer que de cas qui passent,
    **plus** une mutation du vrai fichier. *Trouvé : sur les cinq bancs écrits
    le 2026-08-04, la moitié des défauts découverts étaient dans les outils de
    vérification eux-mêmes — un contrôle silencieusement sauté, une
    reproduction concluant « pas de défaut » sur un scénario qui n'avait pas
    eu lieu, un harnais jugeant sur un code de sortie. Tous **rassuraient**,
    aucun ne levait.* Corollaire : une mutation qui **casse** au lieu de
    **dégrader** ne prouve rien — un `INTERNAL_ERROR` n'est pas un refus.

29. **Un défaut n'a pas de valeur par défaut.** Une valeur de repli détruit
    l'information d'absence, et l'absence est presque toujours l'information
    qui compte. Le critère : *si cette valeur est fausse, est-ce que quelque
    chose le dira ?* Si non, il ne faut pas de valeur — `null` plutôt qu'un
    zéro, deux messages distincts pour « vide » et « illisible ».
    *Trouvé : `CommercantService.login` retombe sur une ligne supprimée au
    lieu de ne rien trouver (P10) ; et côté outillage, quatre `(.items // .)`
    avalant un objet d'erreur, un `|| true` masquant un refus de registre.*
    ⚠️ **Le pire endroit pour un repli est un script de test ou de décor** : il
    y produit un contrôle qui rassure.

30. **Un invariant s'applique, il ne se documente pas.** Dès qu'un commentaire
    dit « même règle que X », « même filtre que X », « doit rester identique à
    X » — c'est l'aveu que **rien ne tient l'invariant à notre place**, et
    **un commentaire ne peut pas échouer**. Le critère n'est pas « ces deux
    bouts se ressemblent-ils » mais **« si l'un change, l'autre doit-il
    changer ? »** — oui ⇒ un seul endroit ; non ⇒ deux endroits et un
    commentaire qui dit pourquoi ; fusion trop coûteuse ⇒ **un contrôle
    exécuté**, jamais une phrase.
    *Trouvé, et c'est cinglant : `assertPhoneAvailable` porte le commentaire
    « même filtre que l'index partiel posé en base » ; `login` n'applique pas
    ce filtre. La phrase existait, elle ne tenait rien — un numéro recyclé
    enferme son repreneur dehors (P10).*

31. **Ce que le serveur sert doit avoir un appelant.** Une capacité écrite,
    testée, documentée et appelée nulle part ne produit aucune erreur : elle
    produit une fonctionnalité absente que personne ne cherche, puisque le
    code existe. Une route neuve n'est pas finie tant qu'un écran ne l'appelle
    pas ; une réponse serveur se lit **en entier** ; et ce qui n'a plus
    d'appelant se supprime. *Généralise la règle 11 (module non branché), dont
    `AuditLogModule` fut le cas fondateur.*

32. **Une valeur qui porte une décision se nomme.** Le critère n'est pas « est-ce
    un littéral » — `maxLines: 1` décrit la nature d'un widget. Le critère est :
    **quelqu'un pourrait-il vouloir en changer, et faudrait-il alors le changer
    ailleurs aussi ?** Distinguer deux familles qui n'appellent pas le même
    remède : les valeurs **d'apparence** (incohérence visuelle, cosmétique) et
    les valeurs **métier**, qui recopient en silence une règle vivant ailleurs.
    *Mesuré au 2026-08-04 : 225 `EdgeInsets`/`SizedBox` littéraux et 25
    `Colors.*`/`Color(0x)` dans les écrans.* Une borne serveur recopiée côté
    app nomme sa source **et** est tenue par `tool/check_server_rules.dart` —
    ou n'est pas recopiée du tout : `HIGHLIGHT_CAP_REACHED` est traduit sans
    reprendre le plafond, la phrase portant le geste à faire.

    ⚠️ **Un fichier `.arb` est le dernier endroit où l'on pense à chercher une
    règle métier, et c'est pour ça qu'elle y survit.** Une valeur écrite au
    milieu d'une phrase traduite échappe à tout : elle n'est ni une constante
    qu'on grep, ni un littéral que `check_server_rules` sait lire, et elle
    existe en autant d'exemplaires qu'il y a de langues. *Trouvé le
    2026-08-05 : `« Plafond de 5 promos atteint »` et `« {count} / 5 promos
    actives »` dans les trois `.arb`, alors que `PromoSlots.plafond` venait
    déjà du serveur. Le calcul suivait donc le serveur et le **texte** ne le
    suivait pas : porter le plafond à 8 aurait autorisé 8 publications tout en
    affichant « 7 / 5 ».* Le remède est un **placeholder**, jamais un chiffre :
    `capReachedLabel(plafond)`, alimenté par la réponse serveur.

33. **La polarité de protection est une décision, pas un détail.** Ici, chaque
    route pose son propre `@UseGuards` ; le seul garde global est le
    `ThrottlerGuard`. **La route qu'on oublie est donc OUVERTE**, et l'oubli ne
    se voit ni à la compilation, ni à l'exécution, ni dans les journaux — à
    l'inverse d'un garde global dont on se retire explicitement.
    **Conséquence directe** : toute route ouverte doit être **épinglée
    nommément** avec sa justification (les 14 actuelles le sont, dans
    `scripts/lib/frontiere_http.py`), et c'est le banc, et lui seul, qui peut
    affirmer qu'aucun garde ne manque. ⚠️ Ne jamais énumérer « les routes
    protégées » depuis leur garde : l'ensemble contrôlé rétrécirait avec ce
    qu'il contrôle.

34. **Toute entrée traverse un DTO décoré.** Le `ValidationPipe` ne valide que
    les classes décorées : un `@Body() dto: { reason?: string }` typé en ligne
    n'est **pas validé du tout** — le type disparaît à la compilation, la
    validation est à l'exécution. *Mesuré au 2026-08-04 : 29 DTO, **0** `@Body`
    typé en ligne, **0** `throw new BadRequestException(...)` brut. La
    discipline est acquise ; cette règle existe pour qu'elle ne se relâche
    pas.* Complète la règle 25 par ses deux pièges : ne jamais lever un refus
    métier à l'intérieur d'un `try` dont le `catch` réemballe (le code se
    perdrait), et laisser passer les `HttpException` dans les `catch`
    génériques.

    ⚠️ **Un DTO décoré n'est pas un DTO borné, et c'est là que ça casse.**
    Mesuré le 2026-08-05 : la discipline tient toujours (100 % des `@Body` en
    DTO de classe, 100 % des `@Query` en DTO, 100 % des `@Param` via
    `UuidParam`), mais **le type n'a jamais été une borne**. Deux défauts réels
    trouvés ce jour-là, tous deux produisant un `500` là où un refus de
    validation était dû :
    - `prixAvant`/`prixApres` portaient `@IsNumber() @IsPositive()` sans
      maximum, alors que la colonne est `numeric(10, 2)` : au-delà de
      99 999 999,99, Postgres lève `22003` et personne ne le rattrape. **Ce que
      la base refuse, l'entrée doit le refuser d'abord** — et la borne se nomme
      une fois (`PRIX_MAX`, à côté de la colonne), pas dans chaque DTO ;
    - `dureeJours`, ajouté le jour même, débordait l'intervalle de dates
      représentable : `new Date(now + 1e30 * 86400000)` rend `Invalid Date`,
      dont `getTime()` vaut `NaN` — et **`NaN <= x` comme `NaN > y` sont tous
      les deux faux**, donc la valeur traversait les deux gardes. Toute
      comparaison numérique sur une donnée venue du réseau doit d'abord établir
      que c'est un nombre fini (`Number.isFinite`), jamais le supposer d'un
      `@IsNumber` en amont.

    Le critère : *pour chaque champ, quelle valeur extrême le fait sortir de ce
    que la base, le calcul ou l'affichage savent encaisser ?* Un `@IsPositive`
    sans plafond, un `@IsString` sans `@MaxLength`, un `@IsArray` sans
    `@ArrayMaxSize` sont des bornes manquantes, pas des choix. **Et un refus
    d'entrée non éprouvé ne compte pas** : `create-promo.dto.spec.ts` porte
    autant de cas qui doivent échouer que de cas qui passent, et le `@Max` y a
    été prouvé par mutation (règle 28).

    ⚠️ **Et l'entrée ne vient pas que du réseau : `configService.get<number>`
    ne convertit rien.** Le `<number>` est une assertion TypeScript, effacée à
    la compilation — exactement le piège du `@Body` typé en ligne, transposé à
    la configuration. `ConfigModule` est monté sans conversion, donc toute
    variable définie dans `.env` arrive en **chaîne**. *Trouvé le 2026-08-05 :
    les cinq lectures numériques de `PromoService` recevaient `'5'`, `'7'`,
    `'30'`… et personne ne l'avait vu parce que tous les usages étaient
    arithmétiques et que JavaScript coerce (`'5' * 86400000` marche,
    `count >= '5'` aussi). Le masque tombait au premier de ces nombres à
    **sortir en JSON** : `GET /promo/me/slots` allait servir `{"plafond":"5"}`
    à un mobile qui fait `as int` — un plantage de désérialisation, pas un
    mauvais chiffre.* Toute lecture numérique passe donc par `configNumber`
    (`common/config/`), qui vérifie le type **avant** `Number()` — celui-ci est
    bien trop accueillant pour servir de garde : `Number(true)` vaut 1,
    `Number([5])` vaut 5, `Number('')` et `Number(' ')` valent 0. Son repli est
    assumé contre la règle 29 **parce qu'il est journalisé** : l'information
    d'absence n'est pas détruite, elle est déplacée.

35. **Une couleur sémantique vient du thème ; les espacements sont recensés,
    pas encore normés.** L'app bascule clair/sombre depuis fin juillet 2026 —
    une couleur écrite en dur **ne suit pas le basculement**, et l'écran est
    simplement faux dans un des deux thèmes, sans erreur ni journal.

    ⚠️ **Un interdit général sur `Colors.*` serait une règle fausse ici**, et la
    mesure le montre : sur 12 occurrences au 2026-08-04, la plupart sont des
    blancs et des noirs posés **au-dessus d'une photo ou d'une tuile de carte**,
    où le contraste se joue contre un contenu arbitraire et non contre une
    surface de thème. Les faire passer par `colorScheme` les rendrait
    illisibles sur une image claire.

    **En pratique** — tenu par `tool/check_theme.dart` :
    - une couleur **sémantique** (`red`, `amber`, `green`, `grey`…) est refusée
      partout : elle a un équivalent dans `colorScheme` ou dans l'extension
      `AppSemanticColors` ;
    - `white`, `black`, `transparent` et les valeurs hexadécimales sont admis
      **dans les fichiers épinglés**, chacun avec sa raison — cinq à ce jour,
      tous des superpositions sur photo ou sur carte ;
    - un nom de couleur **non examiné** passe : refuser par défaut sur un nom
      qu'on n'a pas regardé accuserait à l'aveugle.

    *Trouvé : `promo_card.dart:97` pose `Colors.redAccent` pour le cœur d'un
    favori — sur la même ligne que `colorScheme.onSurfaceVariant` pour l'autre
    branche. Une moitié suit le thème, l'autre non.*

    **Ce que cette règle ne fait PAS**, et pourquoi. Les espacements littéraux
    (339 au 2026-08-04) sont **recensés sans échouer** : il n'existe pas de
    barème `AppSpacing`, et refuser sans barème demanderait de converger vers
    rien. Faire converger 339 valeurs déplace des pixels — c'est une décision
    de design, pas un défaut.

    ⚠️ **Rien à extraire côté thèmes**, contrairement au projet voisin :
    `AppTheme.light` et `AppTheme.dark` sont **dérivés d'une seule fonction**
    `_build(brightness:)`, et les couleurs sémantiques vivent dans une
    `ThemeExtension` à deux variantes. Le défaut « deux thèmes sont deux copies
    que personne ne compare » n'existe pas ici.

36. **Une clé de configuration n'existe pas tant qu'elle n'est pas dans le
    `.env` qui tourne.** `.env.example` est un document, pas une source : il
    n'est lu par aucun processus. Le `.env` réel vit **uniquement dans le clone
    WSL** (voir § Environnement), n'est pas versionné, et ne se met pas à jour
    en tirant une branche. Ajouter une clé au seul `.env.example` produit donc
    exactement l'inverse de ce qu'on croit avoir fait : le dépôt annonce un
    réglage que l'environnement qui tourne ignore.

    Et le défaut est **silencieux par construction**, parce que le repli
    fonctionne : le backend démarre, sert la bonne valeur, et rien ne distingue
    « la clé est absente, je retombe sur 5 » de « la clé vaut 5 ». C'est
    précisément le cas où l'on croira le réglage cassé en le changeant, alors
    qu'il n'aura jamais été branché. *Trouvé le 2026-08-05 : `PROMO_ACTIVE_CAP`
    ajouté aux deux `.env.example` pour rendre le plafond de promos réglable
    sans redéploiement — il ne l'est dans aucun environnement tant que le `.env`
    de WSL ne le porte pas.*

    **En pratique** : toute clé ajoutée l'est dans les **trois** endroits dans
    le même commit — `apps/backend/.env.example`, `.env.production.example`, et
    le `.env` de WSL (hors dépôt, donc à faire à la main et à **dire** dans le
    message de commit ou le journal, sinon personne ne saura que ça reste à
    faire). Corollaire de la règle 29 : si un repli est prévu, la valeur
    effectivement retenue doit être **journalisée au démarrage** — sans ça,
    l'absence de la clé est indiscernable de sa présence, et c'est le
    diagnostic qu'on n'aura pas le jour où le réglage « ne marche pas ».

### Règles de `echango-delivery` volontairement **non** reprises

Une exclusion non écrite est indiscernable d'un oubli.

| Règle | Pourquoi pas ici |
|---|---|
| *Aucune transaction entre systèmes — compenser explicitement* | Delivery joint Fleetbase en HTTP avec sa propre base ; **nous possédons notre Postgres**. Importer ça ferait écrire des compensations là où un `ROLLBACK` suffit — et le verrou consultatif couvre déjà le cas éprouvé |
| *Le statut Fleetbase fait foi — aucun état parallèle* | Pas de Fleetbase. Le seul grain transférable (ne pas dériver un état métier de plusieurs champs amont) **est déjà la règle 8** |
| *Poser les questions de structure au graphe, pas au `grep`* | Suppose Graphify installé — et delivery **mesure lui-même** que le graphe est faux sur du Dart (fonction à 3 appelants vue avec un degré de 1, 64 nœuds fantômes). Notre dépôt est à moitié Dart |

---

## L'environnement, tel qu'il est sur ce poste (2026-08-04)

⚠️ **Il y a DEUX clones, et c'est structurant.**
`C:\…\Desktop\shope\echangopromo\echangopromo` — où l'on édite, commite, et où
tourne Flutter — et **`~/projects/echangopromo` dans WSL**, d'où tournent
réellement le backend et les bancs, et **la seule qui porte
`apps/backend/.env`**. Les deux divergent dès qu'on commite d'un côté sans
tirer de l'autre.

| | |
|---|---|
| Backend | WSL, `npm run start:dev`, **port 3000** |
| Postgres | conteneur `echangopromo-postgres-1`, **port hôte 5433** |
| MinIO | conteneur `echangopromo-minio-1`, **port 9000** |
| Mobile | Windows, Flutter 3.35.7, émulateur Android |
| Depuis l'émulateur | l'hôte est **`10.0.2.2`**, jamais `localhost` |

**Les plafonds, qui dimensionnent tout banc et tout script :**

| Plafond | Valeur | Portée |
|---|---|---|
| global | 60 / min / IP | toutes les routes |
| `STRICT_THROTTLE` | **5 / min / IP** | les 3 logins, `register`, `report` |
| `SENSITIVE_ACTION_THROTTLE` | 20 / min / IP | les écritures — **seau partagé** |
| `MAP_THROTTLE` | 180 / min / IP | `/promo/map` |
| créations de promo | 5 / 24 h / commerçant | agent et admin **exemptés** |
| promos actives | 5 / commerçant | **personne n'est exempté** |

⚠️ **Un 429 se déguise en « identifiants incorrects »** : attendre une minute
entre deux bancs plutôt que chercher un bug d'authentification.

**Trois pièges d'environnement, tous rencontrés le 2026-08-04 :**

- **`--dart-define` se perd** si `flutter` est lancé via un intermédiaire qui
  reconstruit la ligne de commande (`Start-Process` en PowerShell). Le build
  part alors sur la valeur par défaut — la **production** — sans un mot.
  Vérifier en cherchant la chaîne attendue dans `build/…/kernel_blob.bin`.
- **L'analyse HTTPS d'un antivirus casse Gradle** en `PKIX path building
  failed` : la racine de l'antivirus est dans le magasin Windows, pas dans le
  truststore Java. Symptôme reconnaissable — PowerShell télécharge, Java non.
- **`S3_ENDPOINT` sert deux rôles** : point d'accès du client S3 *du serveur*
  **et** base de l'URL publique servie au mobile. Le régler sur `10.0.2.2:9000`
  pour l'émulateur rend chaque création de promo dépendante d'un timeout TCP
  (mesuré : 300 s → 88 ms une fois les rôles séparés via `S3_CDN_BASE_URL`).

---

## Dette connue, non bloquante pour le pilote mais à traiter avant extension

- ~~Couverture de tests backend encore partielle (2 fichiers)~~ — **révisé le
  2026-08-04** : 5 fichiers `.spec.ts`, 5 tests unitaires Dart, **3
  vérificateurs de synchronisation** et **5 bancs de bout en bout**, tous
  prouvés par mutation. Le plafond de 5 promos est désormais éprouvé **sous
  course**, et la fenêtre d'ignore de 30 jours ne l'est toujours pas. **État
  réel, verdicts et ordre de reprise : `docs/status_v0.1.md`.**
- `Admin` reste un compte unique en V0 (pas de gestion multi-admin) —
  `POST /admin/me/revoke-token` couvre l'auto-révocation, mais aucun
  mécanisme pour qu'un admin révoque un *autre* admin n'a de sens tant que
  ce cas n'existe pas.

Détail complet, fichier:ligne, sévérités : `docs/AUDIT_V0.md` et
`docs/AUDIT_V1.md`.

---

## Où vit quoi

⚠️ **Ce fichier porte des RÈGLES, pas un état d'avancement.** Les deux n'ont ni
la même durée de vie ni le même lecteur : une règle se lit *avant d'écrire du
code*, un avancement *avant de choisir quoi faire*. Les mélanger fait relire
des centaines de lignes pour trouver ce qui reste, et fait passer une case
cochée pour une règle. **N'en recopier aucun extrait ici** — ce serait créer
deux sources qui divergent, le défaut que ce fichier dénonce à chaque page.

| Document | Ce qu'on y trouve |
|---|---|
| **`docs/status_v0.1.md`** | **le suivi vivant** — état mesuré, points ouverts, arbitrages, journal daté, et « par où reprendre ». `status_v0.md` est figé au 2026-07-12 |
| `docs/METHODE_TEST.md` | la méthode de test générique à la stack Echango — 11 modes de défaillance, lexique, ordre d'adoption, squelettes |
| `docs/TEST_PROMO.md` | son instanciation ici — surface par persona, matrice de 27 bancs, registre de couverture |
| `docs/SPECS_ECHANGO_PROMO_V0.md` | la source de vérité produit |
| `docs/AUDIT_V0.md` · `AUDIT_V1.md` | les findings historiques, fichier:ligne |
