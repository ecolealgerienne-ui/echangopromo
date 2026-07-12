# Audit performance/optimisation — echango Promo

**Statut** : audit ciblé optimisation (pas un audit à 6 volets comme
`docs/AUDIT_V0.md`), demandé le 2026-07-12 en vue d'un futur ajout de CDN
pour les photos de promo. Méthode : exploration en lecture seule,
fichier:ligne systématique, aucune modification de code pendant l'audit
lui-même.

| # | Point | Sévérité | Statut |
|---|---|---|---|
| 1 | Vignettes téléchargées en pleine résolution (liste/avatars) | Élevée | ❌ Non traité |
| 2 | Upload multi-photo séquentiel (1-3 photos) | Moyenne | ❌ Non traité |
| 3 | Aucun timeout Dio (mobile) | Moyenne-Élevée (fiabilité) | ❌ Non traité |
| 4 | Pas de compression de réponse HTTP (backend) | Moyenne | ❌ Non traité |
| 5 | CDN déjà câblé côté backend | Info | ✅ Rien à faire côté code |
| 6 | Page unique de 100 promos (pas de pagination infinie) | Faible | ⚠️ Compromis déjà assumé/documenté |
| 7 | Index composite promo ne couvre pas `moderationStatus` | Faible | ⚠️ Sans incidence à l'échelle pilote |
| 8 | Boucles séquentielles S3/notifications dans les crons | Faible | ⚠️ Sans incidence (tâches de fond, petits volumes) |
| 9 | Pool de connexions PostgreSQL par défaut | Info | ⚠️ À surveiller si montée en charge |

---

## 1. Les vignettes téléchargent l'image en pleine résolution

**Sévérité : Élevée — c'est le point le plus directement lié au projet de CDN.**

`memCacheWidth`/`memCacheHeight` (`CachedNetworkImage`, utilisés dans
`apps/mobile/lib/features/client/widgets/promo_card.dart:63-64`,
`apps/mobile/lib/features/admin/widgets/promo_moderation_tile.dart:64`,
`apps/mobile/lib/features/commercant/screens/my_promos_screen.dart:130-133`)
ne réduisent que la taille du **bitmap décodé en mémoire** — le fichier est
toujours **téléchargé en entier** depuis le réseau (~150-250 Ko par photo,
cible de `StorageApi._compress`) avant d'être redimensionné localement.
Une liste de 20 promos télécharge donc ~3-5 Mo juste pour afficher des
vignettes de 96×96, sur le marché explicitement identifié comme sensible
au coût data (`storage.service.ts:16-24`).

