#!/usr/bin/env python3
"""Banc du tableau de bord commerçant — une AUDIENCE, pas un trafic.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

`GET /commercant/me/dashboard` ne rend qu'un chiffre : `profileViewCount`. Et
ce chiffre a un sens précis — `recordProfileView` insère avec `orIgnore()`,
donc il compte des **appareils distincts**, pas des consultations.

C'est ce qui le rend intéressant à sonder : un dédoublonnage qui saute ne
casse rien, ne lève rien, et **gonfle l'audience perçue** du commerçant. Il
verrait 300 là où 40 personnes l'ont regardé, prendrait ses décisions
là-dessus, et personne ne pourrait le contredire — c'est exactement la classe
de défaut du surcompte de promos actives (règle 8).

Trois sondes :

1. **Une consultation par un appareil neuf incrémente de 1.**
2. **La même consultation, répétée par le MÊME appareil, n'incrémente pas.**
   C'est la sonde qui distingue une audience d'un trafic.
3. **Un second appareil incrémente à nouveau** — sans quoi la sonde n°2
   passerait aussi bien sur un compteur définitivement bloqué.

⚠️ La n°3 n'est pas décorative : sans elle, un compteur qui n'incrémente
**jamais** satisferait les deux premières.

── Note sur le plan ────────────────────────────────────────────────────────

`TEST_PROMO.md` §6 annonce pour ce banc « le surcompte de promos actives,
défaut historique ». Ce compteur **n'est plus ici** : il a migré vers
`GET /promo/me/slots` le 2026-08-05, couvert par le parcours écran et par la
sonde de plafond. La ligne du plan est périmée — signalé plutôt que couvert en
apparence.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/commercant_dashboard.py --self-test
    ./scripts/test-commercant-dashboard.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.1"))


def verdict_increment(avant, apres, attendu, quoi):
    if avant is None or apres is None:
        return "non_concluant", "%s : compteur illisible" % quoi
    delta = apres - avant
    if delta != attendu:
        return ("echec",
                "%s : le compteur a bougé de %+d, attendu %+d (%d → %d)"
                % (quoi, delta, attendu, avant, apres))
    return "ok", "%d → %d (%+d)" % (avant, apres, delta)


def appeler(methode, chemin, jeton=None, device="banc-dash-0001"):
    req = urllib.request.Request(API_URL + chemin, method=methode)
    req.add_header("Content-Type", "application/json")
    req.add_header("X-Device-Id", device)
    if jeton:
        req.add_header("Authorization", "Bearer " + jeton)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            brut = r.read()
            try:
                return r.status, json.loads(brut or b"{}")
            except Exception:
                return r.status, {}
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read())
        except Exception:
            return e.code, {}
    except Exception as e:
        return None, {"code": "RESEAU: %s" % e}


def appeler_json(chemin, corps, device="banc-dash-0001"):
    req = urllib.request.Request(API_URL + chemin,
                                 data=json.dumps(corps).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("X-Device-Id", device)
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


def _exiger(nom):
    v = os.environ.get(nom)
    if not v:
        print("❌ %s absent — lancer ./scripts/provision-decor.sh." % nom)
        sys.exit(2)
    return v


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
    _v("incrément attendu", verdict_increment(4, 5, 1, "x")[0], "ok")
    _v("stabilité attendue", verdict_increment(5, 5, 0, "x")[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le dédoublonnage sauté : le compteur mesure un trafic, pas une
    # audience, et gonfle silencieusement la portée perçue.
    _v("doublon compté", verdict_increment(5, 6, 0, "x")[0], "echec")
    _v("appareil neuf ignoré", verdict_increment(5, 5, 1, "x")[0], "echec")
    _v("compteur qui recule", verdict_increment(5, 3, 1, "x")[0], "echec")
    _v("bond inexpliqué", verdict_increment(5, 12, 1, "x")[0], "echec")
    _v("compteur illisible → non concluant",
       verdict_increment(None, 5, 1, "x")[0], "non_concluant")

    refus = 5
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


def main():
    tel = _exiger("COMMERCANT_TEL")
    pin = _exiger("COMMERCANT_PIN")
    cid = _exiger("COMMERCANT_ID")

    print("═" * 64)
    print("  Tableau de bord commerçant — une audience, pas un trafic")
    print("═" * 64)

    st, d = appeler_json("/commercant/login", {"telephone": tel, "pin": pin})
    jc = d.get("accessToken")
    if not jc:
        print("❌ connexion commerçant impossible (HTTP %s, %s)"
              % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-42s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    def compteur():
        _, d = appeler("GET", "/commercant/me/dashboard", jc)
        return d.get("profileViewCount")

    marque = time.strftime("%H%M%S")
    appareil_a = "banc-dash-A-%s" % marque
    appareil_b = "banc-dash-B-%s" % marque

    print("\n── 1. un appareil neuf compte pour un ──")
    avant = compteur()
    appeler("GET", "/commercant/%s/public" % cid, device=appareil_a)
    time.sleep(PACE)
    noter("consultation par un appareil neuf",
          *verdict_increment(avant, compteur(), 1, "appareil A"))
    time.sleep(PACE)

    print("\n── 2. le même appareil ne compte pas deux fois ──")
    avant = compteur()
    for _ in range(3):
        appeler("GET", "/commercant/%s/public" % cid, device=appareil_a)
        time.sleep(0.3)
    time.sleep(PACE)
    noter("trois consultations du MÊME appareil",
          *verdict_increment(avant, compteur(), 0, "appareil A répété"))
    time.sleep(PACE)

    print("\n── 3. mais un second appareil, si ──")
    # ⚠️ Sans cette sonde, un compteur définitivement bloqué satisferait les
    # deux précédentes.
    avant = compteur()
    appeler("GET", "/commercant/%s/public" % cid, device=appareil_b)
    time.sleep(PACE)
    noter("consultation par un second appareil",
          *verdict_increment(avant, compteur(), 1, "appareil B"))

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
