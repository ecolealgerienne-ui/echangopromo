#!/usr/bin/env python3
"""Banc de cycle de vie — suspension ≠ suppression.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

Deux états qu'il serait facile de confondre, et dont la confusion se paie cher :

| | suspension | suppression |
|---|---|---|
| champ posé | `suspendedAt` | `deletedAt` |
| numéro de téléphone | **reste pris** | **libéré** |
| promos | `publiee` → `brouillon` (réversible) | → `supprimee` |
| réversible | oui | non |
| session en cours | révoquée | révoquée |

⚠️ **La réactivation ne republie RIEN.** C'est contre-intuitif et délibéré
(décision produit 2026-07-14) : le commerçant republie lui-même après avoir
vérifié que ses prix et dates sont encore à jour. Un banc qui supposerait le
contraire échouerait sur une intention, pas sur un défaut.

⚠️ **Le numéro est le vrai discriminant.** C'est la seule différence
*observable de l'extérieur* entre les deux états — et celle qui casse en
silence : si la suspension libérait le numéro, un tiers pourrait s'inscrire
avec le numéro d'un commerçant momentanément suspendu.

── Ce banc est destructeur, par nature ──────────────────────────────────────

Il supprime réellement un commerçant. Il travaille donc sur le SIEN, créé au
début et jamais réutilisé ailleurs — jamais sur celui du décor. Comme la
suppression libère le numéro, le banc est rejouable tel quel.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/cycle_commercant.py --self-test
    python3 scripts/lib/cycle_commercant.py
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "3.2"))
TEL = os.environ.get("TEL_CYCLE", "+213555000199")
PIN = "135791"


def appeler(methode, chemin, jeton=None, corps=None, entetes=None):
    donnees = json.dumps(corps if corps is not None else {}).encode() \
        if methode in ("POST", "PUT", "PATCH", "DELETE") else None
    req = urllib.request.Request(API_URL + chemin, data=donnees, method=methode)
    req.add_header("Content-Type", "application/json")
    if jeton:
        req.add_header("Authorization", "Bearer " + jeton)
    for k, v in (entetes or {}).items():
        req.add_header(k, v)
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
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_numero_pris(statut, code):
    """Le numéro doit être REFUSÉ : il appartient encore à quelqu'un."""
    if code == "COMMERCANT_PHONE_TAKEN":
        return "ok", "refusé (%s)" % code
    if statut in (200, 201):
        return "echec", "le numéro a été RÉATTRIBUÉ alors qu'il ne devait pas l'être"
    return "non_concluant", "refus pour une autre raison : %s (HTTP %s)" % (code, statut)


def verdict_numero_libre(statut, code):
    """Le numéro doit être ACCEPTÉ : la suppression l'a libéré."""
    if statut in (200, 201):
        return "ok", "accepté — le numéro a bien été libéré"
    if code == "COMMERCANT_PHONE_TAKEN":
        return "echec", "le numéro est resté pris après suppression"
    return "non_concluant", "refus pour une autre raison : %s (HTTP %s)" % (code, statut)


def verdict_session_revoquee(statut, code):
    if code == "AUTH_TOKEN_REVOKED":
        return "ok", code
    if statut in (200, 201):
        return "echec", "la session reste valide après un changement d'état de sécurité"
    return "non_concluant", "refus pour une autre raison : %s (HTTP %s)" % (code, statut)


def verdict_compte(observe, attendu, quoi):
    if observe == attendu:
        return "ok", "%d %s" % (observe, quoi)
    return "echec", "%d %s, attendu %d" % (observe, quoi, attendu)


# ─────────────────────────────────────────────────────────────────────────────

def _exiger(nom):
    v = os.environ.get(nom)
    if not v:
        print("❌ %s absent — lancer ./scripts/provision-decor.sh." % nom)
        sys.exit(2)
    return v


