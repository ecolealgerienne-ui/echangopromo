#!/usr/bin/env python3
"""Banc du tableau de bord — le surcompte, et le cloisonnement des projections.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

Le tableau de bord est le seul endroit du produit où l'on regarde des
**nombres** plutôt que des objets. C'est ce qui le rend dangereux : un chiffre
faux a toujours l'air juste, et rien dans l'interface ne permet de le
contredire.

Deux défauts réels y sont déjà nés :

1. **Le surcompte des promos actives** — cas fondateur de la **règle 8**. Le
   cycle de vie et la modération vivaient dans un seul enum, si bien que deux
   services répliquaient chacun leur idée de « qu'est-ce qui est visible » ; le
   tableau de bord comptait des promos qu'aucun client ne voyait.
2. **`countPendingModeration` rendait 6 pour 2 promos** — un `getCount()` sur
   une requête groupée comptait des LIGNES là où la file compte des entités.

D'où les deux sondes de cohérence : **un compteur doit égaler ce qu'il prétend
compter**, mesuré contre la liste elle-même et non contre une valeur écrite
dans le banc.

Et deux sondes de cloisonnement, sur une surface que `test-appartenance` ne
couvre pas : celui-ci éprouve les **actions** d'un agent hors de ses communes,
celui-là éprouve ses **projections**. Un agent qui ne peut rien faire ailleurs
mais qui *voit* tout n'est pas cloisonné.

── Ce qu'il n'éprouve PAS, et pourquoi ─────────────────────────────────────

Les valeurs absolues. Ce banc ne sait pas — et ne doit pas savoir — combien de
commerces existent : il vérifie des **relations** entre ce que le serveur dit
et ce qu'il montre. Une attente chiffrée devrait être mise à jour à chaque
passage d'un autre banc, et finirait par être ajustée jusqu'à ne plus rien
tester.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/admin_dashboard.py --self-test
    ./scripts/test-admin-dashboard.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.1"))
DEVICE_ID = "banc-dashboard-0001"


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_inclusion(compteur, reference, quoi):
    """Le compteur global doit CONTENIR ce que le client voit localement.

    ⚠️ **Cette sonde exigeait l'ÉGALITÉ, et elle a rendu rouge sur un produit
    correct** (2026-08-13 : tableau de bord 89, liste 51). Elle datait d'avant
    la bascule géographique, quand `GET /promo` servait tout le parc. Depuis, la
    liste est bornée au rayon par défaut autour du point du serveur, tandis que
    `countVisible()` compte le pays entier : les deux ne mesurent plus la même
    chose, et l'égalité n'était plus qu'un vestige.

    C'est la règle 38 dans sa forme la plus coûteuse — une contre-mesure sur une
    prémisse périmée accuse le produit, et elle est crue parce qu'un banc qui
    échoue est cru.

    **Ce qui reste vrai et vérifiable** : le local est un sous-ensemble du
    global. `liste ≤ compteur`, toujours. Un tableau de bord qui annoncerait
    moins de promos que le client n'en voit dans cinq kilomètres serait
    faux — et c'est ce que cette sonde attrape désormais.
    """
    if compteur is None or reference is None:
        return "non_concluant", "%s illisible — pas de verdict" % quoi
    if reference > compteur:
        return ("echec",
                "%s : le client voit %d promos dans le seul rayon par défaut, "
                "alors que le tableau de bord n'en annonce que %d pour TOUT le "
                "parc — le compteur global est faux"
                % (quoi, reference, compteur))
    if compteur == reference:
        return "ok", "%d = %d" % (compteur, reference)
    return ("ok",
            "%d au global, %d dans le rayon par défaut — le local est bien "
            "contenu dans le global" % (compteur, reference))


def verdict_coherence(compteur, reference, quoi):
    """Deux mesures GLOBALES du même fait doivent être égales.

    ⚠️ **À ne pas confondre avec [verdict_inclusion].** J'ai d'abord relâché
    celui-ci en inclusion pour faire passer les promos publiées — et l'auto-test
    l'a refusé, parce que ce verdict sert AUSSI aux signalements en attente,
    dont la file de modération est globale elle aussi. Relâcher un verdict
    partagé affaiblit la sonde qui n'en avait pas besoin : deux questions
    différentes veulent deux verdicts.
    """
    if compteur is None or reference is None:
        return "non_concluant", "%s illisible — pas de verdict" % quoi
    if compteur != reference:
        return ("echec",
                "%s : le tableau de bord dit %d, la référence en contient %d"
                % (quoi, compteur, reference))
    return "ok", "%d = %d" % (compteur, reference)


def verdict_compteurs_egaux(valeur_a, valeur_b, valeur_admin, quoi):
    """Portée globale ⇒ les deux agents et l'admin annoncent le MÊME compteur.

    ⚠️ **Remplace `verdict_somme_disjointe` le 2026-08-13.** L'ancienne sonde
    exigeait `A + B ≤ admin` pour deux agents aux communes disjointes ; son
    propre docstring notait déjà que l'égalité « est aussi le résultat qu'on
    obtient quand le périmètre a purement disparu ». C'est exactement ce qui
    vient d'arriver — elle ne pourrait donc plus refuser.

    L'égalité stricte, elle, refuse : tout reliquat de filtrage sur l'un des
    deux agents fait diverger son compteur.
    """
    if None in (valeur_a, valeur_b, valeur_admin):
        return "non_concluant", "%s illisible — pas de verdict" % quoi
    if valeur_a != valeur_b:
        return ("echec",
                "%s : agent A annonce %d, agent B %d — deux agents sans "
                "territoire doivent compter la même chose ; un filtre de "
                "périmètre a survécu" % (quoi, valeur_a, valeur_b))
    if valeur_a != valeur_admin:
        return ("echec",
                "%s : les agents annoncent %d, l'admin %d — les agents ne "
                "voient pas le parc entier" % (quoi, valeur_a, valeur_admin))
    return "ok", "A = B = admin = %d" % valeur_a


def verdict_meme_vue(ids_a, ids_b, ids_admin, quoi):
    """Portée globale ⇒ deux agents voient la MÊME chose, égale à l'admin.

    ⚠️ **Remplace `verdict_disjonction` le 2026-08-13, et c'est son inverse
    exact.** L'ancienne sonde exigeait que deux agents aux communes disjointes
    n'aient aucun élément en commun ; le chantier « agent global » supprime la
    frontière, donc elle rendait ❌ sur un produit correct (règle 38).

    ⚠️ **Il fallait la remplacer, pas la supprimer.** « L'agent voit tout » est
    indiscernable de « l'agent voit ce qu'il voyait » tant qu'on n'observe
    qu'un seul agent — c'est le cas exact de la règle 28 : la sonde ne pourrait
    pas refuser. Avec deux agents, un filtre résiduel oublié quelque part fait
    diverger les deux listes, et c'est le seul contrôle du parc qui le verrait.

    La comparaison à l'admin est le second pied : deux agents également bridés
    seraient égaux entre eux sans être complets.
    """
    if not ids_admin:
        return "non_concluant", "%s : l'admin lui-même ne voit rien" % quoi
    if ids_a != ids_b:
        seul_a = sorted(ids_a - ids_b)
        seul_b = sorted(ids_b - ids_a)
        return ("echec",
                "%s : les deux agents ne voient PAS la même chose — %d vu(s) "
                "par A seul (ex. %s), %d par B seul (ex. %s). Un filtre de "
                "périmètre a survécu quelque part."
                % (quoi, len(seul_a), seul_a[0][:8] if seul_a else "—",
                   len(seul_b), seul_b[0][:8] if seul_b else "—"))
    if ids_a != ids_admin:
        manquants = sorted(ids_admin - ids_a)
        return ("echec",
                "%s : les agents voient la même chose (%d) mais PAS ce que "
                "voit l'admin (%d) — %d élément(s) leur échappent (ex. %s)"
                % (quoi, len(ids_a), len(ids_admin), len(manquants),
                   manquants[0][:8]))
    return "ok", "A = B = admin, %d élément(s)" % len(ids_a)


# ⚠️ `verdict_projection` a été retiré le 2026-08-13 avec la section 3 :
# « aucun élément hors du périmètre de l'agent » n'a plus de sens quand il n'y a
# plus de périmètre. C'était le SEUL contrôle de projection du parc — sa
# disparition est une perte de couverture assumée, pas un nettoyage. Ce qui la
# compense en partie est la section 4 : deux agents doivent voir la même chose
# que l'admin, ce qu'un filtre résiduel ferait échouer.


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
    _v("compteur cohérent", verdict_coherence(3, 3, "x")[0], "ok")
    _v("compteur cohérent à zéro", verdict_coherence(0, 0, "x")[0], "ok")
    _v("les deux agents et l'admin comptent pareil",
       verdict_compteurs_egaux(7, 7, 7, "x")[0], "ok")
    _v("les deux agents voient la même liste que l'admin",
       verdict_meme_vue({"a", "b"}, {"a", "b"}, {"a", "b"}, "x")[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le cas fondateur de la règle 8 : le tableau de bord surcompte.
    _v("surcompte", verdict_coherence(6, 2, "x")[0], "echec")
    _v("sous-compte", verdict_coherence(1, 2, "x")[0], "echec")
    # ⚠️ L'inclusion : le local tient dans le global, jamais l'inverse.
    _v("local contenu dans le global",
       verdict_inclusion(89, 51, "x")[0], "ok")
    _v("inclusion à égalité", verdict_inclusion(3, 3, "x")[0], "ok")
    _v("global plus petit que le local",
       verdict_inclusion(2, 6, "x")[0], "echec")
    _v("inclusion illisible",
       verdict_inclusion(None, 6, "x")[0], "non_concluant")
    _v("compteur illisible → non concluant",
       verdict_coherence(None, 2, "x")[0], "non_concluant")
    # ⚠️ **LE cas que ce chantier doit pouvoir attraper** : un filtre de
    # périmètre oublié quelque part, qui fait diverger les deux agents. C'est
    # la seule signature observable d'une suppression incomplète.
    _v("les deux agents ne comptent pas pareil",
       verdict_compteurs_egaux(7, 5, 7, "x")[0], "echec")
    _v("les agents comptent pareil, mais moins que l'admin",
       verdict_compteurs_egaux(5, 5, 9, "x")[0], "echec")
    _v("compteur d'agent illisible → non concluant",
       verdict_compteurs_egaux(None, 5, 5, "x")[0], "non_concluant")
    _v("un élément vu par un seul des deux agents",
       verdict_meme_vue({"a", "z"}, {"a"}, {"a", "z"}, "x")[0], "echec")
    _v("les deux agents d'accord, mais l'admin voit plus",
       verdict_meme_vue({"a"}, {"a"}, {"a", "z"}, "x")[0], "echec")
    # ⚠️ Une base vide satisfait n'importe quelle égalité — c'est la même
    # famille que « une liste vide satisfait toute assertion d'absence ».
    _v("admin ne voit rien → non concluant",
       verdict_meme_vue(set(), set(), set(), "x")[0], "non_concluant")

    refus = 10
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
    agent_b_email = _exiger("AGENT_B_EMAIL")
    agent_b_password = _exiger("AGENT_B_PASSWORD")

    print("═" * 64)
    print("  Tableau de bord — cohérence des compteurs, portée globale")
    print("═" * 64)

    def connecter(chemin, corps, qui):
        st, d = appeler("POST", chemin, corps=corps)
        jeton = d.get("accessToken")
        if not jeton:
            print("❌ connexion %s impossible (HTTP %s, %s)"
                  % (qui, st, d.get("code")))
            print("   ⚠️ un 429 se déguise en « identifiants incorrects ».")
            sys.exit(2)
        time.sleep(PACE)
        return jeton

    ja = connecter("/admin/login",
                   {"email": admin_email, "password": admin_password}, "admin")
    jg = connecter("/agent/login",
                   {"email": agent_email, "password": agent_password}, "agent A")
    jb = connecter("/agent/login",
                   {"email": agent_b_email, "password": agent_b_password},
                   "agent B")

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-42s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    # ── 1. Les compteurs disent-ils ce qu'ils comptent ? ────────────────────
    print("\n── 1. un compteur égale ce qu'il prétend compter ──")
    _, tb_admin = appeler("GET", "/admin/dashboard", ja)
    time.sleep(PACE)

    # `promosPubliees` (vue globale) doit égaler ce que le client voit sans
    # filtre de commune : les deux appliquent les MÊMES cinq conditions de
    # visibilité, via `applyVisibleConditions`. C'est le surcompte de la
    # règle 8 qui est visé ici.
    _, client = appeler("GET", "/promo?limit=1")
    noter("promos publiées = promos vues du client",
          *verdict_inclusion(tb_admin.get("promosPubliees"),
                             client.get("total"), "promos publiées"))
    time.sleep(PACE)

    _, file_moderation = appeler("GET", "/admin/moderation/queue?limit=100", ja)
    noter("signalements en attente = file de modération",
          *verdict_coherence(tb_admin.get("signalementsEnAttente"),
                             file_moderation.get("total"),
                             "signalements en attente"))
    time.sleep(PACE)

    # ── 2. Les compteurs de l'agent ────────────────────────────────────────
    #
    # ⚠️ **Ce que prouvaient les sections 2 et 3 n'existe plus.** Elles
    # établissaient que l'agent voit un SOUS-ensemble de l'admin (compteurs)
    # et que ses listes ne débordent pas de son périmètre (projections). Le
    # chantier « agent global » du 2026-08-13 supprime le périmètre : les deux
    # relations deviennent des assertions qui **ne peuvent plus refuser**, et
    # `verdict_somme_disjointe` l'écrivait déjà — « c'est aussi le résultat
    # qu'on obtient quand le périmètre a purement disparu ».
    #
    # Les laisser au vert aurait été le pire des deux mondes : une couverture
    # affichée sans mesure (règle 28). Elles sont **remplacées**, pas
    # supprimées — la section 4 porte désormais la charge de la preuve, à
    # l'endroit exact où elle est vérifiable.
    print("\n── 2. lecture des vues de l'agent A (matière de la section 4) ──")
    _, tb_agent = appeler("GET", "/admin/dashboard", jg)
    time.sleep(PACE)

    _, mes_commercants = appeler("GET", "/admin/commercant?limit=100", jg)
    autorises = {c["id"] for c in mes_commercants.get("items", [])}
    time.sleep(PACE)

    # ── 4. Deux agents — la sonde qui ne passe pas par accident ──
    print("\n── 4. deux agents, portée globale ──")
    # ⚠️ **Retournée le 2026-08-13.** Cette section prouvait le cloisonnement
    # entre deux agents aux communes disjointes. Le chantier « agent global »
    # supprime la notion même de commune : elle prouve désormais l'inverse —
    # que les deux voient **exactement la même chose**, et que cette chose est
    # ce que voit l'admin.
    #
    # ⚠️ **L'agent B du décor reste indispensable, et pour la même raison
    # qu'avant.** Avec un seul agent, « il voit tout » est indiscernable de
    # « il voit ce qu'il voyait » : la sonde ne pourrait pas refuser (règle
    # 28). C'est le second agent qui fait la mesure, hier comme aujourd'hui.
    #
    # ⚠️ Plus de prémisse « communes disjointes » à établir — il n'y a plus de
    # communes. La prémisse restante est que l'admin voie quelque chose, et
    # `verdict_meme_vue` la vérifie plutôt que de la supposer.
    _, tb_agent_b = appeler("GET", "/admin/dashboard", jb)
    time.sleep(PACE)
    noter("commercesActifs : agent B = agent A = admin",
          *verdict_compteurs_egaux(tb_agent.get("commercesActifs"),
                                   tb_agent_b.get("commercesActifs"),
                                   tb_admin.get("commercesActifs"),
                                   "commercesActifs"))

    _, commercants_b = appeler("GET", "/admin/commercant?limit=100", jb)
    autorises_b = {c["id"] for c in commercants_b.get("items", [])}
    _, commercants_admin = appeler("GET", "/admin/commercant?limit=100", ja)
    autorises_admin = {c["id"] for c in commercants_admin.get("items", [])}
    noter("les deux agents voient la même liste que l'admin",
          *verdict_meme_vue(autorises, autorises_b, autorises_admin,
                            "listes de commerçants"))

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
