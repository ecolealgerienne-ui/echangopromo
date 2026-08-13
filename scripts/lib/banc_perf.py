#!/usr/bin/env python3
"""Banc de performance — des chiffres, avant toute optimisation.

── Pourquoi ce banc avant tout le reste ────────────────────────────────────

Le dépôt porte 46 bancs de correction et **aucune mesure de performance**. Une
cible de fluidité qu'on ne mesure pas est un commentaire, et un commentaire ne
peut pas échouer (règle 30). Tant qu'aucun chiffre n'existe, toute optimisation
est une opinion : on ne saura ni si elle a servi, ni si un changement ultérieur
l'a défaite.

`docs/AUDIT_PERFORMANCE_V0.md` (2026-07-12) a traité cinq points sur neuf. Ses
acquis sont des **cases cochées dans un tableau** — rien ne les tient. Ce banc en
transforme le principal en contrôle exécuté : si quelqu'un retire le middleware
`compression`, la sonde de compression passe au rouge le jour même au lieu
d'être découverte sur la facture data d'un utilisateur.

⚠️ Et cet audit **précède la bascule géographique** : il ignore que la liste fait
désormais un cadre rectangulaire plus une distance haversine à chaque requête, et
que `/promo/map` existe. Les deux routes les plus chaudes du produit n'y figurent
pas.

── Les quatre grandeurs mesurées, et pourquoi ces quatre-là ────────────────

1. **Le poids sur le fil** (brut et gzip). C'est la grandeur qui coûte de
   l'argent à l'utilisateur, sur un marché explicitement identifié comme
   sensible au coût data (`storage.service.ts`). Mesuré le 2026-08-13 :
   `/promo?limit=20` pèse 15 516 o brut et **2 559 o** en gzip, `/promo/map`
   39 323 o et **5 731 o**. La compression divise par six ; c'est le levier
   déjà tiré, et c'est précisément pour ça qu'il faut le garder sous contrôle.

2. **La latence p50/p95**, jamais la moyenne : une moyenne noie le cas lent
   sous les cas rapides, et l'utilisateur ne vit pas la moyenne, il vit son
   propre appel.

3. **La présence d'un cache HTTP, et son efficacité réelle.** ⚠️ J'avais
   d'abord écrit « il n'y en a aucun » après avoir cherché `ETag` dans le
   CODE : c'était faux. **Express en pose un d'office** sur toute réponse
   JSON, et une requête conditionnelle obtient bien un `304`. Ce qui manque
   vraiment est `Cache-Control` : sans lui, l'app refait l'aller-retour à
   chaque écran — elle économise le corps, jamais le trajet. Chercher dans le
   code ce qui se lit dans la réponse est une erreur de méthode, et elle
   coûte un diagnostic entier.

4. **Le nombre de transactions PostgreSQL par appel HTTP.** C'est la seule
   sonde qui voit venir un N+1 (règle 14, trouvé deux fois dans ce dépôt) : à
   74 promos il est invisible en temps, à 74 000 il est fatal. On mesure la
   **forme** de la requête, pas sa durée du jour.

── ⚠️ Trois pièges de mesure, tous évitables et tous payés ailleurs ────────

**Un 429 est une réponse TRÈS rapide.** Le seau global est de 60 requêtes par
minute et par IP : un banc qui échantillonne sans regarder les codes ferait
chuter son p50 en mesurant des refus de débit. Ici, **seules les réponses 200
entrent dans les statistiques**, et un échantillon trop maigre rend « non
concluant » — jamais un chiffre flatteur.

**La compression ne s'observe pas sans la demander.** `curl` sans
`Accept-Encoding: gzip` reçoit du brut, et on conclurait que le middleware est
absent. Les deux formes sont donc mesurées explicitement.

**Le premier appel n'est pas représentatif** : connexion TCP, pool PostgreSQL
froid, cache de plan vide. Un appel de chauffe est jeté avant l'échantillon, et
il est dit — le taire ferait passer une mesure pour une autre.

── Ce que ce banc n'est PAS ────────────────────────────────────────────────

Ce n'est pas un test de charge : il mesure un appel à la fois, sans concurrence.
Il répond à « cette route est-elle bien formée ? », pas à « que se passe-t-il à
500 utilisateurs ? ». Les deux questions sont réelles ; les confondre donnerait
un banc qui ment sur les deux.

── Usage ───────────────────────────────────────────────────────────────────

    python3 scripts/lib/banc_perf.py --self-test
    ./scripts/test-perf.sh

⚠️ Aucune écriture, aucun identifiant : il lit des routes publiques. Il peut se
lancer contre n'importe quel environnement, y compris la production.

⚠️ **La sonde SQL exige un accès à PostgreSQL** (`psycopg2`, `psql` ou
`docker exec`). Depuis le clone Windows elle n'a aucun des trois et le dit ;
depuis WSL, où vivent le backend et la base, elle mesure.
"""

