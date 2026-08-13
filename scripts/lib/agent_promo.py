#!/usr/bin/env python3
"""Banc de la promo créée par l'agent — à qui elle appartient, et avec quelle clé.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

`POST /promo/agent/:commercantId` fait agir un compte **pour le compte d'un
autre**. Deux détails y sont contre-intuitifs, et tous deux ont produit un
défaut réel.

1. **La promo appartient au COMMERÇANT, pas à l'agent.** C'est ce que le client
   voit, ce que le plafond de 5 actives décompte, et ce que la suppression du
   compte emporte. Si `commercantId` portait l'agent, la promo survivrait à la
   fermeture du commerce et compterait sur le mauvais quota.

2. **La clé S3 peut porter le préfixe de l'AGENT.** Défaut trouvé le
   2026-08-05 : `photoKey` fuyait dans la réponse publique et contenait
   « l'UUID de l'agent (pas du commerçant) pour les promos créées par un
   agent ». Le garde `assertPhotoKeysOwned` doit donc accepter **deux**
   propriétaires possibles — et c'est exactement le genre de subtilité qu'un
   resserrement ultérieur casse sans s'en apercevoir : l'agent ne pourrait plus
   déposer de photo, sur le terrain, sans que personne ne comprenne pourquoi.

3. **L'agent est exempté du plafond quotidien**, sans quoi tous les autres
   bancs échoueraient à poser leur décor.

── Ce qu'il n'éprouve PAS, et pourquoi ─────────────────────────────────────

Que l'agent soit refusé hors de ses communes. ⚠️ **Il ne l'est plus depuis le
2026-08-13** : l'agent est global, la notion de territoire a disparu, et
`appartenance.py` est suspendu en attendant d'être réécrit pour prouver
l'inverse — qu'il est ACCEPTÉ partout. Le plafond de 5 actives sous course est
l'objet de
`test-promo-plafond`.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/agent_promo.py --self-test
    ./scripts/test-agent-promo.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.1"))
DEVICE_ID = "banc-agent-promo-0001"


def verdict_proprietaire(commercant_id_promo, cid_attendu):
    if commercant_id_promo is None:
        return "non_concluant", "promo illisible"
    if commercant_id_promo != cid_attendu:
        return ("echec",
                "la promo appartient à %s, pas au commerçant %s — elle "
                "survivrait à la fermeture du commerce et compterait sur le "
                "mauvais quota"
                % (commercant_id_promo[:8], cid_attendu[:8]))
    return "ok", "commercantId = %s" % cid_attendu[:8]


def verdict_cle_agent(statut, code):
    """Une clé au préfixe de l'AGENT doit être acceptée."""
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if statut in (200, 201):
        return "ok", "acceptée (%s)" % statut
    if code == "STORAGE_KEY_NOT_OWNED":
        return ("echec",
                "clé au préfixe de l'agent REFUSÉE — un agent ne peut plus "
                "déposer de photo sur le terrain, et personne ne comprendra "
                "pourquoi")
    return "echec", "refusée pour une autre raison (%s, %s)" % (statut, code)


