# -*- coding: utf-8 -*-
"""À partir de combien de commerçants le choix d'index commence-t-il à payer ?

⚠️ **Ce n'est PAS un banc.** Il ne rend aucun verdict et ne peut donc rien
refuser : il produit un tableau, qu'un humain lit. Le confondre avec un contrôle
serait exactement le genre d'erreur que ce dépôt traque — un outil qui rassure
sans jamais pouvoir dire non. Les contrôles de cette zone sont
`test-plan-sql.sh` et `test-perf.sh`.

── La question à laquelle il répond ────────────────────────────────────────

La bascule du 2026-08-13 (btree → GiST) n'a produit **aucun effet mesurable** sur
les temps de réponse : à 156 commerçants, PostgreSQL parcourt la table sans
consulter d'index. Restait la seule question qui vaille — *à partir de quelle
taille cette décision paie-t-elle ?*

── ⚠️ La répartition change tout, et la première version le manquait ───────

`uniforme` étale les commerçants au hasard sur le nord de l'Algérie. Mesuré :
**aucun gain**, les deux index font jeu égal. C'est logique — une bande de
latitude y contient une part proportionnelle du parc, donc filtrer sur la seule
latitude suffit déjà. Ce cas est **favorable au btree**.

`villes` les groupe autour de soixante centres urbains **alignés en latitude**,
comme le sont réellement Djelfa, Laghouat, Bou Saada ou Aflou sur les hauts
plateaux. Une bande de latitude en traverse alors plusieurs d'un coup.

⚠️ Une première version répartissait les villes sur une grille dont **aucune ne
tombait dans la bande de latitude mesurée** : le tableau montrait une parfaite
égalité, parce qu'il ne mesurait rien d'autre que la taille de l'index. Un
générateur de décor qui rate sa cible produit un résultat parfaitement lisible
et parfaitement vide.

── Ce qui a été mesuré, trois passages concordants (2026-08-13) ────────────

    commerçants     GiST (en place)     btree (ancien)
    156             0,08 ms             0,06 ms
    5 156           0,08 – 0,11 ms      0,07 – 0,10 ms
    25 156          0,08 – 0,13 ms      0,15 – 0,22 ms
    100 156         0,10 – 0,13 ms      0,33 – 0,39 ms
    400 156         0,12 – 0,14 ms      0,85 – 1,23 ms

Le GiST reste **plat** pendant que la table est multipliée par 2 500 ; le btree
se dégrade jusqu'à **sept à neuf fois plus lent**. La bascule commence à payer
vers **25 000 commerçants**, et devient structurante au-delà de 100 000.

⚠️ Données synthétiques, tout en mémoire, un point de mesure par palier. Ce qui
est solide est la **forme des deux courbes** — l'une plate, l'autre croissante —
pas les millisecondes au centième.

⚠️ Tout se passe dans une transaction ANNULÉE : les commerçants synthétiques
sont insérés, mesurés, puis disparaissent. Une vérification finale contrôle que
la base est rendue telle quelle **et** que l'index de production est revenu.

── Usage ───────────────────────────────────────────────────────────────────

    python3 scripts/lib/echelle_geo.py uniforme
    python3 scripts/lib/echelle_geo.py villes
"""
import math
import re
import sys

import psycopg2

LAT, LNG, RAYON = 34.6703, 3.2630, 5.0
DEG_KM = 111.32
PALIERS = [0, 5_000, 25_000, 100_000, 400_000]

dlat = RAYON / DEG_KM
dlng = RAYON / (DEG_KM * max(math.cos(math.radians(LAT)), 0.01))
P = dict(south=LAT - dlat, north=LAT + dlat, west=LNG - dlng, east=LNG + dlng)

CADRE_GIST = """select c.id from commercant c
 where c."deletedAt" is null
   and point(c.longitude, c.latitude)
       <@ box(point(%(west)s,%(south)s), point(%(east)s,%(north)s))"""

CADRE_BTREE = """select c.id from commercant c
 where c."deletedAt" is null
   and c.latitude between %(south)s and %(north)s
   and c.longitude between %(west)s and %(east)s"""

# ⚠️ **Deux répartitions, et c'est tout l'intérêt.**
#
# `uniforme` étale les commerçants au hasard sur le nord de l'Algérie. C'est le
# cas FAVORABLE au btree : une bande de latitude y contient une part
# proportionnelle du parc, donc filtrer sur la seule latitude suffit déjà.
#
# `villes` les groupe autour de trente centres urbains, comme un parc réel. Une
# bande de latitude y traverse alors PLUSIEURS villes d'un coup — et c'est là
# que ne restreindre que sur une dimension coûte cher.
PEUPLER_UNIFORME = """insert into commercant
  (telephone, nom, categorie, "accountState", "originVerification",
   latitude, longitude)
select '+2135' || lpad(g::text, 8, '0'),
       'Synthetique ' || g,
       'alimentation'::commercant_categorie_enum,
       'cree_agent'::commercant_accountstate_enum,
       'confirme_agent'::commercant_originverification_enum,
       32 + random() * 5,
       -2 + random() * 10
  from generate_series(1, %s) g"""

