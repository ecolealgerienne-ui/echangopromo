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

def verdict_coherence(compteur, reference, quoi):
    """Un compteur doit égaler ce qu'il prétend compter."""
    if compteur is None or reference is None:
        return "non_concluant", "%s illisible — pas de verdict" % quoi
    if compteur != reference:
        return ("echec",
                "%s : le tableau de bord dit %d, la liste en contient %d"
                % (quoi, compteur, reference))
    return "ok", "%d = %d" % (compteur, reference)


def verdict_cloisonnement(valeur_agent, valeur_admin, quoi):
    """Ce que voit l'agent est un SOUS-ensemble de ce que voit l'admin.

    ⚠️ L'assertion porte sur la relation, pas sur des nombres : le banc ne sait
    pas combien de commerces existent, et une attente chiffrée finirait
    ajustée à chaque passage jusqu'à ne plus rien tester.
    """
    if valeur_agent is None or valeur_admin is None:
        return "non_concluant", "%s illisible — pas de verdict" % quoi
    if valeur_agent > valeur_admin:
        return ("echec",
                "%s : l'agent voit %d, l'admin %d — l'agent voit PLUS que la "
                "vue globale, son périmètre n'est pas restreint"
                % (quoi, valeur_agent, valeur_admin))
    return "ok", "agent %d ≤ admin %d" % (valeur_agent, valeur_admin)


def verdict_somme_disjointe(valeur_a, valeur_b, valeur_admin, quoi):
    """Deux agents aux communes DISJOINTES ne peuvent pas totaliser plus que
    la vue globale.

    ⚠️ **C'est cette sonde qui rend le cloisonnement vérifiable.** Comparer un
    agent à l'admin par `≤` ne prouve rien : si l'agent couvre presque tout le
    territoire, l'égalité est le résultat normal — et c'est aussi le résultat
    qu'on obtient quand le périmètre a purement disparu. Mesuré le 2026-08-05 :
    « agent 48 ≤ admin 48 » passait, et serait passé à l'identique sans aucun
    cloisonnement.

    Deux agents disjoints, en revanche, ne peuvent pas voir chacun la totalité
    sans que leur somme ne dépasse le tout.
    """
    if None in (valeur_a, valeur_b, valeur_admin):
        return "non_concluant", "%s illisible — pas de verdict" % quoi
    if valeur_a + valeur_b > valeur_admin:
        return ("echec",
                "%s : agents disjoints A=%d et B=%d, total %d > %d vus par "
                "l'admin — au moins l'un des deux voit hors de ses communes"
                % (quoi, valeur_a, valeur_b, valeur_a + valeur_b, valeur_admin))
    return "ok", "A %d + B %d ≤ admin %d" % (valeur_a, valeur_b, valeur_admin)


def verdict_disjonction(ids_a, ids_b, quoi):
    """Communes disjointes ⇒ listes disjointes. Sans semantique à interpréter."""
    if not ids_a and not ids_b:
        return "non_concluant", "%s : les deux listes sont vides" % quoi
    communs = sorted(ids_a & ids_b)
    if communs:
        return ("echec",
                "%s : %d élément(s) vus par les DEUX agents alors que leurs "
                "communes sont disjointes (ex. %s)"
                % (quoi, len(communs), communs[0][:8]))
    return "ok", "A %d, B %d, aucun en commun" % (len(ids_a), len(ids_b))


