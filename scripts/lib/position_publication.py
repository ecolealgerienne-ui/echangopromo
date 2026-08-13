#!/usr/bin/env python3
"""Banc — publier exige une position, préparer un brouillon non.

**Ce que ce banc prouve, et pourquoi il est bâti ainsi.**

Le plan de bascule (`docs/PLAN_BASCULE_GEO.md` §9.1) décrivait une séquence en
cinq temps dont le second était « retirer la position ». Elle ne pouvait pas
tenir : le seul chemin pour retirer une position est `PATCH /commercant/me`, qui
allume `profilePendingReview` — et ce drapeau bloque **aussi** la publication.
Le contrôle aurait alors constaté un `403 COMMERCANT_PROFILE_PENDING_REVIEW` en
croyant mesurer le refus de position. **Vert pour la mauvaise raison** (règles
#28 et #38).

Ce banc prend donc l'autre bout : **un seul commerçant, une seule variable**.
Il naît sans position, on lui refuse de publier, on lui pose sa position, il
publie. Rien d'autre ne change entre les deux tentatives — donc si la seconde
réussit, c'est la position qui manquait, et rien d'autre.

⚠️ **La prémisse est établie par la fin, pas supposée au début** (règle #38).
Le contrôle 4 est ce qui donne son sens au contrôle 1 : sans lui, un refus
pourrait venir de n'importe quelle autre garde (registre, revue de profil,
plafond) et on l'attribuerait à la position.

⚠️ Le contrôle 2 n'est pas décoratif : `promo.service.ts` documente une
régression déjà survenue où des gardes de publication refusaient aussi
« Enregistrer comme brouillon », « avec un message parlant de publier, sur un
geste qui ne publie pas ». Sans ce contrôle, on ne saurait pas qu'on vient de
la refabriquer.

Usage :
    ./scripts/test-position-publication.sh

⚠️ Ce banc ÉCRIT : il crée SON PROPRE commerçant (auto-inscription, donc sans
position — ce que la création par agent n'autorise plus). Il ne touche à aucun
compte existant.

⚠️ Il consomme **une** inscription sur le seau strict (5/min/IP), une connexion
sur celui de l'authentification (50/min/IP) et ~5 sur le seau des écritures
(20/min/IP). Les deux seaux étroits sont donc l'inscription et les écritures ;
la connexion ne l'est plus depuis le 2026-08-13.
"""

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.2"))
DEVICE_ID = "banc-position-0001"
PIN = "654321"
# Position posée au contrôle 3, à Djelfa. Elle n'a pas à être exacte : ce qui
# est mesuré est le passage de « absente » à « présente », pas sa justesse.
POS_LAT, POS_LNG = 34.6707, 3.2641

JPEG_1x1 = base64.b64decode(
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof"
    "Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB"
    "AAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q=="
)


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


def televerser(jeton, purpose):
    """POST multipart vers /storage/upload — écrit à la main."""
    frontiere = "----banc%s" % uuid.uuid4().hex
    corps = b"".join([
        ('--%s\r\nContent-Disposition: form-data; name="purpose"\r\n\r\n%s\r\n'
         % (frontiere, purpose)).encode(),
        ('--%s\r\nContent-Disposition: form-data; name="file"; '
         'filename="promo.jpg"\r\nContent-Type: image/jpeg\r\n\r\n'
         % frontiere).encode(),
        JPEG_1x1,
        ("\r\n--%s--\r\n" % frontiere).encode(),
    ])
    req = urllib.request.Request(API_URL + "/storage/upload", data=corps,
                                 method="POST")
    req.add_header("Content-Type",
                   "multipart/form-data; boundary=%s" % frontiere)
    req.add_header("X-Device-Id", DEVICE_ID)
    req.add_header("Authorization", "Bearer " + jeton)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read())
        except Exception:
            return e.code, {}
    except Exception as e:
        return None, {"code": "RESEAU: %s" % e}


# ─────────────────────────────────────────────────────────────────────────────
# Verdicts — isolés du réseau pour pouvoir être éprouvés par `--self-test`.
# ─────────────────────────────────────────────────────────────────────────────

def verdict_refus_position(statut, code):
    """Le refus doit être CELUI-LÀ, pas n'importe lequel.

    ⚠️ Le piège que ce verdict existe pour fermer : quatre gardes se suivent
    dans `PromoService` (registre, revue de profil, position, plafond) et
    rendent toutes un 403. Se contenter du statut ferait passer le banc au vert
    en mesurant une autre règle que celle qu'on croit tenir.
    """
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict, c'est un seau plein"
    if statut is None:
        return "non_concluant", "pas de réponse du serveur"
    if statut == 500 or code == "INTERNAL_ERROR":
        # Une mutation qui CASSE au lieu de REFUSER ne prouve rien (règle #28).
        return "echec", "500 — le serveur a planté au lieu de refuser"
    if statut in (200, 201):
        return "echec", "publication ACCEPTÉE sans position (%s)" % statut
    if code != "COMMERCANT_POSITION_REQUIRED":
        return "echec", "refusé pour une autre raison : %s (HTTP %s)" % (code, statut)
    return "ok", "403 COMMERCANT_POSITION_REQUIRED"