# ⚠️ **Les villes sont ALIGNÉES EN LATITUDE, et c'est le point.** Une première
# version les répartissait sur une grille dont aucune ne tombait dans la bande
# de latitude mesurée : le tableau montrait alors une parfaite égalité, parce
# qu'il ne mesurait rien d'autre que la taille de l'index.
#
# La géographie réelle est celle-ci : les villes des hauts plateaux — Djelfa,
# Laghouat, Bou Saada, Aflou — s'étalent d'est en ouest à des latitudes
# voisines. Une bande de latitude en traverse donc plusieurs d'un coup, et c'est
# exactement là qu'un index qui ne restreint qu'une dimension paie le prix fort.
#
# Six lignes de latitude, dix villes chacune étalées en longitude, la ligne
# centrale passant PAR le point de mesure. Chaque ville tient dans ~12 km.
PEUPLER_VILLES = """insert into commercant
  (telephone, nom, categorie, "accountState", "originVerification",
   latitude, longitude)
select '+2135' || lpad(g::text, 8, '0'),
       'Synthetique ' || g,
       'alimentation'::commercant_categorie_enum,
       'cree_agent'::commercant_accountstate_enum,
       'confirme_agent'::commercant_originverification_enum,
       v.lat + (random() - 0.5) * 0.22,
       v.lng + (random() - 0.5) * 0.26
  from generate_series(1, %s) g
  join lateral (
    select 34.6703 + (((g %% 60) / 10) - 2) * 1.1 as lat,
           -2.0 + ((g %% 60) %% 10) * 1.15 as lng
  ) v on true"""


def lignes(plan, motif):
    for l in plan:
        if motif in l:
            m = re.search(r"rows=(\d+)", l)
            if m:
                return int(m.group(1))
    return None


def acces(plan):
    for l in plan:
        if "Seq Scan on commercant" in l:
            return "Seq Scan"
        if "Index Scan" in l and "commercant" in l:
            return "Index"
        if "Bitmap Index Scan" in l:
            return "Index"
    return "?"


REPARTITION = None


def main():
    global REPARTITION
    mode = sys.argv[1] if len(sys.argv) > 1 else "uniforme"
    REPARTITION = PEUPLER_VILLES if mode == "villes" else PEUPLER_UNIFORME
    cx = psycopg2.connect(host="localhost", port=5433, user="echango",
                          password="echango", dbname="echango_promo")
    cur = cx.cursor()
    cur.execute("select count(*) from commercant")
    base = cur.fetchone()[0]

    print("=" * 78)
    print("  A quelle taille le choix d'index paye ? — repartition : %s" % mode)
    print("=" * 78)
    print("  base reelle : %d commercants — tout ce qui suit est ANNULE\n" % base)
    print("  %-12s %-28s %-28s" % ("commercants", "GiST (en place)",
                                   "btree (ancien)"))
    print("  " + "-" * 74)

    for ajout in PALIERS:
        cur.execute("savepoint p")
        if ajout:
            cur.execute(REPARTITION, (ajout,))
        cur.execute("analyze commercant")
        cur.execute("select count(*) from commercant")
        total = cur.fetchone()[0]

        cur.execute("explain (analyze, costs off) " + CADRE_GIST, P)
        pg = [l for (l,) in cur.fetchall()]
        ms_g = float(re.search(r"Execution Time: ([\d.]+)", pg[-1]).group(1))
        n_g = lignes(pg, "IDX_commercant_position")

        # L'ancien index, seul : sinon le planificateur reprend le GiST pour le
        # seul prédicat partiel et on mesurerait deux fois la même chose.
        cur.execute('drop index "IDX_commercant_position"')
        cur.execute("""create index bt on commercant (latitude, longitude)
                       where latitude is not null and longitude is not null""")
        cur.execute("analyze commercant")
        cur.execute("explain (analyze, costs off) " + CADRE_BTREE, P)
        pb = [l for (l,) in cur.fetchall()]
        ms_b = float(re.search(r"Execution Time: ([\d.]+)", pb[-1]).group(1))
        n_b = lignes(pb, "bt")

        print("  %-12s %-28s %-28s"
              % (total,
                 "%-9s %7.2f ms %s" % (acces(pg), ms_g,
                                       ("%d l." % n_g) if n_g else ""),
                 "%-9s %7.2f ms %s" % (acces(pb), ms_b,
                                       ("%d l." % n_b) if n_b else "")))
        cur.execute("rollback to savepoint p")

    cx.rollback()
    cur2 = cx.cursor()
    cur2.execute("select count(*) from commercant")
    apres = cur2.fetchone()[0]
    cur2.execute("select count(*) from pg_indexes where indexname in "
                 "('bt','IDX_commercant_position')")
    idx = cur2.fetchone()[0]
    print("\n  base rendue telle quelle : %d commercants (%d au depart), "
          "index de production present : %s"
          % (apres, base, "oui" if idx == 1 else "NON — ALERTE"))
    return 0 if (apres == base and idx == 1) else 1


if __name__ == "__main__":
    sys.exit(main())
