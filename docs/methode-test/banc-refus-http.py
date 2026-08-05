#!/usr/bin/env python3
"""Banc de refus de la frontière HTTP — squelette (étage 3).

Chaque route protégée est appelée trois fois : sans jeton, avec le jeton d'un
AUTRE rôle, et avec un jeton révoqué. Les trois doivent être refusées, avec le
bon statut ET le bon code — un refus sans code est un refus que l'application
ne sait pas traduire.

── Pourquoi les routes sont énumérées depuis la source ──────────────────────

Une liste écrite à la main aurait exactement le défaut qu'elle prétend
corriger : la route ajoutée demain n'y serait pas.

⚠️ **Et pourquoi l'énumération ne part PAS des décorateurs de protection**
(mode M11). Un banc qui énumérerait « les routes protégées » depuis leur garde
verrait l'ensemble RÉTRÉCIR quand on ouvre une route — le total tomberait sans
qu'une seule assertion passe au rouge. On énumère donc TOUTES les routes, et
les routes publiques sont **épinglées nommément** ci-dessous : chacune est une
décision qui doit s'écrire. Une route publique non épinglée est une erreur.

── Usage ────────────────────────────────────────────────────────────────────

    python3 banc-refus-http.py --self-test   # d'abord, et c'est bloquant
    python3 banc-refus-http.py --list        # les routes vues, sans rien appeler
    python3 banc-refus-http.py               # le banc

    PACE_SECONDS=0.8 python3 banc-refus-http.py   # si le débit plafonne (M9)
"""

import os
import re
import sys
import time
import json
import urllib.error
import urllib.request

# ─────────────────────────────────────────────────────────────────────────────
# À ADAPTER — configuration du projet
# ─────────────────────────────────────────────────────────────────────────────

BASE_URL = os.environ.get("BASE_URL", "http://localhost:3000")
SRC_DIR = os.environ.get("SRC_DIR", "apps/backend/src")
PACE_SECONDS = float(os.environ.get("PACE_SECONDS", "0.25"))

# Les routes ouvertes, épinglées une par une AVEC leur justification.
# ⚠️ Ne jamais y ajouter une entrée pour faire passer le banc : une route
# publique est la seule surface qu'un inconnu peut marteler.
ROUTES_PUBLIQUES = {
    ("POST", "/auth/login"): "connexion — throttle strict appliqué",
    ("GET", "/health"): "sonde de disponibilité",
    # À ADAPTER : ajouter ici les routes réellement publiques du projet.
}

# Comment obtenir des jetons. À ADAPTER : ces trois fonctions sont le seul
# endroit qui connaît le schéma d'authentification du projet.
#
# ⚠️ Aucune valeur de repli (mode M3) : un jeton absent doit ARRÊTER le banc,
# jamais le laisser conclure « tout est refusé » — ce qui serait vrai et vide
# de sens, puisqu'une requête sans jeton valide est refusée de toute façon.


def jeton_role_a():
    """Un jeton VALIDE d'un rôle qui n'a pas accès aux routes testées."""
    raise NotImplementedError("À ADAPTER : connexion du rôle A")


def jeton_revoque():
    """Un jeton dont le compte a été révoqué (tokenVersion incrémenté)."""
    raise NotImplementedError("À ADAPTER : produire un jeton révoqué")


# Les codes d'erreur attendus. À ADAPTER selon le registre du projet.
CODE_SANS_JETON = {"AUTH_TOKEN_MISSING"}
CODE_MAUVAIS_ROLE = {"AUTH_FORBIDDEN", "FORBIDDEN"}
CODE_REVOQUE = {"AUTH_TOKEN_REVOKED"}

# ─────────────────────────────────────────────────────────────────────────────
# Énumération des routes depuis la source
# ─────────────────────────────────────────────────────────────────────────────

# ⚠️ **Ancrés en début de ligne** (`^\s*`), et c'est ce qui distingue un vrai
# décorateur d'une chaîne qui en contient le texte — `const s = "@Controller(…)"`
# ne doit rien produire. Défaut trouvé par l'auto-test, pas par la relecture.
_CONTROLLER = re.compile(r"^\s*@Controller\(\s*(?:'([^']*)'|\"([^\"]*)\")?", re.M)
_METHODE = re.compile(
    r"^\s*@(Get|Post|Put|Patch|Delete)\(\s*(?:'([^']*)'|\"([^\"]*)\")?\s*\)", re.M
)
_PUBLIC = re.compile(r"@Public\(\s*\)")
_GARDE = re.compile(r"@UseGuards\(")
_CLASSE = re.compile(r"^\s*(?:export\s+)?(?:abstract\s+)?class\s", re.M)

