#!/usr/bin/env python3
"""Banc du point client — le point enregistré sépare-t-il vraiment deux villes ?

── Les deux scénarios du client, côté serveur ──────────────────────────────

Formulés le 2026-08-13 :

  1. un nouveau client a une ville par défaut avec ses promos ; il enregistre
     une position, et aux lancements suivants il est envoyé sur cette ville ;
  2. il explore la carte, choisit une autre ville, et on lui sert **les promos
     de cette ville-là**.

Les gestes (bandeau, consentement, recentrage) sont éprouvés par les parcours
d'écran. **Ce que ceux-ci ne peuvent pas prouver, c'est que le serveur sépare
les deux villes** : sur un décor où tout tient dans un rayon, un parcours
d'écran resterait vert avec un serveur qui ignore complètement le point.

── Pourquoi `client_rayon.py` ne couvre pas ce cas ─────────────────────────

Il éprouve la **géométrie** — que le cadre rectangulaire soit rogné par la
distance haversine, avec un point en diagonale dans le carré et hors du cercle.
C'est une propriété du calcul, mesurée sur des commerçants qu'il fabrique
lui-même autour d'un seul point.

Ici on éprouve autre chose : que **deux villes réelles du décor soient
mutuellement invisibles**. Djelfa et Hassi Bahbah sont à ~50 km, très au-delà
des 5 km du rayon servi — un client posé sur l'une ne doit voir aucun commerce
de l'autre. C'est la promesse produit, et c'est ce qu'un client vérifie en
premier.

⚠️ **Et un décor trop pauvre rend ce banc non concluant, pas vert.** Si une des
deux villes n'a aucune promo, la disjonction est vraie par vacuité : un serveur
qui ignore le point passerait (règle 38 — établir d'abord que la mesure pouvait
varier).

── La sonde qu'on n'attend pas ─────────────────────────────────────────────

Chaque promo servie doit porter **les coordonnées de son commerçant**
(`commercantLatitude` / `commercantLongitude`). L'app les décode pour placer la
promo sur la carte ; si le serveur ne les sert pas, le champ arrive `null`, la
promo n'est placée nulle part et **rien ne lève** — la carte est simplement plus
pauvre que la liste. C'est le défaut symétrique de la règle 31 : ici ce n'est
pas une route sans appelant, c'est un appelant sans donnée.

⚠️ La longitude 0 (Greenwich) est un vrai cas, et `if (lng)` la traiterait comme
absente. Ce banc distingue donc **absent** de **zéro**.

── Usage ──────────────────────────────────────────────────────────────────

    python3 scripts/lib/ville_client.py --self-test
    ./scripts/test-ville-client.sh

⚠️ Aucun décor à provisionner, aucune écriture, aucun identifiant : il lit une
route publique. Il suppose seulement que le décor à trois villes est en base.
"""

import json
import os
import sys
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")

# Les villes du décor. ⚠️ Ce ne sont PAS des valeurs attendues — ce sont les
# points où l'on va se placer pour interroger. Le banc n'affirme rien sur les
# noms des commerces : il compare des ensembles d'identifiants.
VILLES = [
    ("Djelfa", 34.6703, 3.2630),
    ("Hassi Bahbah", 35.0774, 3.0281),
    ("Alger", 36.7538, 3.0588),
]


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_separation(nom_a, ids_a, nom_b, ids_b):
    """⚠️ **La sonde centrale.** Deux villes éloignées doivent être disjointes.

    Trois issues distinctes, et il faut les trois :
      · un ensemble vide ⇒ non concluant (disjoint par vacuité) ;
      · deux ensembles identiques ⇒ le point n'est pas pris en compte du tout ;
      · un recouvrement partiel ⇒ le rayon déborde, ou le filtre est faux.
    """
    if ids_a is None or ids_b is None:
        return "non_concluant", "une des deux listes est illisible"
    if not ids_a or not ids_b:
        vide = nom_a if not ids_a else nom_b
        return ("non_concluant",
                "aucune promo autour de %s : la disjonction serait vraie par "
                "vacuité, et un serveur qui ignore le point passerait" % vide)
    if ids_a == ids_b:
        return ("echec",
                "%s et %s servent EXACTEMENT les mêmes %d promos : le point du "
                "client n'est pas pris en compte"
                % (nom_a, nom_b, len(ids_a)))
    commun = ids_a & ids_b
    if commun:
        return ("echec",
                "%d promo(s) servie(s) à la fois autour de %s et de %s, "
                "distantes de bien plus que le rayon — un client voit des "
                "promos d'une ville où il n'est pas"
                % (len(commun), nom_a, nom_b))
    return "ok", "%d promos ici, %d là, aucune en commun" % (
        len(ids_a), len(ids_b))


