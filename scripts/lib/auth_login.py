#!/usr/bin/env python3
"""Banc des connexions — le verrou, et ce que le refus ne doit pas dire.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

1. **Le verrou de connexions existe et se déclenche.** Sans lui, un PIN et un
   mot de passe d'agent sont brute-forçables en ligne — c'est la **règle 2**,
   et `@nestjs/throttler` n'était même pas installé avant l'audit V0.

   ⚠️ **Ce banc ne connaît pas le plafond, et c'est délibéré.** Il a compté
   « 5 tentatives par minute » en dur jusqu'au 2026-08-13 — le jour où les
   connexions sont passées à 50 (`AUTH_THROTTLE`), il aurait rendu ❌ sur un
   produit parfaitement correct : dix essais sans 429, donc « le verrou ne se
   déclenche pas ». C'est exactement la **règle 38**, un banc qui accuse le
   produit parce que sa prémisse a vieilli. Il essaie donc jusqu'à une borne de
   sûreté (`BORNE_ESSAIS`) qui n'exprime aucune valeur produit, et **rapporte**
   le rang du verrou au lieu de l'exiger. Changer le plafond ne le casse plus ;
   seul le retirer le fait lever.

2. **Un refus ne dit pas si le compte existe.** Se tromper de mot de passe et
   viser un compte inexistant doivent être **indiscernables** : même statut,
   même code. Sinon la page de connexion devient un annuaire — on énumère les
   numéros de commerçants sans jamais deviner un PIN.

3. **Le 429 est reconnaissable.** C'est le piège documenté de ce dépôt : *« un
   429 se déguise en identifiants incorrects »*. Il a coûté des heures de
   diagnostic sur de faux bugs d'authentification. Le banc vérifie que le
   plafond rend bien `429` et non un refus d'identifiants — sans quoi
   personne ne peut distinguer « trop d'essais » de « mauvais PIN », ni dans
   l'app, ni dans un banc.

⚠️ **Ce banc DÉCLENCHE le verrou volontairement.** C'est son objet, et c'est
pourquoi il doit tourner **seul** : pendant une minute après son passage,
toute connexion depuis la même IP est refusée — y compris celles des autres
bancs, qui accuseraient alors leurs propres identifiants.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/auth_login.py --self-test
    ./scripts/test-auth-login.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
DEVICE_ID = "banc-auth-0001"

# Borne de sûreté du banc — **pas** le plafond du produit, qu'on ne veut
# justement pas recopier ici (voir l'en-tête). Elle est simplement plus haute
# que tout plafond de connexion défendable : au-delà, ce n'est plus « un banc
# un peu court », c'est qu'il n'y a pas de verrou. Le seul réglage à toucher si
# `AUTH_THROTTLE` devait un jour dépasser cette valeur.
BORNE_ESSAIS = 80


def verdict_verrou(statuts):
    """Une série d'essais doit finir par un 429, pas continuer indéfiniment.

    Le **rang** du verrou est rapporté, jamais exigé : ce banc ne sait pas où
    le plafond est réglé, et n'a pas à le savoir.
    """
    if not statuts:
        return "non_concluant", "aucune tentative"
    if 429 not in statuts:
        # ⚠️ **La cause la plus probable n'est pas le produit.** Le 2026-08-15,
        # ce message a accusé le limiteur pendant une heure alors que le `.env`
        # de développement portait `THROTTLE_FACTOR=20` : plafond à 1000, ce
        # banc en tente 80, il ne pouvait PAS voir de 429. Le nommer ici évite
        # de refaire le chemin — un banc qui accuse doit dire quoi vérifier
        # avant de croire son accusation (règle #38).
        return ("echec",
                "%d tentatives sans jamais de 429 — soit THROTTLE_FACTOR est "
                "relevé côté serveur (le vérifier D'ABORD : au-delà de 1, ce "
                "banc ne peut pas atteindre le plafond), soit le verrou ne se "
                "déclenche pas et le PIN d'un commerçant est brute-forçable "
                "en ligne (règle 2)" % len(statuts))
    rang = statuts.index(429) + 1
    return "ok", "verrou au %de essai (%d tentatives)" % (rang, len(statuts))


def verdict_indiscernable(refus_compte_inexistant, refus_mauvais_secret):
    """Les deux refus doivent être identiques — statut ET code."""
    if None in (refus_compte_inexistant[0], refus_mauvais_secret[0]):
        return "non_concluant", "une des deux tentatives n'a pas abouti"
    if 429 in (refus_compte_inexistant[0], refus_mauvais_secret[0]):
        return "non_concluant", "429 pendant la comparaison — ce n'est pas un verdict"
    if refus_compte_inexistant != refus_mauvais_secret:
        return ("echec",
                "compte inexistant → %s, mauvais secret → %s : la page de "
                "connexion devient un annuaire, on énumère les comptes sans "
                "deviner un seul secret"
                % (refus_compte_inexistant, refus_mauvais_secret))
    return "ok", "identiques (%s %s)" % refus_mauvais_secret


def verdict_429_reconnaissable(statut, code):
    """Le plafond doit rendre 429, pas un refus d'identifiants déguisé."""
    if statut is None:
        return "echec", "pas de réponse : %s" % code
    if statut != 429:
        return ("echec",
                "plafond atteint mais HTTP %s/%s — indiscernable d'un mauvais "
                "identifiant, exactement le piège qui a coûté des heures de "
                "diagnostic" % (statut, code))
    return "ok", "429 %s" % (code or "")


