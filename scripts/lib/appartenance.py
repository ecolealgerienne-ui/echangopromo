#!/usr/bin/env python3
"""Banc d'appartenance — un agent n'agit que dans ses communes.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

Le jeton est **valide**, le rôle est **le bon** : la question n'est plus « qui
êtes-vous » mais « cette ressource est-elle à vous ». C'est la seconde moitié
du contrôle d'accès, celle qui vit dans chaque service et repose sur le fait
que son auteur y a pensé.

C'était la faille critique de l'audit V0 — un agent pouvait modifier les promos
de n'importe quel commerçant — corrigée puis **jamais rejouée**. Et la surface
réelle est bien plus large que les promos : un agent dispose de 14 routes à
identifiant, dont suspendre, **supprimer**, valider un registre, réinitialiser
un PIN et modérer.

── Le piège central, et pourquoi les corps sont valides ─────────────────────

⚠️ **Un 400 n'est pas un refus d'accès.** Sondées avec un corps vide, deux
routes rendent `VALIDATION_ERROR` : la requête meurt à la validation, **avant**
d'atteindre le contrôle d'appartenance. Un banc qui compterait ce 400 comme un
refus conclurait juste par accident, et resterait vert le jour où
l'appartenance disparaît. Chaque sonde envoie donc un corps que la validation
accepte, et un `VALIDATION_ERROR` est déclaré **non concluant** — jamais réussi.

── Le témoin, et pourquoi il est indispensable ──────────────────────────────

Un banc qui n'observe que des refus passe au vert si TOUT est refusé — y
compris pour l'agent légitime. Le témoin positif prouve que le filtre laisse
passer ce qu'il doit laisser passer. Il est **restauré** : suspendre puis
réactiver rend l'état d'origine.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/appartenance.py --self-test
    python3 scripts/lib/appartenance.py
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.2"))

# Codes qui prouvent un refus D'APPARTENANCE (pas d'authentification).
CODES_APPARTENANCE = {
    "COMMERCANT_NOT_IN_AGENT_COMMUNES",
    "COMMERCANT_NOT_FOUND",
    "PROMO_NOT_FOUND",
    "PROMO_NOT_OWNED_BY_COMMERCANT",
}

PIN_NEUF = "987654"          # 6-12 chiffres, conforme à PIN_SET_PATTERN
PROMO_CORPS = {
    "description": "Sonde du banc d'appartenance",
    "prixAvant": 1000,
    "prixApres": 700,
    "categorie": "alimentation",
    "photoKeys": ["promo-photos/banc/appartenance.jpg"],
}


# ─────────────────────────────────────────────────────────────────────────────
# Le verdict d'une sonde — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_refus(statut, code):
    """Rend ('ok'|'non_concluant'|'echec', explication).

    ⚠️ `VALIDATION_ERROR` n'est PAS un refus : la requête est morte avant le
    contrôle d'appartenance. Le déclarer non concluant est ce qui empêche ce
    banc de se rassurer tout seul.
    """
    if statut is None:
        return "echec", "pas de réponse : %s" % code
    if statut == 429:
        return "non_concluant", "429 — plafond atteint, ce n'est pas un verdict"
    if code == "VALIDATION_ERROR":
        return ("non_concluant",
                "400 VALIDATION_ERROR — le corps n'a pas passé la validation, "
                "la sonde n'a jamais atteint le contrôle d'appartenance")
    if statut not in (403, 404):
        return "echec", "statut %s (attendu 403 ou 404) — accès NON refusé" % statut
    if code not in CODES_APPARTENANCE:
        return "echec", "statut %s mais code %r, hors des codes d'appartenance" % (statut, code)
    return "ok", "%s %s" % (statut, code)


def verdict_temoin(statut, code):
    """L'agent légitime ne doit PAS être refusé pour appartenance."""
    if statut is None:
        return "echec", "pas de réponse : %s" % code
    if code in CODES_APPARTENANCE:
        return "echec", "l'agent LÉGITIME est refusé (%s %s) — le filtre est trop strict" % (
            statut, code)
    if statut >= 500:
        return "echec", "statut %s" % statut
    return "ok", str(statut)


# ─────────────────────────────────────────────────────────────────────────────