def verdict_sans_point(total_sans, total_au_defaut):
    """Sans coordonnées, le serveur doit appliquer SON point — pas tout servir.

    ⚠️ C'est ce que l'app envoie tant que le client n'a rien enregistré. Un
    serveur qui servirait tout le parc dans ce cas donnerait un premier écran
    plein de promos à 400 km, sans que rien ne le signale.
    """
    if total_sans is None or total_au_defaut is None:
        return "non_concluant", "un des deux totaux est illisible"
    if total_sans != total_au_defaut:
        return ("echec",
                "sans coordonnées le serveur sert %d promos, mais %d quand on "
                "lui passe explicitement son propre point par défaut — la "
                "requête sans point ne suit pas la configuration"
                % (total_sans, total_au_defaut))
    return "ok", "%d promos dans les deux cas" % total_sans


def verdict_coordonnees(items):
    """Chaque promo servie porte-t-elle la position de son commerçant ?

    ⚠️ Sans elle, l'app ne peut pas placer la promo sur la carte, et **rien ne
    lève** : la carte est juste plus pauvre que la liste. Le champ manquant est
    indiscernable d'un commerçant qui n'aurait pas de position.
    """
    if items is None:
        return "non_concluant", "réponse illisible"
    if not items:
        return "non_concluant", "aucune promo servie — rien à vérifier"
    # ⚠️ `is None`, jamais une évaluation de vérité : la longitude 0 (Greenwich)
    # est une coordonnée valide qu'un `if not lng` déclarerait absente.
    muettes = [
        i.get("id") for i in items
        if i.get("commercantLatitude") is None
        or i.get("commercantLongitude") is None
    ]
    if muettes:
        return ("echec",
                "%d promo(s) sur %d sans coordonnées de commerçant : l'app ne "
                "peut pas les placer sur la carte, et aucune erreur ne le dira"
                % (len(muettes), len(items)))
    return "ok", "les %d promos portent la position de leur commerce" % len(
        items)


def verdict_decor(villes_garnies):
    """⚠️ Le banc a-t-il de quoi juger ?

    Une seule ville garnie, et toutes les comparaisons deviennent des vacuités.
    On le dit au lieu de compter des contrôles réussis (règle 28).
    """
    if villes_garnies is None:
        return "non_concluant", "décor illisible"
    if len(villes_garnies) < 2:
        return ("non_concluant",
                "une seule ville garnie (%s) : aucune séparation n'est "
                "mesurable sur ce décor"
                % (villes_garnies[0] if villes_garnies else "aucune"))
    return "ok", "%d villes garnies : %s" % (
        len(villes_garnies), ", ".join(villes_garnies))


# ─────────────────────────────────────────────────────────────────────────────

def appeler(chemin):
    req = urllib.request.Request(API_URL + chemin)
    req.add_header("X-Device-Id", "banc-ville-0001")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read())
        except Exception:
            return e.code, {}
    except Exception:
        return None, {}


# ⚠️ **100 est le plafond serveur**, pas un choix de confort : `limit=200` rend
# `400 VALIDATION_ERROR` (« limit must not be greater than 100 »). Mesuré le
# 2026-08-13 — ce banc demandait 200 et rendait « liste illisible » sur trois
# contrôles, ce qui était le bon comportement : il a refusé au lieu de conclure.
PAGE_MAX = 100


def promos_autour(lat, lng):
    """Identifiants des promos servies autour d'un point, ou `None`.

    ⚠️ Rend aussi le total annoncé : au-delà d'une page, l'ensemble comparé est
    **tronqué** (règle 15). Une troncature ne peut pas inventer un recouvrement,
    mais elle peut en cacher un — donc elle se dit, elle ne se subit pas.
    """
    st, d = appeler(
        "/promo?limit=%d&latitude=%s&longitude=%s" % (PAGE_MAX, lat, lng))
    if st != 200:
        return None, None, None
    items = d.get("items")
    if items is None:
        return None, None, None
    return {i.get("id") for i in items}, items, d.get("total")


_ok = 0
_echecs = []


def _v(libelle, obtenu, attendu):
    global _ok
    if obtenu == attendu:
        _ok += 1
    else:
        _echecs.append("%s — attendu %r, obtenu %r" % (libelle, attendu, obtenu))


