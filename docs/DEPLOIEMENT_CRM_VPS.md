# Déploiement de l'export CRM — les deux applications

**À exécuter une fois**, pour mettre en service la synchronisation nocturne
d'echango Promo vers EchangoCrm (PR #28 côté Promo, module `echango_promo_crm`
côté CRM).

Complète `DEPLOIEMENT_VPS.md` (Promo) et `docs/DEPLOIEMENT_VPS.md` du dépôt
`crm`, qu'elle ne remplace pas.

---

## L'ordre, et pourquoi il est dans ce sens

**Odoo d'abord, Promo ensuite.** Pas par prudence : c'est Odoo qui **produit le
jeton** que Promo doit porter.

⚠️ **Aucun des deux ordres ne casse quoi que ce soit**, et c'est voulu :

| | |
|---|---|
| Odoo déployé, Promo pas encore | le module attend ; aucun lot n'arrive, la source est marquée **silencieuse** |
| Promo déployé, jeton absent | la tâche de 04:00 **journalise son abstention** et ne pousse rien |

Ce sont les deux seules issues possibles, et aucune n'est une panne. C'est ce
qui permet de déployer en deux temps, un jour d'écart s'il le faut.

**Aucune migration de schéma dans ce lot, des deux côtés.**

---

## 1. EchangoCrm — le module qui reçoit

```bash
cd /opt/echangocrm
git pull origin main
docker compose --env-file .env.production -f docker-compose.crm.yml up -d
```

Le service `odoo-init` réinstalle la liste de modules, `echango_promo_crm`
compris — il figure désormais dans `--init=`. « Exited (0) » est son résultat
normal.

### ⚠️ Vérifier que le module est bien chargé, pas seulement que ça démarre

```bash
docker compose --env-file .env.production -f docker-compose.crm.yml \
  logs odoo-init | grep -iE "echango_promo_crm|Modules loaded|error"
```

⚠️ **`--init` n'installe qu'un module ABSENT.** Pour une mise à jour ultérieure
du module, c'est `--update` qu'il faut, puis un **redémarrage du serveur** :

```bash
cd /opt/echangocrm
git pull origin main

CONT=$(docker compose --env-file .env.production -f docker-compose.crm.yml ps -q odoo)

docker exec "$CONT" sh -c 'odoo \
  --database=echango_crm \
  --db_host="$HOST" --db_user="$USER" --db_password="$PASSWORD" \
  --update=echango_promo_crm \
  --http-port=8079 --gevent-port=8082 \
  --stop-after-init'

docker compose --env-file .env.production -f docker-compose.crm.yml restart odoo
```

