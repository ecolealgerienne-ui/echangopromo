#!/usr/bin/env python3
"""Banc du point par défaut — ce que voit un client qui vient d'installer l'app.

── Le défaut que ce banc éprouve, et il est écrit depuis des semaines ───────

`.env.example` porte cet avertissement, mot pour mot :

    ⚠️ Le pilote est à Djelfa, le défaut ci-dessous est Alger. Pendant le
    pilote, mettre 34.6703 / 3.2630 (Djelfa) : sinon un rayon de 5 km autour
    d'Alger rend la liste VIDE pour tout client qui n'a pas enregistré son
    point.

**Et c'est un commentaire.** Il ne peut pas échouer (règle 30). `.env.production
.example` porte les mêmes coordonnées d'Alger : qui le copie tel quel met en
production un serveur dont le premier écran est vide pour chaque nouvel
utilisateur — sans erreur, sans journal, sans rien qui distingue « aucune promo
près de vous » d'un produit qui marche.

⚠️ Le repli **codé** du serveur est Alger (`DEFAUT_CLIENT_LATITUDE`), et c'est
un choix délibéré, éprouvé par `promo.service.client-config.spec.ts`. Le repli
de l'app, lui, est **Djelfa** (`kPointDeRepliHorsLigne`). Deux replis, deux
villes : un client hors ligne voit Djelfa, le même client en ligne sur un
serveur non configuré voit Alger. Ce banc ne tranche pas cette divergence — il
la nomme.

── ⚠️ Ce qu'il éprouve est l'EFFET, pas le réglage ─────────────────────────

Comparer les coordonnées servies à une valeur attendue ne dit rien de ce qui
compte : ce qui compte est que **le premier écran ne soit pas vide**. Un point
juste sur une zone sans commerce échouerait au même endroit qu'un point faux, et
c'est le même dégât pour l'utilisateur.

D'où la sonde centrale : `GET /promo` **sans coordonnées** — exactement ce que
l'app envoie tant que le client n'a rien enregistré — doit rendre des promos.
Mesuré le 2026-08-13 : 74 promos existent en base, cette requête en rend 44. Le
serveur applique donc bel et bien son point et son rayon ; ce n'est pas une
route qui sert tout.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/defaut_client.py --self-test
    ATTENDU_LAT=34.6703 ATTENDU_LNG=3.2630 ./scripts/test-defaut-client.sh
"""

import json
import os
import sys
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")

# Le repli **codé** du serveur, quand aucune clé n'est configurée. Recopié ici
# pour une seule raison : reconnaître « on sert le repli » et le DIRE. Ce n'est
# pas une valeur attendue — l'attendue vient de l'appelant.
REPLI_SERVEUR = (36.7538, 3.0588)   # Alger, DEFAUT_CLIENT_LATITUDE/LONGITUDE
REPLI_APP = (34.6703, 3.2630)       # Djelfa, kPointDeRepliHorsLigne


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_premier_ecran(total):
    """⚠️ **La sonde qui compte.** Un premier écran vide n'est pas une erreur.

    Il ne lève rien, ne journalise rien, et se lit comme « il n'y a pas de promo
    près de chez vous ». Un client qui installe l'app et ne voit rien la
    désinstalle sans que personne n'apprenne pourquoi.
    """
    if total is None:
        return "non_concluant", "réponse illisible"
    if total == 0:
        return ("echec",
                "un client qui vient d'installer l'app ne verrait AUCUNE "
                "promo : le point par défaut du serveur pointe une zone sans "
                "commerce. Aucune erreur ne sera levée — l'écran dira "
                "simplement « rien près de vous »")
    return "ok", "%d promo(s) au premier lancement" % total


def verdict_point_declare(servi, attendu):
    """Le point servi est-il celui qu'on a déclaré pour cet environnement ?"""
    if servi is None:
        return "non_concluant", "GET /promo/config illisible"
    if attendu is None:
        return ("non_concluant",
                "aucun point attendu fourni — sans lui ce contrôle ne peut "
                "que constater ce qui est, jamais le refuser")
    if servi != attendu:
        return ("echec",
                "le serveur sert %s, on attendait %s — un client sans point "
                "enregistré cherche autour du mauvais lieu"
                % (servi, attendu))
    return "ok", "%s" % (servi,)