def verdict_brouillon(statut, code):
    """Un commerçant sans position doit pouvoir PRÉPARER ses promos."""
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if statut is None:
        return "non_concluant", "pas de réponse du serveur"
    if statut in (200, 201):
        return "ok", "brouillon accepté (%s)" % statut
    return ("echec",
            "brouillon REFUSÉ (%s / %s) — la garde a été posée hors du "
            "`if (!dto.asDraft)`, régression de promo.service.ts" % (statut, code))


def verdict_publication(statut, code):
    """Après la pose de la position, publier doit passer — et sans détour admin.

    Un `COMMERCANT_PROFILE_PENDING_REVIEW` ici serait le défaut exact que
    `PATCH /commercant/me/position` existe pour éviter : le commerçant a fait ce
    qu'on lui demandait et se retrouve à attendre un humain.
    """
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if statut is None:
        return "non_concluant", "pas de réponse du serveur"
    if code == "COMMERCANT_PROFILE_PENDING_REVIEW":
        return ("echec",
                "poser la position a déclenché une revue de profil — le "
                "commerçant reste bloqué, il ne peut pas s'en sortir seul")
    if statut not in (200, 201):
        return "echec", "publication refusée après la pose : %s (HTTP %s)" % (code, statut)
    return "ok", "publication acceptée (%s)" % statut


def _exiger(nom):
    valeur = os.environ.get(nom)
    if not valeur:
        print("❌ %s absent de l'environnement — coller le bloc export du décor."
              % nom)
        sys.exit(2)
    return valeur


def _v(libelle, obtenu, attendu):
    if obtenu != attendu:
        print("  ❌ auto-test : %s → %r au lieu de %r" % (libelle, obtenu, attendu))
        return False
    return True


