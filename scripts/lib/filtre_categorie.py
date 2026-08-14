#!/usr/bin/env python3
"""Banc du filtre par catégorie — ce que la liste sert quand on la restreint.

── L'observation qui a fait écrire ce banc ─────────────────────────────────

Le 2026-08-13, sur Djelfa, l'app affichait :

    filtre « Autre »        →  4 promos
    filtre « Alimentation » → 22 promos
    filtre « Toutes »       → 24 promos

**22 + 4 = 26, et « Toutes » en annonce 24.** Deux promos manquent d'un côté ou
sont comptées deux fois de l'autre, et rien dans le produit ne le signale : les
trois nombres sont plausibles pris isolément. C'est exactement le défaut qui ne
lève jamais — on ne le voit qu'en additionnant, et personne n'additionne.

⚠️ **Ce banc mesure le SERVEUR, et c'est délibéré.** Les chiffres ci-dessus
viennent des écrans, où la carte et la liste ne comptent pas la même chose (la
carte se borne au cadre visible, la liste au rayon). Tant qu'on n'a pas établi
que le serveur somme juste, on ne peut pas savoir laquelle des deux couches
ment — et on ira corriger la mauvaise. Si ce banc est vert, l'écart est dans
l'app ; s'il est rouge, il est dans la requête SQL, et aucune retouche
d'affichage ne le réparera.

── Ce qu'un total juste ne prouve pas ─────────────────────────────────────

Qu'un filtre rende le bon NOMBRE ne dit pas qu'il rend les bonnes LIGNES : une
requête qui ignore la catégorie et tronque à la bonne longueur passerait. D'où
la seconde sonde, qui lit les items servis et vérifie que **chacun** porte la
catégorie demandée.

── Et une valeur inconnue doit être refusée ───────────────────────────────

`?categorie=nimportequoi` doit rendre **400**, jamais la liste entière. Un
filtre qui retombe sur « tout » quand il ne comprend pas est le cas d'école de
la règle 29 : l'utilisateur croit avoir restreint, il voit plus de résultats
qu'il n'en a demandé, et aucune erreur ne le détrompe.

── Usage ──────────────────────────────────────────────────────────────────

    python3 scripts/lib/filtre_categorie.py --self-test
    ./scripts/test-filtre-categorie.sh
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")

# Recopiée de `common/enums/categorie.enum.ts`. ⚠️ Cette duplication est une
# dette assumée, pas un oubli : la tenir à jour est le prix d'un banc qui
# n'exécute pas le code qu'il éprouve. Elle est **tenue par une sonde** — si le
# serveur connaît une catégorie absente d'ici, `verdict_enum_complet` le dit
# (règle 30 : un invariant s'applique, il ne se documente pas).
CATEGORIES = [
    "alimentation",
    "restauration",
    "vetements_textile",
    "electromenager",
    "beaute_hygiene",
    "maison_ameublement",
    "autre",
]


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_somme(total, par_categorie):
    """⚠️ **La sonde qui a motivé ce banc.**

    Les catégories forment une partition : chaque promo en porte une et une
    seule (colonne non nulle, enum fermé). La somme des filtres doit donc valoir
    exactement le total non filtré. Tout écart est une promo perdue par le
    filtre ou comptée deux fois.
    """
    if total is None or any(v is None for v in par_categorie.values()):
        return "non_concluant", "un des totaux est illisible"
    somme = sum(par_categorie.values())
    if somme != total:
        detail = ", ".join(
            "%s=%d" % (c, n) for c, n in par_categorie.items() if n)
        return ("echec",
                "la somme des catégories vaut %d, « toutes » en annonce %d "
                "(écart %+d) — %s. Une promo est soit perdue par le filtre, "
                "soit comptée deux fois"
                % (somme, total, somme - total, detail or "toutes vides"))
    return "ok", "%d = %d, la partition est exacte" % (somme, total)


def verdict_purete(categorie, items):
    """Le filtre rend-il les bonnes lignes, ou seulement le bon nombre ?

    ⚠️ Une liste **vide** ne prouve rien : elle est pure par vacuité. On le dit
    au lieu de compter un contrôle réussi (règle 28).
    """
    if items is None:
        return "non_concluant", "réponse illisible"
    if not items:
        return "non_concluant", "aucune promo servie — rien à vérifier"
    intrus = sorted({
        i.get("categorie") for i in items if i.get("categorie") != categorie})
    if intrus:
        return ("echec",
                "le filtre « %s » sert aussi %s — il ne filtre pas, il "
                "tronque" % (categorie, ", ".join(map(str, intrus))))
    return "ok", "%d promo(s), toutes en « %s »" % (len(items), categorie)


def verdict_categorie_inconnue(statut):
    """Une valeur hors enum doit être **refusée**, jamais ignorée.

    ⚠️ Ignorer un filtre incompris sert PLUS de résultats que demandé, sans
    aucune erreur : l'utilisateur croit avoir restreint (règle 29).
    """
    if statut is None:
        return "non_concluant", "aucune réponse"
    if statut == 400:
        return "ok", "400 — la valeur inconnue est refusée"
    if statut == 200:
        return ("echec",
                "200 sur une catégorie inexistante : le filtre est ignoré en "
                "silence et la liste sert tout, alors que le client croit "
                "avoir restreint")
    return ("non_concluant",
            "statut %d — ni un refus de validation ni un service" % statut)


def verdict_enum_complet(categories_servies):
    """Le serveur connaît-il une catégorie que ce banc ignore ?

    Sans ça, une catégorie ajoutée au backend échapperait à la somme : le banc
    resterait vert en n'additionnant qu'une partie du parc.
    """
    if categories_servies is None:
        return "non_concluant", "liste des promos illisible"
    inconnues = sorted(categories_servies - set(CATEGORIES))
    if inconnues:
        return ("echec",
                "le serveur sert des catégories absentes de ce banc : %s — la "
                "somme ci-dessus en a donc ignoré une partie"
                % ", ".join(inconnues))
    return "ok", "aucune catégorie hors de la liste connue"


def verdict_couverture(par_categorie):
    """⚠️ Un filtre ne se prouve pas sur un décor à une seule catégorie.

    Si tout le parc est en « autre », filtrer sur « autre » rend le total et
    filtrer sur le reste rend zéro : la somme tombe juste **et** un filtre qui
    ne filtre pas passerait. Le banc le dit plutôt que de rassurer (règle 38 :
    établir que la mesure pouvait varier).
    """
    if not par_categorie or any(v is None for v in par_categorie.values()):
        return "non_concluant", "totaux illisibles"
    garnies = [c for c, n in par_categorie.items() if n]
    if len(garnies) < 2:
        return ("non_concluant",
                "une seule catégorie est garnie (%s) : un filtre inopérant "
                "rendrait exactement les mêmes chiffres — ce banc ne peut rien "
                "affirmer sur un décor aussi pauvre"
                % (garnies[0] if garnies else "aucune"))
    return "ok", "%d catégories garnies — le filtre a de quoi se tromper" % len(
        garnies)


# ─────────────────────────────────────────────────────────────────────────────

def appeler(chemin):
    req = urllib.request.Request(API_URL + chemin)
    req.add_header("X-Device-Id", "banc-filtre-0001")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read())
        except Exception:
            return e.code, {}
    except Exception:
        return None, {}


_ok = 0
_echecs = []


def _v(libelle, obtenu, attendu):
    global _ok
    if obtenu == attendu:
        _ok += 1
    else:
        _echecs.append("%s — attendu %r, obtenu %r" % (libelle, attendu, obtenu))


def self_test():
    plein = {"alimentation": 22, "autre": 4}

    # ── Doivent PASSER ───────────────────────────────────────────────────────
    _v("partition exacte", verdict_somme(26, plein)[0], "ok")
    _v("filtre pur",
       verdict_purete("autre", [{"categorie": "autre"}] * 3)[0], "ok")
    _v("valeur inconnue refusée", verdict_categorie_inconnue(400)[0], "ok")
    _v("enum couvert", verdict_enum_complet({"autre", "alimentation"})[0], "ok")
    _v("décor varié", verdict_couverture(plein)[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le cas exact observé sur Djelfa : 22 + 4 = 26, l'app annonçait 24.
    _v("somme fausse (cas Djelfa)", verdict_somme(24, plein)[0], "echec")
    _v("filtre qui laisse passer un intrus",
       verdict_purete("autre",
                      [{"categorie": "autre"}, {"categorie": "alimentation"}])[0],
       "echec")
    _v("valeur inconnue servie", verdict_categorie_inconnue(200)[0], "echec")
    _v("catégorie serveur inconnue du banc",
       verdict_enum_complet({"autre", "jardinage"})[0], "echec")

    # ── Doivent rester NON CONCLUANTS ────────────────────────────────────────
    # ⚠️ Une liste vide est pure par vacuité : elle ne prouve rien.
    _v("filtre sans résultat", verdict_purete("autre", [])[0], "non_concluant")
    # ⚠️ Un décor mono-catégorie rendrait les mêmes chiffres sans filtre.
    _v("une seule catégorie garnie",
       verdict_couverture({"autre": 40, "alimentation": 0})[0], "non_concluant")
    _v("total illisible", verdict_somme(None, plein)[0], "non_concluant")
    _v("catégorie illisible",
       verdict_somme(26, {"autre": None})[0], "non_concluant")
    _v("aucune réponse", verdict_categorie_inconnue(None)[0], "non_concluant")
    _v("statut inattendu", verdict_categorie_inconnue(500)[0], "non_concluant")
    _v("items illisibles", verdict_purete("autre", None)[0], "non_concluant")
    _v("enum illisible", verdict_enum_complet(None)[0], "non_concluant")

    refus = 12
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


# ─────────────────────────────────────────────────────────────────────────────

def main():
    print("═" * 68)
    print("  Filtre par catégorie — la somme des parts fait-elle le tout ?")
    print("═" * 68)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-38s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    # ⚠️ Aucune coordonnée sur AUCUNE des requêtes : le serveur applique alors
    # son point et son rayon, les mêmes pour toutes. Passer des coordonnées à
    # certaines et pas à d'autres comparerait deux populations différentes, et
    # l'écart accuserait le filtre pour une différence de périmètre.
    st, tout = appeler("/promo?limit=100")
    total = tout.get("total") if st == 200 else None
    items_tous = tout.get("items") if st == 200 else None

    print("\n── 1. le décor permet-il de juger un filtre ? ──")
    par_categorie = {}
    for c in CATEGORIES:
        s, d = appeler("/promo?limit=100&categorie=" + urllib.parse.quote(c))
        par_categorie[c] = d.get("total") if s == 200 else None
    noter("au moins deux catégories garnies", *verdict_couverture(par_categorie))

    print("\n── 2. le serveur connaît-il d'autres catégories ? ──")
    noter("enum du banc à jour",
          *verdict_enum_complet(
              {i.get("categorie") for i in items_tous} if items_tous else None))

    print("\n── 3. la somme des filtres vaut le total ──")
    noter("Σ catégories = « toutes »", *verdict_somme(total, par_categorie))

    print("\n── 4. chaque filtre sert bien SA catégorie ──")
    for c in CATEGORIES:
        if not par_categorie.get(c):
            continue
        s, d = appeler("/promo?limit=100&categorie=" + urllib.parse.quote(c))
        noter(c, *verdict_purete(c, d.get("items") if s == 200 else None))

    print("\n── 5. une catégorie inexistante est refusée ──")
    s, _ = appeler("/promo?limit=1&categorie=nimportequoi")
    noter("?categorie=nimportequoi", *verdict_categorie_inconnue(s))

    print("\n" + "═" * 68)
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