def verdict_replis(servi):
    """⚠️ Servir le repli codé est indiscernable d'une clé absente.

    `configNumber` journalise le repli, mais un banc ne lit pas les journaux du
    serveur — et personne ne les relit. Quand la valeur servie est exactement
    celle du repli, on ne peut pas savoir si elle a été **choisie** ou
    **subie** : c'est « non concluant », jamais « ok ».
    """
    if servi is None:
        return "non_concluant", "GET /promo/config illisible"
    if servi == REPLI_SERVEUR:
        return ("non_concluant",
                "le serveur sert exactement son repli codé %s : impossible de "
                "distinguer « configuré ainsi » de « CLIENT_DEFAULT_LATITUDE "
                "absente du .env qui tourne » (règle 36)" % (REPLI_SERVEUR,))
    if servi == REPLI_APP:
        return "ok", "point configuré, et il coïncide avec le repli de l'app"
    return ("ok",
            "point configuré %s — ⚠️ différent du repli hors ligne de l'app "
            "%s : un client sans réseau cadrera ailleurs" % (servi, REPLI_APP))


# ─────────────────────────────────────────────────────────────────────────────

def appeler(chemin):
    req = urllib.request.Request(API_URL + chemin)
    req.add_header("X-Device-Id", "banc-defaut-0001")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read())
        except Exception:
            return e.code, {}
    except Exception as e:
        return None, {"code": "RESEAU: %s" % e}


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
    _v("premier écran garni", verdict_premier_ecran(44)[0], "ok")
    _v("point conforme",
       verdict_point_declare((34.6703, 3.263), (34.6703, 3.263))[0], "ok")
    _v("point configuré = repli app", verdict_replis(REPLI_APP)[0], "ok")
    _v("point configuré ailleurs", verdict_replis((35.0, 2.0))[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le défaut visé : le premier écran de tout nouveau client est vide.
    _v("premier écran vide", verdict_premier_ecran(0)[0], "echec")
    _v("point différent du déclaré",
       verdict_point_declare(REPLI_SERVEUR, (34.6703, 3.263))[0], "echec")
    # ⚠️ Servir le repli codé ne se distingue pas d'une clé absente.
    _v("repli codé servi", verdict_replis(REPLI_SERVEUR)[0], "non_concluant")
    # ⚠️ Sans valeur attendue, ce contrôle constate mais ne refuse pas — il le
    # dit au lieu de passer au vert (règle 29).
    _v("aucun attendu fourni",
       verdict_point_declare((34.0, 3.0), None)[0], "non_concluant")
    _v("config illisible", verdict_point_declare(None, (34.0, 3.0))[0],
       "non_concluant")
    _v("total illisible", verdict_premier_ecran(None)[0], "non_concluant")
    _v("replis sur config illisible", verdict_replis(None)[0], "non_concluant")

    refus = 7
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


# ─────────────────────────────────────────────────────────────────────────────

def main():
    print("═" * 64)
    print("  Point par défaut — ce que voit un client qui vient d'installer")
    print("═" * 64)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-40s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    st, conf = appeler("/promo/config")
    servi = None
    if st == 200 and conf.get("defaultLatitude") is not None:
        servi = (conf["defaultLatitude"], conf["defaultLongitude"])

    attendu = None
    la, ln = os.environ.get("ATTENDU_LAT"), os.environ.get("ATTENDU_LNG")
    if la and ln:
        attendu = (float(la), float(ln))

    print("\n── 1. le point servi est celui qu'on a déclaré ──")
    noter("GET /promo/config", *verdict_point_declare(servi, attendu))

    print("\n── 2. configuré, ou subi ? ──")
    noter("le point ne vient pas d'un repli", *verdict_replis(servi))

    # ── 3. L'effet, et c'est lui qui compte ─────────────────────────────────
    #
    # ⚠️ Sans latitude ni longitude — exactement ce que l'app envoie tant que le
    # client n'a rien enregistré. Le serveur applique alors SON point et SON
    # rayon.
    print("\n── 3. le premier écran d'un nouveau client n'est pas vide ──")
    st, liste = appeler("/promo?limit=1")
    noter("GET /promo sans coordonnées",
          *verdict_premier_ecran(liste.get("total") if st == 200 else None))

    if servi and conf.get("defaultRadiusKm"):
        print("\n   rayon servi : %s km — c'est lui qui borne ce premier écran"
              % conf["defaultRadiusKm"])

    print("\n" + "═" * 64)
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