⚠️ **Les paramètres de base ne sont PAS optionnels ici, et leur absence ne
parle pas de base.** `docker exec … odoo` court-circuite l'entrypoint de
l'image, qui est le seul à traduire `HOST` / `USER` / `PASSWORD` en
`--db_host` / `--db_user` / `--db_password`. Sans eux, Odoo tente une connexion
par **socket Unix local** et rend `No such file or directory` — un message qui
fait chercher un conteneur mort ou un volume perdu. *Cette commande figurait
ici sans eux jusqu'au 2026-08-15, où elle a échoué au premier usage réel.* Les
lire depuis les variables du conteneur (`sh -c '…'`, guillemets **simples** :
c'est le shell de dedans qui doit les résoudre) évite d'en recopier la valeur,
et de la laisser dans l'historique.

⚠️ **Les deux commandes, pas une.** Une mise à jour lancée dans un `docker exec`
est un **second processus** : celui qui sert le navigateur garde son registre en
mémoire, donc ses modèles d'avant. Le symptôme est trompeur — une erreur Owl
sur un champ qui existe pourtant en base. Et `--http-port` évite un
`Address already in use` qui ne parle ni de module ni de mise à jour.

### ⚠️ Constater que la mise à jour a chargé les données, pas seulement le code

```bash
PG=$(docker compose --env-file .env.production -f docker-compose.crm.yml ps -q postgres_crm)
docker exec -i "$PG" psql -U odoo -d echango_crm -c \
  "SELECT c.code, COUNT(*) FROM res_country_state s
     JOIN res_country c ON c.id = s.country_id
    WHERE c.code IN ('DZ','AE') GROUP BY 1"
```

Attendu : **`DZ` 58** et **`AE` 7**. Un `DZ` à 0 signifie que le fichier de
référence n'a pas été chargé — le module tournera sans erreur et l'« État »
restera vide sur toutes les fiches algériennes, sans que rien ne le signale.

### Rattraper les fiches déjà géocodées — **une seule fois, après cette mise à jour**

⚠️ **La tâche planifiée ne les reprendra JAMAIS.** Une fiche n'est re-géocodée
que si sa position a bougé de plus de 200 m : tout ce qui portait déjà
`Géocodé` avant cette mise à jour garderait sa ville et un **État vide pour
toujours**. Ce n'est pas un état d'attente, c'est un état stable et faux.

Le rattrapage **n'appelle pas Nominatim** — le nom de wilaya est déjà stocké
dans `wilaya_geocodee`. Il n'y a donc aucun risque de quota :

```bash
docker exec -i "$CONT" sh -c 'odoo shell --database=echango_crm \
  --db_host="$HOST" --db_user="$USER" --db_password="$PASSWORD" \
  --http-port=8079 --gevent-port=8082 --no-http' <<'PY'
Compte = env['echango.promo.account']
rattrapes, refuses = 0, {}
for c in Compte.search([('wilaya_geocodee', '!=', False)]):
    if c.partner_id.state_id:
        continue
    etat = c._etat_correspondant(c.wilaya_geocodee)
    if etat:
        c.partner_id.state_id = etat.id
        rattrapes += 1
    else:
        refuses[c.wilaya_geocodee] = refuses.get(c.wilaya_geocodee, 0) + 1
env.cr.commit()
print('RATTRAPEES=%d' % rattrapes)
print('NON APPARIEES :', refuses)
PY
```

⚠️ **`docker exec -i`, avec le `-i`.** Sans lui l'entrée standard n'est pas
transmise : `odoo shell` démarre, ne lit rien, et sort **sans un mot** — on
croit alors que le script n'a rien trouvé.

**Lire la ligne `NON APPARIEES`, elle n'est pas décorative.** Un nom qui y
figure est un refus, et il y a deux sortes de refus :

| Ce qu'on y voit | Ce que ça veut dire |
|---|---|
| un nom hors DZ/AE (`Californie`, `Île-de-France`) | position aberrante — un GPS d'émulateur, une saisie fantaisiste. **Normal**, rien à faire |
| une **wilaya bien réelle** | son nom diverge de `res_country_state_dz.xml` — il manque une entrée dans `ALIAS_ETATS` côté CRM |

### 2. Créer la source et générer le jeton

Dans l'interface : **CRM → echango Promo → Source et jeton**.

1. Créer une source (nom libre, « echango Promo » par défaut).
2. Bouton **Générer un jeton**.
3. **Copier le jeton maintenant** — il n'est stocké nulle part, seule son
   empreinte l'est. S'il est perdu, il faut en générer un autre, ce qui révoque
   le précédent immédiatement.

---

## 3. echango Promo — celui qui pousse

### Poser les trois clés

⚠️ **Le troisième endroit de la règle 36.** Les deux `.example` versionnés
portent déjà ces clés ; le fichier qui tourne, lui, vit **hors du dépôt** et
aucun `git pull` ne le met à jour.

```bash
cd /opt/echangopromo
nano .env.production
```

```ini
# Export vers le CRM Odoo
CRM_SYNC_URL=http://echangocrm-odoo-1:8069
CRM_SYNC_TOKEN=<le jeton copié à l'étape 2>
CRM_SYNC_PAGE_SIZE=200
```

⚠️ **Une URL interne plutôt que publique.** Les deux stacks partagent le réseau
Docker `echango_network` : Promo atteint Odoo sans sortir sur Internet, donc
sans DNS public, sans TLS et sans dépendre du retour de boucle du routeur.
Vérifier le nom réel du conteneur avant de le poser :

```bash
docker ps --format '{{.Names}}' | grep -i odoo
```

Si l'URL interne ne résout pas, `https://echangocrm.echango.com` fonctionne
aussi — c'est le même chemin que n'importe quel client externe.

### Déployer

```bash
cd /opt/echangopromo
git pull origin main
docker compose --env-file .env.production -f docker-compose.promo.yml up -d --build backend
```

---

## 4. Ne pas attendre 04:00 pour savoir si ça marche

### La façon courte — depuis le conteneur, sans aucun jeton

```bash
cd /opt/echangopromo
docker compose --env-file .env.production -f docker-compose.promo.yml   exec backend npm run crm:sync:prod
```

⚠️ **Être dans le conteneur EST l'authentification.** Quiconque peut lancer
cette commande peut déjà lire la base et le `.env` : exiger un jeton HTTP de
plus ne protégerait rien, il ajouterait seulement un mot de passe à retrouver au
pire moment — et pousserait à confondre le JWT d'administrateur avec
`CRM_SYNC_TOKEN`, qui n'a rien à voir.

Elle démarre le contexte Nest complet et appelle **le même service** que la
tâche de 04:00 : un déclencheur qui emprunterait un autre chemin ne prouverait
rien de celui qui tourne la nuit.

| Sortie | Code | Ce que ça veut dire |
|---|---|---|
| `Lot … — N fiche(s) en P page(s), acquitté.` | 0 | c'est passé |
| `Rien envoyé : CRM_SYNC_URL / CRM_SYNC_TOKEN absents` | **2** | les clés ne sont pas lues — ce n'est **pas** une panne |
| `Envoi échoué : …` | 1 | Odoo a refusé, ou est injoignable — le message dit lequel |

⚠️ **Deux codes de sortie distincts pour « rien envoyé » et « envoi raté »** :
les confondre ferait traiter une configuration absente comme un incident.

### La façon longue — par HTTP, avec un jeton d'administrateur

Le premier envoi réel ne doit pas être le premier test.

```bash
# Un jeton admin — en VOYANT ce que le serveur répond.
#
# ⚠️ La version courte (un curl dont la réponse part directement dans un
# python3 -c) laisse JETON VIDE quand la connexion échoue, et l'appel suivant
# rend alors « 401 AUTH_TOKEN_INVALID » : un message qui accuse l'export alors
# que c'est la connexion qui a raté. Un script qui jette la réponse du serveur
# ne peut pas savoir qu'il a échoué.
REPONSE=$(curl -s -w '\n%{http_code}' -X POST https://promo.echango.com/admin/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"<admin>","password":"<mot de passe>"}')
CODE=$(echo "$REPONSE" | tail -1)
CORPS=$(echo "$REPONSE" | head -n -1)
echo "connexion -> $CODE"
[ "$CODE" = "201" ] || echo "  $CORPS"

JETON=$(echo "$CORPS" | python3 -c "import sys,json;print(json.load(sys.stdin).get('accessToken',''))")
echo "jeton reçu : ${#JETON} caractères"   # 0 = la connexion a échoué

# ⚠️ Ce jeton n'est PAS `CRM_SYNC_TOKEN`. Deux authentifications opposées :
# celui-ci est un JWT d'administrateur DE PROMO, qui sert à déclencher
# l'export ; l'autre est le jeton D'ODOO, que Promo présente en poussant. Les
# confondre rend exactement ce « 401 AUTH_TOKEN_INVALID ».

# Ce que l'export produit, SANS rien envoyer
curl -s "https://promo.echango.com/crm/merchants?limit=3" \
  -H "Authorization: Bearer $JETON" | python3 -m json.tool | head -40

# L'envoi réel, celui que fait la tâche de 04:00 — même code, même lot
curl -s -X POST https://promo.echango.com/crm/sync -H "Authorization: Bearer $JETON"
```

### Les trois choses à regarder, dans cet ordre

| Où | Quoi |
|---|---|
| Réponse de `/crm/merchants` | `equivalence.divergences` doit être **vide**. Une divergence signifie que le SQL et la table des motifs ne disent plus la même chose — le CRM annoncerait « peut publier » sur des commerçants que le serveur refuse |
| Réponse de `/crm/sync` | `{envoyees, pages, lot}` |
| Odoo → **Journal des lots** | **deux lignes** : le lot et son acquittement, `accepté` à vrai, `refusées` à zéro |

⚠️ **Un journal vide n'est pas un succès** : il dit que rien n'est arrivé.
L'écran **Source et jeton** dit depuis quand — une source sans lot reçu depuis
36 h est marquée **silencieuse**.

---

## 5. Ce qui se met en route tout seul, et qu'il faut savoir

- **La tâche de 04:00** (heure d'Alger, fuseau explicite) pousse l'instantané
  complet chaque nuit.
- **Le géocodage inverse** tourne côté Odoo toutes les 15 minutes, par lots de
  25, contre Nominatim. ⚠️ Sa politique d'usage impose **une requête par
  seconde** : le rythme est déjà calibré, ne pas l'accélérer — un dépassement
  fait bannir l'adresse IP du serveur, et cela se découvre bien après. Un parc
  de 300 fiches se géocode en environ trois heures, puis ne bouge plus : une
  fiche n'est re-géocodée que si sa position a bougé de plus de 200 m.

  ⚠️ **Ne pas lancer de rattrapage manuel massif.** Le 2026-08-15, un lot de
  216 fiches lancé à la main a fait répondre **429 Too Many Requests** à
  Nominatim, et 61 fiches sont retombées en `erreur` d'un coup. Depuis, un 429
  **interrompt le lot** au lieu d'enchaîner — mais la bonne conduite reste de
  laisser la tâche planifiée faire son travail. Il n'y a rien à rattraper : elle
  reprend seule ce qui a échoué.

- **La ville ET l'état natif d'Odoo** sont remplis. Deux pièges, opposés :

  | | |
  |---|---|
  | **Algérie** | Odoo ne livre **aucune** wilaya — le module pose les **58** (`data/res_country_state_dz.xml`). Sans elles, « État » restait vide quoi que fasse le géocodage |
  | **Émirats** | Odoo livre **déjà** les 7 émirats, en **anglais**. En reposer un fichier viole `res_country_state_name_code_uniq` et **empêche l'installation du module** |

  ⚠️ **Et l'appariement ne se fait pas sur le nom brut.** Nominatim, à qui l'on
  demande pourtant du français, rend `Doubaï` (mesuré) là où Odoo stocke
  `Dubai`, et `Abou Dabi` là où Odoo stocke `Abu Dhabi`. Le rapprochement passe
  par des formes normalisées et une table d'alias (`ALIAS_ETATS`) — **jamais**
  un `ilike` sur le nom, qui échouerait en silence.
- **Aucune écriture vers Promo.** Le CRM ne fait que recevoir.

## 6. Deux réglages optionnels

| Clé | Où | Effet |
|---|---|---|
| `ECHANGO_PROMO_RETENTION_DAYS` | Compose du CRM | purge du journal des lots. **Absente ⇒ conservation indéfinie**, journalisée à chaque passage. À deux lignes par nuit, ~730 par an |
| `CRM_SYNC_PAGE_SIZE` | `.env.production` de Promo | 200 par défaut. Le contrôleur Odoo refuse au-delà de 500 |

---

## Revenir en arrière

**Vider les deux clés de `.env.production` côté Promo et redémarrer le backend.**
La tâche journalise alors son abstention et ne pousse plus rien ; les données
déjà reçues restent dans Odoo, intactes.

C'est le seul retour arrière nécessaire : aucun schéma n'a changé, et le module
Odoo n'écrit jamais vers Promo.
