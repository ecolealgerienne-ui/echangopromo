#!/usr/bin/env python3
"""Banc de l'auto-suppression — `DELETE /commercant/me`, action irréversible.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

**Aucun test à ce jour** sur la seule route par laquelle un commerçant efface
son propre compte (T4). Elle fait trois choses d'un coup — marquer le compte
supprimé, révoquer la session, effacer les promos — et **chacune peut manquer
sans que rien ne le dise**.

Cinq règles sondées :

1. **La session en cours est révoquée immédiatement.** Sans ça, un compte
   supprimé continue d'agir avec son jeton jusqu'à expiration — soit **30
   jours** ici (`JWT_EXPIRES_IN`). C'est la règle 6 : un jeton long doit
   prévoir sa révocation, et `tokenVersion` existe précisément pour ça.
2. **Les promos quittent l'affichage client.** Un commerce disparu dont les
   promos restent visibles, c'est un client qui se déplace pour rien.
3. **Le numéro est libéré.** C'est P10 : l'unicité ne porte que sur les comptes
   vivants (`UQ_commercant_telephone_active`, index partiel
   `WHERE "deletedAt" IS NULL`). Sans libération, un commerce qui change de
   main enferme son repreneur dehors. ⚠️ Cet index est exactement celui que
   `migration:generate` proposait de **supprimer** le 2026-08-05 : une sonde de
   plus dessus n'est pas du luxe.
4. **L'ancien PIN ne rouvre plus rien.**
5. **Le rayon d'action est borné.** Un second commerçant, créé et laissé
   tranquille, doit être intact — compte vivant et promo toujours visible. Un
   `update()` dont le critère aurait sauté effacerait la base entière sans que
   les quatre sondes précédentes ne bronchent : elles ne regardent que la
   victime.

── Précautions ─────────────────────────────────────────────────────────────

⚠️ Le banc ne touche **jamais** au commerçant du décor : il crée les siens, par
l'**agent** (`POST /agent/commercant`), ce qui évite le seau strict de 5
connexions/minute et laisse le décor utilisable par les autres bancs.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/autosuppression.py --self-test
    ./scripts/test-commercant-autosuppression.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.2"))
DEVICE_ID = "banc-autosupp-0001"
PIN = "654321"
# Position de décor, à Djelfa — voir agent_creation.py : obligatoire à la
# création par agent depuis le 2026-08-12, et sans elle publier est refusé
# (règle #38 : un banc qui accuse le produit à tort est le pire faux négatif).
DECOR_LAT, DECOR_LNG = 34.6738, 3.2664


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_revocation(statut, code):
    """Le jeton d'un compte supprimé ne doit plus rien ouvrir.

    ⚠️ Un `404` ou un `500` ne comptent pas : on veut la preuve que la session
    est REFUSÉE, pas que la ressource a disparu. Les confondre laisserait
    passer un jeton encore valide sur toutes les autres routes.
    """
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if statut is None:
        return "echec", "pas de réponse : %s" % code
    if statut in (200, 201):
        return ("echec",
                "le jeton du compte supprimé fonctionne ENCORE — il reste "
                "exploitable jusqu'à expiration (30 j)")
    if code != "AUTH_TOKEN_REVOKED":
        return ("non_concluant",
                "refusé en %s/%s au lieu de AUTH_TOKEN_REVOKED — refus obtenu "
                "pour une autre raison que la révocation" % (statut, code))
    return "ok", "%s %s" % (statut, code)


def verdict_invisible(promos_publiques, pid):
    """La promo du compte supprimé ne doit plus être servie au client."""
    if pid in promos_publiques:
        return ("echec",
                "la promo du compte supprimé est TOUJOURS visible du client")
    return "ok", "retirée de l'affichage client"


def verdict_numero_libere(statut, code):
    """Recréer avec le même numéro doit réussir (P10)."""
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if statut in (200, 201):
        return "ok", "numéro repris par un nouveau compte"
    if code == "COMMERCANT_PHONE_TAKEN":
        return ("echec",
                "le numéro reste pris après suppression — le repreneur du "
                "commerce est enfermé dehors (P10)")
    return "echec", "recréation refusée en %s/%s" % (statut, code)


def verdict_intact(vivant, promo_visible):
    """Le voisin n'avait rien demandé.

    ⚠️ C'est la sonde du rayon d'action : sans elle, un `update()` dont le
    critère aurait sauté passerait inaperçu, les autres sondes ne regardant
    que la victime.
    """
    if not vivant:
        return ("echec",
                "le second commerçant a été supprimé LUI AUSSI — le critère "
                "de l'update a-t-il sauté ?")
    if not promo_visible:
        return ("echec",
                "la promo du second commerçant a disparu — la suppression a "
                "débordé sur un tiers")
    return "ok", "compte et promo intacts"


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
        print("❌ %s absent — lancer ./scripts/provision-decor.sh et coller son "
              "bloc." % nom)
        sys.exit(2)
    return v


def promos_publiques():
    _, d = appeler("GET", "/promo?limit=100")
    return {p["id"] for p in d.get("items", [])}


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
    _v("révocation constatée",
       verdict_revocation(401, "AUTH_TOKEN_REVOKED")[0], "ok")
    _v("promo retirée", verdict_invisible({"autre"}, "p1")[0], "ok")
    _v("numéro libéré", verdict_numero_libere(201, None)[0], "ok")
    _v("voisin intact", verdict_intact(True, True)[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le cas le plus grave : le jeton survit à la suppression du compte.
    _v("jeton encore valide",
       verdict_revocation(200, None)[0], "echec")
    _v("pas de réponse", verdict_revocation(None, "RESEAU")[0], "echec")
    _v("refus pour une autre raison → non concluant",
       verdict_revocation(404, "COMMERCANT_NOT_FOUND")[0], "non_concluant")
    _v("429 → non concluant", verdict_revocation(429, None)[0], "non_concluant")
    _v("promo toujours visible",
       verdict_invisible({"p1", "autre"}, "p1")[0], "echec")
    _v("numéro resté pris",
       verdict_numero_libere(409, "COMMERCANT_PHONE_TAKEN")[0], "echec")
    _v("recréation refusée autrement",
       verdict_numero_libere(400, "VALIDATION_ERROR")[0], "echec")
    # ⚠️ Le rayon d'action : la victime est bien traitée, le voisin aussi.
    _v("voisin supprimé lui aussi", verdict_intact(False, True)[0], "echec")
    _v("promo du voisin disparue", verdict_intact(True, False)[0], "echec")

    refus = 9
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


# ─────────────────────────────────────────────────────────────────────────────

def main():
    agent_email = _exiger("AGENT_EMAIL")
    agent_password = _exiger("AGENT_PASSWORD")
    admin_email = _exiger("ADMIN_EMAIL")
    admin_password = _exiger("ADMIN_PASSWORD")

    print("═" * 64)
    print("  Auto-suppression du commerçant — action irréversible")
    print("═" * 64)

    st, d = appeler("POST", "/agent/login",
                    corps={"email": agent_email, "password": agent_password})
    jg = d.get("accessToken")
    if not jg:
        print("❌ connexion agent impossible (HTTP %s, %s)" % (st, d.get("code")))
        print("   ⚠️ un 429 se déguise en « identifiants incorrects ».")
        return 2
    time.sleep(PACE)

    st, d = appeler("POST", "/admin/login",
                    corps={"email": admin_email, "password": admin_password})
    ja = d.get("accessToken")
    if not ja:
        print("❌ connexion admin impossible (HTTP %s, %s)" % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-40s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    # ── Décor : DEUX commerçants à nous ─────────────────────────────────────
    #
    # ⚠️ Jamais celui du décor : l'action est irréversible. Créés par l'AGENT,
    # ce qui évite le seau strict de 5 connexions/minute que `register`
    # partage avec les logins.
    print("\n── décor : deux commerçants, créés pour ce banc ──")
    # ⚠️ Format algérien : `+213` suivi de NEUF chiffres. Un préfixe de trois
    # chiffres (556/557) plus l'heure (six) fait exactement le compte — une
    # première version en mettait dix et `@IsPhoneNumber('DZ')` refusait, ce
    # qui s'affichait comme une panne de décor.
    base = time.strftime("%H%M%S")
    tel_victime = "+213556%s" % base
    tel_voisin = "+213557%s" % base

    def creer(tel, nom):
        st, d = appeler("POST", "/agent/commercant", jg, {
            "telephone": tel, "nom": nom, "pin": PIN,
            "adresse": "Rue du banc", "categorie": "alimentation",
            "communeId": _commune_de_l_agent(jg),
            "latitude": DECOR_LAT, "longitude": DECOR_LNG})
        if st not in (200, 201):
            print("❌ création de %s refusée (HTTP %s, %s)"
                  % (nom, st, d.get("code")))
            sys.exit(2)
        time.sleep(PACE)
        return d.get("id")

    cid_victime = creer(tel_victime, "Commerce Victime")
    cid_voisin = creer(tel_voisin, "Commerce Voisin")
    noter("deux comptes créés", "ok", "%s / %s" % (tel_victime, tel_voisin))

    def promo_pour(cid, marque):
        st, d = appeler("POST", "/promo/agent/%s" % cid, jg, {
            "description": "Promo %s" % marque, "prixAvant": 600,
            "prixApres": 300, "categorie": "alimentation",
            "photoKeys": ["promo-photos/%s/p.jpg" % cid]})
        if st not in (200, 201):
            print("❌ promo %s refusée (HTTP %s, %s)" % (marque, st, d.get("code")))
            sys.exit(2)
        time.sleep(PACE)
        return d.get("id")

    pid_victime = promo_pour(cid_victime, "victime")
    pid_voisin = promo_pour(cid_voisin, "voisin")

    avant = promos_publiques()
    if pid_victime not in avant or pid_voisin not in avant:
        noter("les deux promos sont visibles avant", "non_concluant",
              "l'une des deux manque déjà — la suite ne prouverait rien")
        return 1
    noter("les deux promos sont visibles avant", "ok", "2 promos servies")

    # ── L'auto-suppression ──────────────────────────────────────────────────
    print("\n── 1. le commerçant se supprime lui-même ──")
    st, d = appeler("POST", "/commercant/login",
                    corps={"telephone": tel_victime, "pin": PIN})
    jv = d.get("accessToken")
    if not jv:
        noter("connexion de la victime", "non_concluant",
              "HTTP %s %s" % (st, d.get("code")))
        return 1
    time.sleep(PACE)

    st, d = appeler("DELETE", "/commercant/me", jv)
    if st not in (200, 201, 204):
        noter("DELETE /commercant/me", "echec",
              "HTTP %s %s" % (st, d.get("code")))
        return 1
    noter("DELETE /commercant/me", "ok", "HTTP %s" % st)
    time.sleep(PACE)

    # ── Les conséquences ────────────────────────────────────────────────────
    print("\n── 2. ce que la suppression doit entraîner ──")
    st, d = appeler("GET", "/commercant/me", jv)
    noter("la session en cours est révoquée",
          *verdict_revocation(st, d.get("code")))
    time.sleep(PACE)

    apres = promos_publiques()
    noter("la promo quitte l'affichage client",
          *verdict_invisible(apres, pid_victime))

    st, d = appeler("POST", "/commercant/login",
                    corps={"telephone": tel_victime, "pin": PIN})
    if st in (200, 201):
        noter("l'ancien PIN ne rouvre plus rien", "echec",
              "la connexion réussit encore sur un compte supprimé")
    else:
        noter("l'ancien PIN ne rouvre plus rien", "ok",
              "%s %s" % (st, d.get("code")))
    time.sleep(PACE)

    st, d = appeler("POST", "/agent/commercant", jg, {
        "telephone": tel_victime, "nom": "Commerce Repreneur", "pin": PIN,
        "adresse": "Rue du banc", "categorie": "alimentation",
        "communeId": _commune_de_l_agent(jg),
        "latitude": DECOR_LAT, "longitude": DECOR_LNG})
    noter("le numéro est libéré (P10)", *verdict_numero_libere(st, d.get("code")))
    time.sleep(PACE)

    # ── Le rayon d'action ───────────────────────────────────────────────────
    print("\n── 3. le rayon d'action ──")
    st, d = appeler("GET", "/commercant/%s/public" % cid_voisin)
    voisin_vivant = st in (200, 201)
    noter("le voisin n'a rien subi",
          *verdict_intact(voisin_vivant, pid_voisin in apres))

    print("\n" + "═" * 64)
    echecs = resultats.count("echec")
    non_concluants = resultats.count("non_concluant")
    print("%d contrôles, %d échec(s), %d non concluant(s)"
          % (len(resultats), echecs, non_concluants))
    if non_concluants and not echecs:
        print("⚠️  des sondes n'ont pas conclu : ce n'est pas une réussite.")
    return 1 if (echecs or non_concluants) else 0


_commune_cache = {}


def _commune_de_l_agent(jg):
    """La première commune de l'agent — un commerçant doit naître chez lui."""
    if "id" not in _commune_cache:
        _, d = appeler("GET", "/agent/me", jg)
        communes = d.get("communes") or []
        if not communes:
            print("❌ l'agent du décor n'a aucune commune — décor incomplet.")
            sys.exit(2)
        _commune_cache["id"] = communes[0]["id"]
    return _commune_cache["id"]


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)
    sys.exit(main())
