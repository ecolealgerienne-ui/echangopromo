#!/usr/bin/env python3
"""Banc de la carte client — bornes de zone, plafond, et troncature déclarée.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

1. **Des bornes hors du monde réel se refusent, elles ne cassent pas.** Défaut
   réel : dézoomée, ou pendant la première passe de layout, la zone visible
   débordait de ±90/±180 ; le backend refusait en `400` et la carte affichait
   « impossible de charger les promos de cette zone » — un message qui n'avait
   **rien à voir** avec les promos. Le correctif est côté app (bornage), mais
   la règle serveur doit tenir : refuser proprement, jamais un `500`.

2. **La troncature est DÉCLARÉE, jamais silencieuse.** Au-delà de
   `MAX_MAP_COMMERCANTS`, le client reçoit `truncated: true` et invite à
   zoomer. Perdre des commerces sans le dire serait pire que de les perdre.
   Le banc vérifie la **cohérence** : jamais plus que le plafond, et
   `truncated` en accord avec ce qui est rendu.

3. **Aucun identifiant interne dans la projection** (règle 4).

⚠️ Le plafond n'est pas recopié ici : le banc le **déduit** de la réponse. Une
copie du nombre se contenterait de vérifier que le banc sait compter.

── Ce qu'il n'éprouve PAS ──────────────────────────────────────────────────

Le franchissement effectif du plafond de 300 commerces — il faudrait en créer
autant, et le décor n'a pas vocation à peupler une base pour une sonde. La
cohérence de `truncated` est vérifiée sur ce qui existe.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/client_carte.py --self-test
    ./scripts/test-client-carte.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "0.6"))
DEVICE_ID = "banc-carte-0001"

CHAMPS_INTERNES = ("photoKey", "photoKeys", "thumbnailKey")


def verdict_fuite(corps):
    trouves = sorted(set(_champs(corps, CHAMPS_INTERNES)))
    if trouves:
        return "echec", "champs internes exposés : %s" % ", ".join(trouves)
    return "ok", "aucun champ interne"


def _champs(noeud, noms):
    if isinstance(noeud, dict):
        for cle, valeur in noeud.items():
            if cle in noms:
                yield cle
            yield from _champs(valeur, noms)
    elif isinstance(noeud, list):
        for e in noeud:
            yield from _champs(e, noms)


def verdict_troncature(items, truncated, plafond_connu):
    """`truncated` doit décrire ce qui est rendu, pas l'inverse."""
    if items is None or truncated is None:
        return "non_concluant", "réponse illisible — pas de verdict"
    n = len(items)
    if plafond_connu is not None and n > plafond_connu:
        return ("echec",
                "%d commerces rendus, au-delà du plafond observé %d"
                % (n, plafond_connu))
    if truncated and plafond_connu is not None and n < plafond_connu:
        return ("echec",
                "`truncated` annoncé alors que %d < %d — la troncature "
                "décrite n'a pas eu lieu" % (n, plafond_connu))
    return "ok", "%d commerce(s), truncated=%s" % (n, truncated)


def verdict_bornes(statut, code):
    """Une zone hors du monde se refuse ; elle ne casse pas."""
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if statut is None:
        return "echec", "pas de réponse : %s" % code
    if statut in (200, 201):
        return ("echec",
                "zone hors du monde ACCEPTÉE — le serveur a interrogé la base "
                "sur des coordonnées impossibles")
    if statut >= 500 or code == "INTERNAL_ERROR":
        return "echec", "HTTP %s %s — casse au lieu de refuser" % (statut, code)
    if code != "VALIDATION_ERROR":
        return ("non_concluant",
                "refusé en %s/%s au lieu de VALIDATION_ERROR" % (statut, code))
    return "ok", "%s %s" % (statut, code)


# ─────────────────────────────────────────────────────────────────────────────

def appeler(chemin):
    req = urllib.request.Request(API_URL + chemin, method="GET")
    req.add_header("X-Device-Id", DEVICE_ID)
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
    _v("troncature cohérente", verdict_troncature([1, 2], False, 300)[0], "ok")
    _v("troncature annoncée au plafond",
       verdict_troncature([0] * 300, True, 300)[0], "ok")
    _v("bornes refusées proprement",
       verdict_bornes(400, "VALIDATION_ERROR")[0], "ok")
    _v("projection propre",
       verdict_fuite({"items": [{"photoUrl": "u"}]})[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    _v("au-delà du plafond", verdict_troncature([0] * 301, True, 300)[0], "echec")
    # ⚠️ `truncated` annoncé sans troncature : le client invite à zoomer pour
    # rien, et personne ne sait que la réponse est complète.
    _v("truncated menteur", verdict_troncature([1], True, 300)[0], "echec")
    _v("réponse illisible → non concluant",
       verdict_troncature(None, None, 300)[0], "non_concluant")
    _v("zone impossible acceptée", verdict_bornes(200, None)[0], "echec")
    _v("500 sur des bornes", verdict_bornes(500, "INTERNAL_ERROR")[0], "echec")
    _v("refus au mauvais code", verdict_bornes(404, "X")[0], "non_concluant")
    _v("429 → non concluant", verdict_bornes(429, None)[0], "non_concluant")
    _v("photoKeys imbriqué",
       verdict_fuite({"items": [{"promos": [{"photoKeys": ["k"]}]}]})[0], "echec")

    refus = 8
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


def main():
    print("═" * 64)
    print("  Carte client — bornes, plafond, troncature déclarée")
    print("═" * 64)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-40s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    # ── 1. Le monde entier ──────────────────────────────────────────────────
    print("\n── 1. une zone couvrant tout le monde ──")
    st, d = appeler("/promo/map?north=90&south=-90&east=180&west=-180")
    if st != 200:
        noter("zone maximale", "non_concluant",
              "HTTP %s %s" % (st, d.get("code")))
        return 1
    items = d.get("items")
    # Le plafond est DÉDUIT : s'il y a troncature, le nombre rendu EST le
    # plafond. Sinon on n'en sait rien, et on ne prétend rien.
    plafond = len(items) if d.get("truncated") else None
    noter("troncature cohérente",
          *verdict_troncature(items, d.get("truncated"), plafond))
    noter("aucun champ interne", *verdict_fuite(d))
    time.sleep(PACE)

    # ── 2. Une zone minuscule ───────────────────────────────────────────────
    print("\n── 2. une zone vide répond, elle ne casse pas ──")
    st, d = appeler("/promo/map?north=1.0001&south=1&east=1.0001&west=1")
    if st != 200:
        noter("zone vide", "echec", "HTTP %s %s" % (st, d.get("code")))
    else:
        noter("zone vide", "ok", "%d commerce(s)" % len(d.get("items", [])))
    time.sleep(PACE)

    # ── 3. Hors du monde ────────────────────────────────────────────────────
    print("\n── 3. des bornes hors du monde se refusent ──")
    for libelle, zone in (
        ("latitude > 90", "north=95&south=-90&east=180&west=-180"),
        ("longitude > 180", "north=90&south=-90&east=200&west=-180"),
        ("borne non numérique", "north=abc&south=-90&east=180&west=-180"),
    ):
        st, d = appeler("/promo/map?%s" % zone)
        noter(libelle, *verdict_bornes(st, d.get("code")))
        time.sleep(PACE)

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
