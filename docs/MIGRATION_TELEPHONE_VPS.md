# Migration du téléphone en E.164 — procédure VPS

**À exécuter une seule fois**, au premier déploiement qui embarque les
migrations `1783890000000` et `1783900000000` (fusionnées dans `main` par la
PR #25, le 2026-08-15).

Complète `docs/DEPLOIEMENT_VPS.md`, qu'elle ne remplace pas.

---

## Ce que ces deux migrations font, et à quoi il faut s'attendre

Elles réécrivent **l'identifiant de connexion de toutes les fiches
commerçant** :

| | avant | après |
|---|---|---|
| forme stockée | `0555000101` **et/ou** `+213555000101`, au hasard de la saisie | `+213555000101`, toujours |
| colonne `pays` | n'existe pas | `DZ` par défaut |
| unicité | sur `telephone` seul | sur `(pays, telephone)` |

**Aucun commerçant ne perd sa connexion** : la saisie est normalisée avant la
recherche, donc `0555000101`, `+213555000101` et `00213555000101` mènent tous
au même compte. Mesuré, pas déduit — voir `docs/status_v0.1.md` (2026-08-15).

⚠️ **Ce qu'il faut savoir avant de lancer, et qui n'est pas dans le runbook
général** : sur le VPS, les migrations tournent **au démarrage du conteneur**
(`Dockerfile` : `npx typeorm migration:run && node dist/main`). Une migration
qui échoue empêche donc `node dist/main` de s'exécuter — **le backend ne
démarre pas du tout**. Ce n'est pas une dégradation, c'est une coupure.

Et ces migrations **échouent volontairement** s'il existe deux comptes actifs
qui deviennent un doublon une fois normalisés. C'est le bon comportement —
choisir lequel garder est une décision produit, pas celle d'une migration —
mais cela veut dire qu'un doublon en base **coupe la production au
redéploiement**.

D'où l'étape 1, qui n'est pas optionnelle.

---

## 1. Chercher les doublons AVANT de déployer (lecture seule)

Depuis `/opt/echangopromo`, sur la base de production :

```bash
cd /opt/echangopromo

# Le nom du conteneur Postgres de prod n'est pas celui du dev — le vérifier.
docker ps --format '{{.Names}}' | grep postgres
```

Puis, en remplaçant `<conteneur>`, `<user>` et `<base>` :

```bash
docker exec <conteneur> psql -U <user> -d <base> -c "
WITH normalise AS (
  SELECT id, telephone, \"deletedAt\",
         right(regexp_replace(telephone, '[^0-9]', '', 'g'), 9) AS chiffres
    FROM commercant
)
SELECT chiffres,
       COUNT(*)                       AS comptes_actifs,
       string_agg(telephone, ' | ')   AS formes_en_base
  FROM normalise
 WHERE \"deletedAt\" IS NULL
 GROUP BY chiffres
HAVING COUNT(*) > 1
 ORDER BY 2 DESC;"
```

**Zéro ligne** ⇒ la migration passera. Vous pouvez déployer.

**Une ligne ou plus** ⇒ **ne pas déployer**. Chaque ligne est un même numéro
porté par plusieurs comptes actifs sous des écritures différentes. Il faut
décider, pour chacun, lequel garder :

- regarder les deux fiches (`SELECT id, nom, adresse, "createdAt" FROM
  commercant WHERE telephone IN (…)`) ;
- supprimer ou fusionner celle qui doit partir, **via le produit** — l'écran
  admin, ou `scripts/supprimer-commercants-prod.sh` (voir le runbook §
  « Outils d'exploitation ») ;
- relancer la requête ci-dessus jusqu'à ce qu'elle ne rende rien.

⚠️ **La requête compare les 9 derniers chiffres**, la même clé que le produit.
Elle est volontairement un peu plus large que la migration : elle peut signaler
un cas que la migration accepterait, jamais l'inverse. Un faux positif coûte
une vérification ; un faux négatif coûte une production à l'arrêt.

## 2. Sauvegarder

```bash
cd /opt/echangopromo && ./scripts/backup-db.sh
```

Huit contrôles doivent s'afficher. ⚠️ **La ligne qui compte ici est
`chiffrement + déchiffrement`** : une sauvegarde qui ne se rouvre pas ne vaut
rien le jour où on en a besoin.

## 3. Déployer

```bash
cd /opt/echangopromo
git pull origin main
docker compose --env-file .env.production -f docker-compose.promo.yml up -d --build backend
```

## 4. Lire ce que la migration a dit — pas seulement qu'elle a fini

```bash
docker compose --env-file .env.production -f docker-compose.promo.yml logs --tail=200 backend
```

Trois choses à chercher, dans cet ordre :

| À chercher | Ce que ça veut dire |
|---|---|
| `Conversion E.164 impossible` ou `Normalisation impossible` | un doublon est passé au travers de l'étape 1 — **le backend n'a pas démarré**, la base est intacte, revenir à l'étape 1 |
| `numéro(s) non normalisables` | des fiches à l'écriture aberrante ont été **laissées telles quelles**, et sont nommées. Elles étaient déjà inutilisables avant ; les reprendre à la main |
| `Migration … has been executed successfully` ×2 | les deux migrations sont passées |

⚠️ **Ne pas filtrer ces journaux sur les seules lignes de succès** : c'est ainsi
qu'un échec passe pour un succès (CLAUDE.md règle 12).

## 5. Vérifier l'état, puis le comportement

```bash
docker exec <conteneur> psql -U <user> -d <base> -c "
SELECT COUNT(*)                                          AS total,
       COUNT(*) FILTER (WHERE telephone LIKE '+%')       AS en_e164,
       COUNT(*) FILTER (WHERE telephone NOT LIKE '+%')   AS restantes,
       COUNT(DISTINCT pays)                              AS nb_pays
  FROM commercant;"
```

Attendu : `restantes = 0`, sauf autant de fiches que le journal en a nommées à
l'étape 4.

**Puis le seul contrôle qui compte vraiment** — une connexion réelle, avec
l'ancienne écriture, celle que les commerçants ont dans leur téléphone :

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://promo.echango.com/commercant/login \
  -H 'Content-Type: application/json' \
  -d '{"telephone":"+213XXXXXXXXX","pin":"<le PIN d un compte de test>"}'
```

`201` attendu. ⚠️ **Sans témoin négatif, ce `201` ne prouve que la capacité à
dire oui** : refaire l'appel avec un PIN faux, et exiger `400`.

## 6. L'app mobile — ordre de déploiement

Le nouveau champ `pays` envoyé par l'app est **ignoré** par un backend
antérieur (`ValidationPipe` en `whitelist: true` **sans**
`forbidNonWhitelisted` : les champs inconnus sont retirés, pas refusés). Donc :

- **une app à jour sur un backend ancien fonctionne**, mais le sélecteur de
  pays n'a aucun effet : tout numéro non algérien sera refusé par l'ancien
  `@IsPhoneNumber('DZ')` ;
- **une app ancienne sur un backend à jour fonctionne** aussi : sans `pays`, le
  défaut `DZ` s'applique, et la saisie est normalisée comme avant.

Il n'y a donc **pas d'ordre imposé**. Le seul déploiement qui décoit est l'app
en premier, parce qu'elle promet un choix de pays que le serveur n'honore pas
encore.

---

## Retour arrière

Les deux migrations ont un `down`. Mais :

⚠️ **Le `down` ne restaure pas les écritures d'origine** — elles ne sont
enregistrées nulle part, et les inventer serait pire que l'absence. Il ramène à
la forme nationale, pas au mélange de départ. Le vrai retour arrière d'un
incident est la **sauvegarde de l'étape 2**, pas le `down`.