def self_test():
    """⚠️ Autant de cas qui doivent REFUSER que de cas qui passent (règle #28)."""
    ok = True

    # ── Doivent PASSER ───────────────────────────────────────────────────────
    ok &= _v("refus attendu",
             verdict_refus_position(403, "COMMERCANT_POSITION_REQUIRED")[0], "ok")
    ok &= _v("brouillon accepté", verdict_brouillon(201, None)[0], "ok")
    ok &= _v("publication acceptée", verdict_publication(201, None)[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # Le cas fondateur : publier sans position ne DOIT pas passer.
    ok &= _v("publication acceptée sans position",
             verdict_refus_position(201, None)[0], "echec")
    # ⚠️ Le piège de ce banc : quatre gardes rendent 403. Un refus qui n'est pas
    # le bon mesure une autre règle que celle qu'on croit tenir.
    ok &= _v("refusé pour la mauvaise raison",
             verdict_refus_position(403, "COMMERCANT_PROFILE_PENDING_REVIEW")[0],
             "echec")
    # Une mutation qui casse au lieu de refuser ne prouve rien.
    ok &= _v("500 au lieu d'un refus",
             verdict_refus_position(500, "INTERNAL_ERROR")[0], "echec")
    ok &= _v("brouillon refusé", verdict_brouillon(403, "X")[0], "echec")
    ok &= _v("revue de profil déclenchée par la pose",
             verdict_publication(403, "COMMERCANT_PROFILE_PENDING_REVIEW")[0],
             "echec")
    # ── Ne doivent RIEN conclure ─────────────────────────────────────────────
    ok &= _v("429 ne conclut pas",
             verdict_refus_position(429, None)[0], "non_concluant")
    ok &= _v("serveur muet ne conclut pas",
             verdict_publication(None, None)[0], "non_concluant")

    if ok:
        print("  ✅ auto-test : 10 cas, dont 6 qui doivent refuser ou ne pas conclure")
    return ok


def main():
    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-46s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    print("── 1. un commerçant qui s'inscrit seul, sans position ──")
    tel = "+213557%s" % time.strftime("%H%M%S")
    st, d = appeler("POST", "/commercant/register", corps={
        "telephone": tel, "nom": "Commerce Sans Point", "pin": PIN,
        "categorie": "alimentation",
        "acceptedTerms": True})
    if st not in (200, 201):
        print("  ⚠️  inscription refusée (%s %s) — pas de verdict possible"
              % (st, d.get("code")))
        return 2
    jeton = d.get("accessToken")
    time.sleep(PACE)

    st, moi = appeler("GET", "/commercant/me", jeton)
    if moi.get("latitude") is not None:
        # Si le compte naissait AVEC une position, tout ce qui suit mesurerait
        # autre chose que ce qu'on croit (règle #38 : établir la prémisse).
        print("  ⚠️  le compte naît avec une position — prémisse fausse")
        return 2
    print("  ⓘ  compte créé sans position, comme attendu")
    commercant_id = moi.get("id")
    time.sleep(PACE)

    # ── Lever TOUS les autres blocages, sinon on mesure le mauvais refus ─────
    #
    # ⚠️ Ce bloc n'est pas du décor de confort, c'est la prémisse elle-même
    # (règle #38). La première version de ce banc s'en passait : un commerçant
    # auto-inscrit était refusé par `COMMERCANT_REGISTRE_NOT_VALIDATED` bien
    # avant d'atteindre la garde de position, et le banc rendait ❌ sur un
    # produit correct. Il a rendu ❌ pour la bonne raison — il exige le CODE et
    # pas le statut — mais c'était le scénario qui était faux, pas le produit.
    #
    # Quatre gardes se suivent dans `PromoService` : registre, revue de profil,
    # position, plafond. Pour mesurer la troisième, il faut avoir franchi les
    # deux premières. La validation du registre efface aussi
    # `profilePendingReview` (`resolveRegistreVerification`), donc ces quelques
    # requêtes lèvent bien les deux.
    print("\n── 1 bis. lever le blocage registre, pour isoler la position ──")
    admin_email = _exiger("ADMIN_EMAIL")
    admin_password = _exiger("ADMIN_PASSWORD")
    st, d = appeler("POST", "/admin/login",
                    corps={"email": admin_email, "password": admin_password})
    jeton_admin = d.get("accessToken")
    if not jeton_admin:
        print("  ⚠️  connexion admin impossible (%s %s)" % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    st, up = televerser(jeton, "registre")
    cle_registre = up.get("key")
    if not cle_registre:
        print("  ⚠️  téléversement du registre impossible (%s)" % st)
        return 2
    time.sleep(PACE)

    st, d = appeler("POST", "/commercant/me/registre", jeton,
                    {"registreKey": cle_registre})
    if st not in (200, 201):
        print("  ⚠️  dépôt du registre refusé (%s %s)" % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    st, d = appeler("POST", "/admin/commercant/%s/registre/valider"
                    % commercant_id, jeton_admin)
    if st not in (200, 201):
        print("  ⚠️  validation du registre refusée (%s %s)" % (st, d.get("code")))
        return 2
    print("  ⓘ  registre validé — il ne reste que la position")
    time.sleep(PACE)

    # La prémisse, vérifiée et non supposée : le compte n'a toujours pas de
    # position, et plus aucun autre blocage.
    _, moi = appeler("GET", "/commercant/me", jeton)
    if moi.get("latitude") is not None or moi.get("profilePendingReview"):
        print("  ⚠️  état de départ inattendu (position ou revue de profil)")
        return 2
    time.sleep(PACE)

    st, up = televerser(jeton, "promo")
    cle = up.get("key")
    if not cle:
        print("  ⚠️  téléversement impossible (%s) — MinIO joignable ?" % st)
        return 2
    time.sleep(PACE)

    promo = {"description": "Banc position — publication",
             "prixAvant": 1000, "prixApres": 700,
             "categorie": "alimentation", "photoKeys": [cle]}

    print("\n── 2. publier est refusé, et pour LA bonne raison ──")
    st, d = appeler("POST", "/promo", jeton, promo)
    noter("publier sans position", *verdict_refus_position(st, d.get("code")))
    time.sleep(PACE)

    print("\n── 3. préparer un brouillon reste possible ──")
    st, d = appeler("POST", "/promo", jeton, dict(promo, asDraft=True))
    noter("enregistrer en brouillon", *verdict_brouillon(st, d.get("code")))
    brouillon_id = d.get("id")
    time.sleep(PACE)

    print("\n── 4. poser la position, puis publier — sans détour par un admin ──")
    st, d = appeler("PATCH", "/commercant/me/position", jeton,
                    {"latitude": POS_LAT, "longitude": POS_LNG})
    if st != 200:
        noter("poser la position", "echec",
              "PATCH /commercant/me/position → %s %s" % (st, d.get("code")))
    else:
        noter("poser la position", "ok", "%s, %s" % (POS_LAT, POS_LNG))
        # ⚠️ Le contrôle qui donne son sens à tout le reste : c'est le MÊME
        # commerçant, et la seule chose qui a changé est la position.
        if brouillon_id:
            time.sleep(PACE)
            st, d = appeler("POST", "/promo/%s/publish" % brouillon_id, jeton)
            noter("publier le brouillon préparé",
                  *verdict_publication(st, d.get("code")))
        else:
            noter("publier le brouillon préparé", "non_concluant",
                  "aucun brouillon n'a été créé au contrôle 3")

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