def self_test():
    a, b = {"p1", "p2"}, {"p3", "p4"}

    # ── Doivent PASSER ───────────────────────────────────────────────────────
    _v("villes disjointes", verdict_separation("A", a, "B", b)[0], "ok")
    _v("sans point = point par défaut", verdict_sans_point(44, 44)[0], "ok")
    _v("coordonnées présentes",
       verdict_coordonnees([{"id": "p1", "commercantLatitude": 34.6,
                             "commercantLongitude": 3.2}])[0], "ok")
    # ⚠️ Longitude 0 : Greenwich est une coordonnée valide, pas une absence.
    _v("longitude zéro acceptée",
       verdict_coordonnees([{"id": "p1", "commercantLatitude": 51.5,
                             "commercantLongitude": 0}])[0], "ok")
    _v("décor à deux villes", verdict_decor(["Djelfa", "Alger"])[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le défaut visé : le point du client n'est pas pris en compte.
    _v("mêmes promos partout",
       verdict_separation("A", a, "B", set(a))[0], "echec")
    _v("recouvrement partiel",
       verdict_separation("A", a, "B", {"p2", "p9"})[0], "echec")
    _v("sans point sert autre chose",
       verdict_sans_point(74, 44)[0], "echec")
    _v("latitude absente",
       verdict_coordonnees([{"id": "p1", "commercantLatitude": None,
                             "commercantLongitude": 3.2}])[0], "echec")
    _v("longitude absente",
       verdict_coordonnees([{"id": "p1", "commercantLatitude": 34.6}])[0],
       "echec")

    # ── Doivent rester NON CONCLUANTS ────────────────────────────────────────
    # ⚠️ Disjoint par vacuité : un serveur qui ignore le point passerait.
    _v("une ville vide", verdict_separation("A", a, "B", set())[0],
       "non_concluant")
    _v("liste illisible", verdict_separation("A", None, "B", b)[0],
       "non_concluant")
    _v("aucune promo à vérifier", verdict_coordonnees([])[0], "non_concluant")
    _v("items illisibles", verdict_coordonnees(None)[0], "non_concluant")
    _v("total illisible", verdict_sans_point(None, 44)[0], "non_concluant")
    _v("décor mono-ville", verdict_decor(["Djelfa"])[0], "non_concluant")
    _v("décor illisible", verdict_decor(None)[0], "non_concluant")

    refus = 12
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


# ─────────────────────────────────────────────────────────────────────────────

def main():
    print("═" * 68)
    print("  Point client — le point enregistré sépare-t-il deux villes ?")
    print("═" * 68)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-34s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    mesures = {}
    for nom, lat, lng in VILLES:
        ids, items, total = promos_autour(lat, lng)
        mesures[nom] = (ids, items)
        # ⚠️ Dit, jamais tu : un ensemble tronqué peut cacher un recouvrement.
        if total is not None and ids is not None and total > len(ids):
            print("  ⚠️  %s : %d promos annoncées, %d lues — la comparaison "
                  "porte sur une page seulement" % (nom, total, len(ids)))

    print("\n── 1. le décor permet-il de juger ? ──")
    garnies = [n for n, (ids, _) in mesures.items() if ids]
    noter("au moins deux villes garnies", *verdict_decor(garnies))

    # ── 2. Chaque paire de villes est mutuellement invisible ────────────────
    #
    # ⚠️ Toutes les paires, pas seulement la première : un serveur peut séparer
    # correctement deux villes et se tromper sur la troisième — et c'est
    # justement celle qu'on n'aurait pas regardée.
    print("\n── 2. deux villes éloignées sont mutuellement invisibles ──")
    for i in range(len(VILLES)):
        for j in range(i + 1, len(VILLES)):
            na, nb = VILLES[i][0], VILLES[j][0]
            noter("%s ⇄ %s" % (na, nb),
                  *verdict_separation(na, mesures[na][0], nb, mesures[nb][0]))

    # ── 3. Sans coordonnées, le serveur applique son propre point ───────────
    print("\n── 3. sans point enregistré, le serveur applique le sien ──")
    st, conf = appeler("/promo/config")
    st2, sans = appeler("/promo?limit=1")
    total_sans = sans.get("total") if st2 == 200 else None
    total_defaut = None
    if st == 200 and conf.get("defaultLatitude") is not None:
        s3, d3 = appeler("/promo?limit=1&latitude=%s&longitude=%s"
                         % (conf["defaultLatitude"], conf["defaultLongitude"]))
        total_defaut = d3.get("total") if s3 == 200 else None
    noter("GET /promo sans coordonnées",
          *verdict_sans_point(total_sans, total_defaut))

    # ── 4. Chaque promo peut être placée sur la carte ───────────────────────
    print("\n── 4. chaque promo porte la position de son commerce ──")
    for nom, (ids, items) in mesures.items():
        if ids:
            noter(nom, *verdict_coordonnees(items))

    print("\n" + "═" * 68)
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
