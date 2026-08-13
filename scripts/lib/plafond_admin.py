#!/usr/bin/env python3
"""Banc du plafond réglé par l'admin — le réglage change-t-il quelque chose ?

── Le trou que ce banc comble ──────────────────────────────────────────────

`PATCH /admin/commercant/:id/plafond-promos` est la seule route
**admin-seulement** parmi les gestes sur un commerçant. Un banc la touche :
`portee_agent`, et il prouve exactement une chose — **que l'agent en est
refusé**. Personne n'éprouvait qu'elle *fasse* quelque chose.

C'est le miroir de la règle 28 : on y exige qu'un contrôle sache **refuser** ;
ici on exige qu'un réglage sache **agir**. Un `plafond-promos` devenu inopérant
(valeur écrite mais jamais relue, ou relue depuis la configuration globale)
laisserait `portee_agent` au vert, l'admin croirait avoir donné de l'air à un
commerçant, et rien ne le détromperait.

── Comment on l'éprouve sans publier huit promos ───────────────────────────

En **serrant** plutôt qu'en desserrant. Le commerçant du décor a déjà des promos
en ligne : on met son plafond exactement à ce nombre, et la publication suivante
doit être **refusée** avec `PROMO_ACTIVE_CAP_REACHED`. On desserre d'un cran, et
la même publication doit **passer**.

Les deux sens sont nécessaires. Le refus seul serait satisfait par un serveur
qui refuse toujours ; l'acceptation seule, par un serveur qui n'applique aucun
plafond. C'est le va-et-vient qui prouve que **c'est bien cette valeur-là** qui
décide.

⚠️ Et le plafond n'est pas le quota quotidien : l'agent est exempté des 5
créations par 24 h, **personne** n'est exempté des 5 promos actives. C'est donc
bien la garde qu'on éprouve, et non celle d'à côté.

── ⚠️ Ce banc remet tout en place ──────────────────────────────────────────

Il relit le plafond de départ, le restaure à la fin, et arrête la promo qu'il a
publiée. Un banc qui laisserait un commerçant du décor bridé à 2 casserait tous
les suivants — et le ferait sans un mot.

── Usage ───────────────────────────────────────────────────────────────────

    python3 scripts/lib/plafond_admin.py --self-test
    ./scripts/test-plafond-admin.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.2"))
DEVICE_ID = "banc-plafond-admin-0001"


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_plafond_servi(slots, attendu):
    """Le plafond réglé doit être **servi** au commerçant.

    ⚠️ Vérifié sur `GET /promo/me/slots`, pas sur le code de sortie du PATCH :
    un 200 dit qu'une requête a été acceptée, pas qu'une valeur est appliquée.
    Et c'est ce nombre-là que l'écran du commerçant affiche.
    """
    if not slots:
        return "non_concluant", "GET /promo/me/slots illisible"
    servi = slots.get("plafond")
    if servi is None:
        return "non_concluant", "la réponse ne porte pas de « plafond »"
    if servi != attendu:
        return ("echec",
                "le serveur sert un plafond de %s après en avoir réglé %s : "
                "la valeur est acceptée puis ignorée" % (servi, attendu))
    return "ok", "plafond servi = %d" % servi


def verdict_refus_au_plafond(statut, code):
    """Serré à ras, le commerçant ne doit plus pouvoir publier.

    ⚠️ Le code est asserté, pas seulement « ce n'est pas un 201 » : un 500 ou un
    429 ferment aussi la porte, pour des raisons qu'on ne veut surtout pas
    confondre avec un plafond atteint.
    """
    if statut is None:
        return "non_concluant", "aucune réponse"
    if code == "PROMO_ACTIVE_CAP_REACHED":
        return "ok", "refusée — PROMO_ACTIVE_CAP_REACHED"
    if statut in (200, 201):
        return ("echec",
                "publication ACCEPTÉE alors que le plafond est atteint : le "
                "réglage de l'admin ne règle rien, et il croit avoir borné un "
                "commerçant qui ne l'est pas")
    if statut == 429:
        return ("non_concluant",
                "429 — seau des écritures épuisé, un refus de débit n'est pas "
                "un refus de plafond")
    return ("non_concluant",
            "HTTP %s %s — refus pour une autre raison que le plafond"
            % (statut, code))


def verdict_acceptation_desserree(statut, code, pid):
    """⚠️ **L'autre sens, et il est indispensable.**

    Sans lui, un serveur qui refuserait *toujours* passerait la sonde
    précédente. C'est le va-et-vient qui prouve que c'est bien cette valeur-là
    qui décide (règle 38 : établir que la mesure pouvait varier).
    """
    if statut is None:
        return "non_concluant", "aucune réponse"
    if statut in (200, 201) and pid:
        return "ok", "publication acceptée après desserrage d'un cran"
    if code == "PROMO_ACTIVE_CAP_REACHED":
        return ("echec",
                "toujours refusée pour plafond atteint APRÈS l'avoir relevé : "
                "la valeur réglée n'est pas celle que la garde consulte")
    return ("non_concluant",
            "HTTP %s %s — ni acceptée ni refusée pour le plafond"
            % (statut, code))


def verdict_restauration(slots, attendu):
    """Le décor doit être rendu tel qu'il a été trouvé.

    ⚠️ Un banc qui laisserait le commerçant du décor bridé casserait tous les
    suivants, et le ferait en silence.
    """
    if not slots:
        return "non_concluant", "GET /promo/me/slots illisible"
    if slots.get("plafond") != attendu:
        return ("echec",
                "plafond laissé à %s au lieu de %s — le décor est abîmé pour "
                "les bancs suivants" % (slots.get("plafond"), attendu))
    return "ok", "plafond de départ rendu (%s)" % attendu


def verdict_marge(slots):
    """⚠️ Le commerçant a-t-il de quoi rendre ce banc concluant ?

    Il faut au moins une promo en ligne : avec zéro, « serrer au nombre
    d'actives » vaudrait plafond 0, qui refuse pour une raison différente
    (interdiction totale) — on mesurerait autre chose que le plafond.
    """
    if not slots:
        return "non_concluant", "GET /promo/me/slots illisible"
    en_ligne = slots.get("enLigne")
    if en_ligne is None:
        return "non_concluant", "la réponse ne porte pas d'« enLigne »"
    if en_ligne < 1:
        return ("non_concluant",
                "aucune promo en ligne : serrer à 0 interdirait tout et ne "
                "mesurerait pas le plafond mais l'interdiction")
    return "ok", "%d promo(s) en ligne — de quoi serrer à ras" % en_ligne


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
            return r.status, json.loads(r.read() or b"{}")
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
    _v("plafond servi", verdict_plafond_servi({"plafond": 2}, 2)[0], "ok")
    _v("refus au plafond",
       verdict_refus_au_plafond(400, "PROMO_ACTIVE_CAP_REACHED")[0], "ok")
    _v("accepté desserré",
       verdict_acceptation_desserree(201, None, "p1")[0], "ok")
    _v("décor restauré", verdict_restauration({"plafond": 5}, 5)[0], "ok")
    _v("marge suffisante", verdict_marge({"enLigne": 2})[0], "ok")
    # ⚠️ Un plafond `null` (défaut global) est une valeur légitime.
    _v("plafond nul rendu", verdict_restauration({"plafond": None}, None)[0],
       "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le défaut visé : la valeur est acceptée puis ignorée.
    _v("plafond ignoré", verdict_plafond_servi({"plafond": 5}, 2)[0], "echec")
    # ⚠️ Le défaut visé : le réglage de l'admin ne borne rien.
    _v("publication au-delà du plafond",
       verdict_refus_au_plafond(201, None)[0], "echec")
    # ⚠️ Le défaut visé : la garde consulte une autre valeur que celle réglée.
    _v("refus malgré desserrage",
       verdict_acceptation_desserree(400, "PROMO_ACTIVE_CAP_REACHED", None)[0],
       "echec")
    _v("décor laissé bridé", verdict_restauration({"plafond": 2}, 5)[0],
       "echec")

    # ── Doivent rester NON CONCLUANTS ────────────────────────────────────────
    # ⚠️ Un 429 n'est pas un refus de plafond (piège du parc : seau partagé).
    _v("seau épuisé", verdict_refus_au_plafond(429, None)[0], "non_concluant")
    _v("refus pour autre chose",
       verdict_refus_au_plafond(403, "FORBIDDEN")[0], "non_concluant")
    # ⚠️ Sans promo en ligne, on mesurerait l'interdiction, pas le plafond.
    _v("aucune marge", verdict_marge({"enLigne": 0})[0], "non_concluant")
    _v("slots illisibles", verdict_marge(None)[0], "non_concluant")
    _v("enLigne absent", verdict_marge({})[0], "non_concluant")
    _v("plafond absent", verdict_plafond_servi({}, 2)[0], "non_concluant")
    _v("slots illisibles au réglage",
       verdict_plafond_servi(None, 2)[0], "non_concluant")
    _v("aucune réponse au refus",
       verdict_refus_au_plafond(None, None)[0], "non_concluant")
    _v("aucune réponse au desserrage",
       verdict_acceptation_desserree(None, None, None)[0], "non_concluant")
    _v("restauration illisible",
       verdict_restauration(None, 5)[0], "non_concluant")

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
    tel = _exiger("COMMERCANT_TEL")
    pin = _exiger("COMMERCANT_PIN")
    cid = _exiger("COMMERCANT_ID")

    print("═" * 70)
    print("  Plafond réglé par l'admin — le réglage change-t-il quelque chose ?")
    print("═" * 70)

    st, d = appeler("POST", "/admin/login",
                    corps={"email": admin_email, "password": admin_password})
    ja = d.get("accessToken")
    st, d = appeler("POST", "/agent/login",
                    corps={"email": agent_email, "password": agent_password})
    jg = d.get("accessToken")
    st, d = appeler("POST", "/commercant/login",
                    corps={"telephone": tel, "pin": pin})
    jc = d.get("accessToken")
    if not (ja and jg and jc):
        print("❌ connexions impossibles (admin=%s agent=%s commerçant=%s)"
              % (bool(ja), bool(jg), bool(jc)))
        return 2
    time.sleep(PACE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-40s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    def slots():
        st, d = appeler("GET", "/promo/me/slots", jc)
        return d if st == 200 else None

    def regler(valeur):
        return appeler("PATCH", "/admin/commercant/%s/plafond-promos" % cid,
                       ja, {"plafond": valeur})

    def publier(suffixe):
        st, d = appeler("POST", "/promo/agent/%s" % cid, jg, {
            "description": "Promo du banc de plafond %s" % suffixe,
            "prixAvant": 900, "prixApres": 600, "categorie": "alimentation",
            "photoKeys": ["promo-photos/%s/plafond-%s.jpg" % (cid, suffixe)]})
        return st, d

    # ── 0. De quoi juger ? ──────────────────────────────────────────────────
    print("\n── 0. le commerçant a-t-il de quoi rendre ce banc concluant ? ──")
    depart = slots()
    noter("GET /promo/me/slots", *verdict_marge(depart))
    if not depart or not depart.get("enLigne"):
        return 1
    en_ligne = depart["enLigne"]
    plafond_initial = depart.get("plafond")
    print("     départ : %d en ligne, plafond %s" % (en_ligne, plafond_initial))
    time.sleep(PACE)

    # ── 1. Serré à ras : la publication doit être refusée ───────────────────
    print("\n── 1. serré au nombre d'actives, la publication est refusée ──")
    st, d = regler(en_ligne)
    if st not in (200, 201):
        noter("PATCH plafond-promos", "non_concluant",
              "HTTP %s %s — sans réglage, rien à mesurer" % (st, d.get("code")))
        return 1
    time.sleep(PACE)
    noter("le plafond réglé est servi", *verdict_plafond_servi(slots(), en_ligne))
    time.sleep(PACE)
    st, d = publier("serre")
    noter("publication au plafond",
          *verdict_refus_au_plafond(st, d.get("code")))
    time.sleep(PACE)

    # ── 2. Desserré d'un cran : la même publication passe ───────────────────
    print("\n── 2. desserré d'un cran, la même publication passe ──")
    st, d = regler(en_ligne + 1)
    if st not in (200, 201):
        noter("PATCH plafond-promos (+1)", "non_concluant",
              "HTTP %s %s" % (st, d.get("code")))
    else:
        time.sleep(PACE)
        noter("le nouveau plafond est servi",
              *verdict_plafond_servi(slots(), en_ligne + 1))
        time.sleep(PACE)
        st, d = publier("desserre")
        pid = d.get("id")
        noter("publication après desserrage",
              *verdict_acceptation_desserree(st, d.get("code"), pid))
        time.sleep(PACE)
        # ⚠️ On retire la promo du banc : la laisser en ligne fausserait le
        # décompte de tous les bancs suivants.
        if pid:
            appeler("POST", "/promo/%s/stop" % pid, jg)
            time.sleep(PACE)

    # ── 3. Le décor est rendu tel qu'il a été trouvé ────────────────────────
    print("\n── 3. le décor est rendu tel qu'il a été trouvé ──")
    regler(plafond_initial)
    time.sleep(PACE)
    noter("plafond de départ restauré",
          *verdict_restauration(slots(), plafond_initial))

    print("\n" + "═" * 70)
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