_COMMENTAIRE_BLOC = re.compile(r"/\*[\s\S]*?\*/")
_COMMENTAIRE_LIGNE = re.compile(r"//[^\n]*")

# ─── Les deux polarités de protection, et pourquoi il faut savoir laquelle ───
#
# "global"    : un garde d'authentification est posé en APP_GUARD, et une route
#               s'ouvre avec @Public(). ⇒ **la route qu'on oublie est fermée.**
# "par_route" : chaque route pose son @UseGuards(). ⇒ **la route qu'on oublie
#               est OUVERTE**, et l'oubli ne se voit nulle part — ni à la
#               compilation, ni à l'exécution, ni dans les journaux.
#
# ⚠️ En mode "par_route", le banc traite toute route SANS garde comme ouverte :
# elle doit alors figurer nommément dans ROUTES_PUBLIQUES, sans quoi c'est une
# régression. C'est le seul moyen de rendre l'oubli visible.
MODE_PROTECTION = os.environ.get("MODE_PROTECTION", "par_route")  # À ADAPTER


def routes_du_source(texte, mode=None):
    """Les routes déclarées dans un fichier de contrôleur.

    Rend une liste de (methode, chemin, est_ouvert).

    ⚠️ `est_ouvert` est REMONTÉ pour pouvoir être comparé à la liste épinglée,
    jamais pour exclure la route de l'ensemble énuméré (mode M11).
    """
    mode = mode or MODE_PROTECTION

    # ⚠️ Les commentaires sont retirés d'abord. Sans ça, un contrôleur ou une
    # route mis en commentaire — pendant une mise hors service, typiquement —
    # serait sondé, et son 404 compté comme un refus réussi. Le banc
    # conclurait « protégée » sur une route qui n'existe plus.
    texte = _COMMENTAIRE_BLOC.sub("", texte)
    texte = _COMMENTAIRE_LIGNE.sub("", texte)

    prefixe_m = _CONTROLLER.search(texte)
    if not prefixe_m:
        return []
    prefixe = (prefixe_m.group(1) or prefixe_m.group(2) or "").strip("/")

    # ⚠️ Un décorateur posé AVANT la déclaration de classe s'applique à TOUTES
    # les méthodes. L'ignorer ferait passer pour non protégé un contrôleur
    # entier gardé au niveau de la classe — un faux positif massif qui ferait
    # abandonner le banc.
    #
    # ⚠️ **Et l'en-tête ne commence PAS au `@Controller`.** L'ordre habituel en
    # NestJS est `@UseGuards` puis `@Roles` puis `@Controller` : partir du
    # `@Controller` fait manquer le garde qui le précède. Constaté sur le vrai
    # code — six routes d'administration remontées comme ouvertes alors
    # qu'elles étaient gardées trois lignes plus haut. Trouvé en faisant
    # tourner le banc sur le dépôt réel, pas en relisant le parseur (mode M1).
    #
    # On prend donc **toutes les lignes de décorateur** situées avant la
    # déclaration de classe, quel que soit leur ordre.
    classe_m = _CLASSE.search(texte, prefixe_m.end())
    fin_entete = classe_m.start() if classe_m else prefixe_m.end()
    entete = "\n".join(
        l for l in texte[:fin_entete].split("\n") if l.lstrip().startswith("@")
    )
    public_classe = bool(_PUBLIC.search(entete))
    garde_classe = bool(_GARDE.search(entete))

    routes = []
    curseur = fin_entete
    for m in _METHODE.finditer(texte, fin_entete):
        methode = m.group(1).upper()
        segment = (m.group(2) or m.group(3) or "").strip("/")

        # Le segment qui précède ce décorateur : c'est là, et nulle part
        # ailleurs, que vivent les décorateurs propres à cette route.
        avant = texte[curseur:m.start()]
        curseur = m.end()

        if mode == "global":
            est_ouvert = public_classe or bool(_PUBLIC.search(avant))
        else:
            est_ouvert = not (garde_classe or bool(_GARDE.search(avant)))

        parties = [p for p in (prefixe, segment) if p]
        routes.append((methode, "/" + "/".join(parties), est_ouvert))
    return routes


