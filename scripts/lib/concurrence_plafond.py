#!/usr/bin/env python3
"""Banc de concurrence — le plafond de 5 promos actives tient sous course.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

Le plafond de 5 promos actives était vérifiable en **race condition** : deux
créations quasi simultanées lisaient chacune un compte de 4 et passaient toutes
les deux, aboutissant à 6 actives. Corrigé par un verrou consultatif Postgres
scopé au commerçant (`pg_advisory_xact_lock`) — et **jamais éprouvé sous
charge** depuis.

⚠️ **Un banc de course qui « passe » une fois ne prouve rien.** L'absence de
collision peut tenir au hasard de l'ordonnancement. D'où plusieurs tours, et un
verdict qui n'est rendu qu'à la fin.

── Comment il contourne les DEUX autres plafonds ────────────────────────────

Trois plafonds se marchent dessus, et les confondre rendrait le banc
inexploitable :

  1. **5 actives** (`assertUnderCap`) — compté sur `lifecycleStatus = publiee`.
     C'est celui qu'on éprouve. Il s'applique à **tout le monde**, y compris
     agent et admin (`promo.service.ts` : « reste lui appliqué à tout le
     monde »).
  2. **5 créations / 24 h glissantes** (anti-abus) — dont **agent et admin sont
     exemptés** (`trustedActor`).
  3. **cooldown de republication de 24 h** — même exemption.

Le banc passe donc par un **agent** (`POST /promo/agent/:commercantId`) : sans
ça, cinq créations épuiseraient le plafond quotidien dès le premier tour et les
suivants échoueraient pour la mauvaise raison.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/concurrence_plafond.py --self-test
    python3 scripts/lib/concurrence_plafond.py            # 3 tours
    TOURS=6 python3 scripts/lib/concurrence_plafond.py
"""

import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
TOURS = int(os.environ.get("TOURS", "3"))
SIMULTANEES = int(os.environ.get("SIMULTANEES", "3"))
PACE = float(os.environ.get("PACE_SECONDS", "0.6"))

CAP = 5  # ⚠️ lu ici pour l'affichage seulement — l'assertion porte sur le
         # COMPORTEMENT (un seul gagnant), jamais sur une copie du nombre.


def corps_promo(marque, cid):
    # ⚠️ La clé S3 doit APPARTENIR au compte (2026-08-05). `assertPhotoKeysOwned`
    # exige le préfixe `promo-photos/<commercantId>/` — ou celui de l'agent, une
    # promo créée par un agent portant l'UUID de l'agent. Le banc posait
    # `promo-photos/banc/course.jpg`, un préfixe qui n'appartient à personne :
    # les trois tours échouaient en `STORAGE_KEY_NOT_OWNED` avant même
    # d'atteindre la course qu'ils devaient éprouver.
    #
    # Le banc n'a PAS annoncé un faux vert pour autant — il a dit « 0 tour
    # concluant, le banc n'a rien prouvé ». C'est ce qu'on lui demande : un tour
    # non concluant n'est pas une réussite (règle #29).
    return {
        "description": "Course %s" % marque,
        "prixAvant": 1000,
        "prixApres": 700,
        "categorie": "alimentation",
        "photoKeys": ["promo-photos/%s/course.jpg" % cid],
    }


# ─────────────────────────────────────────────────────────────────────────────

def appeler(methode, chemin, jeton, corps=None):
    donnees = json.dumps(corps if corps is not None else {}).encode()
    req = urllib.request.Request(API_URL + chemin, data=donnees, method=methode)
    req.add_header("Content-Type", "application/json")
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


# ─────────────────────────────────────────────────────────────────────────────
# Le verdict d'un tour — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_tour(resultats, actives_apres):
    """resultats : liste de (statut, code). Rend (verdict, explication).

    ⚠️ L'assertion porte sur **un seul gagnant**, pas sur un nombre recopié :
    c'est la sérialisation qu'on éprouve, pas la valeur du plafond.
    """
    gagnants = [r for r in resultats if r[0] in (200, 201)]
    plafonnes = [r for r in resultats if r[1] == "PROMO_ACTIVE_CAP_REACHED"]
    autres = [r for r in resultats
              if r not in gagnants and r[1] != "PROMO_ACTIVE_CAP_REACHED"]

    if any(r[1] == "VALIDATION_ERROR" for r in autres):
        return "non_concluant", "un corps a été refusé à la validation — la sonde " \
                                "n'a pas atteint le plafond"
    if any(r[0] == 429 for r in resultats):
        return "non_concluant", "429 — plafond de requêtes atteint, ce n'est pas un verdict"
    if autres:
        return "non_concluant", "refus inattendu : %s" % sorted({r[1] for r in autres})
    if len(gagnants) > 1:
        return "echec", "%d créations ont réussi simultanément — le verrou n'a pas " \
                        "sérialisé (c'est LE défaut visé)" % len(gagnants)
    if len(gagnants) == 0:
        return "echec", "aucune création n'a réussi — le décor n'était pas à %d actives" % (CAP - 1)
    if actives_apres is not None and actives_apres != CAP:
        return "echec", "%d actives après le tour, attendu %d" % (actives_apres, CAP)
    return "ok", "1 gagnant, %d plafonnées, %d actives" % (len(plafonnes), actives_apres)


# ─────────────────────────────────────────────────────────────────────────────

def _exiger(nom):
    v = os.environ.get(nom)
    if not v:
        print("❌ %s absent — lancer ./scripts/provision-decor.sh et coller son bloc." % nom)
        sys.exit(2)
    return v


def promos_du_commercant(jeton_commercant):
    _, d = appeler("GET", "/promo/me/all?limit=100", jeton_commercant)
    return d.get("items", [])


