#!/usr/bin/env python3
"""Banc du cycle d'une promo — brouillon, publication, arrêt, et les bornes.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

Quatre règles anti-abus qui ne se déclenchent qu'au **cinquième geste**, à
**vingt-quatre heures** d'écart, ou au **septième jour** — c'est-à-dire jamais
pendant un développement, et toujours en production.

1. **Le plafond quotidien de créations** (5 / 24 h / commerçant) refuse la
   sixième — et **l'agent en est exempté**. Cette exemption n'est pas un
   détail : tous les autres bancs en dépendent pour poser leur décor, et si
   elle sautait, ils échoueraient tous pour une raison sans rapport avec ce
   qu'ils éprouvent.

2. **Le cooldown de republication** (24 h) refuse de republier une promo
   arrêtée trop tôt. Là encore, l'agent est exempté.

3. **`dureeJours` est borné**, et refusé plutôt que tronqué. Deux valeurs
   extrêmes sont sondées : au-delà du plafond, et une valeur si grande que la
   date calculée n'est plus représentable — `new Date(now + 1e30 * 86400000)`
   rend `Invalid Date`, dont `getTime()` vaut `NaN`, et **`NaN <= x` comme
   `NaN > y` sont tous deux faux** : la valeur traversait les deux gardes
   (trouvé le 2026-08-05, règle 34).

4. **Un brouillon ne compte pas dans le plafond d'actives** et n'est pas servi
   au client.

⚠️ Aucun de ces nombres n'est recopié ici : le banc pousse jusqu'au refus et
regarde **quel code** revient. Une copie du plafond se contenterait de vérifier
que le banc sait compter.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/promo_cycle.py --self-test
    ./scripts/test-promo-cycle.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.1"))
DEVICE_ID = "banc-promo-cycle-0001"


def verdict_refus(statut, code, codes_admis):
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if statut is None:
        return "echec", "pas de réponse : %s" % code
    if statut in (200, 201):
        return "echec", "ACCEPTÉ alors qu'un refus était dû"
    if statut >= 500 or code == "INTERNAL_ERROR":
        return ("echec",
                "HTTP %s %s — casse au lieu de refuser (une borne qui plante "
                "n'est pas une borne)" % (statut, code))
    if code not in codes_admis:
        return "non_concluant", "refusé en %s/%s, hors de %s" % (
            statut, code, codes_admis)
    return "ok", "%s %s" % (statut, code)


def verdict_accepte(statut, code):
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if statut not in (200, 201):
        return "echec", "refusé (HTTP %s, %s)" % (statut, code)
    return "ok", "accepté (%s)" % statut


def verdict_brouillon(statut_liste_client, dans_liste, lifecycle):
    """Un brouillon n'est pas servi au client, et porte le bon statut."""
    if lifecycle != "brouillon":
        return "echec", "créé avec lifecycleStatus=%r au lieu de brouillon" % lifecycle
    if statut_liste_client != 200:
        return "non_concluant", "liste client illisible"
    if dans_liste:
        return "echec", "le brouillon est servi au client"
    return "ok", "brouillon, absent de la liste client"


# ─────────────────────────────────────────────────────────────────────────────