def toutes_les_routes(racine):
    vues = []
    for dossier, _, fichiers in os.walk(racine):
        for f in fichiers:
            if not f.endswith(".controller.ts"):
                continue
            chemin = os.path.join(dossier, f)
            with open(chemin, encoding="utf-8") as fh:
                vues.extend(routes_du_source(fh.read()))
    return sorted(set(vues))


def url_sondable(chemin):
    """Remplace les paramètres par un identifiant inexistant mais BIEN FORMÉ.

    ⚠️ Mal formé, on mesurerait la validation du format et non le refus
    d'accès — et un 400 passerait pour un refus alors qu'il n'en est pas un.
    """
    return re.sub(r":([A-Za-z_]+)", "00000000-0000-4000-8000-000000000000", chemin)


# ─────────────────────────────────────────────────────────────────────────────
# Les sondes
# ─────────────────────────────────────────────────────────────────────────────


def appeler(methode, chemin, jeton=None):
    """Rend (statut, code_metier). Ne lève pas sur une réponse d'erreur."""
    req = urllib.request.Request(BASE_URL + chemin, method=methode)
    req.add_header("Content-Type", "application/json")
    if jeton:
        req.add_header("Authorization", "Bearer " + jeton)
    corps = b"{}" if methode in ("POST", "PUT", "PATCH") else None
    try:
        with urllib.request.urlopen(req, corps, timeout=15) as r:
            return r.status, None
    except urllib.error.HTTPError as e:
        brut = e.read()
        try:
            return e.code, json.loads(brut).get("code")
        except Exception:
            return e.code, None
    except Exception as e:
        # ⚠️ Pas de repli sur « refusé » : une panne réseau n'est pas un refus.
        return None, "ERREUR_RESEAU: %s" % e


def sonder(methode, chemin, jeton, statuts_ok, codes_ok, libelle):
    statut, code = appeler(methode, url_sondable(chemin), jeton)
    time.sleep(PACE_SECONDS)
    if statut is None:
        return False, "%s : %s" % (libelle, code)
    if statut not in statuts_ok:
        return False, "%s : statut %s (attendu %s)" % (libelle, statut, statuts_ok)
    if codes_ok and code not in codes_ok:
        return False, "%s : code %r (attendu %s)" % (libelle, code, codes_ok)
    return True, ""


# ─────────────────────────────────────────────────────────────────────────────
# Auto-test — cas qui doivent PASSER et cas qui doivent ÉCHOUER (mode M1)
# ─────────────────────────────────────────────────────────────────────────────

_CAS = [
    # (mode, source, routes attendues) — doivent PASSER
    ("global", "@Controller('promo')\n@Get()\nlist() {}",
     [("GET", "/promo", False)]),
    ("global", "@Controller('promo')\n@Get(':id')\none() {}",
     [("GET", "/promo/:id", False)]),
    ("global", "@Controller('admin')\n@Post('agent')\ncreate() {}",
     [("POST", "/admin/agent", False)]),
    ("global", "@Controller()\n@Get('health')\nh() {}",
     [("GET", "/health", False)]),
    ("global", "@Controller('a')\n@Public()\n@Get('b')\nb() {}",
     [("GET", "/a/b", True)]),
    # Plusieurs méthodes dans un même fichier.
    ("global", "@Controller('x')\n@Get()\na() {}\n@Delete(':id')\nb() {}",
     [("DELETE", "/x/:id", False), ("GET", "/x", False)]),
    # ── Polarité inverse : le garde est posé par route ────────────────────────
    ("par_route", "@Controller('x')\n@UseGuards(A, B)\n@Get()\na() {}",
     [("GET", "/x", False)]),
    # ⚠️ Le cas qui compte : une route SANS garde est OUVERTE, et doit remonter
    # comme telle. C'est l'oubli que ce mode existe pour rendre visible.
    ("par_route", "@Controller('x')\n@Get()\na() {}",
     [("GET", "/x", True)]),
    # Garde posé au niveau de la CLASSE : il couvre toutes les méthodes.
    ("par_route",
     "@Controller('x')\n@UseGuards(A)\nexport class C {\n@Get()\na() {}\n@Post()\nb() {}\n}",
     [("GET", "/x", False), ("POST", "/x", False)]),
    # ⚠️ **Le cas venu du vrai code**, et celui qu'aucun cas fabriqué n'avait
    # anticipé : l'ordre habituel en NestJS place @UseGuards AVANT @Controller.
    # Un parseur qui part du @Controller manque le garde et annonce une route
    # d'administration ouverte. Six faux positifs sur le dépôt réel.
    ("par_route",
     "@UseGuards(A, B)\n@Roles('admin')\n@Controller('admin/x')\n"
     "export class C {\n@Get()\na() {}\n}",
     [("GET", "/admin/x", False)]),
]

