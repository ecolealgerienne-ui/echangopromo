#!/usr/bin/env python3
"""Banc de création par l'agent — un commerçant naît AVEC SON POINT.

── Ce que ce banc éprouvait, et ce qu'il éprouve maintenant ─────────────────

⚠️ **Son sujet a changé le 2026-08-13.** Il éprouvait la règle 1 sur
`POST /agent/commercant` : la route prenait une `communeId` fournie par
l'appelant, ce qui est exactement la forme d'un IDOR — le rôle est bon, le
jeton est valide, et la question devient « cette commune est-elle la sienne ? ».
Le chantier « agent global » supprime le territoire, donc la question.

**Il reste le seul invariant de cette route** : la position est obligatoire.
Ce n'est pas un lot de consolation — c'est la garde qui empêche une tournée de
fabriquer des fiches invisibles. Mesuré le 2026-08-12 : **40 des 44 commerçants
sans position venaient d'ici**, et rien dans le produit ne le disait. Un
commerce sans point n'apparaît sur aucune carte, ne sort d'aucune liste au
rayon, et ne peut rien publier.

Trois sondes :

1. **`GET /agent/me` répond et l'agent s'y reconnaît** — seule source dont
   l'app dispose pour composer ses écrans.
2. **Le commerçant créé porte sa position**, vérifié sur la **fiche publique**
   et non sur la réponse de création : ce qui compte est ce que le serveur
   SERT. Un point stocké mais non servi produirait exactement l'invisibilité
   qu'on cherche à empêcher.
3. **Sans position, la création est refusée** — et refusée par la validation,
   code asserté : un 400 rendu pour une autre raison laisserait croire que la
   garde tient alors qu'elle aurait pu disparaître.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/agent_creation.py --self-test
    ./scripts/test-agent-creation.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.1"))
DEVICE_ID = "banc-agent-creation-0001"
PIN = "654321"
# Position de décor, à Djelfa. ⚠️ Obligatoire depuis le 2026-08-12 : la création
# par agent l'exige, et publier sans position est refusé. Sans ces deux valeurs
# le banc rendrait ❌ sur un produit parfaitement correct (règle #38) — et
# d'autant plus crédiblement que le message parlerait bien de position.
DECOR_LAT, DECOR_LNG = 34.6702, 3.2611


def verdict_position(fiche):
    """Le commerçant créé par l'agent doit porter SA position.

    ⚠️ Vérifié sur la fiche publique, pas sur la réponse de création : ce qui
    compte est ce que le serveur SERT, pas ce qu'il a accepté. Un point stocké
    mais non servi rendrait le commerce invisible sans qu'aucun code d'erreur
    ne le dise — c'est le mode de défaillance qui a produit 40 fiches
    invisibles avant le 2026-08-12.
    """
    lat, lng = fiche.get("latitude"), fiche.get("longitude")
    if lat is None or lng is None:
        return ("echec",
                "la fiche publique ne sert aucune position (lat=%r, lng=%r) — "
                "ce commerce n'apparaîtra sur aucune carte et ne pourra rien "
                "publier" % (lat, lng))
    return "ok", "%.4f / %.4f" % (lat, lng)


def verdict_refus_sans_position(statut, code):
    """Créer sans position doit être refusé, et par la VALIDATION.

    ⚠️ Le code compte autant que le statut : un 400 rendu pour une autre raison
    (numéro déjà pris, PIN mal formé) laisserait croire que la garde de
    position tient alors qu'elle aurait pu disparaître.
    """
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if statut is None:
        return "echec", "pas de réponse : %s" % code
    if statut in (200, 201):
        return ("echec",
                "création ACCEPTÉE sans position — chaque tournée peut de "
                "nouveau fabriquer des fiches invisibles")
    if statut >= 500 or code == "INTERNAL_ERROR":
        return "echec", "HTTP %s %s — casse au lieu de refuser" % (statut, code)
    if code != "VALIDATION_ERROR":
        return ("echec",
                "refusé en %s mais avec %s, pas VALIDATION_ERROR — une AUTRE "
                "garde a répondu" % (statut, code or "(sans code)"))
    return "ok", "%s %s" % (statut, code)


def verdict_identite(moi, statut):
    """`GET /agent/me` répond, et l'agent s'y reconnaît."""
    if statut != 200:
        return "non_concluant", "GET /agent/me illisible (HTTP %s)" % statut
    if not moi.get("id") or not moi.get("email"):
        return "echec", "réponse sans id ni email — contrat rompu"
    return "ok", "agent %s" % moi["id"][:8]


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
    _v("position servie",
       verdict_position({"latitude": 34.67, "longitude": 3.26})[0], "ok")
    _v("refus de validation attendu",
       verdict_refus_sans_position(400, "VALIDATION_ERROR")[0], "ok")
    _v("agent identifié",
       verdict_identite({"id": "a1", "email": "a@b.c"}, 200)[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le cas fondateur : une fiche née sans point est invisible, et rien
    # dans le produit ne le dit — 40 des 44 commerçants sans position mesurés
    # le 2026-08-12 venaient de cette route.
    _v("fiche sans position", verdict_position({})[0], "echec")
    _v("latitude seule",
       verdict_position({"latitude": 34.67})[0], "echec")
    _v("création sans position acceptée",
       verdict_refus_sans_position(201, None)[0], "echec")
    # ⚠️ Refusé, mais par une AUTRE garde : un banc qui n'asserterait que le
    # statut serait vert le jour où la garde de position disparaît.
    _v("refusé par une autre garde",
       verdict_refus_sans_position(400, "COMMERCANT_PHONE_TAKEN")[0], "echec")
    _v("500 au lieu d'un refus",
       verdict_refus_sans_position(500, "INTERNAL_ERROR")[0], "echec")
    _v("429 → non concluant",
       verdict_refus_sans_position(429, None)[0], "non_concluant")
    _v("agent sans identité", verdict_identite({}, 200)[0], "echec")
    _v("/agent/me illisible → non concluant",
       verdict_identite({}, 500)[0], "non_concluant")

    refus = 7
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


def main():
    agent_email = _exiger("AGENT_EMAIL")
    agent_password = _exiger("AGENT_PASSWORD")
    agent_b_email = _exiger("AGENT_B_EMAIL")
    agent_b_password = _exiger("AGENT_B_PASSWORD")

    print("═" * 64)
    print("  Création par l'agent — un commerçant naît AVEC SON POINT")
    print("═" * 64)

    def connecter(email, mdp, qui):
        st, d = appeler("POST", "/agent/login",
                        corps={"email": email, "password": mdp})
        j = d.get("accessToken")
        if not j:
            print("❌ connexion %s impossible (HTTP %s, %s)"
                  % (qui, st, d.get("code")))
            sys.exit(2)
        time.sleep(PACE)
        return j

    jg = connecter(agent_email, agent_password, "agent A")
    jb = connecter(agent_b_email, agent_b_password, "agent B")

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-42s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    # ── 1. Le territoire ────────────────────────────────────────────────────
    print("\n── 1. l'agent se reconnaît ──")
    st, moi = appeler("GET", "/agent/me", jg)
    noter("GET /agent/me", *verdict_identite(moi, st))
    time.sleep(PACE)

    # ── 2. Créer un commerçant, positionné ──────────────────────────────────
    #
    # ⚠️ **Les sections « créé chez soi » et « pas chez un autre » ont disparu
    # le 2026-08-13** avec le territoire de l'agent. Elles étaient le sujet
    # même de ce banc — son titre disait « un commerçant naît dans SES
    # communes ».
    #
    # Ce qui reste est **le seul invariant de cette route** : la position est
    # obligatoire. Posée au lot 4 de la bascule géographique, elle est ce qui
    # empêche une tournée de fabriquer des fiches invisibles — 40 des 44
    # commerçants sans position mesurés le 2026-08-12 venaient d'ici.
    print("\n── 2. un commerçant créé par l'agent, avec sa position ──")
    base = time.strftime("%H%M%S")
    st, d = appeler("POST", "/agent/commercant", jg, {
        "telephone": "+213558%s" % base, "nom": "Commerce Agent",
        "pin": PIN, "adresse": "Rue de l'agent", "categorie": "alimentation",
        "latitude": DECOR_LAT, "longitude": DECOR_LNG})
    if st not in (200, 201):
        noter("création par l'agent", "non_concluant",
              "HTTP %s %s" % (st, d.get("code")))
        return 1
    cid = d.get("id")
    time.sleep(PACE)
    # Vérifié sur la RESSOURCE, pas sur le code de sortie.
    _, fiche = appeler("GET", "/commercant/%s/public" % cid)
    noter("le commerçant est né avec sa position", *verdict_position(fiche))
    time.sleep(PACE)

    # ── 3. Sans position, la création est refusée ───────────────────────────
    print("\n── 3. et sans position, elle est refusée ──")
    st, d = appeler("POST", "/agent/commercant", jg, {
        "telephone": "+213559%s" % base, "nom": "Commerce Sans Point",
        "pin": PIN, "adresse": "Rue d'ailleurs",
        "categorie": "alimentation"})
    noter("création sans latitude ni longitude",
          *verdict_refus_sans_position(st, d.get("code")))

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
