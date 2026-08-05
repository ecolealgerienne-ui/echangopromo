#!/usr/bin/env python3
"""Banc du référentiel commune — la liste complète, jamais tronquée.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

`GET /commune` n'est pas un flux paginé à l'écran : c'est une **liste de
référence** que le mobile charge **en entier** pour construire le sélecteur
wilaya → commune (`CommuneCascadeField`). C'est l'exception nommée de la
règle 15 : paginer par défaut sans adapter ce client tronquerait la liste dès
que le total dépasse la taille de page — silencieusement, et le sélecteur
n'afficherait plus certaines communes sans que rien ne le signale.

Trois sondes :

1. **La boucle de pagination rend bien `total` éléments.** C'est ce que fait
   `CommuneApi.list()` ; si le contrat se met à mentir sur `total` ou à
   plafonner sans le dire, le sélecteur perd des communes.
2. **Aucun doublon entre les pages.** Un tri instable ferait réapparaître les
   mêmes lignes et en sauter d'autres — la liste aurait la bonne longueur et le
   mauvais contenu.
3. **Un `limit` au-delà du maximum se refuse**, il ne se rabat pas en silence.

⚠️ Le nombre de communes n'est pas écrit ici : le banc compare `total` à ce
qu'il a **réellement collecté**. Une attente chiffrée devrait être corrigée à
chaque seed et finirait ajustée jusqu'à ne plus rien tester.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/client_commune.py --self-test
    ./scripts/test-client-commune.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "0.6"))
DEVICE_ID = "banc-commune-0001"


def verdict_completude(collectes, total):
    """Ce qu'on a ramassé doit égaler ce que le serveur annonce."""
    if total is None:
        return "non_concluant", "`total` absent — pas de verdict"
    if collectes != total:
        return ("echec",
                "%d commune(s) collectées pour un total annoncé de %d — le "
                "sélecteur wilaya → commune en perdrait %d"
                % (collectes, total, abs(total - collectes)))
    return "ok", "%d = %d" % (collectes, total)


def verdict_doublons(ids, collectes):
    """Aucune ligne vue deux fois entre les pages."""
    if collectes == 0:
        return "non_concluant", "rien à examiner"
    if len(ids) != collectes:
        return ("echec",
                "%d identifiants distincts pour %d lignes ramassées — des "
                "pages se recouvrent, d'autres communes manquent"
                % (len(ids), collectes))
    return "ok", "%d distinctes" % len(ids)


def verdict_limite(statut, code):
    """Un `limit` hors borne se refuse ; il ne se rabat pas en silence."""
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if statut is None:
        return "echec", "pas de réponse : %s" % code
    if statut in (200, 201):
        return ("echec",
                "`limit` hors borne ACCEPTÉ — la borne est décorative, et un "
                "appelant peut demander la base entière")
    if statut >= 500:
        return "echec", "HTTP %s — casse au lieu de refuser" % statut
    if code != "VALIDATION_ERROR":
        return "non_concluant", "refusé en %s/%s" % (statut, code)
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
    _v("collecte complète", verdict_completude(36, 36)[0], "ok")
    _v("aucun doublon", verdict_doublons({"a", "b"}, 2)[0], "ok")
    _v("limite refusée", verdict_limite(400, "VALIDATION_ERROR")[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le cas de la règle 15 : la liste est tronquée sans le dire.
    _v("collecte tronquée", verdict_completude(20, 36)[0], "echec")
    _v("collecte excédentaire", verdict_completude(40, 36)[0], "echec")
    _v("total absent → non concluant",
       verdict_completude(20, None)[0], "non_concluant")
    _v("pages qui se recouvrent", verdict_doublons({"a"}, 2)[0], "echec")
    _v("rien à examiner → non concluant",
       verdict_doublons(set(), 0)[0], "non_concluant")
    _v("limite hors borne acceptée", verdict_limite(200, None)[0], "echec")
    _v("500 sur la limite", verdict_limite(500, None)[0], "echec")
    _v("refus au mauvais code", verdict_limite(404, "X")[0], "non_concluant")

    refus = 7
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


def main():
    print("═" * 64)
    print("  Référentiel commune — la liste complète, jamais tronquée")
    print("═" * 64)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-40s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    # ── La boucle, exactement celle de CommuneApi.list() ────────────────────
    print("\n── 1. la boucle de pagination ramasse tout ──")
    ids, collectes, total, page = set(), 0, None, 1
    while True:
        st, d = appeler("/commune?page=%d&limit=100" % page)
        if st != 200:
            noter("page %d" % page, "non_concluant",
                  "HTTP %s %s" % (st, d.get("code")))
            return 1
        lot = d.get("items", [])
        total = d.get("total")
        collectes += len(lot)
        ids.update(c["id"] for c in lot)
        if not lot or (total is not None and collectes >= total):
            break
        page += 1
        if page > 50:  # garde-fou : une boucle infinie n'est pas un verdict
            noter("boucle de pagination", "echec",
                  "50 pages sans atteindre le total annoncé")
            return 1
        time.sleep(PACE)

    noter("collecté = total annoncé", *verdict_completude(collectes, total))
    noter("aucun doublon entre les pages", *verdict_doublons(ids, collectes))
    time.sleep(PACE)

    # ── La borne de pagination ──────────────────────────────────────────────
    print("\n── 2. un `limit` hors borne se refuse ──")
    st, d = appeler("/commune?limit=100000")
    noter("limit=100000", *verdict_limite(st, d.get("code")))
    time.sleep(PACE)
    st, d = appeler("/commune?limit=0")
    noter("limit=0", *verdict_limite(st, d.get("code")))

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
