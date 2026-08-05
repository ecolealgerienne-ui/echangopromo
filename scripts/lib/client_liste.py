#!/usr/bin/env python3
"""Banc de la liste client — une seule définition de « visible », zéro fuite.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

Deux défauts réels, tous deux nés ici :

1. **`photoKey` fuyait dans la réponse.** Un `{...promo, photoUrl}` transforme
   l'instance TypeORM en objet plain et **désactive silencieusement les
   `@Exclude()`** (règle 4). La clé exposée contient l'UUID de l'**agent** pour
   une promo créée par un agent — un identifiant interne dans une réponse
   anonyme. La recherche est **récursive** : le défaut était dans un objet
   imbriqué, pas à la racine.

2. **« Visible » avait deux définitions.** `GET /promo/:id` ne reprenait qu'une
   des cinq conditions (`VISIBLE_MODERATION_STATUSES`) : une promo arrêtée,
   expirée, en brouillon ou d'un commerçant suspendu restait **intégralement
   consultable par quiconque avait le lien**. Corrigé le 2026-08-05 en faisant
   passer la route par `applyVisibleConditions`.

D'où la sonde centrale : **ce que la liste montre et ce que le détail sert
doivent être le même ensemble**, éprouvé sur une promo qu'on fait basculer.

Et deux sondes d'entrée, parce qu'un `500` sur une URL malformée est une
information offerte à qui sonde : identifiant inexistant et identifiant qui
n'est pas un UUID.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/client_liste.py --self-test
    ./scripts/test-client-liste.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.1"))
DEVICE_ID = "banc-client-liste-0001"

CHAMPS_INTERNES = ("photoKey", "photoKeys", "thumbnailKey", "imageKey")


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_fuite(corps):
    """Aucun champ interne, à quelque profondeur que ce soit."""
    trouves = sorted(set(_champs(corps, CHAMPS_INTERNES)))
    if trouves:
        return "echec", "champs internes exposés : %s" % ", ".join(trouves)
    return "ok", "aucun champ interne"


def _champs(noeud, noms):
    if isinstance(noeud, dict):
        for cle, valeur in noeud.items():
            if cle in noms:
                yield cle
            yield from _champs(valeur, noms)
    elif isinstance(noeud, list):
        for e in noeud:
            yield from _champs(e, noms)


def verdict_accord(dans_liste, statut_detail, devrait_etre_visible):
    """La liste et le détail doivent dire la MÊME chose.

    ⚠️ C'est la sonde qui vaut le banc : deux définitions de « visible » ne se
    contredisent que sur les cas limites, et ces cas-là ne se voient jamais
    dans un usage normal — seulement quand quelqu'un possède le lien.
    """
    servi = statut_detail in (200, 201)
    if statut_detail == 429:
        return "non_concluant", "429 sur le détail — ce n'est pas un verdict"
    if statut_detail is not None and statut_detail >= 500:
        return "echec", "le détail casse (HTTP %s) au lieu de trancher" % statut_detail
    if devrait_etre_visible:
        if not dans_liste:
            return "echec", "promo visible absente de la liste"
        if not servi:
            return ("echec",
                    "listée mais le détail refuse (HTTP %s)" % statut_detail)
        return "ok", "listée et servie"
    if dans_liste:
        return "echec", "promo NON visible encore présente dans la liste"
    if servi:
        return ("echec",
                "retirée de la liste mais le DÉTAIL la sert encore — "
                "consultable par quiconque a le lien (deux définitions de "
                "« visible »)")
    return "ok", "absente de la liste et refusée au détail"


def verdict_entree(statut, code, codes_admis):
    """Une URL malformée se refuse ; elle ne casse pas."""
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if statut is None:
        return "echec", "pas de réponse : %s" % code
    if statut in (200, 201):
        return "echec", "ACCEPTÉ alors qu'un refus était dû"
    if statut >= 500 or code == "INTERNAL_ERROR":
        return ("echec",
                "HTTP %s %s — l'endpoint casse au lieu de refuser, et un 500 "
                "renseigne qui sonde" % (statut, code))
    if code not in codes_admis:
        return ("non_concluant",
                "refusé en %s/%s, hors de %s" % (statut, code, codes_admis))
    return "ok", "%s %s" % (statut, code)


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


def ids_listes():
    _, d = appeler("GET", "/promo?limit=100")
    return {p["id"] for p in d.get("items", [])}, d


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
    _v("réponse propre", verdict_fuite({"items": [{"photoUrls": ["u"]}]})[0], "ok")
    _v("visible : listée et servie",
       verdict_accord(True, 200, True)[0], "ok")
    _v("invisible : absente et refusée",
       verdict_accord(False, 404, False)[0], "ok")
    _v("refus d'entrée au bon code",
       verdict_entree(404, "PROMO_NOT_FOUND", ("PROMO_NOT_FOUND",))[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    _v("photoKey à la racine", verdict_fuite({"photoKey": "k"})[0], "echec")
    # ⚠️ Le cas fondateur : la clé était dans un objet imbriqué.
    _v("photoKeys imbriqué",
       verdict_fuite({"items": [{"promo": {"photoKeys": ["k"]}}]})[0], "echec")
    _v("thumbnailKey profond",
       verdict_fuite({"a": {"b": {"thumbnailKey": "k"}}})[0], "echec")
    # ⚠️ LE défaut de 2026-08-05 : retirée de la liste, servie au détail.
    _v("invisible mais servie au détail",
       verdict_accord(False, 200, False)[0], "echec")
    _v("invisible mais toujours listée",
       verdict_accord(True, 404, False)[0], "echec")
    _v("visible mais absente de la liste",
       verdict_accord(False, 200, True)[0], "echec")
    _v("visible mais détail refusé",
       verdict_accord(True, 404, True)[0], "echec")
    _v("le détail casse", verdict_accord(False, 500, False)[0], "echec")
    _v("accepté là où un refus était dû",
       verdict_entree(200, None, ("PROMO_NOT_FOUND",))[0], "echec")
    _v("500 compté comme refus",
       verdict_entree(500, "INTERNAL_ERROR", ("PROMO_NOT_FOUND",))[0], "echec")
    _v("refus au mauvais code → non concluant",
       verdict_entree(400, "AUTRE", ("PROMO_NOT_FOUND",))[0], "non_concluant")

    refus = 10
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
    cid = _exiger("COMMERCANT_ID")

    print("═" * 64)
    print("  Liste client — une seule définition de « visible », zéro fuite")
    print("═" * 64)

    st, d = appeler("POST", "/agent/login",
                    corps={"email": agent_email, "password": agent_password})
    jg = d.get("accessToken")
    if not jg:
        print("❌ connexion agent impossible (HTTP %s, %s)" % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-40s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    # ── 1. Aucune fuite ─────────────────────────────────────────────────────
    print("\n── 1. la projection publique ne porte aucun identifiant interne ──")
    ids, liste = ids_listes()
    noter("GET /promo", *verdict_fuite(liste))
    if not ids:
        noter("des promos à examiner", "non_concluant",
              "la liste est vide — la suite ne prouverait rien")
        return 1
    time.sleep(PACE)

    un = sorted(ids)[0]
    st, detail = appeler("GET", "/promo/%s" % un)
    noter("GET /promo/:id", *verdict_fuite(detail))
    time.sleep(PACE)

    # ── 2. Liste et détail disent la même chose ─────────────────────────────
    #
    # Éprouvé sur une promo qu'on fait BASCULER : c'est le seul moyen de voir
    # les deux définitions diverger, puisqu'elles ne se contredisent que sur
    # les cas limites.
    print("\n── 2. la liste et le détail servent le même ensemble ──")
    st, d = appeler("POST", "/promo/agent/%s" % cid, jg, {
        "description": "Promo du banc liste", "prixAvant": 900, "prixApres": 600,
        "categorie": "alimentation",
        "photoKeys": ["promo-photos/%s/liste.jpg" % cid]})
    pid = d.get("id")
    if not pid:
        noter("promo du banc", "non_concluant",
              "création refusée (HTTP %s, %s)" % (st, d.get("code")))
        return 1
    time.sleep(PACE)

    ids, _ = ids_listes()
    st_detail, _ = appeler("GET", "/promo/%s" % pid)
    noter("promo publiée : listée ET servie",
          *verdict_accord(pid in ids, st_detail, True))
    time.sleep(PACE)

    st, d = appeler("POST", "/promo/%s/stop" % pid, jg)
    if st not in (200, 201):
        noter("arrêt de la promo", "non_concluant",
              "HTTP %s %s — la bascule n'a pas eu lieu" % (st, d.get("code")))
        return 1
    time.sleep(PACE)

    ids, _ = ids_listes()
    st_detail, _ = appeler("GET", "/promo/%s" % pid)
    noter("promo arrêtée : ni listée NI servie",
          *verdict_accord(pid in ids, st_detail, False))
    time.sleep(PACE)

    # ── 3. Les entrées malformées ───────────────────────────────────────────
    print("\n── 3. une URL malformée se refuse, elle ne casse pas ──")
    st, d = appeler("GET", "/promo/11111111-2222-4333-8444-555555555555")
    noter("identifiant inexistant",
          *verdict_entree(st, d.get("code"), ("PROMO_NOT_FOUND",)))
    time.sleep(PACE)

    st, d = appeler("GET", "/promo/pas-un-uuid")
    noter("identifiant qui n'est pas un UUID",
          *verdict_entree(st, d.get("code"), ("VALIDATION_ERROR",)))

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
