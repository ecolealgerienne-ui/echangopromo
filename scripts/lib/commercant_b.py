#!/usr/bin/env python3
"""Banc d'appartenance commerçant — « la promo d'un autre ».

── Pourquoi ce banc existe, et pourquoi maintenant ──────────────────────────

`PROMO_NOT_OWNED_BY_COMMERCANT` est la garde qui empêche un commerçant d'agir
sur la promo d'un autre. **Elle n'était provoquée par aucun banc.** Mesuré le
2026-08-13 : le code n'apparaissait qu'une seule fois dans tout `scripts/`, en
tant que code *accepté* dans les `CODES_APPARTENANCE` d'`appartenance.py` —
jamais déclenché. Et aucun second commerçant n'existait dans les décors :
`COMMERCANT_B`, zéro occurrence.

Tant que l'agent était borné à ses communes, ce n'était qu'une lacune parmi
d'autres. Le chantier « agent global » du 2026-08-13 retire les quatorze gardes
d'appartenance côté agent — cette branche-ci devient alors la garde
d'appartenance **principale** de tout `PromoController`. Livrer ce chantier
sans ce banc laisserait le produit avec **zéro** couverture sur sa dernière
frontière entre deux commerçants.

── Ce qui est asserté, et pourquoi ce n'est pas le statut ───────────────────

⚠️ **Le verdict porte sur le CODE, jamais sur le statut.** Un `403` est rendu
par la garde de rôle, par le compte suspendu, par le registre non validé, par
le profil en attente, par la position absente — six gardes au moins partagent
ce statut sur ces routes. Là où plusieurs gardes partagent un même statut, le
statut ne mesure rien : un banc qui se contenterait de « 403 » serait vert le
jour où l'appartenance disparaît, pourvu qu'une autre garde tombe à sa place.

── La prémisse, établie et non supposée (règle #38) ─────────────────────────

Constater que B est refusé sur la promo de A ne prouve rien tout seul : B
pourrait être refusé partout, parce que son compte est neuf, son registre non
validé, ou sa position absente. Le contrôle 2 lui fait donc faire le **même
geste sur sa PROPRE promo** — et exige qu'il **passe**. Une seule chose change
entre les deux : le propriétaire de la promo.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/commercant_b.py --self-test   # d'abord, bloquant
    ./scripts/test-commercant-b.sh

⚠️ Ce banc ÉCRIT : il crée SON PROPRE commerçant B via l'agent, lui publie une
promo, et se supprime en fin de course. Il ne modifie aucun compte existant —
les trois sondes hostiles doivent toutes être REFUSÉES, donc sans effet.
"""

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.2"))
DEVICE_ID = "banc-appartenance-0001"
PIN = "654321"

# JPEG 1×1 réel : `/storage/upload` vérifie le contenu, pas seulement le
# `Content-Type` déclaré (règle #5). Un octet arbitraire serait refusé.
JPEG_1x1 = base64.b64decode(
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof"
    "Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB"
    "AAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q=="
)

# Position quelconque mais RÉELLE : la route de création l'exige depuis le
# 2026-08-12, et la publication la réclame. Djelfa, comme le décor.
REF_LAT, REF_LNG = 34.6703, 3.2630

CODE_ATTENDU = "PROMO_NOT_OWNED_BY_COMMERCANT"

resultats = []


def noter(libelle, etat, detail):
    symbole = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[etat]
    resultats.append(etat)
    print("  %s %-46s %s" % (symbole, libelle, detail))


# ─────────────────────────────────────────────────────────────────────────────
# Verdicts
# ─────────────────────────────────────────────────────────────────────────────

def verdict_refus_appartenance(statut, code, quoi):
    """B est refusé sur la promo de A, et pour LA BONNE raison.

    ⚠️ Trois issues distinctes, qui ne doivent pas se confondre :
      - le bon code           ⇒ ok ;
      - un autre code en 403  ⇒ **échec**, pas « ok quand même » : la garde qui
        a répondu n'est pas celle qu'on éprouve, et celle qu'on éprouve n'a
        peut-être plus d'existence ;
      - 2xx                   ⇒ échec franc, l'IDOR est ouvert.
    """
    if statut is None:
        return "non_concluant", "%s : pas de réponse lisible" % quoi
    if 200 <= statut < 300:
        return ("echec",
                "%s : ACCEPTÉ (%d) — un commerçant agit sur la promo d'un "
                "autre, IDOR ouvert" % (quoi, statut))
    if code == CODE_ATTENDU:
        return "ok", "%d %s" % (statut, code)
    return ("echec",
            "%s : refusé en %d mais avec %s, pas %s — une AUTRE garde a "
            "répondu ; celle de l'appartenance n'a peut-être pas été atteinte"
            % (quoi, statut, code or "(sans code)", CODE_ATTENDU))