import json
import math
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
DEVICE_ID = "banc-perf-0001"

# ── Accès PostgreSQL — recopiés de `docker-compose.yml`, qui est versionné ──
#
# ⚠️ Ce banc a rendu « PostgreSQL injoignable » pendant deux passages en portant
# `postgres/postgres/echangopromo`, inventés faute d'avoir regardé. Les vraies
# valeurs sont dans le compose du dépôt, et `plan_sql.py` les portait déjà
# correctement : deux endroits, une seule vérité, et c'est celui qui se trompait
# qui rendait le verdict le plus rassurant — « pas mesurable » plutôt que faux.
PG_HOTE = "localhost"
PG_PORT = "5433"
PG_UTILISATEUR = "echango"
PG_MOT_DE_PASSE = "echango"
PG_BASE = "echango_promo"

# ── Les seuils, nommés parce qu'ils portent une décision (règle 32) ─────────
#
# ⚠️ Ce ne sont pas des mesures : ce sont des **budgets**. Les mesures du
# 2026-08-13 tiennent toutes largement dedans, et c'est voulu — un budget calé
# au ras de l'existant passerait au rouge au premier ajout de champ légitime.

# 300 ms côté serveur laisse de la place au réseau : sur un lien mobile
# algérien, c'est le trajet qui domine, et au-delà d'une seconde bout en bout
# une interaction cesse d'être ressentie comme instantanée.
# ⚠️ La mesure INCLUT le réseau : lancé contre un VPS distant, ce seuil juge
# aussi le lien, ce qui est honnête pour un client mais faux pour le serveur.
SEUIL_P95_MS = float(os.environ.get("SEUIL_P95_MS", "300"))

# Un facteur de compression sous 2 signale un middleware absent ou contourné.
# Mesuré : 6,1× sur la liste, 6,9× sur la carte — la marge est confortable.
SEUIL_COMPRESSION = float(os.environ.get("SEUIL_COMPRESSION", "2.0"))

# Nombre d'échantillons. ⚠️ Multiplié par le nombre de routes, il doit rester
# sous le seau global de 60/min/IP — sinon on mesure des 429.
ECHANTILLONS = int(os.environ.get("ECHANTILLONS", "8"))

# Budget de poids **compressé**, par route, en octets. C'est ce qui traverse
# réellement le réseau de l'utilisateur.
ROUTES = [
    ("/promo/config", 512,
     "servie à chaque démarrage de l'app"),
    ("/promo?limit=20", 8192,
     "la vitrine — le premier écran de tout client"),
    ("/promo?limit=20&latitude=34.6703&longitude=3.2630", 8192,
     "la même, avec le point du client (cadre + haversine)"),
    ("/promo/map?north=34.72&south=34.62&east=3.31&west=3.21", 16384,
     "la carte — la route la plus lourde du produit"),
]


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_echantillon(reussites, total):
    """⚠️ **La garde de toutes les autres sondes.**

    Un 429 revient en quelques millisecondes : mesuré sans filtre, il
    *améliorerait* le p50. Un échantillon amputé ne donne donc pas un chiffre
    prudent, il donne un chiffre **flatteur** — le pire des faux négatifs.
    """
    if total == 0:
        return "non_concluant", "aucun appel effectué"
    if reussites == 0:
        return ("non_concluant",
                "aucune réponse 200 sur %d appels — probablement le seau de "
                "60/min ; aucun chiffre n'est mesurable" % total)
    if reussites < total:
        return ("non_concluant",
                "%d réponses non-200 sur %d écartées : l'échantillon est "
                "amputé, et un 429 rapide fausserait le p50 vers le bas"
                % (total - reussites, total))
    return "ok", "%d/%d appels en 200" % (reussites, total)