def self_test():
    cas = [
        (verdict_numero_pris, 400, "COMMERCANT_PHONE_TAKEN", "ok"),
        (verdict_numero_libre, 201, None, "ok"),
        (verdict_session_revoquee, 401, "AUTH_TOKEN_REVOKED", "ok"),
        # ── Doivent REFUSER ──────────────────────────────────────────────────
        # Le défaut visé : la suspension libère le numéro.
        (verdict_numero_pris, 201, None, "echec"),
        (verdict_numero_libre, 400, "COMMERCANT_PHONE_TAKEN", "echec"),
        (verdict_session_revoquee, 200, None, "echec"),
        # Un refus pour une AUTRE raison ne prouve rien.
        (verdict_numero_pris, 400, "VALIDATION_ERROR", "non_concluant"),
        (verdict_numero_libre, 429, "RATE_LIMITED", "non_concluant"),
        (verdict_session_revoquee, 403, "AUTH_FORBIDDEN_ROLE", "non_concluant"),
    ]
    echecs, passes = [], 0
    for fn, st, code, attendu in cas:
        obtenu, _ = fn(st, code)
        if obtenu == attendu:
            passes += 1
        else:
            echecs.append("%s(%s,%r)=%s attendu %s" % (fn.__name__, st, code, obtenu, attendu))

    for observe, attendu, verdict in ((2, 2, "ok"), (0, 2, "echec")):
        v, _ = verdict_compte(observe, attendu, "promos")
        if v == verdict:
            passes += 1
        else:
            echecs.append("verdict_compte(%d,%d)=%s attendu %s" % (observe, attendu, v, verdict))

    total = len(cas) + 2
    print("auto-test : %d cas, dont %d refus" % (total, 7))
    for e in echecs:
        print("  ❌ " + e)
    print("  %d/%d" % (passes, total))
    return not echecs


