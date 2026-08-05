#!/usr/bin/env python3
"""Banc de création par l'agent — un commerçant naît dans SES communes.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

`POST /agent/commercant` est la porte par laquelle un agent de terrain inscrit
un commerce. Elle prend une `communeId` **fournie par l'appelant** — et c'est
exactement la forme d'un IDOR : le rôle est bon, le jeton est valide, et la
question devient « cette commune est-elle la sienne ? ».

C'est la règle 1 dans son énoncé : *le rôle JWT ne suffit jamais pour une
action sur la ressource d'un tiers*. La faille corrigée à l'audit V0 ne portait
que sur les promos ; la surface réelle inclut celle-ci.

Trois sondes :

1. **Le commerçant créé tombe dans une commune de l'agent** — vérifié sur la
   ressource, pas sur le code de sortie de la requête qui prétend l'avoir
   posée.
2. **Une commune qui n'est pas la sienne est refusée.** Le décor fournit un
   agent B aux communes disjointes : sa commune est le contre-exemple parfait.
3. **`GET /agent/me` dit la vérité sur son territoire** — c'est la seule source
   dont dispose l'app pour composer ses écrans, et c'est aussi ce dont ce banc
   se sert pour savoir ce qui est légitime.

⚠️ La disjonction des deux agents est **vérifiée**, pas supposée : le décor l'a
laissée se perdre une fois (agent A avait accumulé quatre communes, dont celle
de l'agent B). Si elle ne tient pas, la sonde n°2 ne conclut pas.

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


def verdict_commune(commune_creee, communes_agent):
    """Le commerçant doit naître chez son agent."""
    if not communes_agent:
        return "non_concluant", "l'agent n'a aucune commune — décor incomplet"
    if commune_creee is None:
        return "echec", "le commerçant créé n'a pas de commune"
    if commune_creee not in communes_agent:
        return ("echec",
                "créé dans %s, hors des %d commune(s) de l'agent — un agent "
                "peut inscrire hors de son territoire"
                % (commune_creee[:8], len(communes_agent)))
    return "ok", "commune %s, dans son territoire" % commune_creee[:8]


def verdict_refus_commune(statut, code):
    """Créer dans la commune d'un autre doit être refusé."""
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if statut is None:
        return "echec", "pas de réponse : %s" % code
    if statut in (200, 201):
        return ("echec",
                "création ACCEPTÉE dans une commune qui n'est pas la sienne — "
                "l'agent élargit son territoire tout seul (règle 1)")
    if statut >= 500 or code == "INTERNAL_ERROR":
        return "echec", "HTTP %s %s — casse au lieu de refuser" % (statut, code)
    return "ok", "%s %s" % (statut, code)


def verdict_territoire(communes, statut):
    if statut != 200:
        return "non_concluant", "GET /agent/me illisible (HTTP %s)" % statut
    if not communes:
        return "echec", "l'agent ne connaît aucune de ses communes"
    return "ok", "%d commune(s)" % len(communes)


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
    _v("créé chez lui", verdict_commune("c1", {"c1", "c2"})[0], "ok")
    _v("refus attendu", verdict_refus_commune(403, "X")[0], "ok")
    _v("territoire connu", verdict_territoire(["c1"], 200)[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le cas de la règle 1 : le rôle est bon, la ressource ne l'est pas.
    _v("créé hors de son territoire",
       verdict_commune("z9", {"c1"})[0], "echec")
    _v("créé sans commune", verdict_commune(None, {"c1"})[0], "echec")
    _v("agent sans commune → non concluant",
       verdict_commune("c1", set())[0], "non_concluant")
    _v("création hors territoire acceptée",
       verdict_refus_commune(201, None)[0], "echec")
    _v("500 au lieu d'un refus",
       verdict_refus_commune(500, "INTERNAL_ERROR")[0], "echec")
    _v("429 → non concluant", verdict_refus_commune(429, None)[0], "non_concluant")
    _v("agent qui s'ignore", verdict_territoire([], 200)[0], "echec")
    _v("/agent/me illisible → non concluant",
       verdict_territoire([], 500)[0], "non_concluant")

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
    print("  Création par l'agent — un commerçant naît dans SES communes")
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
    print("\n── 1. ce que l'agent sait de son territoire ──")
    st, moi = appeler("GET", "/agent/me", jg)
    communes_a = [c["id"] for c in (moi.get("communes") or [])]
    noter("GET /agent/me", *verdict_territoire(communes_a, st))
    if not communes_a:
        return 1
    time.sleep(PACE)

    st, moi_b = appeler("GET", "/agent/me", jb)
    communes_b = [c["id"] for c in (moi_b.get("communes") or [])]
    time.sleep(PACE)

    # ── 2. Créer chez soi ───────────────────────────────────────────────────
    print("\n── 2. un commerçant créé tombe dans une commune de l'agent ──")
    base = time.strftime("%H%M%S")
    st, d = appeler("POST", "/agent/commercant", jg, {
        "telephone": "+213558%s" % base, "nom": "Commerce Agent",
        "pin": PIN, "adresse": "Rue de l'agent", "categorie": "alimentation",
        "communeId": communes_a[0]})
    if st not in (200, 201):
        noter("création chez soi", "non_concluant",
              "HTTP %s %s" % (st, d.get("code")))
        return 1
    cid = d.get("id")
    time.sleep(PACE)
    # Vérifié sur la RESSOURCE, pas sur le code de sortie.
    _, fiche = appeler("GET", "/commercant/%s/public" % cid)
    noter("le commerçant est né chez son agent",
          *verdict_commune(fiche.get("communeId"), set(communes_a)))
    time.sleep(PACE)

    # ── 3. Créer chez un autre ──────────────────────────────────────────────
    print("\n── 3. et pas dans la commune d'un autre ──")
    hors = [c for c in communes_b if c not in communes_a]
    if not hors:
        noter("prémisse : une commune hors territoire", "non_concluant",
              "les deux agents partagent leurs communes — relancer "
              "provision-decor.sh")
    else:
        st, d = appeler("POST", "/agent/commercant", jg, {
            "telephone": "+213559%s" % base, "nom": "Commerce Intrus",
            "pin": PIN, "adresse": "Rue d'ailleurs",
            "categorie": "alimentation", "communeId": hors[0]})
        noter("création dans la commune de l'agent B",
              *verdict_refus_commune(st, d.get("code")))

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