def verdict_latence(p95_ms, seuil_ms):
    """Le p95, jamais la moyenne : l'utilisateur vit son appel, pas la moyenne."""
    if p95_ms is None:
        return "non_concluant", "aucune latence mesurable"
    if p95_ms > seuil_ms:
        return ("echec",
                "p95 = %.0f ms, budget %.0f ms — au-delà, l'écran cesse d'être "
                "ressenti comme instantané" % (p95_ms, seuil_ms))
    return "ok", "p95 = %.0f ms (budget %.0f)" % (p95_ms, seuil_ms)


def verdict_poids(octets_gzip, budget):
    """Ce qui traverse réellement le réseau de l'utilisateur, et qu'il paie."""
    if octets_gzip is None:
        return "non_concluant", "poids illisible"
    if octets_gzip > budget:
        return ("echec",
                "%d o compressés, budget %d o — sur un marché sensible au coût "
                "data, chaque ouverture d'écran se paie"
                % (octets_gzip, budget))
    return "ok", "%d o compressés (budget %d)" % (octets_gzip, budget)


# Seuil par défaut du middleware `compression` : il ne compresse PAS sous
# 1 Ko, et c'est correct — l'en-tête gzip coûterait plus que le gain.
SEUIL_COMPRESSIBLE_O = 1024


def verdict_compression(brut, gzip_, seuil, plancher=SEUIL_COMPRESSIBLE_O):
    """⚠️ Transforme une case cochée de l'audit en contrôle exécuté.

    Le middleware `compression` a été ajouté le 2026-07-12 et **rien ne le
    tenait** depuis. S'il disparaît, cette sonde le dit le jour même au lieu
    qu'on le découvre sur la facture data d'un utilisateur (règle 30).

    ⚠️ **Sous 1 Ko, le middleware ne compresse pas, et il a raison** : l'en-tête
    gzip coûterait plus que le gain. Ce banc a rendu ROUGE sur `/promo/config`
    (89 o) à son premier passage, en accusant un middleware qui se comportait
    correctement — la règle 38 dans le banc lui-même, pour la deuxième fois de
    la journée. Sous le plancher, la sonde n'a pas d'objet et le dit.
    """
    if brut is None or gzip_ is None:
        return "non_concluant", "une des deux mesures est illisible"
    if gzip_ <= 0:
        return "non_concluant", "réponse compressée vide"
    if brut < plancher:
        return ("non_concluant",
                "%d o : sous le plancher de %d o du middleware, qui ne "
                "compresse pas — et il a raison. Rien à mesurer ici"
                % (brut, plancher))
    facteur = brut / float(gzip_)
    if facteur < seuil:
        return ("echec",
                "compression ×%.1f seulement (brut %d o, gzip %d o) : le "
                "middleware `compression` est absent ou contourné"
                % (facteur, brut, gzip_))
    return "ok", "×%.1f (%d o → %d o)" % (facteur, brut, gzip_)


def verdict_cache(entetes):
    """L'absence de cache n'est pas une panne : c'est une décision jamais prise.

    ⚠️ Donc « non concluant », et non « échec » — accuser le produit pour un
    choix que personne n'a fait serait un contrôle sur une fausse prémisse
    (règle 38). Mais « non concluant » n'est pas une réussite non plus, et c'est
    exactement le statut de ce point.
    """
    if entetes is None:
        return "non_concluant", "en-têtes illisibles"
    etag = "etag" in entetes
    directive = "cache-control" in entetes
    if not etag and not directive:
        return ("non_concluant",
                "aucun en-tête de cache : chaque ouverture d'écran refait "
                "l'aller-retour complet, même quand rien n'a changé")
    # ⚠️ **Un ETag seul ne suffit pas, et ce banc l'a d'abord cru.** Express en
    # pose un d'office ; sans `Cache-Control`, la conservation du corps est
    # laissée à l'heuristique de chaque client — donc à rien de fiable. Rendre
    # « ok » sur l'ETag seul masquerait exactement l'écart que P3 vient combler.
    if etag and not directive:
        return ("non_concluant",
                "ETag servi mais AUCUN Cache-Control : le client n'a aucune "
                "consigne de conservation, et la revalidation dépend de son "
                "heuristique")
    if directive and not etag:
        return ("non_concluant",
                "Cache-Control servi sans ETag : le client sait qu'il peut "
                "conserver, mais n'a rien pour revalider")
    return "ok", "ETag + %s" % entetes["cache-control"]