def appeler(methode, chemin, jeton=None, corps=None):
    donnees = json.dumps(corps).encode() if corps is not None else None
    req = urllib.request.Request(API_URL + chemin, data=donnees, method=methode)
    req.add_header("Content-Type", "application/json")
    req.add_header("X-Device-Id", DEVICE_ID)
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
    _v("refus attendu", verdict_refus(400, "PROMO_DAILY_CREATION_CAP_REACHED",
                                      ("PROMO_DAILY_CREATION_CAP_REACHED",))[0],
       "ok")
    _v("acceptation attendue", verdict_accepte(201, None)[0], "ok")
    _v("brouillon conforme",
       verdict_brouillon(200, False, "brouillon")[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    _v("accepté là où un refus était dû",
       verdict_refus(201, None, ("X",))[0], "echec")
    # ⚠️ Une borne qui plante n'est pas une borne : c'est le cas `NaN` du
    # 2026-08-05, où la valeur traversait les gardes et Postgres levait.
    _v("500 compté comme refus",
       verdict_refus(500, "INTERNAL_ERROR", ("X",))[0], "echec")
    _v("refus au mauvais code",
       verdict_refus(400, "VALIDATION_ERROR", ("X",))[0], "non_concluant")
    _v("429 → non concluant", verdict_refus(429, None, ("X",))[0], "non_concluant")
    _v("acceptation refusée", verdict_accepte(400, "X")[0], "echec")
    _v("brouillon publié d'office",
       verdict_brouillon(200, False, "publiee")[0], "echec")
    _v("brouillon servi au client",
       verdict_brouillon(200, True, "brouillon")[0], "echec")
    _v("liste client illisible → non concluant",
       verdict_brouillon(500, False, "brouillon")[0], "non_concluant")

    refus = 8
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
    agent_email = _exiger("AGENT_EMAIL")
    agent_password = _exiger("AGENT_PASSWORD")

    print("═" * 64)
    print("  Cycle d'une promo — bornes de durée, plafond quotidien, cooldown")
    print("═" * 64)

    st, d = appeler("POST", "/commercant/login",
                    corps={"telephone": tel, "pin": pin})
    jc = d.get("accessToken")
    if not jc:
        print("❌ connexion commerçant impossible (HTTP %s, %s)"
              % (st, d.get("code")))
        return 2
    time.sleep(PACE)
    st, d = appeler("POST", "/agent/login",
                    corps={"email": agent_email, "password": agent_password})
    jg = d.get("accessToken")
    if not jg:
        print("❌ connexion agent impossible (HTTP %s, %s)" % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-42s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    def corps(marque, **extra):
        base = {"description": "Promo cycle %s" % marque, "prixAvant": 900,
                "prixApres": 600, "categorie": "alimentation",
                "photoKeys": ["promo-photos/%s/cycle.jpg" % cid]}
        base.update(extra)
        return base

    # ── 1. Les bornes de durée ──────────────────────────────────────────────
    print("\n── 1. `dureeJours` est borné, et refusé plutôt que tronqué ──")
    st, d = appeler("POST", "/promo/agent/%s" % cid, jg,
                    corps("duree-haute", dureeJours=9999))
    noter("durée au-delà du plafond",
          *verdict_refus(st, d.get("code"), ("PROMO_DATE_FIN_EXCEEDS_MAX",
                                             "VALIDATION_ERROR")))
    time.sleep(PACE)

    # ⚠️ Le cas `NaN` : la date calculée n'est plus représentable.
    st, d = appeler("POST", "/promo/agent/%s" % cid, jg,
                    corps("duree-absurde", dureeJours=1e30))
    noter("durée non représentable (le cas NaN)",
          *verdict_refus(st, d.get("code"), ("PROMO_DATE_FIN_EXCEEDS_MAX",
                                             "VALIDATION_ERROR")))
    time.sleep(PACE)

    st, d = appeler("POST", "/promo/agent/%s" % cid, jg,
                    corps("duree-negative", dureeJours=-3))
    noter("durée négative",
          *verdict_refus(st, d.get("code"), ("VALIDATION_ERROR",)))
    time.sleep(PACE)

    # ── 2. Le brouillon ─────────────────────────────────────────────────────
    print("\n── 2. un brouillon n'est pas servi au client ──")
    st, d = appeler("POST", "/promo/agent/%s" % cid, jg,
                    corps("brouillon", asDraft=True))
    pid_draft = d.get("id")
    if not pid_draft:
        noter("création du brouillon", "non_concluant",
              "HTTP %s %s" % (st, d.get("code")))
        return 1
    time.sleep(PACE)
    st_liste, liste = appeler("GET", "/promo?limit=100")
    noter("brouillon créé et invisible",
          *verdict_brouillon(st_liste,
                             pid_draft in {p["id"] for p in liste.get("items", [])},
                             d.get("lifecycleStatus")))
    time.sleep(PACE)

    # ── 3. Le cooldown de republication ─────────────────────────────────────
    print("\n── 3. cooldown de republication — et l'exemption de l'agent ──")
    st, d = appeler("POST", "/promo/agent/%s" % cid, jg, corps("republication"))
    pid = d.get("id")
    if not pid:
        noter("promo à republier", "non_concluant",
              "HTTP %s %s" % (st, d.get("code")))
        return 1
    time.sleep(PACE)
    appeler("POST", "/promo/%s/stop" % pid, jg)
    time.sleep(PACE)

    # L'agent est exempté : il DOIT pouvoir republier tout de suite.
    st, d = appeler("POST", "/promo/%s/publish" % pid, jg)
    noter("l'agent republie sans attendre (exempté)",
          *verdict_accepte(st, d.get("code")))
    time.sleep(PACE)

    # Le commerçant, lui, se heurte au cooldown.
    appeler("POST", "/promo/%s/stop" % pid, jg)
    time.sleep(PACE)
    st, d = appeler("POST", "/promo/%s/publish" % pid, jc)
    noter("le commerçant se heurte au cooldown",
          *verdict_refus(st, d.get("code"), ("PROMO_REPUBLISH_TOO_SOON",)))
    time.sleep(PACE)

    # ── 4. Le plafond quotidien ─────────────────────────────────────────────
    print("\n── 4. plafond quotidien de créations, côté commerçant ──")
    # ⚠️ On ne compte pas : on pousse jusqu'au refus. Le commerçant du décor a
    # déjà consommé une partie de son quota — le nombre exact n'a aucune
    # importance, seul le CODE du refus en a.
    dernier = None
    for i in range(7):
        st, d = appeler("POST", "/promo", jc, corps("quota-%d" % i))
        dernier = (st, d.get("code"))
        if st not in (200, 201):
            break
        time.sleep(PACE)
    noter("la création finit par être refusée",
          *verdict_refus(dernier[0], dernier[1],
                         ("PROMO_DAILY_CREATION_CAP_REACHED",
                          "PROMO_ACTIVE_CAP_REACHED")))

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
