#!/usr/bin/env python3
"""Banc du signalement — changer un en-tête ne doit pas suffire.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

`POST /report` est la seule route d'écriture ouverte aux anonymes, et elle
porte la **règle 7** dans son énoncé exact : *un endpoint public protégé
uniquement par un identifiant déclaratif fourni par le client doit être
rate-limité par IP*.

Le défaut trouvé à l'audit V0 : `X-Device-Id` n'est **jamais vérifié côté
serveur**. Il suffisait donc de le changer trois fois pour faire masquer la
promo d'un concurrent — trois requêtes, un en-tête, aucun compte. Le correctif
n'a pas été de vérifier l'en-tête (impossible : il n'est adossé à rien) mais de
**borner par IP**, ce qui rend l'attaque coûteuse là où elle était gratuite.

Quatre sondes :

1. **L'en-tête est requis.** Sans lui l'anti-doublon n'a aucune prise, et un
   seul appareil pourrait signaler indéfiniment.
2. **Le seuil de modération masque la promo** — c'est l'effet recherché quand
   les signalements sont légitimes.
3. **Changer `X-Device-Id` ne contourne PAS le plafond IP.** C'est le
   correctif : le seau est compté par IP, pas par appareil déclaré. Sans lui,
   l'attaque d'origine reste gratuite.
4. **Le refus de plafond est un `429`**, reconnaissable — pas un refus déguisé.

⚠️ **Ce banc épuise le seau strict** (5/min) et masque une promo. Il crée la
sienne, et doit tourner **seul**.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/abus_signalement.py --self-test
    ./scripts/test-abus-signalement.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "0.4"))


def verdict_entete_requis(statut, code):
    if statut in (200, 201):
        return ("echec",
                "signalement ACCEPTÉ sans X-Device-Id — l'anti-doublon n'a "
                "aucune prise, un seul appareil peut signaler indéfiniment")
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if code != "DEVICE_ID_MISSING":
        return "non_concluant", "refusé en %s/%s" % (statut, code)
    return "ok", "%s %s" % (statut, code)


def verdict_masquee(visible, signalements_acceptes, seuil_observe):
    """Au-delà du seuil, la promo doit quitter l'affichage client."""
    if visible is None:
        return "non_concluant", "liste client illisible"
    if signalements_acceptes < seuil_observe:
        return ("non_concluant",
                "%d signalement(s) acceptés seulement — le seuil n'a pas été "
                "atteint, la suite ne prouverait rien" % signalements_acceptes)
    if visible:
        return ("echec",
                "%d signalements acceptés et la promo est TOUJOURS visible — "
                "le seuil de modération ne produit aucun effet"
                % signalements_acceptes)
    return "ok", "masquée après %d signalements" % signalements_acceptes


def verdict_plafond_ip(statuts):
    """Changer l'appareil déclaré ne doit pas rouvrir le seau."""
    if 429 not in statuts:
        return ("echec",
                "%d signalements depuis la MÊME IP avec des X-Device-Id "
                "différents, sans jamais de 429 — changer un en-tête suffit "
                "encore à masquer la promo d'un concurrent (règle 7)"
                % len(statuts))
    return "ok", "429 au %de envoi" % (statuts.index(429) + 1)


# ─────────────────────────────────────────────────────────────────────────────

def signaler(promo_id, device=None, raison="arnaque"):
    donnees = json.dumps({"promoId": promo_id, "reason": raison}).encode()
    req = urllib.request.Request(API_URL + "/report", data=donnees,
                                 method="POST")
    req.add_header("Content-Type", "application/json")
    if device:
        req.add_header("X-Device-Id", device)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}").get("code")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read()).get("code")
        except Exception:
            return e.code, None
    except Exception as e:
        return None, "RESEAU: %s" % e