def verdict_revalidation(statut_304, a_etag):
    """⚠️ **Un `ETag` servi ne prouve rien tant qu'il n'économise rien.**

    Express en pose un d'office sur toute réponse JSON — ce qui m'a fait écrire
    d'abord « aucun cache HTTP » en cherchant dans le CODE au lieu de regarder
    la RÉPONSE. Il est bien là. Mais il ne sert que si une requête portant
    `If-None-Match` obtient un **304 sans corps** : c'est ça, l'économie.

    ⚠️ Ce que cette sonde ne dit PAS : que l'app s'en serve. Elle établit que le
    serveur sait répondre 304 ; que Dio envoie `If-None-Match` est une autre
    question, et elle appartient au lot mobile.
    """
    if a_etag is None:
        return "non_concluant", "en-têtes illisibles"
    if not a_etag:
        return ("non_concluant",
                "aucun ETag servi : rien à revalider, chaque appel retransmet "
                "le corps entier")
    if statut_304 is None:
        return "non_concluant", "requête conditionnelle sans réponse"
    if statut_304 != 304:
        return ("echec",
                "un ETag est servi mais une requête conditionnelle rend %s au "
                "lieu de 304 : le corps entier repart à chaque fois, et "
                "l'en-tête ne sert à rien" % statut_304)
    return "ok", "304 sans corps — la revalidation économise le corps"


def verdict_requetes(delta, seuil):
    """⚠️ La seule sonde qui voit venir un N+1 (règle 14, trouvé deux fois).

    On compte les transactions PostgreSQL d'un appel. TypeORM n'ouvrant pas de
    transaction explicite sur une lecture, chaque requête en produit une : le
    delta est un **proxy du nombre de requêtes**, et c'est sa forme qui compte,
    pas sa valeur au chiffre près.

    À 310 promos un N+1 est invisible en temps ; à 310 000 il est fatal. C'est
    pour ça qu'on mesure la forme, aujourd'hui, pendant qu'elle ne coûte rien.

    ⚠️ **Le nombre passé ici est un ÉCART, pas un total**, et la distinction a
    failli produire une fausse accusation. `pg_stat_database.xact_commit` compte
    **toute** la base : les tâches de fond, les autres requêtes, et jusqu'aux
    connexions que la sonde ouvre pour se lire elle-même. Mesuré brut, un appel
    à `/promo/map` semblait coûter **15 transactions** ; mesuré contre un
    intervalle témoin de même durée sans aucun appel, il en coûte **2**. Le
    seuil accusait le bruit de fond et le coût de sa propre mesure (règle 38).
    """
    if delta is None:
        return ("non_concluant",
                "PostgreSQL injoignable (ni psycopg2, ni psql, ni docker) — "
                "lancer ce banc depuis WSL, où vivent le backend et la base")
    if delta > seuil:
        return ("echec",
                "%d transactions imputables à UN appel HTTP (seuil %d), bruit "
                "de fond déduit : c'est la forme d'un N+1, invisible "
                "aujourd'hui et fatale à l'échelle" % (delta, seuil))
    return "ok", "%d transaction(s) imputables à l'appel, bruit déduit" % delta


# ─────────────────────────────────────────────────────────────────────────────