def verdict_premisse(statut, code, quoi):
    """B doit pouvoir faire le même geste sur SA promo.

    Sans ce contrôle, un refus mesuré plus haut pourrait venir de n'importe
    quelle autre cause — compte neuf, registre non validé, position absente.
    C'est la règle #38 : établir que la quantité mesurée dépend bien du geste.
    """
    if statut is None:
        return "non_concluant", "%s : pas de réponse lisible" % quoi
    if 200 <= statut < 300:
        return "ok", "%d — B agit bien sur sa propre promo" % statut
    return ("non_concluant",
            "%s : B est refusé (%d %s) sur SA PROPRE promo — les sondes "
            "hostiles ne prouvent donc rien, elles auraient été refusées de "
            "toute façon" % (quoi, statut, code or "(sans code)"))


# ─────────────────────────────────────────────────────────────────────────────

def self_test():
    ok, echecs = 0, []

    def v(libelle, obtenu, attendu):
        nonlocal ok
        if obtenu == attendu:
            ok += 1
        else:
            echecs.append("%s — attendu %r, obtenu %r"
                          % (libelle, attendu, obtenu))

    # ── Doivent PASSER ──────────────────────────────────────────────────────
    v("refus au bon code",
      verdict_refus_appartenance(403, CODE_ATTENDU, "x")[0], "ok")
    v("prémisse tenue",
      verdict_premisse(200, None, "x")[0], "ok")
    v("prémisse tenue en 201",
      verdict_premisse(201, None, "x")[0], "ok")

    # ── Doivent REFUSER ─────────────────────────────────────────────────────
    # ⚠️ LE cas que ce banc existe pour attraper : l'IDOR ouvert.
    v("geste accepté sur la promo d'un autre",
      verdict_refus_appartenance(200, None, "x")[0], "echec")
    # ⚠️ ET le cas plus sournois : refusé, mais par une autre garde. Un banc
    # qui n'asserterait que le statut serait vert ici — c'est précisément la
    # raison d'être de ce fichier.
    v("refusé par une AUTRE garde (403 partagé)",
      verdict_refus_appartenance(403, "COMMERCANT_SUSPENDED", "x")[0], "echec")
    v("refusé sans aucun code",
      verdict_refus_appartenance(403, None, "x")[0], "echec")
    v("réponse illisible → non concluant",
      verdict_refus_appartenance(None, None, "x")[0], "non_concluant")
    # ⚠️ Un B refusé partout rend les sondes hostiles vides de sens : ce n'est
    # pas un succès, c'est une absence de mesure.
    v("prémisse en défaut → non concluant",
      verdict_premisse(403, "COMMERCANT_REGISTRE_PENDING", "x")[0],
      "non_concluant")

    total = ok + len(echecs)
    print("auto-test : %d cas, dont 5 refus" % total)
    for e in echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (ok, total))
    return not echecs


# ─────────────────────────────────────────────────────────────────────────────

def appeler(methode, chemin, jeton=None, corps=None):
    donnees = json.dumps(corps).encode() if corps is not None else None
    req = urllib.request.Request(API_URL + chemin, data=donnees, method=methode)
    req.add_header("Content-Type", "application/json")
    if jeton:
        req.add_header("Authorization", "Bearer %s" % jeton)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            corps_rep = r.read().decode() or "{}"
            return r.status, json.loads(corps_rep)
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode() or "{}")
        except Exception:
            return e.code, {}
    except Exception:
        return None, {}


def televerser(jeton, purpose):
    frontiere = "----banc%s" % uuid.uuid4().hex
    corps = b"".join([
        ('--%s\r\nContent-Disposition: form-data; name="purpose"\r\n\r\n%s\r\n'
         % (frontiere, purpose)).encode(),
        ('--%s\r\nContent-Disposition: form-data; name="file"; '
         'filename="promo.jpg"\r\nContent-Type: image/jpeg\r\n\r\n'
         % frontiere).encode(),
        JPEG_1x1,
        ("\r\n--%s--\r\n" % frontiere).encode(),
    ])
    req = urllib.request.Request(API_URL + "/storage/upload", data=corps,
                                 method="POST")
    req.add_header("Content-Type",
                   "multipart/form-data; boundary=%s" % frontiere)
    req.add_header("X-Device-Id", DEVICE_ID)
    req.add_header("Authorization", "Bearer " + jeton)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read())
        except Exception:
            return e.code, {}
    except Exception:
        return None, {}


