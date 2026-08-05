#!/usr/bin/env python3
"""Banc de la modération — masquer, rétablir, avertir, et l'effet CLIENT.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

Trois décisions d'admin dont l'effet réel se produit **ailleurs** : dans la
liste que voit le client. C'est ce décalage qui les rend dangereuses — la
réponse peut être `200` et la promo rester visible, sans que rien ne l'indique.

Le défaut fondateur date du **2026-08-05**, et il portait sur `avertir` :
`resolveAvertir` ne remettait `moderationStatus` à `NORMALE` **que** si la
promo était `SIGNALEE`. Avertir une promo **MASQUÉE** la laissait donc masquée
— l'admin croyait avoir levé la sanction en la ramenant à un simple
avertissement, et la promo restait invisible du client. Aucune erreur, aucun
journal : juste un commerçant qui ne comprend pas.

Quatre sondes, toutes vérifiées sur **ce que le client voit**, jamais sur le
code de sortie :

1. `masquer` retire la promo de l'affichage client.
2. `verifier-ok` l'y ramène — le masque est bien levé.
3. `avertir` depuis MASQUÉE la repasse en **brouillon** *et* remet
   `moderationStatus` à `normale`. La promo reste invisible, et c'est voulu :
   « c'est le retour en brouillon qui porte la sanction, pas le masque ». Ce
   qui est éprouvé ici, c'est que **le masque est levé** — sans quoi le
   commerçant republie, consomme un de ses 5 emplacements, obtient 0 vue, et
   n'a aucun moyen de le voir : `moderationStatus` n'est affiché sur aucun
   écran commerçant.
4. Chaque décision laisse une trace neuve (règle 11).

⚠️ La première version de ce banc exigeait qu'`avertir` **rende la promo
visible** — une visibilité que le produit ne promet pas. Le banc avait tort, le
serveur non. Sonder un effet plutôt qu'une règle produit exactement ce genre de
faux rouge.

⚠️ Le banc crée sa propre promo : masquer celle du décor la retirerait des
bancs qui en ont besoin.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/admin_moderation.py --self-test
    ./scripts/test-admin-moderation.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.1"))
DEVICE_ID = "banc-moderation-0001"


def verdict_visibilite(visible, attendu, geste):
    """L'effet se constate chez le CLIENT, pas dans la réponse de l'admin."""
    if visible is None:
        return "non_concluant", "liste client illisible"
    if visible != attendu:
        if attendu:
            return ("echec",
                    "après « %s » la promo reste INVISIBLE du client — la "
                    "sanction n'a pas été levée, et rien ne le dit" % geste)
        return ("echec",
                "après « %s » la promo est TOUJOURS servie au client — la "
                "décision d'admin n'a eu aucun effet" % geste)
    return "ok", "client : %s" % ("visible" if attendu else "retirée")


def verdict_masque_leve(moderation_status, lifecycle_status):
    """Après « avertir », la sanction est le BROUILLON — pas le masque.

    ⚠️ C'est le correctif du 2026-08-05 : `resolveAvertir` ne débloquait que
    `SIGNALEE`, jamais `MASQUEE`. Le commerçant recevait « republiez-la »,
    republiait, et restait masqué — invisible, sans aucun écran pour le lui
    dire.
    """
    if moderation_status is None:
        return "non_concluant", "statut de modération illisible"
    if moderation_status != "normale":
        return ("echec",
                "moderationStatus=%r après « avertir » — le masque n'est pas "
                "levé, le commerçant republiera pour rien"
                % moderation_status)
    if lifecycle_status != "brouillon":
        return ("echec",
                "lifecycleStatus=%r au lieu de brouillon — la sanction "
                "annoncée par la notification n'a pas été appliquée"
                % lifecycle_status)
    return "ok", "brouillon, modération normale (masque levé)"


def verdict_trace(entrees, action, ids_avant):
    neuves = [e for e in entrees
              if e.get("action") == action and e.get("id") not in ids_avant]
    if not neuves:
        return "echec", "aucune trace neuve « %s » (règle 11)" % action
    return "ok", action


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


def visible(pid):
    st, d = appeler("GET", "/promo?limit=100")
    if st != 200:
        return None
    return pid in {p["id"] for p in d.get("items", [])}


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
    _v("masquée effectivement", verdict_visibilite(False, False, "masquer")[0], "ok")
    _v("rétablie effectivement", verdict_visibilite(True, True, "verifier-ok")[0], "ok")
    _v("masque levé, sanction posée",
       verdict_masque_leve("normale", "brouillon")[0], "ok")
    _v("trace présente",
       verdict_trace([{"id": "n", "action": "x"}], "x", set())[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    _v("masque non levé après avertir",
       verdict_masque_leve("masquee", "brouillon")[0], "echec")
    _v("sanction non appliquée",
       verdict_masque_leve("normale", "publiee")[0], "echec")
    _v("statut illisible → non concluant",
       verdict_masque_leve(None, "brouillon")[0], "non_concluant")
    _v("rétablissement non fait", verdict_visibilite(False, True, "verifier-ok")[0], "echec")
    _v("masquage sans effet",
       verdict_visibilite(True, False, "masquer")[0], "echec")
    _v("liste illisible → non concluant",
       verdict_visibilite(None, True, "x")[0], "non_concluant")
    _v("décision non tracée", verdict_trace([], "x", set())[0], "echec")
    _v("trace ancienne seulement",
       verdict_trace([{"id": "v", "action": "x"}], "x", {"v"})[0], "echec")

    refus = 7
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
    agent_password = _exiger("AGENT_PASSWORD")
    cid = _exiger("COMMERCANT_ID")

    print("═" * 64)
    print("  Modération — l'effet se constate chez le client")
    print("═" * 64)

    def connecter(chemin, corps, qui):
        st, d = appeler("POST", chemin, corps=corps)
        j = d.get("accessToken")
        if not j:
            print("❌ connexion %s impossible (HTTP %s, %s)"
                  % (qui, st, d.get("code")))
            sys.exit(2)
        time.sleep(PACE)
        return j

    ja = connecter("/admin/login",
                   {"email": admin_email, "password": admin_password}, "admin")
    jg = connecter("/agent/login",
                   {"email": agent_email, "password": agent_password}, "agent")

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-42s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    def journal_ids():
        _, d = appeler("GET", "/admin/audit-log?limit=100", ja)
        return {e.get("id") for e in d.get("items", [])}

    # ── Décor propre au banc ────────────────────────────────────────────────
    print("\n── décor : une promo à modérer ──")
    st, d = appeler("POST", "/promo/agent/%s" % cid, jg, {
        "description": "Promo du banc modération", "prixAvant": 800,
        "prixApres": 500, "categorie": "alimentation",
        "photoKeys": ["promo-photos/%s/moderation.jpg" % cid]})
    pid = d.get("id")
    if not pid:
        print("❌ création refusée (HTTP %s, %s)" % (st, d.get("code")))
        return 2
    time.sleep(PACE)
    if visible(pid) is not True:
        noter("la promo est visible au départ", "non_concluant",
              "elle ne l'est pas — la suite ne prouverait rien")
        return 1
    noter("la promo est visible au départ", "ok", pid[:8])
    time.sleep(PACE)

    # ── 1. Masquer ──────────────────────────────────────────────────────────
    print("\n── 1. masquer retire la promo de l'affichage client ──")
    avant = journal_ids()
    time.sleep(PACE)
    st, d = appeler("POST", "/admin/moderation/%s/masquer" % pid, ja,
                    {"reason": "banc"})
    if st not in (200, 201):
        noter("masquer", "non_concluant", "HTTP %s %s" % (st, d.get("code")))
        return 1
    time.sleep(PACE)
    noter("masquer", *verdict_visibilite(visible(pid), False, "masquer"))
    _, j = appeler("GET", "/admin/audit-log?limit=100", ja)
    time.sleep(PACE)

    # ── 2. verifier-ok lève le masque et ramène la promo ────────────────────
    print("\n── 2. verifier-ok lève le masque ──")
    st, d = appeler("POST", "/admin/moderation/%s/verifier-ok" % pid, ja,
                    {"reason": "banc"})
    if st not in (200, 201):
        noter("verifier-ok", "non_concluant", "HTTP %s %s" % (st, d.get("code")))
        return 1
    time.sleep(PACE)
    noter("verifier-ok (depuis masquée)",
          *verdict_visibilite(visible(pid), True, "verifier-ok"))
    time.sleep(PACE)

    # ── 3. Avertir depuis MASQUÉE — le cas fondateur ────────────────────────
    #
    # ⚠️ La promo redevient invisible, et c'est VOULU : la sanction d'un
    # avertissement est le retour en brouillon (« c'est le retour en brouillon
    # qui porte la sanction, pas le masque »). Ce qu'on éprouve ici est que le
    # MASQUE est levé — sans quoi le commerçant republie, consomme un de ses 5
    # emplacements, obtient 0 vue, et n'a aucun écran pour le lui dire.
    #
    # La première version de ce banc exigeait la VISIBILITÉ après « avertir ».
    # Le banc avait tort, le serveur non : sonder un effet plutôt qu'une règle
    # produit exactement ce genre de faux rouge.
    print("\n── 3. avertir depuis MASQUÉE : brouillon, mais masque levé ──")
    appeler("POST", "/admin/moderation/%s/masquer" % pid, ja, {"reason": "banc"})
    time.sleep(PACE)
    st, d = appeler("POST", "/admin/moderation/%s/avertir" % pid, ja,
                    {"reason": "banc"})
    if st not in (200, 201):
        noter("avertir", "non_concluant", "HTTP %s %s" % (st, d.get("code")))
        return 1
    time.sleep(PACE)
    _, vue_admin = appeler("GET", "/admin/promo?limit=100", ja)
    etat = next((p for p in vue_admin.get("items", []) if p.get("id") == pid),
                {})
    noter("avertir (depuis masquée)",
          *verdict_masque_leve(etat.get("moderationStatus"),
                               etat.get("lifecycleStatus")))
    time.sleep(PACE)

    # ── 4. Les traces ───────────────────────────────────────────────────────
    print("\n── 4. chaque décision laisse une trace ──")
    _, journal = appeler("GET", "/admin/audit-log?limit=100", ja)
    entrees = journal.get("items", [])
    for action in ("moderation_masquer", "moderation_avertir",
                   "moderation_verifier_ok"):
        # Les trois actions SONT journalisées (`ModerationService.record`,
        # lignes 80/100/120) : la sonde est donc stricte, pas prudente. Une
        # sonde tolérante ici ne vaudrait rien — c'est exactement le geste
        # qu'un journal d'audit existe pour retenir.
        noter(action, *verdict_trace(entrees, action, avant))

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
