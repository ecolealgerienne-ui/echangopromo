#!/usr/bin/env python3
"""Banc de l'upload — taille, format réel, et périmètre par rôle.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

L'upload n'avait **jamais été éprouvé contre un vrai bucket**, alors que MinIO
tourne en local depuis le début. Quatre règles sondées, chacune ancrée sur un
défaut réel ou sur une règle du dépôt née d'un défaut.

1. **Un `Content-Type` déclaré n'engage à rien** (règle 5). Le format est
   vérifié sur les **octets réels**, pas sur ce que le client annonce. C'est la
   sonde qui compte le plus : elle envoie un fichier texte en le déclarant
   `image/jpeg`, exactement ce que ferait quelqu'un qui cherche à déposer
   autre chose qu'une image dans un bucket public.

2. **La taille est bornée deux fois, et les deux doivent rendre le même code.**
   Au-delà de `MAX_UPLOAD_BYTES` (500 Ko) c'est le service qui refuse ; au-delà
   du filet Multer (×4) la requête est coupée **avant** de l'atteindre, et
   c'est `AllExceptionsFilter` qui rattache le `413` à
   `STORAGE_FILE_TOO_LARGE`. Ce rattachement date du 2026-08-05 : sans lui, le
   mobile recevait un code inconnu et affichait un message générique pour un
   cas parfaitement identifiable.

3. **La clé rendue appartient au compte qui a envoyé.** C'est ce qui rend
   `assertPhotoKeysOwned` utile : si la clé ne portait pas l'identifiant de
   l'appelant, le garde posé le 2026-08-05 sur la création de promo n'aurait
   rien à vérifier.

4. **Le `purpose` est cadré par rôle.** `registre` est réservé au commerçant,
   `highlight` à l'admin — non parce qu'un endpoint l'exploiterait autrement,
   mais pour ne pas laisser écrire dans un préfixe qu'on ne contrôle pas
   (audit sécurité 2026-07-11).

── Ce qu'il n'éprouve PAS, et pourquoi ─────────────────────────────────────

Que l'objet soit réellement lisible dans le bucket ensuite. Il faudrait les
identifiants MinIO, que ce banc n'a pas — et la clé rendue suffit à répondre
aux questions posées ici. La lecture effective est couverte par le fait que
l'app affiche les photos, constaté à l'écran.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/storage_upload.py --self-test
    ./scripts/test-storage-upload.sh
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
PACE = float(os.environ.get("PACE_SECONDS", "1.1"))
DEVICE_ID = "banc-upload-0001"

MAX_UPLOAD_BYTES = 500 * 1024  # miroir de storage.service.ts, pour DIMENSIONNER
#                                les échantillons — jamais pour asserter : les
#                                verdicts portent sur le comportement (refusé /
#                                accepté), pas sur une copie du nombre.

# JPEG 1×1 valide — 125 octets. Les octets sont RÉELS : un fichier qui se
# contente d'annoncer `image/jpeg` est justement ce que la sonde n°1 rejette.
JPEG_1x1 = base64.b64decode(
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof"
    "Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB"
    "AAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q=="
)


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_accepte(statut, corps, prefixe_attendu):
    """Un envoi légitime doit réussir ET rendre une clé qui nous appartient."""
    if statut == 429:
        return "non_concluant", "429 — plafond de requêtes, ce n'est pas un verdict"
    if statut not in (200, 201):
        return "echec", "refusé (HTTP %s, %s)" % (statut, corps.get("code"))
    cle = corps.get("key")
    if not cle:
        return "echec", "accepté mais sans clé — rien à rattacher ensuite"
    if not cle.startswith(prefixe_attendu):
        return ("echec",
                "clé %r hors du préfixe %r — `assertPhotoKeysOwned` n'aurait "
                "rien à vérifier" % (cle, prefixe_attendu))
    return "ok", cle


def verdict_refuse(statut, corps, codes_admis):
    """Un refus attendu, au bon code, et surtout PAS un 500.

    ⚠️ `INTERNAL_ERROR` n'est pas un refus : c'est une panne. Les confondre
    ferait passer pour « protégé » un endpoint qui casse (règle 28).
    """
    code = corps.get("code")
    if statut == 429:
        return "non_concluant", "429 — plafond de requêtes, ce n'est pas un verdict"
    if statut is None:
        return "echec", "pas de réponse : %s" % code
    if statut in (200, 201):
        return "echec", "ACCEPTÉ alors qu'un refus était dû"
    if statut >= 500 or code == "INTERNAL_ERROR":
        return ("echec",
                "HTTP %s %s — l'endpoint casse au lieu de refuser" % (statut, code))
    if code not in codes_admis:
        return ("non_concluant",
                "refusé en %s/%s, hors des codes attendus %s — la sonde n'a "
                "pas atteint la règle visée" % (statut, code, codes_admis))
    return "ok", "%s %s" % (statut, code)


# ─────────────────────────────────────────────────────────────────────────────

def poster_fichier(chemin, jeton, contenu, nom_fichier, content_type,
                   champs=None):
    """POST multipart/form-data, écrit à la main (aucune dépendance externe)."""
    frontiere = "----banc%s" % uuid.uuid4().hex
    morceaux = []
    for cle, valeur in (champs or {}).items():
        morceaux.append(
            ('--%s\r\nContent-Disposition: form-data; name="%s"\r\n\r\n%s\r\n'
             % (frontiere, cle, valeur)).encode())
    morceaux.append(
        ('--%s\r\nContent-Disposition: form-data; name="file"; filename="%s"\r\n'
         'Content-Type: %s\r\n\r\n' % (frontiere, nom_fichier, content_type)
         ).encode())
    morceaux.append(contenu)
    morceaux.append(("\r\n--%s--\r\n" % frontiere).encode())
    corps = b"".join(morceaux)

    req = urllib.request.Request(API_URL + chemin, data=corps, method="POST")
    req.add_header("Content-Type", "multipart/form-data; boundary=%s" % frontiere)
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


def appeler(methode, chemin, jeton=None, corps=None):
    donnees = json.dumps(corps).encode() if corps is not None else None
    req = urllib.request.Request(API_URL + chemin, data=donnees, method=methode)
    req.add_header("Content-Type", "application/json")
    req.add_header("X-Device-Id", DEVICE_ID)
    if jeton:
        req.add_header("Authorization", "Bearer " + jeton)
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
        print("❌ %s absent — lancer ./scripts/provision-decor.sh et coller son "
              "bloc." % nom)
        sys.exit(2)
    return v


# ─────────────────────────────────────────────────────────────────────────────
# Auto-test
# ─────────────────────────────────────────────────────────────────────────────

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
    _v("envoi accepté avec la bonne clé",
       verdict_accepte(201, {"key": "promo-photos/c1/x.jpg"},
                       "promo-photos/c1/")[0], "ok")
    _v("refus au bon code",
       verdict_refuse(400, {"code": "STORAGE_INVALID_IMAGE"},
                      ("STORAGE_INVALID_IMAGE",))[0], "ok")
    _v("413 rattaché",
       verdict_refuse(413, {"code": "STORAGE_FILE_TOO_LARGE"},
                      ("STORAGE_FILE_TOO_LARGE",))[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    _v("envoi refusé alors qu'il devait passer",
       verdict_accepte(400, {"code": "X"}, "promo-photos/c1/")[0], "echec")
    _v("accepté sans clé",
       verdict_accepte(201, {}, "promo-photos/c1/")[0], "echec")
    # ⚠️ Le cas qui rend `assertPhotoKeysOwned` utile ou inutile.
    _v("clé hors du préfixe du compte",
       verdict_accepte(201, {"key": "promo-photos/AUTRUI/x.jpg"},
                       "promo-photos/c1/")[0], "echec")
    _v("accepté alors qu'un refus était dû",
       verdict_refuse(201, {}, ("STORAGE_INVALID_IMAGE",))[0], "echec")
    # ⚠️ Une panne n'est pas une protection.
    _v("500 compté comme refus",
       verdict_refuse(500, {"code": "INTERNAL_ERROR"},
                      ("STORAGE_INVALID_IMAGE",))[0], "echec")
    _v("502 sans code",
       verdict_refuse(502, {}, ("STORAGE_INVALID_IMAGE",))[0], "echec")
    _v("pas de réponse", verdict_refuse(None, {"code": "RESEAU"}, ())[0], "echec")
    _v("refus au mauvais code → non concluant",
       verdict_refuse(400, {"code": "VALIDATION_ERROR"},
                      ("STORAGE_INVALID_IMAGE",))[0], "non_concluant")
    _v("429 sur un refus → non concluant",
       verdict_refuse(429, {}, ("STORAGE_INVALID_IMAGE",))[0], "non_concluant")
    _v("429 sur un envoi → non concluant",
       verdict_accepte(429, {}, "promo-photos/c1/")[0], "non_concluant")

    # L'échantillon lui-même doit être une VRAIE image, sinon la sonde n°1
    # ne prouve rien : elle refuserait un fichier invalide dans les deux cas.
    _v("l'échantillon JPEG a bien la signature", JPEG_1x1[:3], b"\xff\xd8\xff")

    refus = 10
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


# ─────────────────────────────────────────────────────────────────────────────

def main():
    tel = _exiger("COMMERCANT_TEL")
    pin = _exiger("COMMERCANT_PIN")
    cid = _exiger("COMMERCANT_ID")

    print("═" * 64)
    print("  Upload — taille, format réel, périmètre par rôle")
    print("═" * 64)

    st, d = appeler("POST", "/commercant/login",
                    corps={"telephone": tel, "pin": pin})
    jc = d.get("accessToken")
    if not jc:
        print("❌ connexion commerçant impossible (HTTP %s, %s)"
              % (st, d.get("code")))
        print("   ⚠️ un 429 se déguise en « identifiants incorrects ».")
        return 2
    time.sleep(PACE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-40s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    # ── 1. L'envoi légitime ─────────────────────────────────────────────────
    print("\n── 1. un envoi légitime, et la clé qu'il rend ──")
    st, d = poster_fichier("/storage/upload", jc, JPEG_1x1, "photo.jpg",
                           "image/jpeg", {"purpose": "promo"})
    noter("JPEG accepté, clé du compte",
          *verdict_accepte(st, d, "promo-photos/%s/" % cid))
    time.sleep(PACE)

    # ── 2. Le format RÉEL ───────────────────────────────────────────────────
    #
    # Le cœur du banc : un fichier texte annoncé `image/jpeg`. Si l'endpoint
    # croit l'en-tête, n'importe quoi entre dans un bucket public.
    print("\n── 2. un Content-Type déclaré n'engage à rien (règle 5) ──")
    st, d = poster_fichier("/storage/upload", jc,
                           b"CECI N'EST PAS UNE IMAGE" * 8, "faux.jpg",
                           "image/jpeg", {"purpose": "promo"})
    noter("texte déclaré image/jpeg refusé",
          *verdict_refuse(st, d, ("STORAGE_INVALID_IMAGE",)))
    time.sleep(PACE)

    # ── 3. Les deux bornes de taille ────────────────────────────────────────
    print("\n── 3. deux bornes, un seul code rendu ──")
    trop_gros = JPEG_1x1 + b"\x00" * (MAX_UPLOAD_BYTES + 1024)
    st, d = poster_fichier("/storage/upload", jc, trop_gros, "gros.jpg",
                           "image/jpeg", {"purpose": "promo"})
    noter("au-delà de la borne métier",
          *verdict_refuse(st, d, ("STORAGE_FILE_TOO_LARGE",)))
    time.sleep(PACE)

    # Au-delà du filet Multer (×4) : coupé AVANT le service, rattaché par
    # `AllExceptionsFilter`. Les deux doivent rendre le même code, sinon le
    # mobile affiche deux messages différents pour le même problème.
    enorme = JPEG_1x1 + b"\x00" * (MAX_UPLOAD_BYTES * 4 + 4096)
    st, d = poster_fichier("/storage/upload", jc, enorme, "enorme.jpg",
                           "image/jpeg", {"purpose": "promo"})
    noter("au-delà du filet Multer (413 rattaché)",
          *verdict_refuse(st, d, ("STORAGE_FILE_TOO_LARGE",)))
    time.sleep(PACE)

    # ── 4. Le périmètre par rôle ────────────────────────────────────────────
    print("\n── 4. le purpose est cadré par rôle ──")
    st, d = poster_fichier("/storage/upload", jc, JPEG_1x1, "photo.jpg",
                           "image/jpeg", {"purpose": "highlight"})
    noter("purpose=highlight refusé au commerçant",
          *verdict_refuse(st, d, ("STORAGE_PURPOSE_NOT_ALLOWED",)))
    time.sleep(PACE)

    st, d = poster_fichier("/storage/upload", jc, JPEG_1x1, "photo.jpg",
                           "image/jpeg", {"purpose": "nimporte-quoi"})
    noter("purpose inconnu refusé",
          *verdict_refuse(st, d, ("VALIDATION_ERROR",)))

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
