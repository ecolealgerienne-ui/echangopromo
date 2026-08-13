#!/usr/bin/env python3
"""Banc du plan SQL — la FORME de la requête géographique, pas sa durée du jour.

── Pourquoi la forme, et pas le temps ──────────────────────────────────────

`banc_perf` mesure des millisecondes : 12 ms en p50 sur la liste. À 310 promos
et 154 commerçants, **ce chiffre ne dit rien** — un parcours séquentiel complet
de deux petites tables est instantané. Le jour où le parc grossit, le même code
peut passer de 12 ms à plusieurs secondes sans qu'une ligne ait changé.

Ce banc regarde donc ce qui ne dépend pas de la taille du jour : **quels index
la requête emprunte, et combien de lignes ils écartent avant la lecture de
table.**

── ⚠️ La reconstitution est VALIDÉE, sinon elle ne vaut rien ───────────────

TypeORM construit la requête ; ce banc la réécrit en SQL pour pouvoir
l'`EXPLAIN`. Une réécriture approximative produirait un plan crédible et faux —
le pire des résultats, puisqu'on partirait optimiser la mauvaise requête.

D'où la première sonde, et elle est bloquante : **le nombre de lignes rendues
par la reconstitution doit égaler le `total` servi par l'API** pour le même
point. Mesuré le 2026-08-13 : 44 des deux côtés. Si les deux divergent, tout ce
qui suit est déclaré sans valeur (règle 38).

── Ce que le plan a montré, et qui contredit un commentaire du code ────────

`promo.service.ts` affirme : « C'est ce `BETWEEN`, et lui seul, qui emprunte
`IDX_commercant_position` ». **Le plan réel montre un `Seq Scan` sur
`commercant`**, 101 lignes écartées sur 154. Le commentaire n'est pas faux sur
l'intention — il est faux sur ce qui se passe.

Et c'est **correct** de la part de PostgreSQL : à 154 lignes tenant dans 6
blocs, un parcours séquentiel bat n'importe quel index. Le vrai risque n'est pas
là. Il est que **personne ne saurait dire si l'index sert un jour**, et un
commentaire ne peut pas échouer (règle 30).

── Le défaut de fond, et la décision qui l'a fermé ─────────────────────────

Un btree `(latitude, longitude)` ne restreint que sur sa **première** colonne :
la longitude n'y est qu'un filtre appliqué après coup, à l'intérieur de l'index.
Sur un cadre de 5 km, il remontait **101 lignes sur 154** là où 53
correspondent.

Ce banc a d'abord servi à **mesurer** l'alternative — index GiST créé puis
annulé par ROLLBACK — et à porter la décision :

    btree (latitude, longitude)          101 lignes remontées
    gist  (point(longitude, latitude))    53 lignes remontées   ← les 53 justes

**La bascule a été faite le 2026-08-13** (`CommercantPositionGistIndex`), et les
rôles se sont inversés : c'est désormais l'ANCIEN btree qui est recréé dans une
transaction annulée, pour que le gain reste **mesuré** plutôt que raconté. Un
chiffre écrit dans un commentaire n'aurait pas bronché le jour où quelqu'un
revient en arrière (règle 30).

Pas de PostGIS : `point` et l'opérateur `<@ box` sont natifs, avec un opclass
GiST fourni en standard.

⚠️ **La reconstitution suit la requête réelle**, `point(...) <@ box(...)`. Tant
qu'elle portait les deux `BETWEEN`, elle rendait le même nombre de lignes — donc
la sonde de fidélité restait verte — tout en faisant analyser un plan que le
produit ne produit plus. Le piège que ce banc dénonce, retourné contre lui-même.

── Usage ───────────────────────────────────────────────────────────────────

    python3 scripts/lib/plan_sql.py --self-test
    ./scripts/test-plan-sql.sh

⚠️ Exige PostgreSQL joignable (`psycopg2`) **et** le backend en ligne : la
validation compare la reconstitution à ce que l'API sert réellement.
⚠️ N'écrit rien : l'index de comparaison est créé dans une transaction annulée.
"""

import json
import math
import os
import re
import sys
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PG = dict(host=os.environ.get("PGHOST", "localhost"),
          port=int(os.environ.get("PGPORT", "5433")),
          user=os.environ.get("PGUSER", "echango"),
          password=os.environ.get("PGPASSWORD", "echango"),
          dbname=os.environ.get("PGDATABASE", "echango_promo"))

LAT = float(os.environ.get("PLAN_LAT", "34.6703"))
LNG = float(os.environ.get("PLAN_LNG", "3.2630"))
RAYON = float(os.environ.get("PLAN_RAYON_KM", "5"))

