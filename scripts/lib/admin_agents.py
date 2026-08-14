#!/usr/bin/env python3
"""Banc des agents — création et réinitialisation, effets et traces vérifiés.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

⚠️ **Le sujet de ce banc a changé le 2026-08-13.** Il éprouvait
`PATCH /admin/agent/:id/communes` et `POST /admin/agent/transfer-communes`, les
deux gestes qui **élargissaient le périmètre IDOR** d'un agent. Ces routes ont
disparu avec le territoire.

**Ce qui survit est ce qui comptait le plus** : `verdict_trace`. C'est le seul
contrôle du parc qui éprouve qu'une action d'administration **laisse une
trace**, et il porte le cas fondateur de la règle 11 — un `AuditLogModule` bien
conçu, présent depuis le premier commit du backend, qui n'a jamais tracé une
seule action pendant des semaines. La gestion d'agents en est le dernier
terrain d'épreuve.

Trois sondes :

1. **Créer un agent le fait exister**, vérifié sur `GET /admin/agent` et non
   sur le code de sortie : un 201 dit qu'une requête a été acceptée, pas
   qu'une ressource existe.
2. **La création laisse une trace NEUVE nommant son auteur.** « Neuve » est
   essentiel : une trace ancienne du même type rendrait la sonde verte sans
   que le geste ait rien écrit.
3. **La réinitialisation de mot de passe laisse la sienne** — geste qui donne
   accès à un compte agent, donc à tout le parc depuis la portée globale.

⚠️ **Ce banc laisse un agent de plus à chaque passage** : il n'existe aucune
route de suppression d'agent. C'est un manque du produit, pas seulement une
gêne — un agent global qui ne peut être que révoqué, jamais supprimé, est un
compte permanent.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/admin_agents.py --self-test
    ./scripts/test-admin-agents.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.2"))
DEVICE_ID = "banc-admin-agents-0001"


def verdict_presence(annuaire, email):
    """L'agent créé doit apparaître dans la liste, pas seulement être accepté.

    ⚠️ Vérifié sur la RESSOURCE et non sur le code de sortie de la création :
    un 201 dit qu'une requête a été acceptée, pas qu'un compte existe.
    """
    if not annuaire:
        return "non_concluant", "annuaire illisible"
    if email not in annuaire:
        return ("echec",
                "création acceptée mais l'agent est absent de "
                "GET /admin/agent — le compte n'existe pas")
    return "ok", "présent dans l'annuaire"


def verdict_trace(entrees, action, ids_avant):
    """Le geste doit laisser une trace NEUVE nommant son auteur (règle 11)."""
    neuves = [e for e in entrees
              if e.get("action") == action and e.get("id") not in ids_avant]
    if not neuves:
        return ("echec",
                "aucune trace neuve « %s » — le geste qui élargit un périmètre "
                "IDOR n'est pas journalisé (règle 11)" % action)
    if not neuves[0].get("actorId"):
        return "echec", "trace sans actorId — on ne saura pas qui a élargi"
    return "ok", "%s par %s" % (action, neuves[0]["actorId"][:8])


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
    _v("agent présent dans l'annuaire",
       verdict_presence({"a@b.c": {}}, "a@b.c")[0], "ok")
    _v("trace présente",
       verdict_trace([{"id": "n", "action": "x", "actorId": "a1"}], "x",
                     set())[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Création acceptée, compte absent : un 201 dit qu'une requête a été
    # acceptée, pas qu'une ressource existe.
    _v("créé mais absent de l'annuaire",
       verdict_presence({"autre@b.c": {}}, "a@b.c")[0], "echec")
    _v("annuaire illisible → non concluant",
       verdict_presence({}, "a@b.c")[0], "non_concluant")
    _v("geste non tracé", verdict_trace([], "x", set())[0], "echec")
    _v("trace ancienne seulement",
       verdict_trace([{"id": "v", "action": "x", "actorId": "a"}], "x",
                     {"v"})[0], "echec")
    _v("trace anonyme",
       verdict_trace([{"id": "n", "action": "x", "actorId": ""}], "x",
                     set())[0], "echec")

    refus = 5
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


def main():
    admin_email = _exiger("ADMIN_EMAIL")
    admin_password = _exiger("ADMIN_PASSWORD")
    agent_email = _exiger("AGENT_EMAIL")
    agent_b_email = _exiger("AGENT_B_EMAIL")

    print("═" * 64)
    print("  Agents — création et réinitialisation, effets et traces vérifiés")
    print("═" * 64)

    st, d = appeler("POST", "/admin/login",
                    corps={"email": admin_email, "password": admin_password})
    ja = d.get("accessToken")
    if not ja:
        print("❌ connexion admin impossible (HTTP %s, %s)" % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-42s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    def agents():
        _, d = appeler("GET", "/admin/agent?limit=100", ja)
        return {a["email"]: a for a in d.get("items", [])}

    def journal_ids():
        _, d = appeler("GET", "/admin/audit-log?limit=100", ja)
        return {e.get("id") for e in d.get("items", [])}

    tous = agents()
    if agent_email not in tous or agent_b_email not in tous:
        print("❌ les agents du décor sont introuvables dans /admin/agent.")
        return 2
    time.sleep(PACE)

    # ⚠️ **Les sections « assigner » et « transférer » ont disparu le
    # 2026-08-13** avec leurs deux routes. Elles étaient le sujet de ce banc.
    #
    # **Ce qui survit est ce qui comptait le plus** : le mécanisme
    # `verdict_trace`. C'est le seul contrôle du parc qui éprouve qu'une action
    # d'administration **laisse une trace**, et il porte le cas fondateur de la
    # règle 11 — un `AuditLogModule` bien conçu qui n'a jamais rien tracé
    # pendant des semaines. La gestion d'agents en est le dernier terrain.

    # ── 1. Créer un agent laisse une trace ──────────────────────────────────
    print("\n── 1. la création d'un agent est tracée ──")
    avant_journal = journal_ids()
    time.sleep(PACE)
    base = time.strftime("%H%M%S")
    email_neuf = "banc-agents-%s@echango.local" % base
    st, d = appeler("POST", "/admin/agent", ja, {
        "email": email_neuf, "password": "banc-agents-2026",
        "nom": "Agent du banc"})
    if st not in (200, 201):
        noter("création d'agent", "non_concluant",
              "HTTP %s %s" % (st, d.get("code")))
        return 1
    id_neuf = d.get("id")
    time.sleep(PACE)

    # Vérifié sur la RESSOURCE : l'agent doit apparaître dans la liste, pas
    # seulement avoir été accepté.
    noter("l'agent apparaît dans la liste",
          *verdict_presence(agents(), email_neuf))
    time.sleep(PACE)

    _, journal = appeler("GET", "/admin/audit-log?limit=100", ja)
    noter("la création est tracée",
          *verdict_trace(journal.get("items", []), "create_agent",
                         avant_journal))
    time.sleep(PACE)

    # ── 2. Réinitialiser un mot de passe laisse une trace ───────────────────
    print("\n── 2. la réinitialisation de mot de passe est tracée ──")
    avant_journal = journal_ids()
    time.sleep(PACE)
    st, d = appeler("POST", "/admin/agent/%s/reset-password" % id_neuf, ja,
                    {"newPassword": "banc-agents-2026-bis"})
    if st not in (200, 201):
        noter("réinitialisation", "non_concluant",
              "HTTP %s %s" % (st, d.get("code")))
    else:
        time.sleep(PACE)
        _, journal = appeler("GET", "/admin/audit-log?limit=100", ja)
        noter("la réinitialisation est tracée",
              *verdict_trace(journal.get("items", []), "reset_agent_password",
                             avant_journal))
        time.sleep(PACE)

    # ⚠️ Pas de nettoyage : il n'existe **aucune route de suppression
    # d'agent**. Ce banc laisse donc un compte de plus à chaque passage — c'est
    # écrit ici plutôt que découvert dans six mois, et c'est un vrai manque du
    # produit, pas seulement une gêne de banc : un agent global qui ne peut
    # être que révoqué, jamais supprimé, est un compte permanent.
    print("\n   ⚠️  agent « %s » laissé en base (aucune route de suppression)"
          % email_neuf)

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
