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
CONT=$(docker compose --env-file .env.production -f docker-compose.crm.yml ps -q odoo)
docker exec "$CONT" odoo --database=echango_crm --update=echango_promo_crm \
  --http-port=8079 --gevent-port=8082 --stop-after-init
docker compose --env-file .env.production -f docker-compose.crm.yml restart odoo
```

⚠️ **Les deux commandes, pas une.** Une mise à jour lancée dans un `docker exec`
est un **second processus** : celui qui sert le navigateur garde son registre en
mémoire, donc ses modèles d'avant. Le symptôme est trompeur — une erreur Owl
sur un champ qui existe pourtant en base. Et `--http-port` évite un
`Address already in use` qui ne parle ni de module ni de mise à jour.

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

Le premier envoi réel ne doit pas être le premier test.

```bash
# Un jeton admin
JETON=$(curl -s -X POST https://promo.echango.com/admin/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"<admin>","password":"<mot de passe>"}' \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['accessToken'])")

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