# Recopié de `promo.service.ts` — 111.32 km par degré de latitude, et un degré
# de longitude qui rétrécit avec le cosinus de la latitude.
DEG_KM = 111.32


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_fidelite(reconstitution, api):
    """⚠️ **Bloquante.** Un plan tiré d'une requête approximative est pire
    qu'aucun plan : il est crédible et il envoie optimiser ailleurs."""
    if reconstitution is None or api is None:
        return "non_concluant", "une des deux mesures est illisible"
    if reconstitution != api:
        return ("echec",
                "la reconstitution rend %d promos, l'API %d — le plan analysé "
                "n'est PAS celui du produit, et tout ce qui suit serait faux"
                % (reconstitution, api))
    return "ok", "%d promos des deux côtés — le plan analysé est le bon" % api


def verdict_index_emprunte(plan, index_attendu):
    """La table doit être atteinte par un index, pas parcourue en entier."""
    if plan is None:
        return "non_concluant", "plan illisible"
    if index_attendu in plan:
        return "ok", "%s emprunté" % index_attendu
    if "Seq Scan" in plan:
        return ("echec",
                "parcours séquentiel : aucun index n'est emprunté, et le coût "
                "croîtra avec la table entière")
    return "non_concluant", "ni %s ni Seq Scan reconnus" % index_attendu


def verdict_index_utilisable(emprunte_si_force):
    """⚠️ Distingue « le planificateur n'en veut pas » de « il ne peut pas ».

    À 154 lignes, PostgreSQL préfère un parcours séquentiel et **il a raison**.
    Ce qu'on veut savoir est autre chose : l'index serait-il capable de servir
    cette requête le jour où la table grossit ? Un index inutilisable pour la
    forme de la requête resterait invisible jusqu'à ce moment-là.
    """
    if emprunte_si_force is None:
        return "non_concluant", "plan forcé illisible"
    if not emprunte_si_force:
        return ("echec",
                "même seqscan désactivé, l'index géographique n'est PAS "
                "emprunté : il ne sait pas servir cette requête, et il ne la "
                "servira pas davantage à un million de lignes")
    return "ok", "utilisable — le planificateur le prendra dès qu'il y aura intérêt"


def verdict_selectivite(btree_lignes, gist_lignes, justes):
    """⚠️ L'index en place ne doit remonter QUE les lignes du cadre.

    Un btree `(lat, lng)` ne restreint que sur sa première colonne : la
    longitude n'y est qu'un filtre interne. Le GiST sur `point(lng, lat)`
    restreint en deux dimensions, et doit donc remonter exactement les lignes
    contenues dans la boîte.

    ⚠️ **Le sens de ce verdict s'est inversé le 2026-08-13.** Il constatait un
    écart à combler ; il garde maintenant un gain acquis. Le jour où quelqu'un
    revient au btree, `gist_lignes` remontera et ce contrôle le dira — un
    chiffre écrit dans un commentaire, lui, n'aurait pas bronché (règle 30).
    """
    if btree_lignes is None or gist_lignes is None:
        return "non_concluant", "une des deux mesures est illisible"
    if justes and gist_lignes > justes:
        return ("echec",
                "l'index remonte %d lignes pour %d réellement dans le cadre : "
                "il ne restreint pas en deux dimensions" % (gist_lignes, justes))
    if btree_lignes <= gist_lignes:
        return ("non_concluant",
                "l'ancien btree remontait %d lignes, l'index en place %d — le "
                "gain mesuré le 2026-08-13 a disparu, ou le cadre choisi ne "
                "permet plus de le voir" % (btree_lignes, gist_lignes))
    return ("ok",
            "%d lignes remontées pour %d dans le cadre ; l'ancien btree en "
            "remontait %d, soit %d lues puis jetées à chaque requête"
            % (gist_lignes, justes, btree_lignes, btree_lignes - gist_lignes))


def verdict_propre(index_restants):
    """L'index de comparaison ne doit RIEN laisser en base."""
    if index_restants is None:
        return "non_concluant", "vérification impossible"
    if index_restants:
        return ("echec",
                "%d index de comparaison laissé(s) en base : ce banc a modifié "
                "le schéma qu'il devait seulement mesurer" % index_restants)
    return "ok", "aucun index laissé — transaction annulée"


# ─────────────────────────────────────────────────────────────────────────────

def cadre(lat, lng, rayon):
    dlat = rayon / DEG_KM
    dlng = rayon / (DEG_KM * max(math.cos(math.radians(lat)), 0.01))
    return dict(south=lat - dlat, north=lat + dlat,
                west=lng - dlng, east=lng + dlng)