def appeler(methode, chemin, jeton, corps=None):
    donnees = json.dumps(corps if corps is not None else {}).encode()
    req = urllib.request.Request(API_URL + chemin, data=donnees, method=methode)
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", "Bearer " + jeton)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            brut = r.read()
            try:
                return r.status, json.loads(brut or b"{}").get("code"), json.loads(brut or b"{}")
            except Exception:
                return r.status, None, {}
    except urllib.error.HTTPError as e:
        brut = e.read()
        try:
            d = json.loads(brut)
            return e.code, d.get("code"), d
        except Exception:
            return e.code, None, {}
    except Exception as e:
        return None, "RESEAU: %s" % e, {}


def _exiger(nom):
    v = os.environ.get(nom)
    if not v:
        print("❌ %s absent — lancer ./scripts/provision-decor.sh et coller son bloc export." % nom)
        sys.exit(2)
    return v


def jeton_agent(email, mot_de_passe, quoi):
    st, code, d = appeler("POST", "/agent/login", "", {"email": email, "password": mot_de_passe})
    jeton = d.get("accessToken")
    if not jeton:
        print("❌ connexion agent %s impossible (HTTP %s, code %s)" % (quoi, st, code))
        sys.exit(2)
    time.sleep(PACE)
    return jeton


# ─────────────────────────────────────────────────────────────────────────────
# Auto-test — la logique de verdict, avec autant de refus que de passes
# ─────────────────────────────────────────────────────────────────────────────

def self_test():
    cas = [
        # (fonction, statut, code, verdict attendu)
        (verdict_refus, 403, "COMMERCANT_NOT_IN_AGENT_COMMUNES", "ok"),
        (verdict_refus, 404, "PROMO_NOT_FOUND", "ok"),
        (verdict_temoin, 200, None, "ok"),
        (verdict_temoin, 201, None, "ok"),
        (verdict_temoin, 400, "PROMO_ALREADY_PUBLISHED", "ok"),
        # ── Doivent REFUSER ──────────────────────────────────────────────────
        # Le cœur du banc : un 400 de validation ne prouve rien.
        (verdict_refus, 400, "VALIDATION_ERROR", "non_concluant"),
        (verdict_refus, 429, None, "non_concluant"),
        (verdict_refus, 200, None, "echec"),          # accès accordé !
        (verdict_refus, 201, None, "echec"),
        (verdict_refus, 403, "AUTH_FORBIDDEN_ROLE", "echec"),  # refus de RÔLE, pas d'appartenance
        (verdict_refus, None, "RESEAU: x", "echec"),
        (verdict_temoin, 403, "COMMERCANT_NOT_IN_AGENT_COMMUNES", "echec"),
        (verdict_temoin, 500, None, "echec"),
    ]
    echecs, passes = [], 0
    for fn, statut, code, attendu in cas:
        obtenu, _ = fn(statut, code)
        if obtenu == attendu:
            passes += 1
        else:
            echecs.append("%s(%s, %r) = %s, attendu %s" % (
                fn.__name__, statut, code, obtenu, attendu))
    refus = sum(1 for c in cas if c[3] != "ok")
    print("auto-test : %d cas, dont %d refus" % (len(cas), refus))
    for e in echecs:
        print("  ❌ " + e)
    print("  %d/%d" % (passes, len(cas)))
    return not echecs


# ─────────────────────────────────────────────────────────────────────────────

