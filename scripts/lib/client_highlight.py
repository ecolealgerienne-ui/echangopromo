#!/usr/bin/env python3
"""Banc du bandeau client — plafond, homogénéité, et globalité de la curation.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

Le pendant client de `test-admin-highlight` : celui-ci regarde la **curation**,
celui-là ce que le bandeau **sert**.

1. **Le bandeau est homogène.** `findForClient` rend soit la curation admin,
   soit le classement de repli — **jamais un mélange**. Un bandeau moitié curé
   moitié calculé signifierait que la bascule s'est faite à moitié, et
   l'admin verrait ses diapositives cohabiter avec des promos qu'il n'a pas
   choisies sans comprendre pourquoi.

2. **Chaque mode a son plafond** : 10 diapositives curées, 8 en repli. Les
   deux sont déduits du comportement, pas recopiés.

3. **La curation est GLOBALE.** Servir des communes ne doit rien changer aux
   diapositives curées — c'est une décision produit assumée
   (`ListHighlightQueryDto`) : une sélection éditoriale qui disparaîtrait selon
   le filtre du client serait incompréhensible côté admin (« je l'ai mise en
   avant et je ne la vois pas »). Cette sonde fixe l'asymétrie plutôt que de la
   laisser à la lecture du code.

4. **Aucun champ interne** — `imageKey` porte l'UUID de l'admin.

── Ce qu'il n'éprouve PAS, et pourquoi ─────────────────────────────────────

Le repli sans commune (vitrine vide depuis le 2026-08-05) n'est atteignable
qu'en désactivant toute la curation. Sur une base partagée, éteindre le bandeau
d'accueil pour une sonde coûte plus qu'elle ne rapporte — et le cas est couvert
en unitaire (`highlight.service.spec.ts`, « ne compose AUCUN repli sans
commune »).

── Usage ────────────────────────────────────────────────────────────────────

⚠️ **La sonde de globalité exige au moins une diapositive CURÉE**, et le banc
la pose lui-même avant de mesurer, puis la retire. Il l'a d'abord empruntée à
`test-admin-highlight.sh` — mauvaise idée : ce banc-là **supprime la sienne en
fin de course**, si bien que la globalité ne concluait jamais. Une dépendance
d'ordre entre bancs est invisible, vraie un jour et fausse le lendemain ; un
banc qui a besoin d'un état le construit.

Exige donc ADMIN_EMAIL / ADMIN_PASSWORD / PROMO_ID (bloc export du décor). Sans
eux il le dit et la globalité reste « non concluant » — jamais un faux vert.

    python3 scripts/lib/client_highlight.py --self-test
    ./scripts/test-client-highlight.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "0.6"))
DEVICE_ID = "banc-cli-highlight-0001"

PLAFOND_CURE = 10
PLAFOND_REPLI = 8
CHAMPS_INTERNES = ("imageKey", "photoKeys", "thumbnailKey")


def verdict_homogene(items):
    """Toutes curées, ou toutes de repli — jamais un mélange."""
    if items is None:
        return "non_concluant", "réponse illisible"
    if not items:
        return "non_concluant", "bandeau vide — rien à examiner"
    modes = {bool(i.get("curated")) for i in items}
    if len(modes) > 1:
        return ("echec",
                "bandeau MIXTE : %d curée(s) et %d de repli cohabitent — la "
                "bascule s'est faite à moitié"
                % (sum(1 for i in items if i.get("curated")),
                   sum(1 for i in items if not i.get("curated"))))
    cure = modes.pop()
    plafond = PLAFOND_CURE if cure else PLAFOND_REPLI
    if len(items) > plafond:
        return ("echec",
                "%d diapositives en mode %s, au-delà du plafond de %d"
                % (len(items), "curé" if cure else "repli", plafond))
    return "ok", "%d diapositive(s), mode %s" % (
        len(items), "curé" if cure else "repli")


def verdict_repli_suit(sans_point, avec_point):
    """Le repli calculé, lui, DOIT changer avec le point.

    Non concluant plutôt qu'échec si aucun repli n'est en jeu : quand la
    curation remplit le bandeau, il n'y a rien qui doive suivre le point.
    """
    if sans_point is None or avec_point is None:
        return "non_concluant", "une des deux réponses est illisible"
    replis_sans = {i["id"] for i in sans_point if not i.get("curated")}
    replis_avec = {i["id"] for i in avec_point if not i.get("curated")}
    if not replis_sans and not replis_avec:
        return ("non_concluant",
                "aucun repli des deux côtés — la curation remplit le bandeau, "
                "il n'y a rien qui doive suivre le point")
    if replis_sans == replis_avec:
        return ("echec",
                "le repli est IDENTIQUE à 1500 km de distance (%d diapo(s)) — "
                "le point n'est pas pris en compte, et la sonde de globalité "
                "ne prouve alors plus rien" % len(replis_sans))
    return "ok", "%d → %d diapo(s) de repli, le cadrage bouge" % (
        len(replis_sans), len(replis_avec))


def verdict_globalite(sans_point, avec_point):
    """La curation ne dépend pas du point de recherche du client.

    ⚠️ **Cette sonde interrogeait `?communeIds=` jusqu'au 2026-08-12**, et ce
    paramètre n'existe plus. `ValidationPipe({ whitelist: true })` retire en
    silence tout paramètre inconnu : les deux réponses seraient devenues
    identiques **parce qu'on n'avait rien demandé**, et le banc aurait conclu
    « la curation ne dépend pas de la commune » sans avoir fait varier quoi que
    ce soit. Vert pour la mauvaise raison, indéfiniment — le mode de panne que
    la règle #28 vise.
    """
    if sans_point is None or avec_point is None:
        return "non_concluant", "une des deux réponses est illisible"
    if not sans_point and not avec_point:
        return "non_concluant", "les deux bandeaux sont vides"
    cures_sans = {i["id"] for i in sans_point if i.get("curated")}
    cures_avec = {i["id"] for i in avec_point if i.get("curated")}
    if not cures_sans and not cures_avec:
        return ("non_concluant",
                "aucune diapositive curée — la globalité ne porte que sur "
                "elles, le repli suit le point par conception")
    if cures_sans != cures_avec:
        manquantes = sorted(cures_sans - cures_avec)
        return ("echec",
                "la curation change avec le point : %d diapositive(s) "
                "disparaissent (ex. %s) — l'admin ne comprendrait pas "
                "pourquoi sa mise en avant s'évapore"
                % (len(manquantes) or len(cures_avec - cures_sans),
                   (manquantes or sorted(cures_avec - cures_sans))[0][:8]))
    return "ok", "%d curée(s), identiques des deux côtés" % len(cures_sans)


def verdict_fuite(corps):
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


# ─────────────────────────────────────────────────────────────────────────────

def appeler_ecrire(methode, chemin, jeton=None, corps=None):
    """Variante authentifiée — le banc pose puis retire sa propre curation."""
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


def appeler(chemin):
    req = urllib.request.Request(API_URL + chemin, method="GET")
    req.add_header("X-Device-Id", DEVICE_ID)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read())
        except Exception:
            return e.code, {}
    except Exception as e:
        return None, {"code": "RESEAU: %s" % e}


_ok = 0
_echecs = []


def _v(libelle, obtenu, attendu):
    global _ok
    if obtenu == attendu:
        _ok += 1
    else:
        _echecs.append("%s — attendu %r, obtenu %r" % (libelle, attendu, obtenu))


def self_test():
    cure = [{"id": "h%d" % i, "curated": True} for i in range(3)]
    repli = [{"id": "a%d" % i, "curated": False} for i in range(3)]

    # ── Doivent PASSER ───────────────────────────────────────────────────────
    _v("bandeau curé homogène", verdict_homogene(cure)[0], "ok")
    _v("bandeau de repli homogène", verdict_homogene(repli)[0], "ok")
    _v("curation identique", verdict_globalite(cure, cure)[0], "ok")
    # Le repli DOIT bouger avec le point : deux ensembles différents = ok.
    _v("le repli change avec le point",
       verdict_repli_suit(repli, [{"id": "z", "curated": False}])[0], "ok")
    _v("projection propre",
       verdict_fuite({"items": [{"imageUrl": "u"}]})[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le mélange : la bascule curation/repli s'est faite à moitié.
    _v("bandeau mixte", verdict_homogene(cure + repli)[0], "echec")
    _v("plafond curé dépassé",
       verdict_homogene([{"id": str(i), "curated": True}
                         for i in range(11)])[0], "echec")
    _v("plafond de repli dépassé",
       verdict_homogene([{"id": str(i), "curated": False}
                         for i in range(9)])[0], "echec")
    _v("bandeau vide → non concluant", verdict_homogene([])[0], "non_concluant")
    # ⚠️ La curation qui suit la commune : décision produit inversée en silence.
    _v("curation qui change avec la commune",
       verdict_globalite(cure, cure[:1])[0], "echec")
    _v("aucune curée → non concluant",
       verdict_globalite(repli, repli)[0], "non_concluant")
    # ⚠️ LE cas qui rattrape un serveur ignorant le paramètre : il rendrait la
    # même chose partout, ce qui satisfait `verdict_globalite` mais ne prouve
    # rien. Sans ce refus, on prouverait l'immobilité en croyant prouver la
    # globalité (règle #38).
    _v("repli identique à 1500 km → le point est ignoré",
       verdict_repli_suit(repli, repli)[0], "echec")
    _v("aucun repli des deux côtés → non concluant",
       verdict_repli_suit(cure, cure)[0], "non_concluant")
    _v("imageKey exposé",
       verdict_fuite({"items": [{"imageKey": "k"}]})[0], "echec")

    refus = 9
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


def main():
    print("═" * 64)
    print("  Bandeau client — plafond, homogénéité, globalité de la curation")
    print("═" * 64)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-40s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    print("\n── 1. sans commune ──")
    st, sans = appeler("/highlight")
    if st != 200:
        noter("GET /highlight", "non_concluant",
              "HTTP %s %s" % (st, sans.get("code")))
        return 1
    noter("bandeau homogène et sous plafond", *verdict_homogene(sans.get("items")))
    noter("aucun champ interne", *verdict_fuite(sans))
    time.sleep(PACE)

    # ── La curation, posée PAR CE BANC ────────────────────────────────────
    #
    # ⚠️ **Sans elle, la sonde de globalité ne peut rien conclure**, et un banc
    # qui ne conclut pas ne mesure pas. Le décor n'en fournit aucune, et
    # `admin_highlight.py` supprime la sienne en fin de course — s'appuyer sur
    # lui aurait été une dépendance d'ordre invisible, vraie un jour et fausse
    # le lendemain. Un banc qui a besoin d'un état le construit.
    hid = None
    ja = None
    admin_email = os.environ.get("ADMIN_EMAIL")
    admin_password = os.environ.get("ADMIN_PASSWORD")
    promo_id = os.environ.get("PROMO_ID")
    if admin_email and admin_password and promo_id:
        _, d = appeler_ecrire("POST", "/admin/login", corps={
            "email": admin_email, "password": admin_password})
        ja = d.get("accessToken")
        if ja:
            _, d = appeler_ecrire("POST", "/admin/highlight", ja, {
                "promoId": promo_id,
                "imageKey": "highlight-images/banc/diapo.jpg",
                "titre": "Banc bandeau", "sousTitre": "curation du banc",
                "active": True})
            hid = d.get("id")
            time.sleep(PACE)
    if hid is None:
        print("  ⓘ  curation impossible a poser — la globalite ne conclura pas")

    print("\n── 2. avec un point de recherche ──")
    # ⚠️ Un point VOLONTAIREMENT loin du décor (Tamanrasset, ~1500 km), pour que
    # la variation soit réelle. Un point voisin rendrait le même repli que sans
    # point, et la sonde ne distinguerait plus « la curation est globale » de
    # « rien n'a changé parce que rien n'a bougé ».
    # ⚠️ On relit « sans point » APRÈS la pose : sinon la comparaison porte
    # sur une photo d'avant la curation — deux états du serveur au lieu de
    # deux cadrages (règle #38 : mesurer au plus près du geste).
    _, sans = appeler("/highlight")
    st, avec = appeler("/highlight?latitude=22.785&longitude=5.523&radiusKm=5")
    if st != 200:
        noter("GET /highlight avec un point", "non_concluant",
              "HTTP %s %s" % (st, avec.get("code")))
        return 1
    # ⚠️ **Pas d'homogénéité ici.** Le point est volontairement à 1500 km du
    # décor : le bandeau y est vide, et demander « est-il homogène ? » à un
    # bandeau vide ne peut rendre qu'un « je ne sais pas ». Une sonde qui ne
    # peut pas conclure là où on l'a placée n'est pas une sonde prudente,
    # c'est une sonde mal placée — l'homogénéité est déjà éprouvée en §1, sur
    # un bandeau qui a du contenu.
    noter("la curation ne dépend pas du point",
          *verdict_globalite(sans.get("items"), avec.get("items")))
    # ⚠️ La contrepartie, et c'est elle qui donne son sens à la sonde
    # précédente : le REPLI, lui, DOIT suivre le point. Prise seule, la
    # globalité est satisfaite par un serveur qui IGNORE le paramètre — il
    # rendrait la même chose partout. On prouverait l'immobilité en croyant
    # prouver la globalité (règle #38).
    noter("le repli, lui, suit le point",
          *verdict_repli_suit(sans.get("items"), avec.get("items")))

    # ── Nettoyage : ne rien laisser derrière soi ─────────────────────────
    if hid and ja:
        appeler_ecrire("DELETE", "/admin/highlight/%s" % hid, ja)

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