def verdict_exemption(statut, code):
    """L'agent ne doit pas se heurter au plafond quotidien du commerçant."""
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if statut in (200, 201):
        return "ok", "créée malgré le quota du commerçant"
    if code == "PROMO_DAILY_CREATION_CAP_REACHED":
        return ("echec",
                "l'agent se heurte au plafond QUOTIDIEN du commerçant — "
                "l'exemption a sauté, et tous les décors de bancs avec elle")
    return "non_concluant", "refusée pour une autre raison (%s, %s)" % (statut, code)


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
    _v("bon propriétaire", verdict_proprietaire("c1", "c1")[0], "ok")
    _v("clé agent acceptée", verdict_cle_agent(201, None)[0], "ok")
    _v("exemption tenue", verdict_exemption(201, None)[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ La promo attribuée à l'agent : elle survit au commerce et fausse les
    # quotas.
    _v("promo attribuée à l'agent",
       verdict_proprietaire("agent1", "c1")[0], "echec")
    _v("promo illisible → non concluant",
       verdict_proprietaire(None, "c1")[0], "non_concluant")
    # ⚠️ Le resserrement qui casse le terrain sans qu'on le voie.
    _v("clé agent refusée",
       verdict_cle_agent(403, "STORAGE_KEY_NOT_OWNED")[0], "echec")
    _v("clé refusée autrement",
       verdict_cle_agent(400, "VALIDATION_ERROR")[0], "echec")
    _v("429 sur la clé → non concluant",
       verdict_cle_agent(429, None)[0], "non_concluant")
    _v("exemption perdue",
       verdict_exemption(400, "PROMO_DAILY_CREATION_CAP_REACHED")[0], "echec")
    _v("autre refus → non concluant",
       verdict_exemption(400, "PROMO_ACTIVE_CAP_REACHED")[0], "non_concluant")

    refus = 6
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


def main():
    agent_email = _exiger("AGENT_EMAIL")
    agent_password = _exiger("AGENT_PASSWORD")
    cid = _exiger("COMMERCANT_ID")

    print("═" * 64)
    print("  Promo créée par l'agent — propriétaire, clé, exemption")
    print("═" * 64)

    st, d = appeler("POST", "/agent/login",
                    corps={"email": agent_email, "password": agent_password})
    jg = d.get("accessToken")
    if not jg:
        print("❌ connexion agent impossible (HTTP %s, %s)" % (st, d.get("code")))
        return 2
    time.sleep(PACE)
    _, moi = appeler("GET", "/agent/me", jg)
    aid = moi.get("id")
    if not aid:
        print("❌ GET /agent/me ne rend pas d'identifiant.")
        return 2
    time.sleep(PACE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-42s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    def corps(marque, cle):
        return {"description": "Promo agent %s" % marque, "prixAvant": 700,
                "prixApres": 400, "categorie": "alimentation",
                "photoKeys": [cle]}

    # ── 1. La clé au préfixe du COMMERÇANT ──────────────────────────────────
    print("\n── 1. clé au préfixe du commerçant ──")
    st, d = appeler("POST", "/promo/agent/%s" % cid, jg,
                    corps("cle-commercant", "promo-photos/%s/a.jpg" % cid))
    noter("acceptée", *verdict_exemption(st, d.get("code")))
    pid = d.get("id")
    if pid:
        time.sleep(PACE)
        _, promo = appeler("GET", "/promo/%s" % pid)
        noter("la promo appartient au commerçant",
              *verdict_proprietaire(promo.get("commercantId"), cid))
    time.sleep(PACE)

    # ── 2. La clé au préfixe de l'AGENT ─────────────────────────────────────
    #
    # ⚠️ Contre-intuitif, et documenté : `photoKey` contient l'UUID de l'AGENT
    # pour les promos créées par un agent. Le garde doit accepter les deux
    # propriétaires possibles.
    print("\n── 2. clé au préfixe de l'AGENT (les deux sont légitimes) ──")
    st, d = appeler("POST", "/promo/agent/%s" % cid, jg,
                    corps("cle-agent", "promo-photos/%s/b.jpg" % aid))
    noter("clé au préfixe de l'agent", *verdict_cle_agent(st, d.get("code")))
    pid2 = d.get("id")
    if pid2:
        time.sleep(PACE)
        _, promo = appeler("GET", "/promo/%s" % pid2)
        noter("elle appartient quand même au commerçant",
              *verdict_proprietaire(promo.get("commercantId"), cid))
    time.sleep(PACE)

    # ── 3. Une clé qui n'appartient à personne ──────────────────────────────
    print("\n── 3. mais pas une clé qui n'appartient à personne ──")
    st, d = appeler("POST", "/promo/agent/%s" % cid, jg,
                    corps("cle-orpheline", "promo-photos/nimporte-quoi/c.jpg"))
    if st in (200, 201):
        noter("clé orpheline refusée", "echec",
              "ACCEPTÉE — n'importe quel fichier peut être rattaché")
    elif d.get("code") == "STORAGE_KEY_NOT_OWNED":
        noter("clé orpheline refusée", "ok", "403 STORAGE_KEY_NOT_OWNED")
    else:
        noter("clé orpheline refusée", "non_concluant",
              "refusée en %s/%s" % (st, d.get("code")))

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