def verdict_projection(ids_vus, ids_autorises, quoi):
    """Aucun élément hors du périmètre de l'agent."""
    if not ids_vus:
        return "non_concluant", "%s : rien à examiner" % quoi
    intrus = sorted(ids_vus - ids_autorises)
    if intrus:
        return ("echec",
                "%s : %d élément(s) hors des communes de l'agent (ex. %s)"
                % (quoi, len(intrus), intrus[0][:8]))
    return "ok", "%d élément(s), tous dans son périmètre" % len(ids_vus)


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
    _v("agent strictement inférieur",
       verdict_cloisonnement(2, 5, "x")[0], "ok")
    _v("agent égal à l'admin (une seule commune peuplée)",
       verdict_cloisonnement(5, 5, "x")[0], "ok")
    _v("projection propre",
       verdict_projection({"a"}, {"a", "b"}, "x")[0], "ok")
    _v("somme de deux agents disjoints",
       verdict_somme_disjointe(2, 3, 10, "x")[0], "ok")
    _v("listes disjointes",
       verdict_disjonction({"a"}, {"b"}, "x")[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le cas fondateur de la règle 8 : le tableau de bord surcompte.
    _v("surcompte", verdict_coherence(6, 2, "x")[0], "echec")
    _v("sous-compte", verdict_coherence(1, 2, "x")[0], "echec")
    _v("compteur illisible → non concluant",
       verdict_coherence(None, 2, "x")[0], "non_concluant")
    # ⚠️ L'agent voit plus large que la vue globale : son périmètre a sauté.
    _v("agent au-dessus de l'admin",
       verdict_cloisonnement(7, 5, "x")[0], "echec")
    _v("valeur d'agent illisible → non concluant",
       verdict_cloisonnement(None, 5, "x")[0], "non_concluant")
    _v("élément hors périmètre",
       verdict_projection({"a", "z"}, {"a"}, "x")[0], "echec")
    _v("rien à examiner → non concluant",
       verdict_projection(set(), {"a"}, "x")[0], "non_concluant")
    # ⚠️ LE cas que le « ≤ » laissait passer : deux agents disjoints voyant
    # chacun la totalité. C'est la signature d'un périmètre disparu.
    _v("deux agents voyant chacun tout",
       verdict_somme_disjointe(10, 10, 10, "x")[0], "echec")
    _v("un commerçant vu par les deux agents",
       verdict_disjonction({"a", "z"}, {"z"}, "x")[0], "echec")
    _v("deux listes vides → non concluant",
       verdict_disjonction(set(), set(), "x")[0], "non_concluant")

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
    print("  Tableau de bord — cohérence des compteurs, cloisonnement des vues")
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
          *verdict_coherence(tb_admin.get("promosPubliees"),
                             client.get("total"), "promos publiées"))
    time.sleep(PACE)

    _, file_moderation = appeler("GET", "/admin/moderation/queue?limit=100", ja)
    noter("signalements en attente = file de modération",
          *verdict_coherence(tb_admin.get("signalementsEnAttente"),
                             file_moderation.get("total"),
                             "signalements en attente"))
    time.sleep(PACE)

    # ── 2. Le cloisonnement des compteurs ──────────────────────────────────
    print("\n── 2. l'agent ne voit pas plus large que la vue globale ──")
    _, tb_agent = appeler("GET", "/admin/dashboard", jg)
    time.sleep(PACE)
    for cle in ("commercesActifs", "promosPubliees", "signalementsEnAttente"):
        noter(cle, *verdict_cloisonnement(tb_agent.get(cle),
                                          tb_admin.get(cle), cle))

    # ── 3. Le cloisonnement des LISTES ─────────────────────────────────────
    #
    # Un agent qui ne peut rien faire ailleurs mais qui VOIT tout n'est pas
    # cloisonné. `test-appartenance` éprouve les actions ; ceci éprouve les
    # projections.
    print("\n── 3. et ses listes ne débordent pas non plus ──")
    _, mes_commercants = appeler("GET", "/admin/commercant?limit=100", jg)
    autorises = {c["id"] for c in mes_commercants.get("items", [])}
    time.sleep(PACE)

    _, promos_agent = appeler("GET", "/admin/promo?limit=100", jg)
    vus = {p.get("commercantId") for p in promos_agent.get("items", [])
           if p.get("commercantId")}
    noter("GET /admin/promo (agent A)",
          *verdict_projection(vus, autorises, "promos listées"))
    time.sleep(PACE)

    # ── 4. Deux agents disjoints — la sonde qui ne passe pas par accident ──
    print("\n── 4. deux agents aux communes disjointes ──")
    # ⚠️ **La prémisse est vérifiée, pas supposée** (2026-08-05). Ces deux
    # sondes n'ont de sens que si les territoires sont réellement disjoints —
    # et ils ne l'étaient pas : le décor n'assignait les communes qu'à la
    # CRÉATION de l'agent, si bien qu'agent A en avait accumulé quatre, dont
    # celle de l'agent B. Les sondes accusaient alors un cloisonnement
    # parfaitement correct.
    #
    # Le décor le garantit désormais (`assurer_communes`). On le revérifie
    # quand même ici : une sonde qui dépend d'une prémisse doit la lire, pas en
    # hériter. Si elle ne tient pas, on ne conclut pas — on ne rougit pas non
    # plus.
    _, moi_a = appeler("GET", "/agent/me", jg)
    _, moi_b = appeler("GET", "/agent/me", jb)
    com_a = {c["id"] for c in (moi_a.get("communes") or [])}
    com_b = {c["id"] for c in (moi_b.get("communes") or [])}
    time.sleep(PACE)
    if not com_a or not com_b or (com_a & com_b):
        noter("prémisse : communes disjointes", "non_concluant",
              "A=%d commune(s), B=%d, %d en commun — relancer "
              "provision-decor.sh" % (len(com_a), len(com_b),
                                      len(com_a & com_b)))
        print("\n" + "═" * 64)
        print("%d contrôles, %d échec(s), %d non concluant(s)"
              % (len(resultats), resultats.count("echec"),
                 resultats.count("non_concluant")))
        return 1
    noter("prémisse : communes disjointes", "ok",
          "A %d, B %d, aucune en commun" % (len(com_a), len(com_b)))

    _, tb_agent_b = appeler("GET", "/admin/dashboard", jb)
    time.sleep(PACE)
    noter("commercesActifs : A + B ≤ admin",
          *verdict_somme_disjointe(tb_agent.get("commercesActifs"),
                                   tb_agent_b.get("commercesActifs"),
                                   tb_admin.get("commercesActifs"),
                                   "commercesActifs"))

    _, commercants_b = appeler("GET", "/admin/commercant?limit=100", jb)
    autorises_b = {c["id"] for c in commercants_b.get("items", [])}
    noter("aucun commerçant vu par les deux",
          *verdict_disjonction(autorises, autorises_b, "listes de commerçants"))

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