def main():
    agent_email = os.environ.get("AGENT_EMAIL")
    agent_password = os.environ.get("AGENT_PASSWORD")
    promo_a = os.environ.get("PROMO_ID")
    if not agent_email or not agent_password:
        print("❌ AGENT_EMAIL / AGENT_PASSWORD absents de l'environnement.")
        print("   Aucune valeur par défaut : un banc qui inventerait un compte")
        print("   échouerait en accusant la garde d'appartenance.")
        return 2
    if not promo_a:
        print("❌ PROMO_ID absent — c'est la promo du commerçant A, la cible")
        print("   des trois sondes. Relancer ./scripts/provision-decor.sh.")
        return 2

    print("── 0. décor : un second commerçant, le B ──")
    st, d = appeler("POST", "/agent/login",
                    corps={"email": agent_email, "password": agent_password})
    jeton_agent = d.get("accessToken")
    if not jeton_agent:
        print("  ⚠️  connexion agent impossible (%s %s)" % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    base = time.strftime("%H%M%S")
    tel_b = "+213557%s" % base
    st, d = appeler("POST", "/agent/commercant", jeton_agent, {
        "telephone": tel_b, "nom": "Banc appartenance B", "pin": PIN,
        "categorie": "alimentation",
        "latitude": REF_LAT, "longitude": REF_LNG})
    if st not in (200, 201):
        print("  ⚠️  création de B refusée (%s %s)" % (st, d.get("code")))
        return 2
    cid_b = d.get("id")
    print("  commerçant B créé (%s)" % (cid_b or "?")[:8])
    time.sleep(PACE)

    # ⚠️ **B est connecté AVANT que quoi que ce soit d'autre puisse échouer.**
    # Le nettoyage se fait par `DELETE /commercant/me`, donc il exige le jeton
    # de B : tout échec survenant entre la création et la connexion laisserait
    # un commerçant orphelin, sans moyen de le retirer. C'est arrivé au premier
    # passage (téléversement en 404) — un banc qui pollue le parc en échouant
    # fausse les bancs qui comptent ce parc.
    st, d = appeler("POST", "/commercant/login",
                    corps={"telephone": tel_b, "pin": PIN})
    jeton_b = d.get("accessToken")
    if not jeton_b:
        print("  ⚠️  connexion de B impossible (%s %s) — commerçant %s laissé "
              "en place, à supprimer à la main" % (st, d.get("code"),
                                                   (cid_b or "?")[:8]))
        return 2
    time.sleep(PACE)

    try:
        st, up = televerser(jeton_agent, "promo")
        cle = up.get("key")
        if not cle:
            print("  ⚠️  téléversement impossible (%s)" % st)
            return 2
        time.sleep(PACE)

        st, d = appeler("POST", "/promo/agent/%s" % cid_b, jeton_agent, {
            "description": "Promo de B — banc appartenance %s" % base,
            "prixAvant": 1000, "prixApres": 700,
            "categorie": "alimentation", "photoKeys": [cle]})
        if st not in (200, 201):
            print("  ⚠️  promo de B refusée (%s %s)" % (st, d.get("code")))
            return 2
        promo_b = d.get("id")
        print("  B connecté, promo de B : %s" % (promo_b or "?")[:8])
        time.sleep(PACE)

        # ── 1. Les trois gestes hostiles ────────────────────────────────────
        print("\n── 1. B tente les 3 écritures sur la promo de A ──")
        sondes = [
            ("PATCH", "/promo/%s" % promo_a,
             {"description": "Détournement par le banc d'appartenance"},
             "PATCH /promo/:id"),
            ("POST", "/promo/%s/publish" % promo_a, None,
             "POST /promo/:id/publish"),
            ("POST", "/promo/%s/stop" % promo_a, None,
             "POST /promo/:id/stop"),
        ]
        for methode, chemin, corps, libelle in sondes:
            st, d = appeler(methode, chemin, jeton_b, corps)
            noter(libelle, *verdict_refus_appartenance(st, d.get("code"),
                                                       libelle))
            time.sleep(PACE)

        # ── 2. La prémisse ──────────────────────────────────────────────────
        print("\n── 2. le même geste sur SA propre promo ──")
        st, d = appeler("PATCH", "/promo/%s" % promo_b, jeton_b,
                        {"description": "Promo de B, modifiée par B %s" % base})
        noter("PATCH sur sa propre promo",
              *verdict_premisse(st, d.get("code"), "prémisse"))
        time.sleep(PACE)
    finally:
        # ⚠️ Auto-nettoyage : sans lui, chaque passage laisserait un commerçant
        # de plus, et le parc de test finirait par mentir aux bancs qui le
        # comptent (`admin_dashboard`, `client_liste`).
        appeler("DELETE", "/commercant/me", jeton_b)

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