def _percentile(valeurs, p):
    """p-ième centile, méthode du plus proche rang — sans dépendance externe.

    ⚠️ `math.ceil`, et surtout pas `round` : Python arrondit au pair, donc
    `round(5.5)` vaut **6** et le p50 de 1..10 rendait 6 au lieu de 5. Défaut
    trouvé par l'auto-test avant le premier passage réel — c'est exactement ce
    qu'un `--self-test` est censé attraper (règle 28).
    """
    if not valeurs:
        return None
    ordonnees = sorted(valeurs)
    rang = int(math.ceil(p / 100.0 * len(ordonnees)))
    return ordonnees[max(0, min(len(ordonnees) - 1, rang - 1))]


def appeler(chemin, gzip_=False, conditionnel=None):
    """(statut, octets, millisecondes, en-têtes en minuscules)."""
    req = urllib.request.Request(API_URL + chemin)
    req.add_header("X-Device-Id", DEVICE_ID)
    if conditionnel:
        req.add_header("If-None-Match", conditionnel)
    if gzip_:
        req.add_header("Accept-Encoding", "gzip")
    else:
        # ⚠️ Explicite : sans ça, urllib n'annonce rien et le serveur PEUT
        # compresser quand même. On veut deux mesures distinctes, pas deux
        # mesures identiques qu'on croirait distinctes.
        req.add_header("Accept-Encoding", "identity")
    debut = time.time()
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            corps = r.read()
            ms = (time.time() - debut) * 1000
            entetes = {k.lower(): v for k, v in r.headers.items()}
            return r.status, len(corps), ms, entetes
    except urllib.error.HTTPError as e:
        ms = (time.time() - debut) * 1000
        try:
            e.read()
        except Exception:
            pass
        return e.code, None, ms, {}
    except Exception:
        return None, None, None, None


def compter_transactions():
    """Transactions validées par PostgreSQL, ou `None` s'il est injoignable.

    Trois transports essayés dans l'ordre, parce que le dépôt vit sur deux
    clones : WSL porte la base, Windows porte Flutter (voir `CLAUDE.md`).
    """
    requete = ("select xact_commit from pg_stat_database "
               "where datname = current_database()")
    try:
        import psycopg2  # noqa: PLC0415
        cx = psycopg2.connect(
            host=os.environ.get("PGHOST", PG_HOTE),
            port=int(os.environ.get("PGPORT", PG_PORT)),
            user=os.environ.get("PGUSER", PG_UTILISATEUR),
            password=os.environ.get("PGPASSWORD", PG_MOT_DE_PASSE),
            dbname=os.environ.get("PGDATABASE", PG_BASE))
        try:
            cur = cx.cursor()
            cur.execute(requete)
            return int(cur.fetchone()[0])
        finally:
            cx.close()
    except Exception:
        pass
    for argv in (
        ["psql", "-U", os.environ.get("PGUSER", PG_UTILISATEUR),
         "-d", os.environ.get("PGDATABASE", PG_BASE), "-tAc", requete],
        ["docker", "exec", os.environ.get("PGCONTAINER",
                                          "echangopromo-postgres-1"),
         "psql", "-U", os.environ.get("PGUSER", "postgres"),
         "-d", os.environ.get("PGDATABASE", PG_BASE), "-tAc", requete],
    ):
        try:
            sortie = subprocess.run(argv, capture_output=True, timeout=20)
            if sortie.returncode == 0:
                return int(sortie.stdout.decode().strip())
        except Exception:
            continue
    return None


_ok = 0
_echecs = []


def _v(libelle, obtenu, attendu):
    global _ok
    if obtenu == attendu:
        _ok += 1
    else:
        _echecs.append("%s — attendu %r, obtenu %r" % (libelle, attendu, obtenu))


