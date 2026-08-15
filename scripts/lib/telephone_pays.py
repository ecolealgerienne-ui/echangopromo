#!/usr/bin/env python3
"""Banc du téléphone et de son pays — une écriture, un compte.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

Depuis le 2026-08-15, un numéro est **normalisé en E.164 avant d'être écrit**
(`+213555000101`), quelle que soit la façon dont il a été saisi, et il porte un
**pays** choisi par le commerçant. Trois propriétés en découlent, et aucune
n'est vérifiable en lisant le code :

1. **Deux écritures du même numéro ne font qu'un compte.** C'est le défaut
   fermé : avant, `0555000101` et `+213555000101` étaient deux chaînes
   distinctes, donc deux comptes actifs possibles pour un même commerçant — et
   une connexion refusée à qui saisissait l'autre forme que la sienne.
2. **Un commerçant non algérien existe.** Le sélecteur propose 245 pays ; rien
   ne prouvait qu'un `+971` traverse réellement l'inscription, la connexion et
   la lecture.
3. **Le pays déclaré fait autorité, dans les TROIS formulaires.** Un numéro
   émirati saisi sous « Algérie » doit être refusé à l'inscription, à la
   création par un agent et à la connexion — pas seulement là où on a pensé à
   regarder.

⚠️ **Ce banc consomme le seau d'inscription** (`STRICT_THROTTLE`, 5/min/IP).
Il espace donc ses inscriptions de `PACE_REGISTER` secondes. Sans cet
espacement, un `429` se déguiserait en refus métier et le banc accuserait le
produit d'un défaut qu'il n'a pas (règle #38).

⚠️ **Il crée de vrais comptes**, sur des numéros qui lui sont propres, et les
supprime en fin de course avec le jeton admin. La suppression libère le numéro,
donc il est rejouable tel quel.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/telephone_pays.py --self-test
    ./scripts/provision-decor.sh     # puis coller le bloc export imprimé
    ./scripts/test-telephone-pays.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.5"))
# 5 inscriptions/min/IP : 15 s garantit au plus 4 par fenêtre glissante.
PACE_REGISTER = float(os.environ.get("PACE_REGISTER", "15"))

ADMIN_EMAIL = os.environ.get("ADMIN_EMAIL", "decor-admin@echango.local")
ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "decor-admin-2026")
AGENT_EMAIL = os.environ.get("AGENT_EMAIL", "decor-agent@echango.local")
AGENT_PASSWORD = os.environ.get("AGENT_PASSWORD", "decor-agent-2026")

PIN = "864213"
# Numéros propres à ce banc, hors des plages du décor (0555…/0556…/0557…).
NAT_A, INTL_A = "0770112233", "+213770112233"
NAT_B, INTL_B = "0770112244", "+213770112244"
# Émirats : national `055 123 4567`, international `+971551234567`.
NAT_AE, INTL_AE = "0551234567", "+971551234567"
DECOR_LAT, DECOR_LNG = 34.6725, 3.2652


def appeler(methode, chemin, jeton=None, corps=None, entetes=None):
    donnees = (
        json.dumps(corps if corps is not None else {}).encode()
        if methode in ("POST", "PUT", "PATCH", "DELETE")
        else None
    )
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
        brut = e.read()
        try:
            return e.code, json.loads(brut or b"{}")
        except Exception:
            return e.code, {}
    except Exception as e:  # réseau, backend éteint…
        return 0, {"code": "INJOIGNABLE", "message": str(e)}


# ── Verdicts : des fonctions PURES, pour que l'auto-test puisse les éprouver ──


def verdict_inscription_acceptee(statut, code):
    if statut == 201:
        return "ok", "compte créé"
    if statut == 429 or code == "RATE_LIMITED":
        return "non_concluant", "plafond d'inscription atteint — banc trop rapide"
    return "echec", "inscription refusée (%s %s)" % (statut, code)


def verdict_doublon_refuse(statut, code):
    if statut == 409 and code == "COMMERCANT_PHONE_TAKEN":
        return "ok", "l'autre écriture du même numéro est vue comme un doublon"
    if statut == 201:
        return "echec", "DEUX comptes actifs pour un même numéro"
    if statut == 429 or code == "RATE_LIMITED":
        return "non_concluant", "plafond d'inscription atteint"
    # Un refus pour une autre raison ne prouve pas l'unicité.
    return "non_concluant", "refusé, mais pour une autre raison (%s %s)" % (statut, code)


def verdict_pays_refuse(statut, code):
    if statut == 400 and code == "VALIDATION_ERROR":
        return "ok", "numéro d'un autre pays refusé"
    if statut in (200, 201):
        return "echec", "numéro d'un autre pays ACCEPTÉ sous le pays déclaré"
    return "non_concluant", "refusé, mais pour une autre raison (%s %s)" % (statut, code)


def verdict_connexion_acceptee(statut, code):
    if statut == 201:
        return "ok", "connexion acceptée"
    if statut == 429 or code == "RATE_LIMITED":
        return "non_concluant", "plafond de connexion atteint"
    return "echec", "connexion refusée (%s %s)" % (statut, code)


def verdict_forme_stockee(observee, attendue):
    if observee == attendue:
        return "ok", "stocké « %s »" % observee
    if observee is None:
        return "non_concluant", "fiche introuvable côté admin"
    return "echec", "stocké « %s », attendu « %s »" % (observee, attendue)


def self_test():
    cas = [
        # ── Doivent PASSER ───────────────────────────────────────────────────
        (verdict_inscription_acceptee, 201, None, "ok"),
        (verdict_doublon_refuse, 409, "COMMERCANT_PHONE_TAKEN", "ok"),
        (verdict_pays_refuse, 400, "VALIDATION_ERROR", "ok"),
        (verdict_connexion_acceptee, 201, None, "ok"),
        # ── Doivent REFUSER — le défaut visé, exactement ─────────────────────
        # Deux comptes pour un même numéro : c'est CE défaut que le banc existe
        # pour attraper.
        (verdict_doublon_refuse, 201, None, "echec"),
        # Un numéro émirati accepté sous « Algérie » : la colonne `pays`
        # deviendrait décorative.
        (verdict_pays_refuse, 201, None, "echec"),
        (verdict_inscription_acceptee, 400, "VALIDATION_ERROR", "echec"),
        (verdict_connexion_acceptee, 400, "AUTH_INVALID_CREDENTIALS", "echec"),
        # ── Ne doivent RIEN conclure ────────────────────────────────────────
        # Un 429 n'est pas un refus métier ; le confondre ferait accuser le
        # produit d'un défaut qui n'est qu'un banc trop rapide (règle #38).
        (verdict_inscription_acceptee, 429, "RATE_LIMITED", "non_concluant"),
        (verdict_doublon_refuse, 429, "RATE_LIMITED", "non_concluant"),
        (verdict_doublon_refuse, 400, "VALIDATION_ERROR", "non_concluant"),
        (verdict_pays_refuse, 409, "COMMERCANT_PHONE_TAKEN", "non_concluant"),
        (verdict_connexion_acceptee, 429, "RATE_LIMITED", "non_concluant"),
    ]
    echecs, passes = [], 0
    for fn, st, code, attendu in cas:
        obtenu, _ = fn(st, code)
        if obtenu == attendu:
            passes += 1
        else:
            echecs.append(
                "%s(%s,%r)=%s attendu %s" % (fn.__name__, st, code, obtenu, attendu)
            )

    formes = [
        ("+213770112233", "+213770112233", "ok"),
        # La forme nationale stockée serait la régression du 2026-08-15.
        ("0770112233", "+213770112233", "echec"),
        (None, "+213770112233", "non_concluant"),
    ]
    for observee, attendue, attendu in formes:
        v, _ = verdict_forme_stockee(observee, attendue)
        if v == attendu:
            passes += 1
        else:
            echecs.append(
                "verdict_forme_stockee(%r,%r)=%s attendu %s"
                % (observee, attendue, v, attendu)
            )

    total = len(cas) + len(formes)
    refus = 6
    print("auto-test : %d cas, dont %d qui doivent refuser" % (total, refus))
    for e in echecs:
        print("  ❌ " + e)
    print("  %d/%d" % (passes, total))
    return not echecs


# ── Le banc ──────────────────────────────────────────────────────────────────


def inscrire(telephone, nom, pays=None, position=True):
    corps = {
        "telephone": telephone,
        "nom": nom,
        "categorie": "alimentation",
        "pin": PIN,
        "acceptedTerms": True,
    }
    if pays:
        corps["pays"] = pays
    if position:
        corps["latitude"], corps["longitude"] = DECOR_LAT, DECOR_LNG
    statut, rep = appeler("POST", "/commercant/register", corps=corps)
    time.sleep(PACE_REGISTER)
    return statut, rep


def connecter(telephone, pays=None, pin=PIN):
    corps = {"telephone": telephone, "pin": pin}
    if pays:
        corps["pays"] = pays
    statut, rep = appeler("POST", "/commercant/login", corps=corps)
    time.sleep(PACE)
    return statut, rep


def jeton(chemin, email, mot_de_passe):
    statut, rep = appeler(
        "POST", chemin, corps={"email": email, "password": mot_de_passe}
    )
    time.sleep(PACE)
    return rep.get("accessToken") if statut in (200, 201) else None


def fiche_admin(jeton_admin, chiffres):
    """La fiche telle que l'admin la voit — donc la forme RÉELLEMENT stockée."""
    statut, rep = appeler(
        "GET", "/admin/commercant?limit=50&search=%s" % chiffres, jeton=jeton_admin
    )
    time.sleep(PACE)
    if statut != 200:
        return None
    for item in rep.get("items", []):
        if "".join(c for c in item.get("telephone", "") if c.isdigit()).endswith(
            chiffres[-9:]
        ):
            return item
    return None