DISTANCE = """(6371 * acos(LEAST(1, GREATEST(-1,
      sin(radians(%(lat)s)) * sin(radians(c.latitude))
      + cos(radians(%(lat)s)) * cos(radians(c.latitude))
      * cos(radians(c.longitude) - radians(%(lng)s))))))"""

# ⚠️ **Le cadre s'écrit `point(...) <@ box(...)` depuis le 2026-08-13**, et
# cette reconstitution DOIT suivre. Tant qu'elle portait les deux `BETWEEN`,
# elle rendait le même nombre de lignes — donc la sonde de fidélité restait
# verte — tout en faisant analyser un plan que le produit ne produit plus.
# C'est exactement le piège que ce banc dénonce, retourné contre lui-même.
CADRE = ("""point(c.longitude, c.latitude)
       <@ box(point(%(west)s,%(south)s), point(%(east)s,%(north)s))""")

LISTE = ("""select p.id from promo p
  inner join commercant c on c.id = p."commercantId"
 where p."lifecycleStatus" = 'publiee'
   and p."moderationStatus" in ('normale','verifiee_ok')
   and p."dateFin" > NOW()
   and c."deletedAt" is null
   and """ + CADRE + "\n   and " + DISTANCE + " <= %(rayon)s")

# Le cadre seul, pour mesurer ce que l'index remonte avant tout filtrage.
CADRE_SEUL = ("""select c.id from commercant c
 where c."deletedAt" is null
   and """ + CADRE)

# ⚠️ L'ancien btree, conservé pour que le gain reste MESURÉ et non raconté.
# Il est créé dans une transaction annulée, exactement comme le GiST l'était
# avant la bascule — les rôles sont simplement inversés.
CADRE_BTREE = """select c.id from commercant c
 where c."deletedAt" is null
   and c.latitude between %(south)s and %(north)s
   and c.longitude between %(west)s and %(east)s"""


