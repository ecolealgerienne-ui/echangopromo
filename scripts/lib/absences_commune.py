#!/usr/bin/env python3
"""Banc des absences — ce qui a été retiré l'est vraiment, et le reste.

── Pourquoi un banc pour prouver que rien n'est là ─────────────────────────

Le 2026-08-13, le découpage administratif a été supprimé : trois routes, deux
tables et une colonne ont disparu. **Rien ne le constate.**

`frontiere_http.py` **dérive ses routes de la source** : une route supprimée ne
lui manque pas, elle sort simplement de sa liste. C'est le bon comportement pour
ce qu'il fait — il vérifie que ce qui existe est gardé — mais ça veut dire que
personne ne remarquerait leur retour. Et côté base, la migration `DropCommune` a
tourné **une fois**, sans contrôle rejouable : rien ne dit qu'elle a été
appliquée sur un environnement donné.

⚠️ **Une absence est le seul état qu'un test ne constate jamais par accident.**
C'est aussi le seul qui se répare tout seul en silence : recréer une route
supprimée ne casse rien, restaurer une sauvegarde antérieure au `DROP` non plus.

── ⚠️ Ce qui rend ce banc difficile, et comment il s'en sort ───────────────

**Tout est absent quand on regarde au mauvais endroit.** Un banc d'absence est
vert si l'API est éteinte, si l'URL est fausse, si la base n'est pas la bonne.
Il ne prouve rien tant qu'il n'a pas montré qu'il sait **voir une présence**.
D'où un témoin positif dans chacune des deux moitiés, et ils sont obligatoires :

- côté HTTP, `GET /promo/config` doit répondre `200` et `POST /admin/login`
  doit exister ;
- côté base, la table `commercant` doit être là et porter ses colonnes.

Sans ces témoins, « la table `commune` est absente » et « je n'ai pas réussi à
interroger la base » rendraient le même verdict.

── La distinction qui porte tout le banc HTTP ─────────────────────────────

Les gardes de ce produit sont posés **route par route**, et il n'existe aucun
garde global d'authentification (règle 33). Une requête sans jeton distingue
donc parfaitement les deux cas :

    route SUPPRIMÉE    → 404
    route EXISTANTE    → 401 AUTH_TOKEN_MISSING   (ou 200 si elle est ouverte)

Aucun identifiant n'est nécessaire, et le banc ne consomme aucun seau de
connexion. C'est aussi ce qui le rend sûr : **il n'écrit rien, il ne peut rien
écrire** — les trois routes sondées n'existent plus, et si l'une revenait, la
sonde s'arrêterait au refus d'authentification sans jamais atteindre son corps.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/absences_commune.py --self-test
    ./scripts/test-absences-commune.sh
"""

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
CONTENEUR_PG = os.environ.get("PG_CONTAINER", "echangopromo-postgres-1")
PG_USER = os.environ.get("PG_USER", "echango")
PG_DB = os.environ.get("PG_DB", "echango_promo")

# Les trois routes retirées le 2026-08-13, avec ce qu'elles portaient. Épinglées
# nommément : une liste dérivée du code ne peut par construction pas contenir ce
# qui n'y est plus.
ROUTES_RETIREES = [
    ("GET", "/commune",
     "référentiel des communes, chargé en entier par CommuneCascadeField"),
    ("PATCH", "/admin/agent/00000000-0000-0000-0000-000000000000/communes",
     "assignation du territoire d'un agent"),
    ("POST", "/admin/agent/transfer-communes",
     "transfert de secteur au départ d'un agent"),
]

# Ce qui doit rester là — le témoin. Sans lui, un banc d'absence est vert sur
# une API éteinte.
ROUTES_TEMOINS = [
    ("GET", "/promo/config", (200,), "lecture publique de la configuration"),
    ("POST", "/admin/login", (401, 400), "route protégée, donc bien présente"),
]

