# PR — `claude/echango-promo-suite-2026-08-04` → `main`

> ⚠️ **`gh` EST installé et authentifié depuis (au moins) le 2026-08-15** —
> compte `ecolealgerienne-ui`, vérifié par `gh auth status`. La PR #25 a été
> ouverte directement par `gh pr create --body-file -`. La phrase d'origine
> (« `gh` n'étant installé ni sur le poste ni dans WSL, revérifié le
> 2026-08-05 ») ferait refaire un copier-coller manuel devenu inutile — et
> c'est le genre d'état périmé qui fait conclure.
>
> Ce fichier reste utile comme **brouillon relisible** avant d'ouvrir une PR ;
> il n'est plus le seul chemin. Lien de comparaison, si besoin :
> https://github.com/ecolealgerienne-ui/echangopromo/compare/main...claude/echango-promo-suite-2026-08-04?expand=1

**1 commit · 2 fichiers · +100 / −1**
En avance de 1 commit sur `main`, **en retard de 0** : la fusion est directe.

> Les deux PR précédentes (#14, #15) sont fusionnées. Celle-ci ne porte que la
> clôture du rejeu contre le VPS.

---

## Titre

`fix(décor) : poser les coordonnées à l'inscription, et le prouver au serveur`

---

## Ce que cette PR apporte

### Le décor pose enfin le point que le banc de la carte va chercher

`provision-decor.sh` inscrivait son commerçant **sans `latitude`/`longitude`**,
que `register-commercant.dto` accepte pourtant depuis toujours. Conséquence :
`GET /promo/map/center` rendait `{"center":null}` pour sa commune, et le
parcours écran « carte » s'arrêtait sur *« centre absent »* — **trois étapes
après la cause**. `seed-demo.sh`, lui, en posait : d'où une commune peuplée avec
centre et une commune de décor sans, écart que rien ne signalait.

### Et surtout, le contrôle qui manquait

Le décor demande maintenant **au serveur** si la commune a un centre, et échoue
sinon. Vérifier qu'on a *envoyé* le point n'aurait rien prouvé : c'est ce que le
serveur en fait qui compte. Sans ce contrôle, l'oubli se reproduit en silence.

⚠️ **Corriger ces coordonnées après coup ne marche pas** : un
`PATCH /commercant/me` remet le commerçant en revue de profil, et ce seul état
lui interdit de publier (`403 COMMERCANT_PROFILE_PENDING_REVIEW`). Un décor qui
répare un profil se sabote lui-même — d'où la pose à l'inscription.

### `docs/status_v0.1.md` — l'entrée de session

**Aucun code produit modifié** : rien sous `apps/backend/src/` ni
`apps/mobile/lib/`.

---

## Ce que le rejeu contre le VPS a donné

Première fois que le harnais tourne ailleurs que contre WSL.

| Lot | Résultat |
|---|---|
| 27 bancs HTTP | **25 verts · 2 non concluants · 0 échec** |
| 12 parcours écran | **tous verts**, contre-mesures serveur comprises |

`frontiere-http` rend les mêmes **50 routes protégées, 144 sondes, 0 échec**
qu'en local : la frontière ne change pas au déploiement.

---

## Ce que le rejeu a appris

| Constat | Portée |
|---|---|
| **Le VPS n'était pas vide** — `/promo` (0) et `/commune` (35) l'avaient fait croire | deux endpoints publics ne montrent ni les commerçants ni les files ; le tableau de bord admin en comptait **11** et **6 dossiers en attente** |
| **`GET /commune` lu sans limite** dans `seed-demo.sh` | **20 communes sur 35** ; invisible tant qu'on visait `.items[0:4]`, n'apparaît qu'en demandant une commune **par son nom** (règle #15 vue depuis l'outillage) — corrigé par comparaison à `total`, pas par un `?limit=100` seul |
| **`i % 4` en dur** dans la répartition des commerces | avec une liste plus courte, `jq` rendait `null` et le commerce partait **sans commune**, sans un mot |
| **Trois blocages, tous dans le décor** | plafond plein · coordonnées absentes · profil en revue — le harnais a **refusé de jouer** à chaque fois, plutôt que rendre un échec parlant de l'écran |

---

## Points ouverts, écrits plutôt que cachés

- **Bandeau « Top promos »** — `client-highlight` rend non concluant :
  `GET /highlight` sert `{"items":[]}`. Mesuré : les **deux** mises en avant
  sont `active: true`, pointent la **même** promo, et le serveur les marque
  `promoVisible: false`. Le filtre public est correct ; c'est l'admin qui
  affiche comme vivante une curation morte, alors que le champ est servi.
  **Non corrigé : décision éditoriale.**
- **`promo-cycle`** — bornes de durée et brouillon invisible passent ; le
  cooldown de republication n'a pas pu être éprouvé (plafond plein). À rejouer
  sur un commerçant neuf.
- **AVG Antivirus intercepte tout le HTTPS de ce poste** — certificat resigné
  par `AVG Web/Mail Shield Root`, constaté aussi sur `api.github.com` et
  `pub.dev`. Windows accepte cette racine, Android non. ⚠️ **L'installer en
  autorité utilisateur ne suffit pas** : Chrome charge la page, l'app non —
  `network_security_config.xml` gouverne la pile Java/Android, pas `HttpClient`
  de `dart:io`. Remède côté machine : exclure le domaine de l'inspection HTTPS.
- **Le clone WSL** porte les scripts corrigés mais pas les commits — `git pull`
  à la prochaine session.