def main():
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)

    resultats = []
    a_nettoyer = []

    def noter(libelle, verdict, quoi):
        icone = {"ok": "✅", "echec": "❌"}.get(verdict, "⚠️ ")
        print("  %s %-52s %s" % (icone, libelle, quoi))
        resultats.append(verdict)

    print("── jetons ──")
    jeton_admin = jeton("/admin/login", ADMIN_EMAIL, ADMIN_PASSWORD)
    jeton_agent = jeton("/agent/login", AGENT_EMAIL, AGENT_PASSWORD)
    if not jeton_admin:
        print("❌ jeton admin absent — poser le décor d'abord.")
        sys.exit(2)
    print("  ✅ admin%s" % ("" if jeton_agent else " (agent absent : test 4c sauté)"))

    print()
    print("── 1. deux écritures du même numéro ne font qu'un compte ──")
    st, rep = inscrire(INTL_A, "Banc tel A")
    noter("inscription en +213…", *verdict_inscription_acceptee(st, rep.get("code")))
    if st == 201:
        a_nettoyer.append(("+213770112233", INTL_A))
    st, rep = inscrire(NAT_A, "Banc tel A doublon")
    noter("ré-inscription en 0…", *verdict_doublon_refuse(st, rep.get("code")))

    st, rep = inscrire(NAT_B, "Banc tel B")
    noter("inscription en 0…", *verdict_inscription_acceptee(st, rep.get("code")))
    if st == 201:
        a_nettoyer.append(("+213770112244", INTL_B))
    st, rep = inscrire(INTL_B, "Banc tel B doublon")
    noter("ré-inscription en +213…", *verdict_doublon_refuse(st, rep.get("code")))

    print()
    print("── 2. la forme stockée est bien l'E.164 ──")
    fiche = fiche_admin(jeton_admin, "770112233")
    noter(
        "ce que la base contient",
        *verdict_forme_stockee(fiche.get("telephone") if fiche else None, INTL_A)
    )

    print()
    print("── 3. un commerçant non algérien existe ──")
    st, rep = inscrire(INTL_AE, "Banc tel Emirats", pays="AE")
    noter("inscription +971 sous pays AE", *verdict_inscription_acceptee(st, rep.get("code")))
    if st == 201:
        a_nettoyer.append(("+971551234567", INTL_AE))
    st, rep = connecter(NAT_AE, pays="AE")
    noter("connexion en saisie nationale AE", *verdict_connexion_acceptee(st, rep.get("code")))
    st, rep = connecter(INTL_AE, pays="AE")
    noter("connexion en +971", *verdict_connexion_acceptee(st, rep.get("code")))
    fiche = fiche_admin(jeton_admin, "551234567")
    noter(
        "forme stockée du compte émirati",
        *verdict_forme_stockee(fiche.get("telephone") if fiche else None, INTL_AE)
    )

    print()
    print("── 4. le pays déclaré fait autorité, dans les TROIS formulaires ──")
    st, rep = inscrire(INTL_AE, "Banc tel mauvais pays")
    noter("inscription : +971 sous DZ", *verdict_pays_refuse(st, rep.get("code")))
    st, rep = connecter(INTL_AE)
    noter("connexion : +971 sous DZ", *verdict_pays_refuse(st, rep.get("code")))
    if jeton_agent:
        st, rep = appeler(
            "POST",
            "/agent/commercant",
            jeton=jeton_agent,
            corps={
                "telephone": INTL_AE,
                "nom": "Banc tel agent mauvais pays",
                "categorie": "alimentation",
                "pin": PIN,
                "latitude": DECOR_LAT,
                "longitude": DECOR_LNG,
            },
        )
        time.sleep(PACE)
        noter("création agent : +971 sous DZ", *verdict_pays_refuse(st, rep.get("code")))

    print()
    print("── nettoyage ──")
    for attendu, _saisie in a_nettoyer:
        fiche = fiche_admin(jeton_admin, "".join(c for c in attendu if c.isdigit()))
        if fiche:
            appeler(
                "POST", "/admin/commercant/%s/delete" % fiche["id"], jeton=jeton_admin
            )
            time.sleep(PACE)
            print("  supprimé %s" % attendu)

    print()
    echecs = resultats.count("echec")
    doutes = resultats.count("non_concluant")
    print(
        "════ %d contrôles, %d échec(s), %d non concluant(s) ════"
        % (len(resultats), echecs, doutes)
    )
    sys.exit(1 if echecs else 0)


if __name__ == "__main__":
    main()