def main():
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)

    cid = _exiger("COMMERCANT_ID")
    pid = _exiger("PROMO_ID")
    a = jeton_agent(_exiger("AGENT_EMAIL"), _exiger("AGENT_PASSWORD"), "A (légitime)")
    b = jeton_agent(_exiger("AGENT_B_EMAIL"), _exiger("AGENT_B_PASSWORD"), "B (intrus)")

    # (méthode, chemin, corps) — corps VALIDE, voir l'en-tête.
    sondes = [
        ("POST", "/admin/commercant/%s/suspend" % cid, {}),
        ("POST", "/admin/commercant/%s/reactivate" % cid, {}),
        ("POST", "/admin/commercant/%s/delete" % cid, {}),
        ("POST", "/admin/commercant/%s/registre/valider" % cid, {}),
        ("POST", "/admin/commercant/%s/registre/rejeter" % cid, {}),
        ("POST", "/admin/commercant/%s/profile/valider" % cid, {}),
        ("POST", "/admin/commercant/%s/reset-pin" % cid, {"newPin": PIN_NEUF}),
        ("POST", "/admin/moderation/%s/masquer" % pid, {}),
        ("POST", "/admin/moderation/%s/verifier-ok" % pid, {}),
        ("POST", "/admin/moderation/%s/avertir" % pid, {}),
        ("PATCH", "/promo/%s" % pid, {"description": "Sonde appartenance"}),
        ("POST", "/promo/%s/publish" % pid, {}),
        ("POST", "/promo/%s/stop" % pid, {}),
        ("POST", "/promo/agent/%s" % cid, PROMO_CORPS),
    ]

    # ⚠️ `--only=<motif>` restreint les sondes. Indispensable pour l'épreuve par
    # mutation : garde neutralisé, la sonde `delete` supprimerait réellement le
    # commerçant du décor, et les sondes suivantes ne prouveraient plus rien.
    # Sur une route inoffensive, la mutation se juge sans rien casser.
    only = next((a_.split("=", 1)[1] for a_ in sys.argv if a_.startswith("--only=")), None)
    if only:
        sondes = [s for s in sondes if only in s[1]]
        if not sondes:
            print("❌ --only=%s ne correspond à aucune sonde." % only)
            sys.exit(2)

    print("════════════════════════════════════════════════════════════════")
    print("  Appartenance — l'agent B (autre commune) sur les ressources de A")
    print("════════════════════════════════════════════════════════════════")
    if only:
        print("  ⚠️  filtre --only=%s : %d sonde(s) sur 14" % (only, len(sondes)))
    print("  commerçant %s\n  promo      %s\n  %d sondes, cadence %.1fs\n"
          % (cid, pid, len(sondes), PACE))

    echecs, non_concluants = [], []
    for methode, chemin, corps in sondes:
        statut, code, _ = appeler(methode, chemin, b, corps)
        time.sleep(PACE)
        v, quoi = verdict_refus(statut, code)
        court = chemin.replace(cid, "{cid}").replace(pid, "{pid}")
        if v == "ok":
            print("  ✅ %-6s %-44s %s" % (methode, court, quoi))
        elif v == "non_concluant":
            print("  ⚠️  %-6s %-44s %s" % (methode, court, quoi))
            non_concluants.append("%s %s — %s" % (methode, court, quoi))
        else:
            print("  ❌ %-6s %-44s %s" % (methode, court, quoi))
            echecs.append("%s %s — %s" % (methode, court, quoi))

    # ── Témoin positif, restauré ─────────────────────────────────────────────
    print("\n── témoin : l'agent A, lui, doit passer ──")
    for methode, chemin, corps, libelle in [
        ("POST", "/admin/commercant/%s/suspend" % cid, {}, "suspendre (agent A)"),
        ("POST", "/admin/commercant/%s/reactivate" % cid, {}, "réactiver (restauration)"),
    ]:
        statut, code, _ = appeler(methode, chemin, a, corps)
        time.sleep(PACE)
        v, quoi = verdict_temoin(statut, code)
        print("  %s %-32s %s" % ("✅" if v == "ok" else "❌", libelle, quoi))
        if v != "ok":
            echecs.append("témoin %s — %s" % (libelle, quoi))

    # ── Projection de la liste ───────────────────────────────────────────────
    print("\n── la liste des commerçants est filtrée par commune ──")
    for jeton, quoi, doit_voir in ((a, "agent A", True), (b, "agent B", False)):
        _, _, d = appeler("GET", "/admin/commercant?limit=100", jeton)
        time.sleep(PACE)
        vu = any(i.get("id") == cid for i in d.get("items", []))
        ok = vu == doit_voir
        print("  %s %-32s %s" % ("✅" if ok else "❌", quoi,
                                 "voit le commerçant" if vu else "ne le voit pas"))
        if not ok:
            echecs.append("liste %s : %s alors qu'il %s" % (
                quoi, "le voit" if vu else "ne le voit pas",
                "devrait" if doit_voir else "ne devrait pas"))

    print("\n════════════════════════════════════════════════════════════════")
    if non_concluants:
        print("⚠️  %d sonde(s) NON CONCLUANTE(S) — elles n'ont pas atteint le" % len(non_concluants))
        print("    contrôle d'appartenance. Ce ne sont pas des réussites.")
    print("%d sondes, %d échec(s), %d non concluante(s)"
          % (len(sondes), len(echecs), len(non_concluants)))
    sys.exit(1 if (echecs or non_concluants) else 0)


if __name__ == "__main__":
    main()
