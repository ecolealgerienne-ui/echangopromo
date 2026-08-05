# PR — `claude/echango-promo-suite-2026-08-04` → `main`

> Ce fichier existe pour être **copié dans la PR GitHub**, `gh` n'étant installé
> ni sur le poste ni dans WSL. Lien direct pour l'ouvrir :
> https://github.com/ecolealgerienne-ui/echangopromo/compare/main...claude/echango-promo-suite-2026-08-04?expand=1

**111 commits · 292 fichiers · +30 506 / −1 981**
En avance de 111 commits sur `main`, **en retard de 0** : la fusion est directe,
aucun conflit possible.

---

## Ce que cette branche apporte

### Exploitation — ce qui manquait pour tenir un pilote

- **Une sauvegarde de base qui se restaure vraiment.** Le script restaure chaque
  dump qu'il produit dans une base jetable et compare les lignes table par
  table : un fichier jamais restauré n'est pas une sauvegarde.
- **Envoi hors site chiffré, et prouvé non lisible** : AES-256 vérifié par
  déchiffrement, dépôt en ACL privée, puis **requête anonyme sur l'objet** — un
  `200` à ce moment-là fait supprimer l'objet et échouer le lot.
- **Rétention 7 quotidiennes + 8 hebdomadaires** (deux mois d'histoire en une
  quinzaine de fichiers), sur un préfixe borné puisque le dépôt est mutualisé.
- **Rapatriement** (`--lister`, `--rapatrier`) : ni `aws`, ni `rclone`, ni
  `s3cmd` n'existent sur ces machines — sans ces deux modes, une sauvegarde
  partie chez OVH n'aurait pas pu être récupérée le jour de l'incident.
- **Rotation du mot de passe admin** rendue possible (elle ne l'était pas).

### Produit

- **Plafond de promos actives par commerçant** (`null` = suit le global).
- **Seuil de signalement réglable**, avec un **plancher à 2** — il avait été
  abaissé à 1 pour un test, et un seul signalement suffisait alors à masquer la
  promo d'un concurrent.
- **L'agent entre par la même porte que l'admin** : `AgentLoginScreen` existait,
  était couvert par les bancs, et **rien dans l'app ne l'atteignait**.
- **Refus Apple 5.1.1(iv) corrigé** : la localisation n'est plus demandée deux
  fois ; l'invitation vit désormais sur la carte, là où la fonction ne marche
  pas sans position.

### Tests

- **12 parcours joués sur l'appareil** (`scripts/test-parcours-ecran.sh`),
  couvrant les quatre profils et chaque geste qui écrit. Rejoués d'un seul
  tenant, code de sortie 0.
- **27 bancs HTTP**, dont les 8 admin/agent rejoués à 59 contrôles, 0 échec.
- Vérificateurs de synchronisation, specs backend (74 tests), et
  `migration:generate` **muet** — toute sortie signale désormais un écart réel.

---

## Les défauts que ce travail a trouvés

Chacun a été **mesuré**, pas supposé.

| Défaut | Portée |
|---|---|
| `PromoListController` écrivait son état après `dispose` | se déclenchait **à chaque frappe** dans la recherche |
| `promoSlotsProvider` n'était invalidé **nulle part** | le serveur comptait 2 promos, l'écran affichait « 1 / 5 » |
| 25 bancs sur 31 n'étaient **pas exécutables** dans git | `./scripts/test-X.sh` rendait « Permission denied » sur un clone neuf |
| Le décor annonçait des **photos inexistantes** | chaque écran de promo recevait un 404 d'image |
| `S3_ENDPOINT` servait **deux rôles** | 300 s de timeout à chaque création de promo → 88 ms |
| Un numéro recyclé **enfermait son repreneur dehors** | `login` n'appliquait pas le filtre que son commentaire annonçait |

---

## Ce qui reste ouvert, et qui est écrit plutôt que caché

- **Les CGU et la politique de confidentialité portent `[à compléter]`** — date
  et e-mail de contact, dans les trois langues. Motif de refus App Store à part
  entière ; les valeurs sont une décision produit.
- **Le VPS** : clé S3 dédiée, phrase de passe rangée hors de la machine
  sauvegardée, cron surveillé par son code de sortie, rotation du mot de passe
  `superadmin`. Procédure complète dans `docs/DEPLOIEMENT_VPS.md`.
- **La rétention distante n'a jamais tourné contre OVH** — le banc local tourne
  contre MinIO, qui ne fait pas de virtual-hosted et rend `non concluant` au
  lieu de conclure. Le premier passage sur le VPS est le seul juge.
- Parcours écran non couverts, déclarés : favoris, partage, première promo par
  l'agent, brouillon commerçant, bandeau « Top promos ».
