#!/usr/bin/env python3
"""Banc de refus de la frontière HTTP — echango Promo (étape 1).

Chaque route protégée est appelée trois fois : sans jeton, avec le jeton d'un
rôle qui n'y a pas droit, et avec un jeton révoqué. Les trois doivent être
refusées — avec le bon statut ET le bon code, parce qu'un refus sans code est
un refus que l'application ne sait pas traduire.

── Pourquoi les routes sont énumérées depuis la source ──────────────────────

Une liste écrite à la main aurait le défaut qu'elle prétend corriger : la route
ajoutée demain n'y serait pas.

⚠️ **Et pourquoi on n'énumère PAS depuis les décorateurs de protection.** Un
banc qui listerait « les routes protégées » depuis leur `@UseGuards` verrait
l'ensemble RÉTRÉCIR quand on ouvre une route : le total tomberait sans qu'une
seule assertion passe au rouge. On énumère donc TOUTES les routes, et les
routes ouvertes sont **épinglées nommément** ci-dessous. Une route ouverte non
épinglée est une régression, pas une donnée d'entrée.

⚠️ **La polarité de ce projet aggrave l'enjeu** : la protection est posée route
par route (`@UseGuards` par contrôleur), le seul garde global étant le
`ThrottlerGuard`. **La route qu'on oublie est donc OUVERTE**, et l'oubli ne se
voit ni à la compilation, ni à l'exécution, ni dans les journaux.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/frontiere_http.py --self-test   # d'abord, bloquant
    python3 scripts/lib/frontiere_http.py --list        # les routes vues
    python3 scripts/lib/frontiere_http.py               # le banc

Identifiants attendus dans l'environnement (aucune valeur par défaut : un banc
qui se rabattrait sur un compte imaginaire accuserait la mauvaise chose) :

    API_URL             défaut http://localhost:3000
    ADMIN_EMAIL / ADMIN_PASSWORD
    AGENT_EMAIL / AGENT_PASSWORD
    COMMERCANT_TEL / COMMERCANT_PIN
    PACE_SECONDS        défaut 1.1 — voir le plafond global de 60 req/min/IP
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

API_URL = os.environ.get("API_URL", "http://localhost:3000")
SRC_DIR = os.environ.get("SRC_DIR", "apps/backend/src")
PACE = float(os.environ.get("PACE_SECONDS", "1.1"))

ROLES_CONNUS = ("commercant", "agent", "admin")

# Les 14 routes ouvertes, épinglées une par une AVEC leur justification.
#
# ⚠️ Ne jamais y ajouter une entrée pour faire passer le banc : une route
# ouverte est la seule surface qu'un inconnu peut marteler.
ROUTES_OUVERTES = {
    ("GET", "/promo"): "consultation client — le client est anonyme par conception",
    ("GET", "/promo/:id"): "idem",
    ("GET", "/promo/map"): "idem — borné par MAP_THROTTLE (180/min)",
    ("GET", "/promo/config"): "repères géographiques (point par défaut, rayon par "
                              "défaut, rayon maximum) — l'app en a besoin AVANT de "
                              "pouvoir demander quoi que ce soit, donc avant tout "
                              "compte ; ne renvoie que quatre nombres de "
                              "configuration, aucune donnée métier ni personnelle",
    # ⚠️ `GET /commune` dépinglée le 2026-08-13, dans le MÊME commit que la
    # suppression de la route. C'est obligatoire dans ce sens-là : une entrée
    # épinglée devenue introuvable ne fait qu'**avertir** ici, alors que
    # l'inverse — une route ouverte non épinglée — sort en échec. Rien ne
    # rattrape donc un dépinglage oublié, et c'est très exactement ce qui est
    # arrivé à `/promo/config` le 2026-08-12.
    ("GET", "/highlight"): "bandeau Top promos de l'accueil",
    ("GET", "/commercant/:id/public"): "fiche commerçant publique",
    ("GET", "/p/:id"): "redirection de partage vers le store",
    ("GET", "/.well-known/assetlinks.json"): "vérification App Links Android",
    ("GET", "/.well-known/apple-app-site-association"): "vérification Universal Links iOS",
    ("POST", "/commercant/login"): "authentification — AUTH_THROTTLE",
    ("POST", "/agent/login"): "authentification — AUTH_THROTTLE",
    ("POST", "/admin/login"): "authentification — AUTH_THROTTLE",
    ("POST", "/commercant/register"): "inscription — STRICT_THROTTLE",
    ("POST", "/report"): "signalement client anonyme — STRICT_THROTTLE, borné par IP "
                         "parce que le X-Device-Id est déclaratif",
}

# Codes attendus, lus dans apps/backend/src/common/errors/error-code.enum.ts.
CODE_SANS_JETON = {"AUTH_TOKEN_MISSING"}
CODE_MAUVAIS_ROLE = {"AUTH_FORBIDDEN_ROLE"}
CODE_REVOQUE = {"AUTH_TOKEN_REVOKED"}

# ⚠️ Routes host-scopées : elles répondent 404 sur localhost par conception
# (contrôleur `@Controller({ host: 'promo.echango.com' })`). Les sonder sans
# en-tête Host conclurait à tort — elles sont ouvertes ET épinglées ci-dessus,
# donc jamais sondées ici. Nommé pour que l'exclusion ne passe pas pour un oubli.
HOST_SCOPEES = {"/p/:id", "/.well-known/assetlinks.json",
                "/.well-known/apple-app-site-association"}

# ─────────────────────────────────────────────────────────────────────────────
# Énumération des routes depuis la source
# ─────────────────────────────────────────────────────────────────────────────

_CONTROLLER = re.compile(r"^\s*@Controller\(\s*(?:'([^']*)'|\"([^\"]*)\")?", re.M)
_METHODE = re.compile(r"^\s*@(Get|Post|Put|Patch|Delete)\(\s*(?:'([^']*)'|\"([^\"]*)\")?\s*\)")
_ROLES = re.compile(r"@Roles\(([^)]*)\)")
_GARDE = re.compile(r"@UseGuards\(")
_CLASSE = re.compile(r"^\s*(?:export\s+)?(?:abstract\s+)?class\s")
_BLOC = re.compile(r"/\*[\s\S]*?\*/")
_LIGNE = re.compile(r"//[^\n]*")


def _decorateur_ou_vide(ligne):
    """Une ligne qui n'INTERROMPT pas un bloc de décorateurs.

    ⚠️ Les lignes vides comptent, et c'est le cœur du correctif du 2026-08-05.
    Les commentaires sont retirés plus haut par substitution — un bloc `/** … */`
    de six lignes laisse donc **six lignes vides** derrière lui. La remontée
    s'arrêtait là, si bien qu'un commentaire glissé entre `@UseGuards` et
    `@Patch` faisait lire une route parfaitement protégée comme OUVERTE.
    `PATCH /admin/agent/:id/communes` en a fait les frais.

    Le sens de l'erreur comptait peu ici : ce banc est le SEUL à pouvoir
    affirmer qu'aucun garde ne manque (règle #33). Qu'il accuse à tort une
    route protégée, et on prend l'habitude de discuter ses verdicts — ce qui
    est la façon la plus sûre de ne pas voir le jour où il a raison.

    ⚠️ Sans danger pour l'autre sens : entre deux routes il y a toujours au
    moins la signature de la précédente ou son `}` fermant, qui ne sont ni
    vides ni des décorateurs. Un bloc ne peut donc pas déborder sur son voisin.
    """
    s = ligne.strip()
    return s == "" or s.startswith("@")


def routes_du_source(texte):
    """Rend [(methode, chemin, roles:set, garde:bool)] pour un contrôleur.

    ⚠️ Les décorateurs d'une méthode forment un bloc CONTIGU **autour** de sa
    déclaration : `@Roles` peut être avant ou après `@Get`, l'ordre est libre en
    NestJS. Ne regarder que ce qui précède attribue à chaque route les rôles de
    la précédente — défaut constaté, d'où la collecte des deux côtés.

    ⚠️ Et l'en-tête de classe ne commence pas au `@Controller` : l'ordre habituel
    est `@UseGuards` → `@Roles` → `@Controller`. Partir du `@Controller` fait
    manquer le garde qui le précède.
    """
    texte = _LIGNE.sub("", _BLOC.sub("", texte))
    lignes = texte.split("\n")

    idx_classe = next((i for i, l in enumerate(lignes) if _CLASSE.match(l)), len(lignes))
    entete = "\n".join(l for l in lignes[:idx_classe] if l.lstrip().startswith("@"))

    cm = _CONTROLLER.search(entete)
    if not cm:
        return []
    prefixe = (cm.group(1) or cm.group(2) or "").strip("/")
    rc = _ROLES.search(entete)
    roles_classe = rc.group(1) if rc else None
    garde_classe = bool(_GARDE.search(entete))

    routes = []
    for i in range(idx_classe, len(lignes)):
        m = _METHODE.match(lignes[i])
        if not m:
            continue
        j = i
        while j > idx_classe and _decorateur_ou_vide(lignes[j - 1]):
            j -= 1
        k = i
        while k + 1 < len(lignes) and _decorateur_ou_vide(lignes[k + 1]):
            k += 1
        bloc = "\n".join(lignes[j:k + 1])

        rm = _ROLES.search(bloc)
        brut = (rm.group(1) if rm else roles_classe) or ""
        roles = {r for r in brut.replace("'", "").replace('"', "").replace(" ", "").split(",") if r}
        garde = garde_classe or bool(_GARDE.search(bloc))

        seg = (m.group(2) or m.group(3) or "").strip("/")
        chemin = "/" + "/".join(p for p in (prefixe, seg) if p)
        routes.append((m.group(1).upper(), chemin, roles, garde))
    return routes


def toutes_les_routes(racine):
    vues = []
    for dossier, _, fichiers in os.walk(racine):
        for f in sorted(fichiers):
            if f.endswith(".controller.ts"):
                with open(os.path.join(dossier, f), encoding="utf-8") as fh:
                    vues.extend(routes_du_source(fh.read()))
    return vues


def url_sondable(chemin):
    """Remplace les paramètres par un identifiant inexistant mais BIEN FORMÉ.

    ⚠️ Mal formé, on mesurerait la validation du format et non le refus d'accès
    — et un 400 passerait pour un refus alors qu'il n'en est pas un.
    """
    return re.sub(r":([A-Za-z_]\w*)", "00000000-0000-4000-8000-000000000000", chemin)


# ─────────────────────────────────────────────────────────────────────────────
# Appels
# ─────────────────────────────────────────────────────────────────────────────

def appeler(methode, chemin, jeton=None, corps=None):
    """Rend (statut, code_metier). Ne lève jamais sur une réponse d'erreur."""
    donnees = json.dumps(corps).encode() if corps is not None else (
        b"{}" if methode in ("POST", "PUT", "PATCH") else None)
    req = urllib.request.Request(API_URL + chemin, data=donnees, method=methode)
    req.add_header("Content-Type", "application/json")
    if jeton:
        req.add_header("Authorization", "Bearer " + jeton)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, json.loads(r.read() or b"{}").get("code") if r.headers.get(
                "content-type", "").startswith("application/json") else (r.status, None)
    except urllib.error.HTTPError as e:
        brut = e.read()
        try:
            return e.code, json.loads(brut).get("code")
        except Exception:
            return e.code, None
    except Exception as e:
        # ⚠️ Pas de repli sur « refusé » : une panne réseau n'est pas un refus.
        return None, "RESEAU: %s" % e