def main():
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)

    resultats = []

    def noter(libelle, verdict, quoi):
        icone = {"ok": "✅", "echec": "❌"}.get(verdict, "⚠️ ")
        print("  %s %-46s %s" % (icone, libelle, quoi))
        resultats.append((libelle, verdict, quoi))

    # ── Sessions ─────────────────────────────────────────────────────────────
    _, d = appeler("POST", "/admin/login", corps={
        "email": _exiger("ADMIN_EMAIL"), "password": _exiger("ADMIN_PASSWORD")})
    ja = d.get("accessToken")
    time.sleep(2)
    _, d = appeler("POST", "/agent/login", corps={
        "email": _exiger("AGENT_EMAIL"), "password": _exiger("AGENT_PASSWORD")})
    jg = d.get("accessToken")
    if not ja or not jg:
        print("❌ connexion impossible — décor à rejouer, ou plafond de 5/min.")
        sys.exit(2)

    print("════════════════════════════════════════════════════════════════")
    print("  Cycle de vie du commerçant — suspension ≠ suppression")
    print("════════════════════════════════════════════════════════════════")
    print("  numéro de travail : %s\n" % TEL)

    def trouver(tel):
        _, d = appeler("GET", "/admin/commercant?limit=100", ja)
        for i in d.get("items", []):
            if i.get("telephone") == tel:
                return i
        return None

    # ── Ménage d'entrée : le banc est rejouable ──────────────────────────────
    ancien = trouver(TEL)
    if ancien:
        appeler("POST", "/admin/commercant/%s/delete" % ancien["id"], ja)
        time.sleep(PACE)
        print("  ·  commerçant précédent supprimé (banc rejouable)\n")

    # ── Décor propre au banc ─────────────────────────────────────────────────
    commune = appeler("GET", "/commune")[1]["items"][0]["id"]
    st, d = appeler("POST", "/agent/commercant", jg, {
        "telephone": TEL, "nom": "Commerce Cycle", "pin": PIN,
        "adresse": "Rue du Cycle", "categorie": "alimentation", "communeId": commune})
    if st not in (200, 201):
        print("❌ création du commerçant de travail refusée : %s" % d.get("code"))
        sys.exit(2)
    cid = d.get("id") or trouver(TEL)["id"]
    time.sleep(PACE)

    for i in range(2):
        appeler("POST", "/promo/agent/%s" % cid, jg, {
            "description": "Promo cycle %d" % i, "prixAvant": 900, "prixApres": 600,
            "categorie": "alimentation", "photoKeys": ["promo-photos/cycle/p.jpg"]})
        time.sleep(PACE)

    def promos_publiques():
        _, d = appeler("GET", "/promo?limit=100")
        return [p for p in d.get("items", []) if p.get("commercantId") == cid]

    noter("décor : promos visibles du client", *verdict_compte(len(promos_publiques()), 2, "promos"))

    _, d = appeler("POST", "/commercant/login", corps={"telephone": TEL, "pin": PIN})
    jeton_avant = d.get("accessToken")
    time.sleep(2)

    # ── SUSPENSION ───────────────────────────────────────────────────────────
    print("\n── suspension ──")
    st, d = appeler("POST", "/admin/commercant/%s/suspend" % cid, ja)
    if st not in (200, 201):
        print("❌ suspension refusée : %s" % d.get("code"))
        sys.exit(2)
    time.sleep(PACE)

    noter("promos dépubliées (brouillon, réversible)",
          *verdict_compte(len(promos_publiques()), 0, "promos visibles"))
    if jeton_avant:
        st, d = appeler("GET", "/commercant/me", jeton_avant)
        noter("session en cours révoquée", *verdict_session_revoquee(st, d.get("code")))
    st, d = appeler("POST", "/commercant/register", corps={
        "telephone": TEL, "nom": "Usurpateur", "categorie": "autre",
        "communeId": commune, "pin": PIN, "acceptedTerms": True})
    noter("numéro TOUJOURS pris (suspension ≠ libération)",
          *verdict_numero_pris(st, d.get("code")))
    time.sleep(PACE)

    # ── RÉACTIVATION ─────────────────────────────────────────────────────────
    print("\n── réactivation ──")
    appeler("POST", "/admin/commercant/%s/reactivate" % cid, ja)
    time.sleep(PACE)
    # ⚠️ Assertion contre-intuitive, et c'est le point : la réactivation ne
    # republie RIEN. Le commerçant republie lui-même après vérification.
    noter("aucune republication automatique",
          *verdict_compte(len(promos_publiques()), 0, "promos visibles"))

    # ── SUPPRESSION ──────────────────────────────────────────────────────────
    print("\n── suppression ──")
    st, d = appeler("POST", "/admin/commercant/%s/delete" % cid, ja)
    if st not in (200, 201):
        print("❌ suppression refusée : %s" % d.get("code"))
        sys.exit(2)
    time.sleep(PACE)

    noter("promos supprimées", *verdict_compte(len(promos_publiques()), 0, "promos visibles"))
    st, d = appeler("POST", "/commercant/register", corps={
        "telephone": TEL, "nom": "Repreneur du local", "categorie": "autre",
        "communeId": commune, "pin": PIN, "acceptedTerms": True})
    noter("numéro LIBÉRÉ par la suppression", *verdict_numero_libre(st, d.get("code")))

    # ── Bilan ────────────────────────────────────────────────────────────────
    echecs = [r for r in resultats if r[1] == "echec"]
    nc = [r for r in resultats if r[1] == "non_concluant"]
    print("\n════════════════════════════════════════════════════════════════")
    if nc:
        print("⚠️  %d contrôle(s) non concluant(s) — ce ne sont pas des réussites." % len(nc))
    print("%d contrôles, %d échec(s), %d non concluant(s)" % (len(resultats), len(echecs), len(nc)))
    sys.exit(1 if (echecs or nc) else 0)


if __name__ == "__main__":
    main()
