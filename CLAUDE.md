# CLAUDE.md — echango Promo

Instructions pour Claude Code sur ce dépôt. Lire aussi `docs/SPECS_ECHANGO_PROMO_V0.md`
(specs fonctionnelles), `docs/ARCHITECTURE.md` (choix de stack),
`docs/AUDIT_V0.md` (audit initial complet, fichier:ligne) et
`docs/AUDIT_V1.md` (audit de suivi — révocation JWT, codes d'erreur) —
ce fichier-ci en est la synthèse actionnable.

## Consignes de fonctionnement (utilisateur)

- **Optimiser l'usage des tokens** : éviter les tâches/vérifications
  inutiles (builds, greps de relecture, allers-retours de confirmation
  superflus), rester concis dans les réponses.
- **Ne jamais lancer les tests/builds/l'app** dans cet environnement
  (pas de `npm install`/`flutter pub get` ici, l'utilisateur développe sur
  sa propre machine WSL/Windows) — donner les commandes exactes à exécuter
  chez lui et attendre ses retours, plutôt que d'essayer de vérifier soi-même.

## Projet en un coup d'œil

Backend NestJS + TypeORM + PostgreSQL (`apps/backend`), app mobile Flutter
multi-rôles Client/Commerçant/Agent (`apps/mobile`). Pilote V0 sur un
quartier de Djelfa. Pas d'admin UI en V0 (API seule, décision assumée).

```
apps/backend/src/{commune,zone,agent,admin,commercant,promo,report,audit-log,storage,auth}
apps/mobile/lib/{app,data,domain,providers,features/{client,commercant,agent,shared}}
```

Commandes utiles :
- Backend : `cd apps/backend && npm run start:dev` / `build` / `lint` /
  `seed:admin -- <email> <password> <nom>` / `seed:communes` /
  `migration:run` / `migration:generate -- src/migrations/<Nom>` /
  `migration:revert`. Schéma géré uniquement par migrations
  (`synchronize: false` toujours, plus de bascule sur `NODE_ENV`) —
  lancer `npm run migration:run` avant le premier `start:dev` sur une
  base neuve, et avant les scripts seed.
- Mobile : `cd apps/mobile && flutter pub get && flutter analyze` — **le
  SDK Flutter n'a jamais pu être installé dans l'environnement de dev
  utilisé jusqu'ici** (proxy réseau bloquant `storage.googleapis.com`),
  donc tout le code mobile actuel a été relu statiquement mais **jamais
  compilé**. `flutter analyze` est la toute première chose à lancer en
  reprenant ce projet en local, avant tout autre travail.

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
    multi-wilayas.

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

19. **Créer un enum Dart miroir pour chaque enum backend** (sur le modèle
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
    (`ApiException`/`errorMessagesFr`) s'appuie pour afficher un texte
    localisé.

26. **Tout `ErrorCode` ajouté côté backend doit obtenir une entrée dans le
    mapping mobile** (`errorMessagesFr`, ou son équivalent futur
    multi-langue) **dans le même commit**, ou être explicitement documenté
    comme exclusion volontaire (cas des messages intrinsèquement
    dynamiques, ex. `VALIDATION_ERROR`). Sans ça, une désynchronisation
    entre l'enum backend et le mapping mobile est silencieuse : le message
    backend brut s'affiche à la place du texte localisé prévu, sans erreur
    de compilation d'aucun côté pour le signaler.

---

## Dette connue, non bloquante pour le pilote mais à traiter avant extension

- Pas de pagination sur les listes (`/promo`, `/admin/agent`, `/zone`,
  `/commune`) — et le N+1 associé sur `ModerationService.queue()` (un
  `SELECT` par promo signalée).
- `Commercant` n'a pas de `tokenVersion` : `POST
  /admin/commercant/:id/reset-pin` efface le PIN mais ne révoque pas les
  JWT déjà émis (valides jusqu'à `JWT_EXPIRES_IN`, 30j par défaut).
  `Admin.tokenVersion` existe mais n'est jamais incrémenté (pas de route
  de révocation pour un admin).
- Mobile : aucune déconnexion automatique quand le backend rejette un
  token révoqué/invalide (401) — l'utilisateur reste sur son écran avec un
  token mort tant qu'il n'utilise pas le bouton logout manuel.
- Rate limiting absent sur des actions sensibles post-authentification
  (`reset-pin`, `revoke-token`, `presigned-upload`, actions promo) — seule
  la limite globale (60 req/min) s'applique.
- `Content-Type` d'un upload S3 toujours purement déclaratif (la taille
  est bien contrainte par la policy S3 depuis cette session, pas le type
  réel du fichier).
- Deux FK sans index (`Agent.zoneId`, `Commercant.createdByAgentId`) —
  impact nul tant qu'aucune requête ne filtre dessus.
- 0% de couverture de tests automatisés côté backend (le mobile a une
  première suite dans `apps/mobile/test/`).

Détail complet, fichier:ligne, sévérités : `docs/AUDIT_V0.md` et
`docs/AUDIT_V1.md`.