def _exiger(nom):
    v = os.environ.get(nom)
    if not v:
        print("❌ %s absent de l'environnement." % nom)
        print("   Aucune valeur par défaut ici : un banc qui se rabattrait sur un")
        print("   compte imaginaire échouerait en accusant la frontière.")
        sys.exit(2)
    return v


def jetons():
    """Les trois jetons valides + un jeton révoqué.

    ⚠️ **La révocation d'abord, la connexion ensuite.** `revoke-token`
    incrémente le `tokenVersion` : le jeton d'avant devient l'échantillon
    révoqué, et une nouvelle connexion rend un jeton valide. L'ordre inverse
    invaliderait le jeton qu'on vient d'obtenir.

    ⚠️ Chaque connexion consomme du AUTH_THROTTLE (50/min/IP depuis le
    2026-08-13, 5 auparavant) — la pause reste, elle ne coûte rien et le seau
    est partagé avec tout ce qui tourne sur la même IP.
    """
    def login(chemin, corps, quoi):
        s, _ = None, None
        st, code = appeler("POST", chemin, corps=corps)
        if st != 200 and st != 201:
            print("❌ connexion %s refusée (HTTP %s, code %s)" % (quoi, st, code))
            print("   Vérifier les identifiants, ou attendre si c'est le plafond (429).")
            sys.exit(2)
        # Relire le corps : `appeler` ne rend que le code d'erreur.
        req = urllib.request.Request(API_URL + chemin,
                                     data=json.dumps(corps).encode(), method="POST")
        req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=20) as r:
            reponse = json.loads(r.read())
        # ⚠️ Le champ s'appelle `accessToken`. Une première version lisait
        # `token` : la connexion réussissait, le jeton ressortait vide, et le
        # banc accusait les identifiants. Un champ absent n'est pas un refus —
        # d'où le nom du champ dans le message, pour que l'erreur soit lisible
        # le jour où le contrat change.
        jeton = reponse.get("accessToken")
        if not jeton:
            print("❌ connexion %s : pas de champ `accessToken` dans la réponse." % quoi)
            print("   Champs reçus : %s" % sorted(reponse.keys()))
            sys.exit(2)
        time.sleep(PACE)
        return jeton

    admin = {"email": _exiger("ADMIN_EMAIL"), "password": _exiger("ADMIN_PASSWORD")}
    agent = {"email": _exiger("AGENT_EMAIL"), "password": _exiger("AGENT_PASSWORD")}
    commercant = {"telephone": _exiger("COMMERCANT_TEL"), "pin": _exiger("COMMERCANT_PIN")}

    a_revoquer = login("/admin/login", admin, "admin (à révoquer)")
    st, _ = appeler("POST", "/admin/me/revoke-token", jeton=a_revoquer)
    if st not in (200, 201, 204):
        print("❌ révocation impossible (HTTP %s) — le banc ne peut pas éprouver" % st)
        print("   la troisième sonde. L'absence de verdict n'est pas un verdict.")
        sys.exit(2)
    time.sleep(PACE)

    return {
        "admin": login("/admin/login", admin, "admin"),
        "agent": login("/agent/login", agent, "agent"),
        "commercant": login("/commercant/login", commercant, "commerçant"),
        "revoque": a_revoquer,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Auto-test
# ─────────────────────────────────────────────────────────────────────────────

_CAS = [
    ("@UseGuards(A)\n@Roles('admin')\n@Controller('admin')\nexport class C {\n"
     "@Get('x')\na() {}\n}",
     [("GET", "/admin/x", {"admin"}, True)]),
    # @Roles APRÈS @Get — l'ordre est libre, et c'est le défaut qui a coûté.
    ("@UseGuards(A)\n@Controller('n')\nexport class C {\n"
     "@Get('a')\n@Roles('commercant')\nx() {}\n@Get('b')\n@Roles('admin')\ny() {}\n}",
     [("GET", "/n/a", {"commercant"}, True), ("GET", "/n/b", {"admin"}, True)]),
    ("@Controller('promo')\nexport class C {\n@Get()\nlist() {}\n}",
     [("GET", "/promo", set(), False)]),
    ("@Controller()\nexport class C {\n@Get('health')\nh() {}\n}",
     [("GET", "/health", set(), False)]),
    ("@UseGuards(A)\n@Controller('m')\nexport class C {\n"
     "@Roles('agent','admin')\n@Post('z')\nz() {}\n}",
     [("POST", "/m/z", {"agent", "admin"}, True)]),
    # ⚠️ Le cas du 2026-08-05 : un commentaire ENTRE les gardes et le verbe.
    # Retiré par substitution, il laisse des lignes vides — et la remontée
    # s'arrêtait dessus, faisant lire `PATCH /admin/agent/:id/communes` comme
    # OUVERTE alors qu'elle porte @UseGuards + @Roles.
    ("@Controller('adm')\nexport class C {\n"
     "@UseGuards(A)\n@Roles('admin')\n/**\n * doc\n */\n@Patch('a/:id/b')\nf() {}\n}",
     [("PATCH", "/adm/a/:id/b", {"admin"}, True)]),
    # Même piège de l'autre côté : commentaire entre le verbe et @Roles.
    ("@Controller('adm')\nexport class C {\n"
     "@UseGuards(A)\n@Get('c')\n// note\n@Roles('agent')\ng() {}\n}",
     [("GET", "/adm/c", {"agent"}, True)]),
    # ⚠️ Doit REFUSER de déborder : une route sans garde, séparée de la
    # précédente par une ligne vide, ne doit pas hériter du @UseGuards voisin.
    ("@Controller('adm')\nexport class C {\n"
     "@UseGuards(A)\n@Get('protegee')\np() {}\n\n@Get('ouverte')\no() {}\n}",
     [("GET", "/adm/protegee", set(), True), ("GET", "/adm/ouverte", set(), False)]),
]

_CAS_REFUS = [
    "// @Controller('promo')\n// @Get()\n",
    "/* @Controller('x')\n@Get()\n*/",
    "@Injectable()\nexport class S {\n@Get()\nr() {}\n}",
    "export class Sans {}",
    "@Controller('promo')\nexport class C {}",
    "const s = \"@Controller('faux')\";",
]


def self_test():
    echecs, passes = [], 0
    for source, attendu in _CAS:
        obtenu = routes_du_source(source)
        if obtenu != attendu:
            echecs.append("attendu %s, obtenu %s" % (attendu, obtenu))
        else:
            passes += 1
    for source in _CAS_REFUS:
        obtenu = routes_du_source(source)
        if obtenu:
            echecs.append("aurait dû ne rien rendre, a rendu %s" % (obtenu,))
        else:
            passes += 1

    # L'URL sondable doit rester bien formée, sinon on mesure la validation.
    for chemin, attendu in [
        ("/promo/:id", "/promo/00000000-0000-4000-8000-000000000000"),
        ("/a/:x/b/:y", "/a/00000000-0000-4000-8000-000000000000/b/"
                       "00000000-0000-4000-8000-000000000000"),
        ("/sans-parametre", "/sans-parametre"),
    ]:
        if url_sondable(chemin) == attendu:
            passes += 1
        else:
            echecs.append("url_sondable(%s) = %s" % (chemin, url_sondable(chemin)))

    total = len(_CAS) + len(_CAS_REFUS) + 3
    print("auto-test : %d cas, dont %d refus" % (total, len(_CAS_REFUS)))
    for e in echecs:
        print("  ❌ " + e)
    print("  %d/%d" % (passes, total))
    return not echecs


# ─────────────────────────────────────────────────────────────────────────────

def main():
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)

    routes = sorted(set((m, c, tuple(sorted(r)), g) for m, c, r, g in toutes_les_routes(SRC_DIR)))
    if not routes:
        print("❌ aucune route trouvée sous %s." % SRC_DIR)
        print("   L'absence de verdict n'est pas un verdict.")
        sys.exit(2)

    ouvertes = {(m, c) for m, c, _, g in routes if not g}
    epinglees = set(ROUTES_OUVERTES)

    if "--list" in sys.argv:
        for m, c, r, g in routes:
            print("%-6s %-48s %s" % (m, c, "OUVERTE" if not g else ",".join(r) or "(sans rôle)"))
        print("\n%d routes — %d ouvertes, %d protégées" %
              (len(routes), len(ouvertes), len(routes) - len(ouvertes)))
        return

    surprises = ouvertes - epinglees
    if surprises:
        print("❌ %d route(s) OUVERTE(s) non épinglée(s)." % len(surprises))
        print("   En polarité « garde par route », une route sans @UseGuards est")
        print("   ouverte. Chacune doit être une décision écrite, ou porter son garde :")
        for m, c in sorted(surprises):
            print("     %s %s" % (m, c))
        sys.exit(1)

    disparues = epinglees - ouvertes
    if disparues:
        print("⚠️  épinglées mais désormais protégées (à retirer de la liste) :")
        for m, c in sorted(disparues):
            print("     %s %s" % (m, c))
        print()

    protegees = [(m, c, r) for m, c, r, g in routes if g]

    # ⚠️ `--only=<motif>` ne filtre QUE la phase de sondage, jamais la
    # vérification d'épinglage ci-dessus : celle-ci doit toujours porter sur
    # l'ensemble, sinon on retrouverait le défaut qu'elle existe pour éviter
    # (un contrôle dont la cible rétrécit avec ce qu'il contrôle).
    only = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--only=")), None)
    if only:
        # ⚠️ Le dénominateur se MESURE. Il était écrit « sur 48 » en dur : un
        # nombre dans une phrase ne peut pas échouer (règle 33), et celui-ci
        # devient faux au premier ajout ou retrait de route protégée — c'est-à-
        # dire exactement quand on regarde cette sortie.
        total_protegees = len(protegees)
        protegees = [t for t in protegees if only in t[1]]
        if not protegees:
            print("❌ --only=%s ne correspond à aucune route protégée." % only)
            sys.exit(2)
        print("⚠️  filtre --only=%s : %d route(s) sondée(s) sur %d.\n"
              % (only, len(protegees), total_protegees))
    sondes = sum(3 if set(r) != set(ROLES_CONNUS) else 2 for _, _, r in protegees)
    print("── banc de refus ──")
    print("%d routes protégées (sur %d, %d ouvertes épinglées, %d host-scopées)"
          % (len(protegees), len(routes), len(epinglees), len(HOST_SCOPEES)))
    print("%d sondes, cadence %.1fs → environ %d min\n" % (sondes, PACE, sondes * PACE / 60 + 1))

    j = jetons()
    echecs, throttle, na = [], 0, 0

    for methode, chemin, roles in protegees:
        url = url_sondable(chemin)

        def sonder(jeton, statuts_ok, codes_ok, libelle):
            nonlocal throttle
            st, code = appeler(methode, url, jeton)
            time.sleep(PACE)
            if st == 429:
                throttle += 1
                return "%s %s — 429 : plafond atteint, ce n'est pas un verdict" % (methode, chemin)
            if st is None:
                return "%s %s — %s : %s" % (methode, chemin, libelle, code)
            if st not in statuts_ok:
                return "%s %s — %s : statut %s (attendu %s)" % (
                    methode, chemin, libelle, st, sorted(statuts_ok))
            if code not in codes_ok:
                return "%s %s — %s : code %r (attendu %s)" % (
                    methode, chemin, libelle, code, sorted(codes_ok))
            return None

        for r in (sonder(None, {401}, CODE_SANS_JETON, "sans jeton"),
                  sonder(j["revoque"], {401}, CODE_REVOQUE, "jeton révoqué")):
            if r:
                echecs.append(r)

        # ⚠️ Sonde « mauvais rôle » : impossible quand la route accepte les trois
        # rôles (les notifications). On ne l'invente pas — on la compte comme
        # non applicable, ce qui se lit dans le total.
        intrus = [x for x in ROLES_CONNUS if x not in roles]
        if not intrus:
            na += 1
        else:
            r = sonder(j[intrus[0]], {401, 403}, CODE_MAUVAIS_ROLE,
                       "rôle %s sur une route %s" % (intrus[0], "/".join(roles)))
            if r:
                echecs.append(r)

    print()
    for e in echecs:
        print("  ❌ " + e)
    if throttle:
        print("\n⚠️  %d sonde(s) ont reçu 429 — augmenter PACE_SECONDS et rejouer." % throttle)
    if na:
        print("⚠️  %d route(s) sans sonde « mauvais rôle » : elles acceptent les 3 rôles." % na)
    print("\n%d routes protégées, %d sondes, %d échec(s)" % (len(protegees), sondes, len(echecs)))
    sys.exit(1 if (echecs or throttle) else 0)


if __name__ == "__main__":
    main()