def self_test():
    # ── Doivent PASSER ───────────────────────────────────────────────────────
    _v("échantillon complet", verdict_echantillon(8, 8)[0], "ok")
    _v("latence sous budget", verdict_latence(25.0, 300)[0], "ok")
    _v("poids sous budget", verdict_poids(2559, 8192)[0], "ok")
    _v("compression effective",
       verdict_compression(15516, 2559, 2.0)[0], "ok")
    _v("cache complet",
       verdict_cache({"etag": 'W/"abc"',
                      "cache-control": "private, max-age=0"})[0], "ok")
    # ⚠️ L'ETag seul : Express en pose un d'office, et ce banc a failli s'en
    # contenter — ce qui aurait masqué l'écart que P3 comble.
    _v("ETag sans Cache-Control",
       verdict_cache({"etag": 'W/"abc"'})[0], "non_concluant")
    _v("Cache-Control sans ETag",
       verdict_cache({"cache-control": "private"})[0], "non_concluant")
    _v("revalidation effective", verdict_revalidation(304, True)[0], "ok")
    _v("une requête par appel", verdict_requetes(3, 10)[0], "ok")
    # ⚠️ Le centile, méthode du plus proche rang, sans dépendance.
    _v("p95 de dix valeurs", _percentile(list(range(1, 11)), 95), 10)
    _v("p50 de dix valeurs", _percentile(list(range(1, 11)), 50), 5)

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    _v("latence hors budget", verdict_latence(900.0, 300)[0], "echec")
    _v("poids hors budget", verdict_poids(20000, 8192)[0], "echec")
    # ⚠️ Le défaut visé : le middleware `compression` retiré sans qu'on le voie.
    _v("compression disparue",
       verdict_compression(15516, 15000, 2.0)[0], "echec")
    # ⚠️ Le défaut visé : un N+1, invisible en temps à l'échelle du pilote.
    _v("forme d'un N+1", verdict_requetes(87, 10)[0], "echec")
    # ⚠️ Le défaut visé : un ETag servi qui n'économise jamais rien.
    _v("ETag décoratif", verdict_revalidation(200, True)[0], "echec")

    # ── Doivent rester NON CONCLUANTS ────────────────────────────────────────
    # ⚠️ Le piège central : un 429 est rapide et flatterait le p50.
    _v("échantillon amputé", verdict_echantillon(3, 8)[0], "non_concluant")
    _v("aucun 200", verdict_echantillon(0, 8)[0], "non_concluant")
    _v("aucun appel", verdict_echantillon(0, 0)[0], "non_concluant")
    # ⚠️ L'absence de cache est une décision jamais prise, pas une panne.
    _v("aucun cache", verdict_cache({})[0], "non_concluant")
    _v("en-têtes illisibles", verdict_cache(None)[0], "non_concluant")
    _v("base injoignable", verdict_requetes(None, 10)[0], "non_concluant")
    _v("latence illisible", verdict_latence(None, 300)[0], "non_concluant")
    _v("poids illisible", verdict_poids(None, 8192)[0], "non_concluant")
    _v("compression illisible",
       verdict_compression(None, 2559, 2.0)[0], "non_concluant")
    _v("réponse gzip vide",
       verdict_compression(15516, 0, 2.0)[0], "non_concluant")
    # ⚠️ Le faux positif payé au premier passage : 89 o, sous le plancher.
    _v("trop petite pour être compressée",
       verdict_compression(89, 89, 2.0)[0], "non_concluant")
    _v("aucun ETag", verdict_revalidation(None, False)[0], "non_concluant")
    _v("ETag sans réponse conditionnelle",
       verdict_revalidation(None, True)[0], "non_concluant")
    _v("revalidation illisible",
       verdict_revalidation(304, None)[0], "non_concluant")
    _v("centile sans valeur", _percentile([], 95), None)

    refus = 21
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


# ─────────────────────────────────────────────────────────────────────────────