**Lien direct avec le CDN envisagé** : un CDN "cache HTTP" classique (ex.
un simple reverse-proxy devant le bucket) n'apporte qu'un gain de latence,
pas de réduction de volume — le fichier plein format resterait quand même
téléchargé. Pour réellement optimiser l'affichage des vignettes, il faut
un CDN avec **redimensionnement à la volée** (Cloudflare Images, Bunny
Optimizer, imgproxy, ou variantes générées à l'upload côté backend) qui
sert une variante ~100-150px pour les listes et l'original uniquement pour
le carousel détail (`PromoPhotoHero`). À garder en tête au moment de
choisir l'offre CDN — toutes ne proposent pas ce redimensionnement.

---

## 2. Upload multi-photo séquentiel

**Sévérité : Moyenne.**

`PromoFormScreen._submit` (`apps/mobile/lib/features/commercant/screens/promo_form_screen.dart:104-111`)
et `AgentPromoFormScreen._submit`
(`apps/mobile/lib/features/agent/screens/agent_promo_form_screen.dart:84-91`)
uploadent les photos une par une dans une boucle `for...await` — trois
appels réseau indépendants exécutés en série. Sur une promo à 3 photos,
`Future.wait` sur les éléments `NewPhotoItem` réduirait le temps
d'attente total de la publication d'un facteur ~2-3 sur un réseau lent
(les `ExistingPhotoItem`, sans appel réseau, n'ont pas besoin d'être
parallélisés).

---

## 3. Aucun timeout configuré sur le client HTTP mobile

**Sévérité : Moyenne-Élevée (fiabilité perçue, pas juste vitesse).**

`ApiClient` (`apps/mobile/lib/data/api/api_client.dart:24`) construit
`Dio(BaseOptions(baseUrl: Env.apiBaseUrl))` sans `connectTimeout` ni
`receiveTimeout`. Par défaut Dio attend indéfiniment — sur la "couverture
réseau variable à Djelfa" déjà documentée ailleurs dans ce repo
(`storage.service.ts:19`), une requête sur une connexion dégradée laisse
l'utilisateur bloqué sur un spinner sans jamais échouer proprement ni
proposer de réessayer. Un `connectTimeout` court (10-15s) et un
`receiveTimeout` plus généreux pour les uploads (30-60s, ou override par
requête sur `StorageApi.uploadPhoto`) transformeraient une attente
infinie en erreur actionnable.

---

## 4. Pas de compression de réponse HTTP côté backend

**Sévérité : Moyenne.**

`apps/backend/package.json` n'a pas le paquet `compression`, et
`main.ts` (`apps/backend/src/main.ts`) ne l'installe pas comme
middleware. Les réponses JSON de liste (`GET /promo`, `GET
/admin/moderation/queue`...) partent donc non compressées. Gain simple
(`app.use(compression())`, 3 lignes) et sans risque, notable sur un
réseau faible — même levier "coût data" que la compression d'image déjà
appliquée côté mobile.

---

## 5. CDN déjà câblé côté backend — aucun changement de code requis pour le cache

**Info, pas un problème.**

`StorageService.buildPublicUrl` (`apps/backend/src/storage/storage.service.ts:157-169`)
bascule automatiquement sur `S3_CDN_BASE_URL` s'il est défini, et chaque
upload part déjà avec `Cache-Control: public, max-age=31536000,
immutable` (`storage.service.ts:139`) — cohérent avec le fait que
`buildKey` ne réutilise jamais une clé (`storage.service.ts:81-87`), donc
un objet donné ne change jamais de contenu une fois écrit. **Activer un
CDN devant le bucket OVH pour les photos de promo est donc une pure
étape d'infra** (créer la distribution CDN, la pointer sur le bucket,
renseigner `S3_CDN_BASE_URL`) — zéro code à toucher pour le cache/latence.
Seul le redimensionnement à la volée (point 1 ci-dessus) demanderait un
choix de CDN spécifique et éventuellement un ajustement de
`buildPublicUrl` pour construire l'URL avec les paramètres de resize du
service choisi.

---

## 6-9. Points mineurs, sans action recommandée à l'échelle actuelle

- **Page unique de 100 promos** (`apps/mobile/lib/data/api/promo_api.dart:10`) :
  compromis déjà assumé et documenté en commentaire (pas un oubli) — à
  revoir seulement si le volume de promos actives par sélection de
  communes dépasse ce seuil.
- **Index composite `Promo(lifecycleStatus, dateFin)`**
  (`apps/backend/src/promo/entities/promo.entity.ts:54`) ne couvre pas
  `moderationStatus`, filtré séparément dans `findActiveForClient`
  (`promo.service.ts:215-217`) — sans incidence sur un volume à l'échelle
  d'un quartier ; à réévaluer si le nombre de promos par commune grossit
  significativement.
- **Boucles séquentielles S3/notifications** dans
  `purgeOldPhotosCron`/`notifyExpiringSoonCron`/le nettoyage de photos
  retirées dans `PromoService.update` (`promo.service.ts`) : tâches de
  fond nocturnes ou tableaux ≤3 éléments, aucun impact utilisateur
  actuel.
- **Pool de connexions PostgreSQL** : configuration par défaut de `pg`
  (`apps/backend/src/data-source.ts`, pas de `extra.max` explicite) —
  suffisant à l'échelle pilote, à surveiller si le nombre de
  commerçants/agents simultanés augmente.

**Confirmé sans problème** : les listes mobiles (`ListView.separated`,
`promo_list_screen.dart:82-92`) sont correctement virtualisées
(`itemBuilder`/`itemCount`) — aucune image hors-écran n'est téléchargée
avant d'entrer dans le viewport. La pagination `page`/`limit` (règle
CLAUDE.md #15) est bien appliquée sur tous les endpoints de liste
backend.