# ─────────────────────────────────────────────────────────────────────────────

def tenter(chemin, corps):
    donnees = json.dumps(corps).encode()
    req = urllib.request.Request(API_URL + chemin, data=donnees, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("X-Device-Id", DEVICE_ID)
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
    _v("verrou déclenché",
       verdict_verrou([400, 400, 400, 400, 400, 429])[0], "ok")
    _v("refus indiscernables",
       verdict_indiscernable((400, "AUTH_INVALID_CREDENTIALS"),
                             (400, "AUTH_INVALID_CREDENTIALS"))[0], "ok")
    _v("429 reconnaissable",
       verdict_429_reconnaissable(429, "RATE_LIMITED")[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ La règle 2 : sans verrou, un PIN tombe en ligne. La série fait
    # `BORNE_ESSAIS` essais — la longueur qu'aura réellement celle du terrain
    # quand le verrou n'existe pas. Elle valait 12 en dur, ce qui décrivait un
    # produit plafonné à 5 et n'aurait plus rien prouvé à 50.
    _v("aucun verrou", verdict_verrou([400] * BORNE_ESSAIS)[0], "echec")
    _v("aucune tentative → non concluant", verdict_verrou([])[0], "non_concluant")
    # ⚠️ L'annuaire : le refus dit si le compte existe.
    _v("codes différents",
       verdict_indiscernable((404, "COMMERCANT_NOT_FOUND"),
                             (400, "AUTH_INVALID_CREDENTIALS"))[0], "echec")
    _v("statuts différents",
       verdict_indiscernable((401, "X"), (400, "X"))[0], "echec")
    _v("429 pendant la comparaison → non concluant",
       verdict_indiscernable((429, None), (400, "X"))[0], "non_concluant")
    _v("tentative sans réponse → non concluant",
       verdict_indiscernable((None, "RESEAU"), (400, "X"))[0], "non_concluant")
    # ⚠️ Le piège du dépôt : le plafond déguisé en mauvais identifiant.
    _v("plafond déguisé",
       verdict_429_reconnaissable(400, "AUTH_INVALID_CREDENTIALS")[0], "echec")
    _v("pas de réponse", verdict_429_reconnaissable(None, "RESEAU")[0], "echec")

    refus = 8
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


def main():
    print("═" * 64)
    print("  Connexions — le verrou, et ce que le refus ne doit pas dire")
    print("═" * 64)
    print("  ⚠️ ce banc déclenche le verrou : il doit tourner SEUL")

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-42s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    # ── 1. Le refus ne dit pas si le compte existe ──────────────────────────
    #
    # Fait EN PREMIER, tant que le seau est plein : une fois le verrou
    # déclenché, les deux réponses seraient identiques pour la mauvaise raison.
    print("\n── 1. un refus ne dit pas si le compte existe ──")
    # ⚠️ Un numéro BIEN FORMÉ mais inutilisé — préfixe `555`, celui du décor.
    # Une première version employait `+213599999999`, que `@IsPhoneNumber('DZ')`
    # refuse : le banc lisait alors un VALIDATION_ERROR venu de son propre
    # échantillon et criait à la fuite d'annuaire. Comparer deux refus n'a de
    # sens que si les deux requêtes atteignent la même règle.
    inexistant = tenter("/commercant/login",
                        {"telephone": "+213555999999", "pin": "654321"})
    mauvais = tenter("/commercant/login",
                     {"telephone": "+213555000101", "pin": "111111"})
    noter("compte inexistant vs mauvais PIN",
          *verdict_indiscernable(inexistant, mauvais))

    # ── 2. Le verrou se déclenche ───────────────────────────────────────────
    print("\n── 2. le verrou de connexions se déclenche ──")
    print("     (jusqu'à %d essais — le banc ne connaît pas le plafond)"
          % BORNE_ESSAIS)
    statuts, dernier = [], (None, None)
    for i in range(BORNE_ESSAIS):
        st, code = tenter("/commercant/login",
                          {"telephone": "+213555000101", "pin": "222222"})
        statuts.append(st)
        dernier = (st, code)
        if st == 429:
            break
    noter("une série d'essais finit par un 429", *verdict_verrou(statuts))

    # ── 3. Et il est reconnaissable ─────────────────────────────────────────
    print("\n── 3. le plafond ne se déguise pas en mauvais identifiant ──")
    if 429 in statuts:
        noter("le refus de plafond est un 429",
              *verdict_429_reconnaissable(*dernier))
    else:
        noter("le refus de plafond est un 429", "non_concluant",
              "le verrou ne s'est pas déclenché")

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
