#!/usr/bin/env python3
"""Banc de la fiche publique — ce qu'un anonyme voit, et surtout ce qu'il ne
voit pas.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

`GET /commercant/:id/public` est la seule projection d'un commerçant servie
**sans aucune authentification**. Le contrôleur y compose une réponse champ par
champ — et c'est précisément ce qui doit être vérifié : la même entité, servie
par `toMeJson`, porte l'état du compte, le statut de registre, la revue de
profil. Rien de tout ça n'a sa place dans une réponse anonyme.

Le défaut de référence est ailleurs dans le dépôt mais de la même famille : un
`{...entity}` transforme l'instance en objet plain et **désactive
silencieusement les `@Exclude()`** (règle 4). Une projection explicite protège
— tant que quelqu'un vérifie qu'elle l'est restée.

Trois sondes :

1. **Aucun champ réservé**, à quelque profondeur que ce soit — état du compte,
   hachage de PIN, horodatages de suppression/suspension, version de jeton,
   clés S3 brutes.
2. **Les champs promis sont là.** Une fiche sans `telephone` casse le
   tap-pour-appeler ajouté le 2026-07-12 ; une fiche sans `nom` n'est pas une
   fiche. L'absence est un défaut au même titre que la fuite.
3. **Un identifiant inexistant ou malformé se refuse** — jamais un `500`, qui
   renseignerait qui sonde.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/client_fiche.py --self-test
    ./scripts/test-client-fiche.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "0.6"))
DEVICE_ID = "banc-fiche-0001"

# Ce qu'une réponse anonyme ne doit jamais porter. Chaque nom correspond à un
# champ réel de l'entité `Commercant` ou de `toMeJson`.
RESERVES = ("pinHash", "deletedAt", "suspendedAt", "tokenVersion",
            "accountState", "registreStatus", "registreKey", "photoKey",
            "profilePendingReview", "originVerification")

# Ce qu'elle doit porter — sans quoi la fiche ne remplit pas son rôle.
# ⚠️ `communeId` remplacé par `adresse` le 2026-08-13. La clé reste présente
# dans la réponse même quand le commerçant n'a pas saisi d'adresse — elle vaut
# alors `null` —, donc l'assertion de PRÉSENCE garde exactement le même
# pouvoir : elle refuse un champ disparu du contrat, pas un champ vide.
PROMIS = ("id", "nom", "categorie", "adresse", "telephone")


def verdict_reserve(corps):
    trouves = sorted(set(_champs(corps, RESERVES)))
    if trouves:
        return "echec", "champs réservés exposés : %s" % ", ".join(trouves)
    return "ok", "aucun champ réservé"


def verdict_promis(corps):
    if not isinstance(corps, dict):
        return "non_concluant", "réponse illisible"
    manquants = [c for c in PROMIS if c not in corps]
    if manquants:
        return ("echec",
                "champs promis absents : %s — l'absence est un défaut au même "
                "titre que la fuite" % ", ".join(manquants))
    return "ok", "%d champ(s) servis" % len(PROMIS)


def _champs(noeud, noms):
    if isinstance(noeud, dict):
        for cle, valeur in noeud.items():
            if cle in noms:
                yield cle
            yield from _champs(valeur, noms)
    elif isinstance(noeud, list):
        for e in noeud:
            yield from _champs(e, noms)


def verdict_entree(statut, code, codes_admis):
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if statut is None:
        return "echec", "pas de réponse : %s" % code
    if statut in (200, 201):
        return "echec", "ACCEPTÉ alors qu'un refus était dû"
    if statut >= 500 or code == "INTERNAL_ERROR":
        return "echec", "HTTP %s %s — casse au lieu de refuser" % (statut, code)
    if code not in codes_admis:
        return "non_concluant", "refusé en %s/%s" % (statut, code)
    return "ok", "%s %s" % (statut, code)


# ─────────────────────────────────────────────────────────────────────────────

def appeler(chemin):
    req = urllib.request.Request(API_URL + chemin, method="GET")
    req.add_header("X-Device-Id", DEVICE_ID)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
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
    fiche = {c: "x" for c in PROMIS}

    # ── Doivent PASSER ───────────────────────────────────────────────────────
    _v("fiche propre", verdict_reserve(fiche)[0], "ok")
    _v("fiche complète", verdict_promis(fiche)[0], "ok")
    _v("refus attendu", verdict_entree(404, "COMMERCANT_NOT_FOUND",
                                       ("COMMERCANT_NOT_FOUND",))[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    _v("pinHash exposé",
       verdict_reserve(dict(fiche, pinHash="h"))[0], "echec")
    _v("deletedAt exposé",
       verdict_reserve(dict(fiche, deletedAt=None))[0], "echec")
    # ⚠️ Le cas de la règle 4 : le champ est dans un objet imbriqué.
    _v("champ réservé imbriqué",
       verdict_reserve({"a": {"b": {"tokenVersion": 3}}})[0], "echec")
    _v("téléphone manquant",
       verdict_promis({c: "x" for c in PROMIS if c != "telephone"})[0], "echec")
    _v("réponse illisible → non concluant",
       verdict_promis([])[0], "non_concluant")
    _v("fiche servie là où un refus était dû",
       verdict_entree(200, None, ("COMMERCANT_NOT_FOUND",))[0], "echec")
    _v("500 compté comme refus",
       verdict_entree(500, "INTERNAL_ERROR", ("COMMERCANT_NOT_FOUND",))[0],
       "echec")
    _v("refus au mauvais code",
       verdict_entree(403, "X", ("COMMERCANT_NOT_FOUND",))[0], "non_concluant")

    refus = 8
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


def main():
    cid = _exiger("COMMERCANT_ID")

    print("═" * 64)
    print("  Fiche publique — ce qu'un anonyme voit, et ce qu'il ne voit pas")
    print("═" * 64)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-40s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    print("\n── 1. la projection ──")
    st, fiche = appeler("/commercant/%s/public" % cid)
    if st != 200:
        noter("la fiche du décor", "non_concluant",
              "HTTP %s %s" % (st, fiche.get("code")))
        return 1
    noter("aucun champ réservé", *verdict_reserve(fiche))
    noter("les champs promis sont servis", *verdict_promis(fiche))
    time.sleep(PACE)

    print("\n── 2. les entrées ──")
    st, d = appeler("/commercant/11111111-2222-4333-8444-555555555555/public")
    noter("identifiant inexistant",
          *verdict_entree(st, d.get("code"), ("COMMERCANT_NOT_FOUND",)))
    time.sleep(PACE)

    st, d = appeler("/commercant/pas-un-uuid/public")
    noter("identifiant qui n'est pas un UUID",
          *verdict_entree(st, d.get("code"), ("VALIDATION_ERROR",)))

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