def appeler(methode, chemin, jeton=None, corps=None):
    donnees = json.dumps(corps).encode() if corps is not None else None
    req = urllib.request.Request(API_URL + chemin, data=donnees, method=methode)
    req.add_header("Content-Type", "application/json")
    req.add_header("X-Device-Id", "banc-abus-0001")
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
    _v("en-tête exigé",
       verdict_entete_requis(400, "DEVICE_ID_MISSING")[0], "ok")
    _v("promo masquée", verdict_masquee(False, 3, 3)[0], "ok")
    _v("plafond IP tenu", verdict_plafond_ip([201, 201, 201, 429])[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    _v("signalement anonyme accepté",
       verdict_entete_requis(201, None)[0], "echec")
    _v("refus au mauvais code",
       verdict_entete_requis(400, "VALIDATION_ERROR")[0], "non_concluant")
    _v("seuil sans effet", verdict_masquee(True, 3, 3)[0], "echec")
    _v("seuil non atteint → non concluant",
       verdict_masquee(True, 1, 3)[0], "non_concluant")
    _v("liste illisible → non concluant",
       verdict_masquee(None, 3, 3)[0], "non_concluant")
    # ⚠️ LE défaut de la règle 7 : changer l'en-tête rouvre le seau.
    _v("plafond IP contourné",
       verdict_plafond_ip([201] * 10)[0], "echec")

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
    print("  Signalement — changer un en-tête ne doit pas suffire")
    print("═" * 64)
    print("  ⚠️ ce banc épuise le seau strict : il doit tourner SEUL")

    st, d = appeler("POST", "/agent/login",
                    corps={"email": agent_email, "password": agent_password})
    jg = d.get("accessToken")
    if not jg:
        print("❌ connexion agent impossible (HTTP %s, %s)" % (st, d.get("code")))
        return 2
    time.sleep(1.2)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-42s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    def visible(pid):
        st, d = appeler("GET", "/promo?limit=100")
        if st != 200:
            return None
        return pid in {p["id"] for p in d.get("items", [])}

    # ── Décor : une promo à sacrifier ───────────────────────────────────────
    print("\n── décor : une promo à signaler ──")
    st, d = appeler("POST", "/promo/agent/%s" % cid, jg, {
        "description": "Promo du banc signalement", "prixAvant": 900,
        "prixApres": 600, "categorie": "alimentation",
        "photoKeys": ["promo-photos/%s/abus.jpg" % cid]})
    pid = d.get("id")
    if not pid:
        print("❌ création refusée (HTTP %s, %s)" % (st, d.get("code")))
        return 2
    noter("promo créée", "ok", pid[:8])
    time.sleep(1.2)

    # ── 1. L'en-tête est requis ─────────────────────────────────────────────
    print("\n── 1. sans X-Device-Id, l'anti-doublon n'a aucune prise ──")
    st, code = signaler(pid, device=None)
    noter("signalement sans en-tête", *verdict_entete_requis(st, code))
    time.sleep(PACE)

    # ── 2 et 3. Le seuil, puis le plafond IP ────────────────────────────────
    #
    # ⚠️ Les deux sondes partagent la même série : on signale depuis la MÊME IP
    # en changeant l'appareil DÉCLARÉ à chaque fois — exactement l'attaque
    # d'origine. Les premiers passent (c'est le seuil de modération), les
    # suivants doivent buter sur le plafond d'IP.
    print("\n── 2. signaler en changeant l'appareil déclaré à chaque fois ──")
    statuts, acceptes = [], 0
    for i in range(10):
        st, code = signaler(pid, device="faux-appareil-%d" % i)
        statuts.append(st)
        if st in (200, 201):
            acceptes += 1
        if st == 429:
            break
        time.sleep(PACE)
    print("     %d envoyés, %d acceptés" % (len(statuts), acceptes))

    noter("le plafond par IP tient", *verdict_plafond_ip(statuts))
    time.sleep(1.2)
    noter("la promo est masquée au seuil",
          *verdict_masquee(visible(pid), acceptes, 3))

    print("\n" + "═" * 64)
    echecs = resultats.count("echec")
    non_concluants = resultats.count("non_concluant")
    print("%d contrôles, %d échec(s), %d non concluant(s)"
          % (len(resultats), echecs, non_concluants))
    print("⚠️  attendre une minute avant tout autre banc : le seau est vide.")
    if non_concluants and not echecs:
        print("⚠️  des sondes n'ont pas conclu : ce n'est pas une réussite.")
    return 1 if (echecs or non_concluants) else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)
    sys.exit(main())