def main():
    print("═" * 76)
    print("  Performance — des chiffres, avant toute optimisation")
    print("═" * 76)
    print("  ⚠️ un appel à la fois, sans concurrence : ce n'est PAS un test de")
    print("     charge. Il répond à « cette route est-elle bien formée ? »")
    print("  seuils : p95 ≤ %.0f ms · compression ≥ ×%.1f · %d échantillons"
          % (SEUIL_P95_MS, SEUIL_COMPRESSION, ECHANTILLONS))

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-30s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    for chemin, budget, quoi in ROUTES:
        court = chemin.split("?")[0] + ("?…" if "?" in chemin else "")
        print("\n── %s — %s ──" % (court, quoi))

        # ⚠️ Appel de chauffe, jeté : connexion TCP, pool PostgreSQL froid,
        # cache de plan vide. Le taire ferait passer une mesure pour une autre.
        appeler(chemin)

        latences, tailles, entetes, reussites = [], [], None, 0
        for _ in range(ECHANTILLONS):
            st, taille, ms, ent = appeler(chemin)
            if st == 200:
                reussites += 1
                latences.append(ms)
                tailles.append(taille)
                entetes = ent
            time.sleep(0.12)

        noter("échantillon", *verdict_echantillon(reussites, ECHANTILLONS))
        if not latences:
            continue

        p50 = _percentile(latences, 50)
        print("     p50 = %.0f ms · p95 = %.0f ms · brut = %d o"
              % (p50, _percentile(latences, 95), tailles[0]))
        noter("latence", *verdict_latence(_percentile(latences, 95),
                                          SEUIL_P95_MS))

        st, taille_gzip, _, _ = appeler(chemin, gzip_=True)
        noter("compression",
              *verdict_compression(tailles[0],
                                   taille_gzip if st == 200 else None,
                                   SEUIL_COMPRESSION))
        noter("poids sur le fil",
              *verdict_poids(taille_gzip if st == 200 else None, budget))
        noter("cache HTTP", *verdict_cache(entetes))
        etag = (entetes or {}).get("etag")
        st_cond = appeler(chemin, conditionnel=etag)[0] if etag else None
        noter("revalidation", *verdict_revalidation(st_cond, bool(etag)))
        time.sleep(0.2)

    # ── La forme des requêtes SQL ───────────────────────────────────────────
    print("\n── transactions PostgreSQL par appel HTTP ──")
    if compter_transactions() is None:
        noter("sonde SQL", *verdict_requetes(None, 0))
    else:
        chemin = ROUTES[3][0]

        def delta_sur(intervalle_s, avec_appel):
            """Transactions écoulées pendant `intervalle_s`, appel compris."""
            avant = compter_transactions()
            if avec_appel:
                appeler(chemin)
            time.sleep(intervalle_s)
            apres = compter_transactions()
            if avant is None or apres is None:
                return None
            return apres - avant

        # ⚠️ **Un intervalle témoin, de même durée, SANS appel.** Sans lui on
        # mesure aussi les tâches de fond et les connexions que cette sonde
        # ouvre pour se lire elle-même — soit 15 transactions attribuées à un
        # appel qui en coûte 2. Trois répétitions de chaque côté : une mesure
        # unique de deux entiers bruités ne vaut rien.
        temoins, mesures = [], []
        for _ in range(3):
            t = delta_sur(0.6, False)
            m = delta_sur(0.6, True)
            if t is not None and m is not None:
                temoins.append(t)
                mesures.append(m)
        if not temoins:
            noter("sonde SQL", *verdict_requetes(None, 0))
        else:
            bruit = sum(temoins) / float(len(temoins))
            total = sum(mesures) / float(len(mesures))
            impute = max(0, int(round(total - bruit)))
            print("     bruit de fond %.1f · avec appel %.1f" % (bruit, total))
            # ⚠️ **15, et le chiffre est raisonné, pas confortable.** Le coût
            # imputé mesuré le 2026-08-13 oscille entre 2 et 5 selon les
            # passages — la déduction du bruit laisse un résidu de quelques
            # unités, et un seuil calé au ras basculerait au hasard. Un banc
            # qui alterne vert et rouge sans que rien ne change est pire
            # qu'absent : on cesse de le lire.
            #
            # Ce qu'on cherche n'est pas une unité près, c'est une FORME : un
            # N+1 sur les 53 commerçants d'un cadre en produirait cinquante et
            # plus. 15 laisse trois fois la marge du bruit et reste trois fois
            # sous la signature d'une boucle.
            noter("GET /promo/map", *verdict_requetes(impute, 15))

    print("\n" + "═" * 76)
    echecs = resultats.count("echec")
    non_concluants = resultats.count("non_concluant")
    print("%d contrôles, %d échec(s), %d non concluant(s)"
          % (len(resultats), echecs, non_concluants))
    if non_concluants and not echecs:
        print("⚠️  des sondes n'ont pas conclu : ce n'est pas une réussite.")
    return 1 if (echecs or non_concluants) else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)
    sys.exit(main())