def actives(promos):
    return [p for p in promos if p.get("lifecycleStatus") == "publiee"]


def preparer(jeton_agent, jeton_commercant, cid):
    """Amène le commerçant à exactement CAP-1 promos actives."""
    for _ in range(20):
        act = actives(promos_du_commercant(jeton_commercant))
        if len(act) == CAP - 1:
            return True
        if len(act) > CAP - 1:
            st, d = appeler("POST", "/promo/%s/stop" % act[0]["id"], jeton_agent)
            if st not in (200, 201):
                print("   ❌ arrêt impossible (HTTP %s, %s)" % (st, d.get("code")))
                return False
        else:
            st, d = appeler("POST", "/promo/agent/%s" % cid, jeton_agent,
                            corps_promo("préparation", cid))
            if st not in (200, 201):
                print("   ❌ création impossible (HTTP %s, %s)" % (st, d.get("code")))
                return False
        time.sleep(PACE)
    print("   ❌ impossible d'atteindre %d actives en 20 gestes" % (CAP - 1))
    return False


def tirer_simultanement(jeton_agent, cid, n):
    """n créations lancées ensemble, avec une barrière pour maximiser la course."""
    barriere = threading.Barrier(n)
    resultats = [None] * n

    def un(i):
        corps = corps_promo("t%d" % i, cid)
        barriere.wait()          # ⚠️ tous partent au même instant
        st, d = appeler("POST", "/promo/agent/%s" % cid, jeton_agent, corps)
        resultats[i] = (st, d.get("code"))

    fils = [threading.Thread(target=un, args=(i,)) for i in range(n)]
    for f in fils:
        f.start()
    for f in fils:
        f.join()
    return resultats


# ─────────────────────────────────────────────────────────────────────────────

def self_test():
    cas = [
        # (resultats, actives_apres, verdict attendu)
        ([(201, None), (400, "PROMO_ACTIVE_CAP_REACHED")], 5, "ok"),
        ([(201, None), (400, "PROMO_ACTIVE_CAP_REACHED"),
          (400, "PROMO_ACTIVE_CAP_REACHED")], 5, "ok"),
        # ── Doivent REFUSER ──────────────────────────────────────────────────
        ([(201, None), (201, None)], 6, "echec"),                    # LE défaut visé
        ([(200, None), (201, None)], 6, "echec"),
        ([(400, "PROMO_ACTIVE_CAP_REACHED")] * 2, 4, "echec"),       # aucun gagnant
        ([(201, None), (400, "PROMO_ACTIVE_CAP_REACHED")], 6, "echec"),  # compte final faux
        ([(201, None), (400, "VALIDATION_ERROR")], 5, "non_concluant"),
        ([(201, None), (429, None)], 5, "non_concluant"),
        ([(201, None), (403, "COMMERCANT_NOT_IN_AGENT_COMMUNES")], 5, "non_concluant"),
    ]
    echecs, passes = [], 0
    for resultats, act, attendu in cas:
        obtenu, _ = verdict_tour(resultats, act)
        if obtenu == attendu:
            passes += 1
        else:
            echecs.append("%s / %s → %s, attendu %s" % (resultats, act, obtenu, attendu))
    refus = sum(1 for c in cas if c[2] != "ok")
    print("auto-test : %d cas, dont %d refus" % (len(cas), refus))
    for e in echecs:
        print("  ❌ " + e)
    print("  %d/%d" % (passes, len(cas)))
    return not echecs


def main():
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)

    cid = _exiger("COMMERCANT_ID")
    _, d = appeler("POST", "/agent/login", "",
                   {"email": _exiger("AGENT_EMAIL"), "password": _exiger("AGENT_PASSWORD")})
    ja = d.get("accessToken")
    _, d = appeler("POST", "/commercant/login", "",
                   {"telephone": _exiger("COMMERCANT_TEL"), "pin": _exiger("COMMERCANT_PIN")})
    jc = d.get("accessToken")
    if not ja or not jc:
        print("❌ connexion impossible — décor à rejouer, ou plafond de 5/min atteint.")
        sys.exit(2)

    print("════════════════════════════════════════════════════════════════")
    print("  Plafond de %d promos actives — sous course" % CAP)
    print("════════════════════════════════════════════════════════════════")
    print("  %d tours × %d créations simultanées\n" % (TOURS, SIMULTANEES))

    echecs, non_concluants = [], []
    for tour in range(1, TOURS + 1):
        print("── tour %d ──" % tour)
        if not preparer(ja, jc, cid):
            non_concluants.append("tour %d : préparation impossible" % tour)
            continue
        resultats = tirer_simultanement(ja, cid, SIMULTANEES)
        time.sleep(PACE)
        act = len(actives(promos_du_commercant(jc)))
        v, quoi = verdict_tour(resultats, act)
        print("   %s %s" % ({"ok": "✅", "echec": "❌"}.get(v, "⚠️ "), quoi))
        if v == "echec":
            echecs.append("tour %d : %s" % (tour, quoi))
        elif v == "non_concluant":
            non_concluants.append("tour %d : %s" % (tour, quoi))

    print("\n════════════════════════════════════════════════════════════════")
    if non_concluants:
        print("⚠️  %d tour(s) non concluant(s) — ce ne sont pas des réussites :"
              % len(non_concluants))
        for n in non_concluants:
            print("     " + n)
    for e in echecs:
        print("  ❌ " + e)
    reussis = TOURS - len(echecs) - len(non_concluants)
    print("%d/%d tours concluants, %d échec(s)" % (reussis, TOURS, len(echecs)))
    if reussis == 0:
        print("⚠️  aucun tour concluant : le banc n'a rien prouvé.")
    sys.exit(1 if (echecs or reussis == 0) else 0)


if __name__ == "__main__":
    main()