OBJETS_DETRUITS = [
    ("table", "commune", "le référentiel"),
    ("table", "agent_communes", "la table de liaison agent ↔ commune"),
    ("colonne", "commercant.communeId", "le rattachement du commerçant"),
]


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_route_absente(statut, code):
    """Une route retirée rend 404. Tout le reste veut dire qu'elle existe.

    ⚠️ **`401` est un ÉCHEC, pas un demi-succès.** Il prouve qu'un garde s'est
    exécuté, donc qu'une route est là pour le porter. C'est très exactement la
    forme qu'aurait un retour de la route : d'abord protégée, donc « ça a l'air
    normal ».
    """
    if statut is None:
        return "non_concluant", "pas de réponse : %s" % code
    if statut == 429:
        return "non_concluant", "429 — plafond de requêtes, pas un verdict"
    if statut == 404:
        return "ok", "404"
    if statut in (401, 403):
        return ("echec",
                "HTTP %s %s — un garde a répondu, donc la route EXISTE. Elle "
                "avait été retirée le 2026-08-13" % (statut, code or ""))
    if statut in (200, 201):
        return ("echec",
                "HTTP %s — la route répond, elle est de retour" % statut)
    return ("echec",
            "HTTP %s %s — ni 404 ni refus connu : impossible de conclure à "
            "l'absence" % (statut, code or ""))


def verdict_temoin_present(statut, attendus):
    """⚠️ Sans ce témoin, « tout est absent » serait vrai d'une API éteinte."""
    if statut is None:
        return ("echec",
                "aucune réponse — l'API ne répond pas, et un banc d'absence "
                "serait vert pour la mauvaise raison")
    if statut == 404:
        return ("echec",
                "404 sur une route qui doit exister — la sonde vise à côté "
                "(mauvaise URL, mauvais port), donc les absences ne prouvent "
                "rien")
    if statut in attendus:
        return "ok", "HTTP %s" % statut
    return "non_concluant", "HTTP %s, attendu %s" % (statut, attendus)


def verdict_objet_detruit(existe, quoi):
    """`existe` vaut True/False, ou None si la base n'a pas répondu."""
    if existe is None:
        return "non_concluant", "%s : base non interrogeable" % quoi
    if existe:
        return ("echec",
                "%s est TOUJOURS en base — la migration DropCommune n'a pas "
                "été appliquée ici, ou une sauvegarde antérieure a été "
                "restaurée par-dessus" % quoi)
    return "ok", "%s absent" % quoi


def verdict_temoin_base(existe):
    """La table `commercant` doit être là — sinon on interroge la mauvaise base."""
    if existe is None:
        return ("echec",
                "base non interrogeable — les trois constats d'absence "
                "ci-dessous ne vaudraient rien")
    if not existe:
        return ("echec",
                "la table `commercant` est absente : ce n'est pas la bonne "
                "base, et tout y paraîtrait supprimé")
    return "ok", "table `commercant` présente"


# ─────────────────────────────────────────────────────────────────────────────

def appeler(methode, chemin):
    """Sans jeton — c'est le 404 vs 401 qui tranche, pas une autorisation."""
    req = urllib.request.Request(API_URL + chemin, method=methode)
    req.add_header("Content-Type", "application/json")
    req.add_header("X-Device-Id", "banc-absences-0001")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, None
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read()).get("code")
        except Exception:
            return e.code, None
    except Exception as e:
        return None, "RESEAU: %s" % e


def interroger_base(sql):
    """Une requête, via le conteneur — `psql` n'est pas installé sur l'hôte.

    Rend `None` en cas d'échec, jamais une valeur de repli : « je n'ai pas pu
    demander » et « la réponse est non » ne doivent pas se confondre (règle 29).
    """
    try:
        sortie = subprocess.run(
            ["docker", "exec", CONTENEUR_PG, "psql", "-U", PG_USER,
             "-d", PG_DB, "-tAc", sql],
            capture_output=True, timeout=30, text=True)
    except Exception:
        return None
    if sortie.returncode != 0:
        return None
    return sortie.stdout.strip()


