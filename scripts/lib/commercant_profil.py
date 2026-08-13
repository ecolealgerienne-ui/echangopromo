#!/usr/bin/env python3
"""Banc du profil commerçant — le patch partiel, et le PIN.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

1. **Un `PATCH` partiel ne doit rien effacer.** Défaut réel du 2026-07-12 :
   `ValidationPipe` produit un DTO portant une propriété **propre** valant
   `undefined` pour chaque champ optionnel non fourni (`useDefineForClassFields`,
   actif dès la cible ES2022). Un `Object.assign(commercant, dto)` écrasait donc
   les valeurs déjà en base. TypeORM ignorait ces `undefined` dans l'`UPDATE`
   SQL — la base restait correcte — **mais pas l'objet renvoyé au client** :
   `nom` et `categorie` disparaissaient de la réponse dès qu'un appel ne
   modifiait que `photoKey`, et le parsing mobile plantait alors que rien
   n'était perdu.

   C'est un défaut qui ne se voit **que** dans la réponse, jamais en base. La
   sonde le rejoue tel quel : patcher un seul champ, et vérifier que les autres
   sont **toujours dans la réponse**.

2. **Le téléphone n'est pas modifiable ici.** Il porte l'unicité des comptes
   actifs et la connexion ; le changer de son propre chef contournerait
   `assertPhoneAvailable`.

3. **Le PIN est borné à la pose, et plus permissif à la vérification.** Deux
   motifs distincts et volontaires (`PIN_SET_PATTERN` 6-12, `PIN_VERIFY_PATTERN`
   4-12) : les PIN fixés avant le 2026-07-13 font 4 chiffres et doivent
   continuer d'ouvrir. Poser un PIN trop court doit être refusé ; l'ancien PIN
   doit cesser de fonctionner après changement.

4. **Aucun champ réservé dans `GET /commercant/me`.**

⚠️ Le banc travaille sur un commerçant **qu'il crée lui-même** : changer le PIN
du décor le rendrait inutilisable pour tous les autres bancs.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/commercant_profil.py --self-test
    ./scripts/test-commercant-profil.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.1"))
DEVICE_ID = "banc-profil-0001"
# Position de décor, à Djelfa — obligatoire à la création par agent depuis le
# 2026-08-12, et sans elle publier est refusé (règle #38).
DECOR_LAT, DECOR_LNG = 34.6689, 3.2597

RESERVES = ("pinHash", "tokenVersion", "deletedAt", "suspendedAt")


def verdict_patch_partiel(avant, apres, champ_modifie):
    """Patcher un champ ne doit pas faire disparaître les autres DE LA RÉPONSE."""
    if not isinstance(avant, dict) or not isinstance(apres, dict):
        return "non_concluant", "réponse illisible"
    perdus = [c for c in avant
              if c != champ_modifie and c not in apres]
    if perdus:
        return ("echec",
                "champs disparus de la réponse après un patch partiel : %s — "
                "le parsing mobile plante alors que rien n'est perdu en base"
                % ", ".join(sorted(perdus)))
    vides = [c for c, v in avant.items()
             if c != champ_modifie and v is not None and apres.get(c) is None]
    if vides:
        return ("echec",
                "champs vidés par un patch qui ne les visait pas : %s"
                % ", ".join(sorted(vides)))
    return "ok", "%d champ(s) préservés" % (len(avant) - 1)


def verdict_reserve(corps):
    trouves = sorted(c for c in RESERVES if _present(corps, c))
    if trouves:
        return "echec", "champs réservés exposés : %s" % ", ".join(trouves)
    return "ok", "aucun champ réservé"


def _present(noeud, nom):
    if isinstance(noeud, dict):
        return nom in noeud or any(_present(v, nom) for v in noeud.values())
    if isinstance(noeud, list):
        return any(_present(e, nom) for e in noeud)
    return False


def verdict_refus(statut, code, codes_admis):
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
    avant = {"id": "c1", "nom": "N", "categorie": "alimentation",
             "adresse": "A"}

    # ── Doivent PASSER ───────────────────────────────────────────────────────
    _v("patch qui préserve",
       verdict_patch_partiel(avant, dict(avant, adresse="B"), "adresse")[0], "ok")
    _v("profil propre", verdict_reserve(avant)[0], "ok")
    _v("refus attendu",
       verdict_refus(400, "VALIDATION_ERROR", ("VALIDATION_ERROR",))[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le défaut du 2026-07-12 : les champs non visés quittent la RÉPONSE.
    _v("champs disparus de la réponse",
       verdict_patch_partiel(avant, {"id": "c1", "adresse": "B"}, "adresse")[0],
       "echec")
    _v("champ vidé sans être visé",
       verdict_patch_partiel(avant, dict(avant, nom=None, adresse="B"),
                             "adresse")[0], "echec")
    _v("réponse illisible → non concluant",
       verdict_patch_partiel(avant, [], "adresse")[0], "non_concluant")
    _v("pinHash exposé",
       verdict_reserve(dict(avant, pinHash="h"))[0], "echec")
    _v("tokenVersion imbriqué",
       verdict_reserve({"a": {"tokenVersion": 2}})[0], "echec")
    _v("accepté là où un refus était dû",
       verdict_refus(200, None, ("VALIDATION_ERROR",))[0], "echec")
    _v("500 compté comme refus",
       verdict_refus(500, "INTERNAL_ERROR", ("VALIDATION_ERROR",))[0], "echec")
    _v("refus au mauvais code",
       verdict_refus(403, "X", ("VALIDATION_ERROR",))[0], "non_concluant")

    refus = 8
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


def main():
    agent_email = _exiger("AGENT_EMAIL")
    agent_password = _exiger("AGENT_PASSWORD")

    print("═" * 64)
    print("  Profil commerçant — patch partiel, et le PIN")
    print("═" * 64)

    st, d = appeler("POST", "/agent/login",
                    corps={"email": agent_email, "password": agent_password})
    jg = d.get("accessToken")
    if not jg:
        print("❌ connexion agent impossible (HTTP %s, %s)" % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-42s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    # ── Un commerçant à nous : changer le PIN du décor le rendrait
    #    inutilisable pour tous les autres bancs.
    base = time.strftime("%H%M%S")
    tel = "+213562%s" % base
    pin_initial, pin_nouveau = "654321", "112233"
    st, d = appeler("POST", "/agent/commercant", jg, {
        "telephone": tel, "nom": "Commerce Profil", "pin": pin_initial,
        "adresse": "Rue du profil", "categorie": "alimentation",
        "latitude": DECOR_LAT, "longitude": DECOR_LNG})
    if st not in (200, 201):
        print("❌ création du commerçant du banc refusée (HTTP %s, %s)"
              % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    st, d = appeler("POST", "/commercant/login",
                    corps={"telephone": tel, "pin": pin_initial})
    jc = d.get("accessToken")
    if not jc:
        print("❌ connexion du commerçant du banc impossible (HTTP %s, %s)"
              % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    # ── 1. La projection ────────────────────────────────────────────────────
    print("\n── 1. GET /commercant/me ──")
    _, avant = appeler("GET", "/commercant/me", jc)
    noter("aucun champ réservé", *verdict_reserve(avant))
    time.sleep(PACE)

    # ── 2. Le patch partiel ─────────────────────────────────────────────────
    print("\n── 2. un patch partiel ne fait rien disparaître ──")
    st, apres = appeler("PATCH", "/commercant/me", jc,
                        {"adresse": "Rue modifiée"})
    if st != 200:
        noter("patch partiel", "non_concluant",
              "HTTP %s %s" % (st, apres.get("code")))
    else:
        noter("les autres champs restent dans la réponse",
              *verdict_patch_partiel(avant, apres, "adresse"))
    time.sleep(PACE)

    st, d = appeler("PATCH", "/commercant/me", jc,
                    {"telephone": "+213500000000"})
    # Le champ doit être ignoré ou refusé — jamais appliqué.
    _, apres_tel = appeler("GET", "/commercant/me", jc)
    if apres_tel.get("telephone") == "+213500000000":
        noter("le téléphone n'est pas modifiable ici", "echec",
              "le numéro a été changé par un PATCH de profil")
    else:
        noter("le téléphone n'est pas modifiable ici", "ok",
              "inchangé (%s)" % apres_tel.get("telephone"))
    time.sleep(PACE)

    # ── 3. Le PIN ───────────────────────────────────────────────────────────
    print("\n── 3. le PIN est borné à la pose ──")
    st, d = appeler("PATCH", "/commercant/me/pin", jc,
                    {"oldPin": pin_initial, "newPin": "123"})
    noter("PIN trop court refusé",
          *verdict_refus(st, d.get("code"), ("VALIDATION_ERROR",)))
    time.sleep(PACE)

    st, d = appeler("PATCH", "/commercant/me/pin", jc,
                    {"oldPin": "000000", "newPin": pin_nouveau})
    # ⚠️ `VALIDATION_ERROR` volontairement PAS admis ici : il est rendu par un
    # corps mal formé, et l'admettre a fait passer cette sonde au vert alors
    # que le banc envoyait de mauvais noms de champs (constaté le 2026-08-05).
    # Un refus au mauvais motif n'est pas un refus.
    noter("PIN actuel faux refusé",
          *verdict_refus(st, d.get("code"),
                         ("COMMERCANT_OLD_PIN_MISMATCH",
                          "AUTH_INVALID_CREDENTIALS")))
    time.sleep(PACE)

    st, d = appeler("PATCH", "/commercant/me/pin", jc,
                    {"oldPin": pin_initial, "newPin": pin_nouveau})
    if st not in (200, 201):
        noter("changement de PIN", "non_concluant",
              "HTTP %s %s" % (st, d.get("code")))
    else:
        noter("changement de PIN", "ok", "accepté")
        time.sleep(PACE)
        st, d = appeler("POST", "/commercant/login",
                        corps={"telephone": tel, "pin": pin_initial})
        noter("l'ancien PIN n'ouvre plus",
              *verdict_refus(st, d.get("code"),
                             ("AUTH_INVALID_CREDENTIALS",)))
        time.sleep(PACE)
        st, d = appeler("POST", "/commercant/login",
                        corps={"telephone": tel, "pin": pin_nouveau})
        if st in (200, 201):
            noter("le nouveau PIN ouvre", "ok", "connexion réussie")
        else:
            noter("le nouveau PIN ouvre", "echec",
                  "HTTP %s %s" % (st, d.get("code")))

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