# Cas de REFUS : des sources sur lesquelles le parseur NE DOIT PAS rendre de
# route. Sans eux, l'auto-test ne montrerait que sa capacité à dire oui.
_CAS_REFUS = [
    "// @Controller('promo')\n// @Get()\n",          # commentaires de ligne
    "/* @Controller('x')\n@Get()\n*/",               # commentaire de bloc
    "@Injectable()\n@Get()\nrien() {}",              # pas un contrôleur
    "class Sans { }",                                # rien du tout
    "@Controller('promo')\n",                        # contrôleur sans route
    "const s = \"@Controller('faux')\";",            # dans une chaîne, pas un décorateur
]


def self_test():
    echecs = []
    passes = 0

    for mode, source, attendu in _CAS:
        obtenu = sorted(routes_du_source(source, mode))
        if obtenu != sorted(attendu):
            echecs.append("[%s] attendu %s, obtenu %s" % (mode, attendu, obtenu))
        else:
            passes += 1

    for source in _CAS_REFUS:
        obtenu = routes_du_source(source)
        if obtenu:
            echecs.append("aurait dû ne rien rendre, a rendu %s" % (obtenu,))
        else:
            passes += 1

    total = len(_CAS) + len(_CAS_REFUS)
    print("auto-test : %d cas, dont %d refus" % (total, len(_CAS_REFUS)))
    for e in echecs:
        print("  ❌ " + e)
    print("  %d/%d" % (passes, total))
    return not echecs


# ─────────────────────────────────────────────────────────────────────────────


def main():
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)

    routes = toutes_les_routes(SRC_DIR)
    if not routes:
        print("❌ aucune route trouvée sous %s — l'absence de verdict n'est pas "
              "un verdict." % SRC_DIR)
        sys.exit(2)

    ouvertes = {(m, c) for m, c, ouv in routes if ouv}
    epinglees = set(ROUTES_PUBLIQUES)

    if "--list" in sys.argv:
        for m, c, ouv in routes:
            print("%-6s %-45s %s" % (m, c, "OUVERTE" if ouv else ""))
        print("\n%d routes, dont %d ouvertes (mode : %s)"
              % (len(routes), len(ouvertes), MODE_PROTECTION))
        return

    # ⚠️ Le contrôle qui ferme le mode M11 : une route ouverte dans le code mais
    # non épinglée ici est une régression, pas une donnée d'entrée. En mode
    # "par_route", c'est CE contrôle qui rend visible le garde oublié — le banc
    # de refus, lui, ne sonde que les routes qui se déclarent protégées.
    surprises = ouvertes - epinglees
    if surprises:
        print("❌ %d route(s) OUVERTE(s) non épinglée(s) — chacune doit être "
              "une décision écrite, ou porter son garde :" % len(surprises))
        for m, c in sorted(surprises):
            print("     %s %s" % (m, c))
        sys.exit(1)

    disparues = epinglees - ouvertes
    if disparues:
        print("⚠️  épinglées mais plus ouvertes dans le code (à retirer d'ici) :")
        for m, c in sorted(disparues):
            print("     %s %s" % (m, c))

    protegees = [(m, c) for m, c, ouv in routes if not ouv]
    print("── banc de refus : %d routes protégées (sur %d, %d ouvertes "
          "épinglées) ──\n" % (len(protegees), len(routes), len(epinglees)))

    autre_role = jeton_role_a()
    revoque = jeton_revoque()

    echecs = []
    for methode, chemin in protegees:
        for ok, msg in (
            sonder(methode, chemin, None, {401}, CODE_SANS_JETON, "sans jeton"),
            sonder(methode, chemin, autre_role, {401, 403}, CODE_MAUVAIS_ROLE, "autre rôle"),
            sonder(methode, chemin, revoque, {401}, CODE_REVOQUE, "jeton révoqué"),
        ):
            if not ok:
                echecs.append("%s %s — %s" % (methode, chemin, msg))

    for e in echecs:
        print("  ❌ " + e)
    print("\n%d routes × 3 sondes — %d échec(s)" % (len(protegees), len(echecs)))
    sys.exit(1 if echecs else 0)


if __name__ == "__main__":
    main()
