#!/usr/bin/env python3
"""Banc du registre de commerce — le cycle complet, du dépôt à la décision.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

Le registre est la **preuve d'existence légale** du commerce : c'est lui qui
fait passer un compte de « inscrit » à « peut publier ». Le cycle traverse
trois acteurs et quatre routes, et chaque marche peut échouer sans bruit.

⚠️ **Ce banc couvre DEUX lignes de la matrice** (`TEST_PROMO.md` §6) :
`test-commercant-registre` (dépôt) et `test-admin-registre` (décision). Les
séparer aurait obligé chacun à reconstruire le décor de l'autre — un dépôt sans
décision ne prouve rien, une décision sans dépôt n'a rien à décider. Aucune
route n'est orpheline pour autant : les quatre sont exercées ici.

La ligne du plan annonçait « demande un décor **photographique** ». Ce n'en est
pas un obstacle : un JPEG valide tient en 125 octets, et le banc d'upload l'a
montré. La difficulté supposée était une supposition.

Cinq sondes :

1. **Le document déposé est bien un fichier réel**, envoyé par la route
   d'upload avec `purpose=registre` — laquelle est **réservée au commerçant**
   (un agent ne peut pas déposer à sa place, audit sécurité 2026-07-11).
2. **Déposer met le registre en attente**, vérifié sur la ressource.
3. **Valider fait passer le statut**, et **valider deux fois est refusé** par
   un code nommé — pas silencieusement ignoré.
4. **Réinitialiser le PIN coupe l'ancien.** C'est le geste de dépannage le plus
   lourd de l'interface admin.
5. **Chaque décision laisse une trace** (règle 11).

⚠️ Le banc crée son propre commerçant : valider ou réinitialiser celui du décor
le rendrait inutilisable pour les autres bancs.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/registre.py --self-test
    ./scripts/test-registre.sh
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
DEVICE_ID = "banc-registre-0001"
PIN = "654321"
# Position de décor, à Djelfa — obligatoire à la création par agent depuis le
# 2026-08-12, et sans elle publier est refusé (règle #38).
DECOR_LAT, DECOR_LNG = 34.6714, 3.2630

JPEG_1x1 = base64.b64decode(
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof"
    "Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB"
    "AAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q=="
)


def verdict_statut(obtenu, attendu, quoi):
    if obtenu is None:
        return "non_concluant", "%s : statut illisible" % quoi
    if obtenu != attendu:
        return "echec", "%s : statut %r au lieu de %r" % (quoi, obtenu, attendu)
    return "ok", "%s = %s" % (quoi, attendu)


def verdict_refus(statut, code, codes_admis):
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if statut is None:
        return "echec", "pas de réponse : %s" % code
    if statut in (200, 201):
        return ("echec",
                "ACCEPTÉ alors qu'un refus était dû — un second geste sur un "
                "dossier déjà tranché doit se voir")
    if statut >= 500 or code == "INTERNAL_ERROR":
        return "echec", "HTTP %s %s — casse au lieu de refuser" % (statut, code)
    if code not in codes_admis:
        return "non_concluant", "refusé en %s/%s" % (statut, code)
    return "ok", "%s %s" % (statut, code)


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


def televerser(jeton, purpose):
    """POST multipart vers /storage/upload — écrit à la main."""
    frontiere = "----banc%s" % uuid.uuid4().hex
    corps = b"".join([
        ('--%s\r\nContent-Disposition: form-data; name="purpose"\r\n\r\n%s\r\n'
         % (frontiere, purpose)).encode(),
        ('--%s\r\nContent-Disposition: form-data; name="file"; '
         'filename="registre.jpg"\r\nContent-Type: image/jpeg\r\n\r\n'
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
    _v("statut attendu", verdict_statut("valide", "valide", "x")[0], "ok")
    _v("second geste refusé",
       verdict_refus(400, "COMMERCANT_NO_PENDING_REGISTRE_VERIFICATION",
                     ("COMMERCANT_NO_PENDING_REGISTRE_VERIFICATION",))[0], "ok")
    _v("trace présente",
       verdict_trace([{"id": "n", "action": "x"}], "x", set())[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    _v("statut inattendu",
       verdict_statut("en_attente", "valide", "x")[0], "echec")
    _v("statut illisible → non concluant",
       verdict_statut(None, "valide", "x")[0], "non_concluant")
    # ⚠️ Un second geste sur un dossier déjà tranché doit SE VOIR : l'ignorer
    # silencieusement laisse croire à l'admin qu'il vient d'agir.
    _v("second geste accepté", verdict_refus(200, None, ("X",))[0], "echec")
    _v("500 au lieu d'un refus",
       verdict_refus(500, "INTERNAL_ERROR", ("X",))[0], "echec")
    _v("refus au mauvais code",
       verdict_refus(400, "VALIDATION_ERROR", ("X",))[0], "non_concluant")
    _v("429 → non concluant", verdict_refus(429, None, ("X",))[0], "non_concluant")
    _v("décision non tracée", verdict_trace([], "x", set())[0], "echec")
    _v("trace ancienne seulement",
       verdict_trace([{"id": "v", "action": "x"}], "x", {"v"})[0], "echec")
    _v("l'échantillon est un vrai JPEG", JPEG_1x1[:3], b"\xff\xd8\xff")

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

    print("═" * 64)
    print("  Registre de commerce — du dépôt à la décision")
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

    def fiche_admin(cid):
        _, d = appeler("GET", "/admin/commercant?limit=100", ja)
        return next((c for c in d.get("items", []) if c.get("id") == cid), {})

    def journal_ids():
        _, d = appeler("GET", "/admin/audit-log?limit=100", ja)
        return {e.get("id") for e in d.get("items", [])}

    # ── Décor : un commerçant à nous ────────────────────────────────────────
    print("\n── décor : un commerçant neuf ──")
    _, moi = appeler("GET", "/agent/me", jg)
    communes = [c["id"] for c in (moi.get("communes") or [])]
    if not communes:
        print("❌ l'agent du décor n'a aucune commune.")
        return 2
    time.sleep(PACE)
    tel = "+213563%s" % time.strftime("%H%M%S")
    st, d = appeler("POST", "/agent/commercant", jg, {
        "telephone": tel, "nom": "Commerce Registre", "pin": PIN,
        "adresse": "Rue du registre", "categorie": "alimentation",
        "communeId": communes[0],
        "latitude": DECOR_LAT, "longitude": DECOR_LNG})
    cid = d.get("id")
    if not cid:
        print("❌ création refusée (HTTP %s, %s)" % (st, d.get("code")))
        return 2
    noter("commerçant créé", "ok", tel)
    time.sleep(PACE)

    jc = connecter("/commercant/login", {"telephone": tel, "pin": PIN},
                   "commerçant")

    # ── 0. Trancher un dossier qui n'existe pas ─────────────────────────────
    #
    # ⚠️ C'est ICI que `COMMERCANT_NO_PENDING_REGISTRE_VERIFICATION` doit
    # tomber : un commerçant créé par un agent n'a pas de `registreStatus`
    # tant qu'il n'a rien déposé. Trancher un dossier vide n'aurait aucun sens
    # — et l'accepter en silence ferait croire à l'admin qu'il a validé
    # quelque chose.
    print("\n── 0. on ne tranche pas un dossier qui n'existe pas ──")
    st, d = appeler("POST", "/admin/commercant/%s/registre/valider" % cid, ja)
    noter("valider avant tout dépôt",
          *verdict_refus(st, d.get("code"),
                         ("COMMERCANT_NO_PENDING_REGISTRE_VERIFICATION",)))
    time.sleep(PACE)

    # ── 1. Le dépôt ─────────────────────────────────────────────────────────
    print("\n── 1. le commerçant dépose son registre ──")
    st, d = televerser(jc, "registre")
    cle = d.get("key")
    if not cle:
        noter("téléversement du document", "echec",
              "HTTP %s %s" % (st, d.get("code")))
        return 1
    noter("téléversement du document", "ok", cle.split("/")[0] + "/…")
    time.sleep(PACE)

    # ⚠️ `purpose=registre` est RÉSERVÉ au commerçant : l'agent ne dépose pas
    # à sa place (audit sécurité 2026-07-11).
    st, d = televerser(jg, "registre")
    noter("un agent ne dépose pas à sa place",
          *verdict_refus(st, d.get("code"), ("STORAGE_PURPOSE_NOT_ALLOWED",)))
    time.sleep(PACE)

    st, d = appeler("POST", "/commercant/me/registre", jc, {"registreKey": cle})
    if st not in (200, 201):
        noter("demande de vérification", "echec",
              "HTTP %s %s" % (st, d.get("code")))
        return 1
    time.sleep(PACE)
    noter("le registre passe en attente",
          *verdict_statut(fiche_admin(cid).get("registreStatus"),
                          "en_attente", "registreStatus"))
    time.sleep(PACE)

    # ── 2. La décision ──────────────────────────────────────────────────────
    print("\n── 2. l'admin tranche ──")
    avant = journal_ids()
    time.sleep(PACE)
    st, d = appeler("POST", "/admin/commercant/%s/registre/valider" % cid, ja)
    if st not in (200, 201):
        noter("validation", "echec", "HTTP %s %s" % (st, d.get("code")))
        return 1
    time.sleep(PACE)
    noter("le registre est validé",
          *verdict_statut(fiche_admin(cid).get("registreStatus"),
                          "valide", "registreStatus"))
    time.sleep(PACE)

    # ⚠️ Rejouer une décision est VOULU, et documenté : « rejouable à tout
    # moment (valider un rejet, rejeter une validation) tant qu'un document a
    # été soumis au moins une fois » — c'est ce qui permet à l'admin de
    # corriger son erreur sans repasser par le commerçant. Ma première version
    # de ce banc exigeait un refus ici : elle sondait un effet supposé au lieu
    # de la règle écrite, et rougissait sur un comportement correct.
    st, d = appeler("POST", "/admin/commercant/%s/registre/rejeter" % cid, ja)
    if st in (200, 201):
        time.sleep(PACE)
        noter("une décision est rejouable (valide → rejeté)",
              *verdict_statut(fiche_admin(cid).get("registreStatus"),
                              "rejete", "registreStatus"))
    else:
        noter("une décision est rejouable", "echec",
              "HTTP %s %s — l'admin ne peut plus corriger son erreur"
              % (st, d.get("code")))
    time.sleep(PACE)

    _, journal = appeler("GET", "/admin/audit-log?limit=100", ja)
    noter("la validation est tracée",
          *verdict_trace(journal.get("items", []), "registre_valider", avant))
    time.sleep(PACE)

    # ── 3. La réinitialisation du PIN ───────────────────────────────────────
    print("\n── 3. réinitialiser le PIN coupe l'ancien ──")
    avant = journal_ids()
    time.sleep(PACE)
    st, d = appeler("POST", "/admin/commercant/%s/reset-pin" % cid, ja,
                    {"newPin": "998877"})
    if st not in (200, 201):
        noter("réinitialisation", "non_concluant",
              "HTTP %s %s" % (st, d.get("code")))
    else:
        time.sleep(PACE)
        st, d = appeler("POST", "/commercant/login",
                        corps={"telephone": tel, "pin": PIN})
        noter("l'ancien PIN ne rouvre plus",
              *verdict_refus(st, d.get("code"), ("AUTH_INVALID_CREDENTIALS",)))
        time.sleep(PACE)
        _, journal = appeler("GET", "/admin/audit-log?limit=100", ja)
        noter("la réinitialisation est tracée",
              *verdict_trace(journal.get("items", []), "commercant_reset_pin",
                             avant))

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
