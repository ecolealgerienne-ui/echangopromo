#!/usr/bin/env python3
"""Banc de la frontière admin — l'agent est-il refusé là où il doit l'être ?

── Ce que ce banc éprouve, et pourquoi le code ne suffit pas ───────────────

Neuf routes sont `@Roles('admin')` **seul**. Mesuré le 2026-08-13 : toutes leurs
écritures ne sont jamais exercées qu'avec un jeton **admin**. Aucun banc ne les
attaque avec un jeton d'**agent**.

Trois seulement ont un témoin négatif (`GET /admin/agent`, `GET
/admin/audit-log`, `PATCH …/plafond-promos`, dans `portee_agent` et
`pentest_dynamique`). **Un `GET` refusé ne prouve rien du `POST` d'à côté** :
ici chaque route pose son propre `@UseGuards`, la polarité est par route, et
« la route qu'on oublie est OUVERTE » (règle 33). L'oubli ne se voit ni à la
compilation, ni à l'exécution, ni dans les journaux.

J'ai lu le code : les gardes sont bien montées, y compris au niveau classe sur
`AdminHighlightController`. **Et c'est précisément ce qu'on n'a pas le droit de
conclure depuis le code** — la règle 33 interdit d'énumérer les routes protégées
depuis leur garde, puisque l'ensemble contrôlé rétrécirait avec ce qu'il
contrôle. Seul un banc peut affirmer qu'aucune ne manque.

── Ce que ça coûterait, concrètement ───────────────────────────────────────

`POST /admin/agent` atteignable par un agent, c'est un agent qui **se fabrique
des comptes**. Les cinq routes de curation atteignables, c'est un agent qui
**décide de la vitrine nationale** — une capacité que le produit réserve
explicitement à l'admin, la curation étant globale et non un outil de terrain.

── ⚠️ Le témoin positif, et pourquoi il est indispensable ──────────────────

Un 403 rendu à l'agent ne prouve rien si la route est morte : une route
inexistante refuse tout le monde. On vérifie donc, pour chacune, que **l'admin
la traverse**.

Et on le fait **sans rien créer ni détruire** : les gardes NestJS s'exécutent
**avant** les pipes de validation. Un corps vide envoyé par l'admin ressort donc
en `400 VALIDATION_ERROR` — ce qui prouve qu'il a franchi la garde — tandis que
le même corps envoyé par l'agent ressort en `403` **avant** d'être regardé. Le
témoin positif est ainsi gratuit : aucun agent créé, aucune curation modifiée.

⚠️ **Une seule exception, et elle est en dernier** : `POST /admin/me/revoke-token`
n'a pas de corps à invalider, et son témoin positif **révoque réellement le
jeton de l'admin**. Il est donc joué à la toute fin, quand plus rien n'en
dépend.

── ⚠️ La limite de ce banc, mesurée par sa propre mutation ─────────────────

En remplaçant le jeton d'agent par celui de l'admin — ce qui simule une garde de
rôle tombée — il rend **5 échecs et 5 non concluants**, jamais un faux vert.
Mais ces cinq « non concluants » disent quelque chose : sur les quatre routes
visant `<absent>`, une garde tombée se manifeste par un `404
AGENT_NOT_FOUND` / `HIGHLIGHT_NOT_FOUND` — la ressource inexistante **masque**
l'absence de garde. Le banc refuse alors de conclure, ce qui est juste, mais sa
sensibilité y est partielle.

**Le rendre pleinement sensible coûterait cher** : il faudrait viser des cibles
réelles, donc laisser l'admin révoquer le jeton d'un vrai agent, réinitialiser
un vrai mot de passe et supprimer une vraie entrée de vitrine à chaque passage.
Le choix est assumé : un banc sans effet de bord, sensible à 100 % sur les cinq
routes sans `:id` et « non concluant plutôt que faux » sur les quatre autres.
Écrit ici pour que personne ne lise son vert comme une preuve plus forte qu'il
ne l'est.

── Usage ───────────────────────────────────────────────────────────────────

    python3 scripts/lib/frontiere_admin.py --self-test
    ./scripts/test-frontiere-admin.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.2"))
DEVICE_ID = "banc-frontiere-admin-0001"

# UUID valide et inexistant : la forme passe `UuidParam`, la ressource n'existe
# pas. ⚠️ Un identifiant mal formé ferait rendre 400 par le pipe — donc **après**
# la garde pour l'admin, mais on ne saurait plus distinguer les deux causes.
ABSENT = "11111111-2222-4333-8444-555555555555"

# ── Les neuf routes `@Roles('admin')` SEUL, et leur corps invalide ──────────
#
# Le corps est volontairement vide : il ne peut rien créer, et il fait ressortir
# l'admin en 400 VALIDATION_ERROR — la preuve qu'il a franchi la garde.
ROUTES = [
    ("POST", "/admin/agent", {},
     "créer un agent — un agent qui se fabrique des comptes"),
    ("POST", "/admin/agent/%s/revoke-token" % ABSENT, None,
     "révoquer les jetons d'un autre agent"),
    ("POST", "/admin/agent/%s/reset-password" % ABSENT, {},
     "changer le mot de passe d'un autre agent"),
    ("GET", "/admin/highlight", None,
     "lire la curation"),
    ("POST", "/admin/highlight", {},
     "ajouter à la vitrine nationale"),
    ("POST", "/admin/highlight/reorder", {},
     "réordonner la vitrine nationale"),
    ("PATCH", "/admin/highlight/%s" % ABSENT, {},
     "modifier une entrée de vitrine"),
    ("DELETE", "/admin/highlight/%s" % ABSENT, None,
     "retirer une entrée de vitrine"),
]

# ⚠️ Joué en DERNIER : son témoin positif révoque pour de bon le jeton admin.
ROUTE_DESTRUCTRICE = ("POST", "/admin/me/revoke-token", None,
                      "révoquer son propre jeton")


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_agent_refuse(statut, code):
    """⚠️ **La sonde centrale.** L'agent doit être refusé POUR SON RÔLE.

    Le code est asserté, et pas seulement « ce n'est pas un 200 » : un 404 ferme
    aussi la porte, mais parce que la ressource n'existe pas — la garde pourrait
    avoir disparu sans qu'on le voie. Un contrôle qui accepte n'importe quel
    refus finit par certifier une route ouverte dont la cible est absente.
    """
    if statut is None:
        return "non_concluant", "aucune réponse"
    if statut == 403 and code == "AUTH_FORBIDDEN_ROLE":
        return "ok", "403 AUTH_FORBIDDEN_ROLE"
    if statut in (200, 201, 204):
        return ("echec",
                "ROUTE ADMIN ATTEINTE PAR UN AGENT (HTTP %s) : la garde de "
                "rôle ne tient pas, et rien dans les journaux ne le dira"
                % statut)
    if statut == 400 and code == "VALIDATION_ERROR":
        return ("echec",
                "l'agent atteint la VALIDATION de la route : la garde de rôle "
                "s'exécute avant les pipes, donc elle ne l'a pas arrêté — seul "
                "un corps invalide le sépare encore de l'écriture")
    if statut == 401:
        return ("non_concluant",
                "401 — jeton non reconnu ; on mesure l'authentification, pas "
                "la frontière de rôle")
    if statut == 429:
        return ("non_concluant",
                "429 — seau épuisé, un refus de débit n'est pas un refus de "
                "rôle")
    return ("non_concluant",
            "HTTP %s %s — porte fermée, mais pour une autre raison que le rôle"
            % (statut, code))


def verdict_admin_passe(statut, code):
    """⚠️ Sans lui, un 403 rendu à l'agent ne prouverait rien.

    Une route morte, mal montée ou renommée refuse **tout le monde** : le témoin
    négatif serait vert sur une capacité disparue (règle 38). On exige donc que
    l'admin franchisse la garde — ce que prouve n'importe quelle réponse **sauf**
    un refus de rôle.
    """
    if statut is None:
        return "non_concluant", "aucune réponse"
    if statut == 403 and code == "AUTH_FORBIDDEN_ROLE":
        return ("echec",
                "l'ADMIN est refusé sur sa propre route : elle est mal montée "
                "ou morte, et le 403 rendu à l'agent ne prouve donc rien")
    if statut == 404 and code is None:
        return ("non_concluant",
                "404 sans code d'erreur — la route n'existe probablement plus, "
                "et le refus opposé à l'agent perd tout son sens")
    if statut == 401:
        return ("non_concluant",
                "401 — le jeton admin n'est plus valide, la mesure ne porte "
                "sur rien")
    return "ok", "l'admin franchit la garde (HTTP %s%s)" % (
        statut, " " + code if code else "")


def verdict_couverture(mesurees, attendues):
    """Toutes les routes annoncées ont-elles été réellement interrogées ?

    ⚠️ Une route sautée en silence est le pire résultat possible : le banc rend
    vert sur une frontière qu'il n'a pas regardée (défaut fondateur de la
    règle 28 — un contrôle silencieusement sauté).
    """
    if mesurees is None:
        return "non_concluant", "décompte illisible"
    if mesurees < attendues:
        return ("echec",
                "%d routes interrogées sur %d annoncées — %d frontière(s) "
                "n'ont pas été regardées"
                % (mesurees, attendues, attendues - mesurees))
    return "ok", "les %d routes annoncées ont été interrogées" % attendues


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
            corps_lu = r.read()
            return r.status, (json.loads(corps_lu) if corps_lu else {})
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read())
        except Exception:
            return e.code, {}
    except Exception:
        return None, {}


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
    _v("agent refusé pour son rôle",
       verdict_agent_refuse(403, "AUTH_FORBIDDEN_ROLE")[0], "ok")
    _v("admin passe (400 de validation)",
       verdict_admin_passe(400, "VALIDATION_ERROR")[0], "ok")
    _v("admin passe (200)", verdict_admin_passe(200, None)[0], "ok")
    # ⚠️ Un 404 AVEC code métier prouve que la route vit et a cherché la cible.
    _v("admin passe (404 métier)",
       verdict_admin_passe(404, "HIGHLIGHT_NOT_FOUND")[0], "ok")
    _v("couverture complète", verdict_couverture(9, 9)[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le défaut visé : un agent atteint une route d'administration.
    _v("agent accepté", verdict_agent_refuse(201, None)[0], "echec")
    _v("agent accepté en 204", verdict_agent_refuse(204, None)[0], "echec")
    # ⚠️ Les gardes passent AVANT les pipes : un agent qui atteint la validation
    # a franchi la garde, et seul un corps invalide le sépare de l'écriture.
    _v("agent atteint la validation",
       verdict_agent_refuse(400, "VALIDATION_ERROR")[0], "echec")
    # ⚠️ Une route morte refuse tout le monde : le témoin négatif ne vaudrait
    # plus rien (règle 38).
    _v("admin refusé sur sa route",
       verdict_admin_passe(403, "AUTH_FORBIDDEN_ROLE")[0], "echec")
    _v("route sautée", verdict_couverture(7, 9)[0], "echec")

    # ── Doivent rester NON CONCLUANTS ────────────────────────────────────────
    # ⚠️ Un 404 ferme la porte, mais pas pour le rôle : la garde a pu tomber.
    _v("porte fermée pour autre chose",
       verdict_agent_refuse(404, "AGENT_NOT_FOUND")[0], "non_concluant")
    _v("403 sans code de rôle",
       verdict_agent_refuse(403, "FORBIDDEN")[0], "non_concluant")
    _v("seau épuisé", verdict_agent_refuse(429, None)[0], "non_concluant")
    _v("jeton agent invalide",
       verdict_agent_refuse(401, None)[0], "non_concluant")
    _v("aucune réponse", verdict_agent_refuse(None, None)[0], "non_concluant")
    _v("route disparue", verdict_admin_passe(404, None)[0], "non_concluant")
    _v("jeton admin expiré", verdict_admin_passe(401, None)[0], "non_concluant")
    _v("admin sans réponse", verdict_admin_passe(None, None)[0], "non_concluant")
    _v("décompte illisible", verdict_couverture(None, 9)[0], "non_concluant")

    refus = 14
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


# ─────────────────────────────────────────────────────────────────────────────

def main():
    admin_email = _exiger("ADMIN_EMAIL")
    admin_password = _exiger("ADMIN_PASSWORD")
    agent_email = _exiger("AGENT_EMAIL")
    agent_password = _exiger("AGENT_PASSWORD")

    print("═" * 74)
    print("  Frontière admin — l'agent est-il refusé là où il doit l'être ?")
    print("═" * 74)
    print("  ⚠️ corps volontairement vides : les gardes s'exécutent AVANT les")
    print("     pipes, donc rien n'est créé ni détruit par ce banc")

    st, d = appeler("POST", "/admin/login",
                    corps={"email": admin_email, "password": admin_password})
    ja = d.get("accessToken")
    st, d = appeler("POST", "/agent/login",
                    corps={"email": agent_email, "password": agent_password})
    jg = d.get("accessToken")
    if not (ja and jg):
        print("❌ connexions impossibles (admin=%s agent=%s)"
              % (bool(ja), bool(jg)))
        return 2
    time.sleep(PACE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-46s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    interrogees = 0

    def eprouver(methode, chemin, corps, quoi):
        """Le couple indissociable : l'agent refusé, l'admin passant."""
        nonlocal interrogees
        etiquette = "%s %s" % (methode, chemin.replace(ABSENT, "<absent>"))
        print("\n   %s — %s" % (etiquette, quoi))
        st, d = appeler(methode, chemin, jg, corps)
        noter("agent refusé", *verdict_agent_refuse(st, d.get("code")))
        time.sleep(PACE)
        st, d = appeler(methode, chemin, ja, corps)
        noter("… et l'admin passe", *verdict_admin_passe(st, d.get("code")))
        interrogees += 1
        time.sleep(PACE)

    print("\n── Les huit routes sans effet de bord ──")
    for methode, chemin, corps, quoi in ROUTES:
        eprouver(methode, chemin, corps, quoi)

    # ── ⚠️ La destructrice, en dernier ──────────────────────────────────────
    #
    # Le témoin positif révoque POUR DE BON le jeton de l'admin : plus rien ne
    # doit en dépendre après. C'est la seule route dont on ne peut pas invalider
    # le corps pour rester sans effet.
    print("\n── ⚠️ La route destructrice, jouée en dernier ──")
    methode, chemin, corps, quoi = ROUTE_DESTRUCTRICE
    eprouver(methode, chemin, corps, quoi)

    print("\n── Aucune frontière n'a été sautée ──")
    noter("routes interrogées",
          *verdict_couverture(interrogees, len(ROUTES) + 1))

    print("\n" + "═" * 74)
    print("  Rappel : GET /admin/agent, GET /admin/audit-log et")
    print("  PATCH …/plafond-promos ont déjà leur témoin négatif dans")
    print("  portee_agent et pentest_dynamique — non redoublés ici.")
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