def _lignes_du_scan(plan, motif):
    for ligne in plan:
        if motif in ligne:
            m = re.search(r"rows=(\d+)", ligne)
            if m:
                return int(m.group(1))
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
    _v("reconstitution fidèle", verdict_fidelite(44, 44)[0], "ok")
    _v("index emprunté",
       verdict_index_emprunte("Bitmap Index Scan on IDX_x", "IDX_x")[0], "ok")
    _v("index utilisable", verdict_index_utilisable(True)[0], "ok")
    # ⚠️ Le gain acquis : le GiST remonte les 53 justes, le btree en remontait
    # 101. C'était « non concluant » avant la bascule ; c'est « ok » depuis.
    _v("gain acquis", verdict_selectivite(101, 53, 53)[0], "ok")
    _v("base rendue propre", verdict_propre(0)[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le défaut le plus grave : analyser une requête qui n'est pas la bonne.
    _v("reconstitution divergente", verdict_fidelite(44, 62)[0], "echec")
    _v("parcours séquentiel",
       verdict_index_emprunte("Seq Scan on promo p", "IDX_x")[0], "echec")
    # ⚠️ Un index que le planificateur ne peut PAS prendre, même forcé.
    _v("index inutilisable", verdict_index_utilisable(False)[0], "echec")
    _v("index laissé en base", verdict_propre(1)[0], "echec")

    # ── Doivent rester NON CONCLUANTS ────────────────────────────────────────
    # ⚠️ L'écart de sélectivité n'est pas un défaut : c'est une décision produit.
    # ⚠️ Le retour en arrière : plus aucun écart entre les deux index.
    _v("gain disparu", verdict_selectivite(53, 53, 53)[0], "non_concluant")
    # ⚠️ Deux mesures qui ne portent pas sur la même chose ne se comparent pas.
    # ⚠️ Le défaut visé : l'index ne restreint pas en deux dimensions.
    _v("index qui déborde du cadre",
       verdict_selectivite(101, 90, 53)[0], "echec")
    _v("fidélité illisible", verdict_fidelite(None, 44)[0], "non_concluant")
    _v("plan illisible", verdict_index_emprunte(None, "IDX_x")[0],
       "non_concluant")
    _v("plan méconnaissable",
       verdict_index_emprunte("Nested Loop", "IDX_x")[0], "non_concluant")
    _v("plan forcé illisible",
       verdict_index_utilisable(None)[0], "non_concluant")
    _v("sélectivité illisible",
       verdict_selectivite(None, 53, 53)[0], "non_concluant")
    _v("nettoyage invérifiable", verdict_propre(None)[0], "non_concluant")

    refus = 13
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


# ─────────────────────────────────────────────────────────────────────────────

def main():
    try:
        import psycopg2
    except ImportError:
        # ⚠️ **Ce message disait « ou lancer ce banc depuis WSL », et c'était
        # un mauvais conseil** : WSL n'a ni `pip` ni `psql`, et `apt` y demande
        # un mot de passe. C'est le clone **Windows** qui porte le pilote, et
        # la base est la même dans les deux cas — un seul conteneur, publié sur
        # le port 5433. Envoyer quelqu'un changer de machine pour joindre la
        # même base coûte une demi-heure et ne mesure rien de plus.
        print("❌ psycopg2 absent — `pip install psycopg2-binary`. "
              "L'absence de verdict n'est pas un verdict.")
        return 2

    print("═" * 74)
    print("  Plan SQL — la FORME de la requête géographique, pas sa durée")
    print("═" * 74)
    print("  point %s, %s · rayon %s km" % (LAT, LNG, RAYON))

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-32s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    p = dict(lat=LAT, lng=LNG, rayon=RAYON, **cadre(LAT, LNG, RAYON))
    cx = psycopg2.connect(**PG)
    cur = cx.cursor()

    def plan(sql, forcer=False):
        cur.execute("set enable_seqscan = %s" % ("off" if forcer else "on"))
        cur.execute("explain (analyze, costs off) " + sql, p)
        return [l for (l,) in cur.fetchall()]

    # ── 1. La reconstitution est-elle celle du produit ? ────────────────────
    print("\n── 1. la requête analysée est bien celle du produit ──")
    cur.execute(LISTE, p)
    mien = len(cur.fetchall())
    try:
        req = urllib.request.Request(
            "%s/promo?limit=1&latitude=%s&longitude=%s" % (API_URL, LAT, LNG))
        req.add_header("X-Device-Id", "banc-plan-0001")
        api = json.loads(urllib.request.urlopen(req, timeout=20).read())["total"]
    except Exception:
        api = None
    noter("reconstitution vs API", *verdict_fidelite(mien, api))
    if mien != api:
        print("\n⚠️  tout ce qui suit serait tiré d'une requête qui n'est pas "
              "celle du produit — arrêt.")
        return 1

    # ── 2. Le plan réel ─────────────────────────────────────────────────────
    print("\n── 2. le plan réel de la liste ──")
    reel = "\n".join(plan(LISTE))
    noter("côté promo", *verdict_index_emprunte(reel, "Bitmap Index Scan"))
    if "Seq Scan on commercant" in reel:
        print("     ⚠️ côté commerçant : Seq Scan — correct à cette taille "
              "(154 lignes, 6 blocs), et c'est justement pourquoi le temps du "
              "jour n'apprend rien")

    # ── 3. L'index géographique est-il utilisable ? ─────────────────────────
    print("\n── 3. l'index géographique est-il seulement utilisable ? ──")
    force = "\n".join(plan(LISTE, forcer=True))
    noter("seqscan désactivé",
          *verdict_index_utilisable("IDX_commercant_position" in force))

    # ── 4. Ce que l'index en place remonte, et ce que l'ancien remontait ──
    print("\n── l'index remonte-t-il seulement le cadre ? ──")
    n_gist = _lignes_du_scan(plan(CADRE_SEUL, forcer=True),
                             "IDX_commercant_position")
    cur.execute("select count(*) from commercant c where c.\"deletedAt\" is null"
                " and " + CADRE, p)
    justes = cur.fetchone()[0]

    # ⚠️ L'ANCIEN index est recréé dans une transaction **annulée**, sous un
    # autre nom : c'est la seule façon de garder le gain mesuré plutôt que
    # raconté. Un chiffre écrit dans un commentaire ne peut pas échouer le jour
    # où quelqu'un revient au btree (règle 30).
    cur.execute("savepoint avant_btree")
    cur.execute("""create index banc_plan_btree on commercant (latitude, longitude)
                   where latitude is not null and longitude is not null""")
    cur.execute("analyze commercant")
    n_btree = _lignes_du_scan(plan(CADRE_BTREE, forcer=True),
                              "banc_plan_btree")
    cur.execute("rollback to savepoint avant_btree")
    cx.rollback()

    noter("sélectivité", *verdict_selectivite(n_btree, n_gist, justes))
    print("     %s commerçants dans le cadre ; l'index en place en remonte %s, "
          "l'ancien btree %s" % (justes, n_gist, n_btree))

    cur2 = cx.cursor()
    cur2.execute("select count(*) from pg_indexes "
                 "where indexname = 'banc_plan_gist'")
    noter("base rendue telle quelle", *verdict_propre(cur2.fetchone()[0]))
    cx.close()

    print("\n" + "═" * 74)
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