def objet_existe(genre, nom):
    if genre == "table":
        r = interroger_base("SELECT to_regclass('public.%s') IS NOT NULL" % nom)
    else:
        table, colonne = nom.split(".")
        r = interroger_base(
            "SELECT count(*) > 0 FROM information_schema.columns "
            "WHERE table_name = '%s' AND column_name = '%s'" % (table, colonne))
    if r not in ("t", "f"):
        return None
    return r == "t"


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
    _v("404 = absente", verdict_route_absente(404, None)[0], "ok")
    _v("témoin ouvert présent", verdict_temoin_present(200, (200,))[0], "ok")
    _v("témoin protégé présent", verdict_temoin_present(401, (401, 400))[0], "ok")
    _v("objet détruit", verdict_objet_detruit(False, "commune")[0], "ok")
    _v("témoin base", verdict_temoin_base(True)[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le cœur du banc : un garde qui répond prouve qu'une route est là.
    _v("401 sur une route retirée",
       verdict_route_absente(401, "AUTH_TOKEN_MISSING")[0], "echec")
    _v("403 sur une route retirée",
       verdict_route_absente(403, "AUTH_FORBIDDEN_ROLE")[0], "echec")
    _v("200 sur une route retirée", verdict_route_absente(200, None)[0], "echec")
    _v("statut inattendu", verdict_route_absente(500, "INTERNAL_ERROR")[0],
       "echec")
    # ⚠️ Le faux vert structurel : l'API est éteinte, donc tout est « absent ».
    _v("témoin muet", verdict_temoin_present(None, (200,))[0], "echec")
    _v("témoin en 404", verdict_temoin_present(404, (200,))[0], "echec")
    # ⚠️ Le même, côté base.
    _v("base injoignable", verdict_temoin_base(None)[0], "echec")
    _v("mauvaise base", verdict_temoin_base(False)[0], "echec")
    _v("objet toujours là", verdict_objet_detruit(True, "commune")[0], "echec")
    # ⚠️ Ne pas avoir pu demander n'est pas une réponse.
    _v("base muette → non concluant",
       verdict_objet_detruit(None, "commune")[0], "non_concluant")
    _v("429 → non concluant", verdict_route_absente(429, None)[0],
       "non_concluant")

    refus = 11
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


# ─────────────────────────────────────────────────────────────────────────────

def main():
    print("═" * 64)
    print("  Absences — ce qui a été retiré le 2026-08-13 l'est vraiment")
    print("═" * 64)
    print("  ⚠️ banc en LECTURE SEULE, sans jeton : il ne peut rien écrire")

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-46s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    # ── 0. Les témoins — sans eux, la suite est vraie de n'importe quoi ─────
    print("\n── 0. témoins : l'API répond et c'est la bonne ──")
    for methode, chemin, attendus, quoi in ROUTES_TEMOINS:
        st, _ = appeler(methode, chemin)
        noter("%s %s" % (methode, chemin), *verdict_temoin_present(st, attendus))

    # ── 1. Les trois routes retirées ────────────────────────────────────────
    print("\n── 1. les trois routes du découpage administratif ──")
    for methode, chemin, quoi in ROUTES_RETIREES:
        st, code = appeler(methode, chemin)
        libelle = "%s %s" % (methode, chemin.split("?")[0])
        if len(libelle) > 46:
            libelle = libelle[:43] + "…"
        noter(libelle, *verdict_route_absente(st, code))

    # ── 2. Le témoin de base ────────────────────────────────────────────────
    print("\n── 2. témoin : c'est bien la base du produit ──")
    noter("table `commercant`", *verdict_temoin_base(objet_existe("table",
                                                                 "commercant")))

    # ── 3. Ce que la migration DropCommune a détruit ────────────────────────
    print("\n── 3. les deux tables et la colonne ──")
    for genre, nom, quoi in OBJETS_DETRUITS:
        noter("%s %s" % (genre, nom),
              *verdict_objet_detruit(objet_existe(genre, nom), nom))

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
