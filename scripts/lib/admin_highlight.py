#!/usr/bin/env python3
"""Banc du bandeau « Top promos » — curation admin et projection client.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

Le module a été livré fin juillet 2026 et **jamais éprouvé de bout en bout**.
Trois règles y ont déjà produit un défaut réel, et ce sont celles-ci qu'on
sonde — pas « couvrons le module ».

1. **La projection publique n'expose pas `imageKey`.** Cette clé contient
   l'UUID de l'admin qui a importé le visuel. Le défaut fondateur est le même
   qu'ailleurs dans ce dépôt : un `{...entity}` transforme l'instance en objet
   plain et **désactive silencieusement les `@Exclude()`** (règle 4). Le
   contrôleur a donc un DTO de sortie explicite — encore faut-il que quelqu'un
   le vérifie.

2. **Une diapositive dont la promo n'est plus visible disparaît du bandeau
   CLIENT, mais reste chez l'ADMIN.** L'asymétrie est voulue : c'est chez
   l'admin qu'elle est corrigeable. Son échec est invisible — le bandeau
   afficherait une promo arrêtée, et personne ne le saurait avant qu'un client
   ne clique dessus.

3. **Le réordonnancement refuse un ordre partiel ou un doublon.** Accepter
   l'un des deux laisserait deux diapositives sur la même position, donc un
   ordre non déterministe. Éprouvé en unitaire depuis juillet ; **jamais par
   HTTP**, où la validation du DTO passe avant le service.

── Ce qu'il n'éprouve PAS, et pourquoi ─────────────────────────────────────

Le plafond de 10 diapositives (`HIGHLIGHT_CAP_REACHED`) demanderait d'en créer
dix et de les nettoyer : sur une base partagée avec les autres bancs, le coût
d'un échec en cours de route (dix diapositives orphelines dans le bandeau
d'accueil) dépasse ce que la sonde rapporte. Déclaré ici plutôt que passé sous
silence — l'absence de sonde et la décision de ne pas sonder doivent rester
distinguables.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/admin_highlight.py --self-test
    ./scripts/test-admin-highlight.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.1"))
DEVICE_ID = "banc-highlight-0001"


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

# ⚠️ Champs qui ne doivent JAMAIS apparaître dans une réponse publique.
# `imageKey` porte l'UUID de l'admin ; `photoKeys` celui du commerçant ou de
# l'agent créateur. Ce sont des identifiants internes, pas des URL.
CHAMPS_INTERNES = ("imageKey", "photoKeys", "thumbnailKey")


def verdict_fuite(corps):
    """Aucun champ interne ne doit remonter dans la projection publique.

    ⚠️ La recherche est RÉCURSIVE : le défaut d'origine (`{...promo, photoUrl}`)
    exposait la clé dans un objet imbriqué, pas à la racine. Ne regarder que le
    premier niveau, c'est reproduire l'angle mort qui a créé le défaut.
    """
    trouves = sorted(set(_champs_presents(corps, CHAMPS_INTERNES)))
    if trouves:
        return "echec", "champs internes exposés : %s" % ", ".join(trouves)
    return "ok", "aucun champ interne exposé"


def _champs_presents(noeud, noms):
    if isinstance(noeud, dict):
        for cle, valeur in noeud.items():
            if cle in noms:
                yield cle
            yield from _champs_presents(valeur, noms)
    elif isinstance(noeud, list):
        for element in noeud:
            yield from _champs_presents(element, noms)


def verdict_projection(vue_client, vue_admin, hid, promo_visible):
    """La diapositive [hid] doit-elle être vue, et par qui ?

    Règle : le CLIENT ne la voit que si sa promo est visible ; l'ADMIN la voit
    toujours, parce que c'est chez lui qu'elle est corrigeable.
    """
    chez_client = hid in vue_client
    chez_admin = hid in vue_admin

    if not chez_admin:
        return ("echec",
                "l'admin ne voit plus sa propre diapositive — elle devient "
                "incorrigeable")
    if promo_visible and not chez_client:
        return "echec", "promo visible, mais la diapositive n'est pas servie au client"
    if not promo_visible and chez_client:
        return ("echec",
                "la promo n'est plus visible et la diapositive est TOUJOURS "
                "servie au client — le bandeau annonce une promo morte")
    return "ok", "client=%s admin=%s" % (chez_client, chez_admin)


def verdict_refus(statut, code, code_attendu):
    """Un refus attendu, et rien d'autre qui y ressemble."""
    if statut is None:
        return "echec", "pas de réponse : %s" % code
    if statut == 429:
        return "non_concluant", "429 — plafond de requêtes, ce n'est pas un verdict"
    if statut in (200, 201):
        return "echec", "accepté (HTTP %s) alors qu'un refus était dû" % statut
    if code != code_attendu:
        # ⚠️ Un refus au bon statut mais au mauvais code n'est PAS une réussite :
        # `VALIDATION_ERROR` signifie que la requête est morte avant la règle
        # qu'on voulait éprouver.
        return ("non_concluant",
                "refusé en %s/%s au lieu de %s — la sonde n'a pas atteint la "
                "règle visée" % (statut, code, code_attendu))
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


def ids(reponse):
    return {i["id"] for i in reponse.get("items", []) if isinstance(i, dict)}


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
    _v("projection nominale (promo visible)",
       verdict_projection({"h1"}, {"h1"}, "h1", True)[0], "ok")
    _v("projection nominale (promo morte)",
       verdict_projection(set(), {"h1"}, "h1", False)[0], "ok")
    _v("aucune fuite dans une réponse propre",
       verdict_fuite({"items": [{"id": "h1", "imageUrl": "http://x/y.jpg"}]})[0], "ok")
    _v("refus attendu reconnu",
       verdict_refus(400, "HIGHLIGHT_REORDER_MISMATCH",
                     "HIGHLIGHT_REORDER_MISMATCH")[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    _v("diapositive morte encore servie au client",
       verdict_projection({"h1"}, {"h1"}, "h1", False)[0], "echec")
    _v("diapositive vivante absente du client",
       verdict_projection(set(), {"h1"}, "h1", True)[0], "echec")
    _v("admin qui ne voit plus sa diapositive",
       verdict_projection(set(), set(), "h1", False)[0], "echec")
    _v("imageKey à la racine",
       verdict_fuite({"imageKey": "highlight-images/a/b.jpg"})[0], "echec")
    # ⚠️ Le cas fondateur : la clé était dans un objet IMBRIQUÉ.
    _v("imageKey imbriqué (le cas de la règle 4)",
       verdict_fuite({"items": [{"promo": {"photoKeys": ["x"]}}]})[0], "echec")
    _v("thumbnailKey imbriqué",
       verdict_fuite({"items": [{"a": {"b": {"thumbnailKey": "k"}}}]})[0], "echec")
    _v("acceptation là où un refus était dû",
       verdict_refus(201, None, "HIGHLIGHT_REORDER_MISMATCH")[0], "echec")
    _v("refus au mauvais code → non concluant",
       verdict_refus(400, "VALIDATION_ERROR",
                     "HIGHLIGHT_REORDER_MISMATCH")[0], "non_concluant")
    _v("429 → non concluant",
       verdict_refus(429, None, "HIGHLIGHT_REORDER_MISMATCH")[0], "non_concluant")
    _v("pas de réponse → échec",
       verdict_refus(None, "RESEAU", "X")[0], "echec")

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
    cid = _exiger("COMMERCANT_ID")

    print("═" * 64)
    print("  Bandeau « Top promos » — curation admin et projection client")
    print("═" * 64)

    st, d = appeler("POST", "/admin/login", corps={
        "email": admin_email, "password": admin_password})
    ja = d.get("accessToken")
    if not ja:
        print("❌ connexion admin impossible (HTTP %s, %s)" % (st, d.get("code")))
        print("   ⚠️ un 429 se déguise en « identifiants incorrects » : "
              "attendre une minute après le décor.")
        return 2
    time.sleep(PACE)

    st, d = appeler("POST", "/agent/login", corps={
        "email": agent_email, "password": agent_password})
    jg = d.get("accessToken")
    if not jg:
        print("❌ connexion agent impossible (HTTP %s, %s)" % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-46s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    # ── Décor propre au banc : une promo à mettre en avant ───────────────────
    #
    # ⚠️ Créée par l'AGENT, pas par le commerçant : l'agent est exempté du
    # plafond de 5 créations/24 h. Un banc qui échouerait parce qu'un autre a
    # tourné le matin n'apprendrait rien sur le bandeau.
    print("\n── décor : une promo à mettre en avant ──")
    st, d = appeler("POST", "/promo/agent/%s" % cid, jg, {
        "description": "Promo du banc highlight", "prixAvant": 800,
        "prixApres": 500, "categorie": "alimentation",
        "photoKeys": ["promo-photos/%s/highlight.jpg" % cid]})
    pid = d.get("id")
    if not pid:
        print("❌ création de la promo du banc refusée (HTTP %s, %s)"
              % (st, d.get("code")))
        return 2
    print("  ✅ promo %s" % pid)
    time.sleep(PACE)

    # ── 1. Cycle de vie d'une diapositive ────────────────────────────────────
    print("\n── 1. curation : créer, projeter, réordonner, supprimer ──")
    # ⚠️ **`imageKey` n'est pas décoratif ici : sans lui la sonde ne prouve
    # rien.** Deux gardes indépendantes écartent une diapositive côté client —
    # « sa promo n'est plus visible » (celle qu'on veut éprouver) et « il n'y a
    # plus rien à afficher ». Sur une diapositive SANS image, la seconde suffit
    # à produire le résultat attendu : le banc passait au vert alors que la
    # première était supprimée.
    #
    # Constaté par mutation le 2026-08-05 — retirer la garde de visibilité ne
    # faisait échouer aucun contrôle. Avec une image, la diapositive garde
    # quelque chose à montrer : seule la garde de visibilité peut encore la
    # retirer, et son absence se voit.
    #
    # La clé ne désigne aucun objet réel (rien ne le vérifie à la création) :
    # ce banc regarde des listes, pas des images.
    st, d = appeler("POST", "/admin/highlight", ja, {
        "promoId": pid, "imageKey": "highlight-images/banc/diapo.jpg",
        "titre": "Banc", "sousTitre": "diapositive de test", "active": True})
    hid = d.get("id")
    if not hid:
        noter("création de la diapositive", "echec",
              "HTTP %s %s" % (st, d.get("code")))
        return 1
    noter("création de la diapositive", "ok", hid)
    time.sleep(PACE)

    # ── 2. La projection publique ────────────────────────────────────────────
    _, public = appeler("GET", "/highlight")
    noter("aucun champ interne dans /highlight", *verdict_fuite(public))
    time.sleep(PACE)

    _, admin_vue = appeler("GET", "/admin/highlight", ja)
    noter("diapositive vivante : vue des deux côtés",
          *verdict_projection(ids(public), ids(admin_vue), hid, True))
    time.sleep(PACE)

    # ── 3. La règle qui casse en silence ─────────────────────────────────────
    #
    # On arrête la promo : la diapositive doit disparaître du bandeau CLIENT
    # sans disparaître de la liste ADMIN.
    print("\n── 2. la promo meurt : le client ne doit plus la voir ──")
    st, d = appeler("POST", "/promo/%s/stop" % pid, jg)
    if st not in (200, 201):
        noter("arrêt de la promo (décor)", "non_concluant",
              "HTTP %s %s — la suite ne prouverait rien" % (st, d.get("code")))
        return 1
    time.sleep(PACE)

    _, public2 = appeler("GET", "/highlight")
    _, admin2 = appeler("GET", "/admin/highlight", ja)
    noter("promo arrêtée : retirée du client, gardée chez l'admin",
          *verdict_projection(ids(public2), ids(admin2), hid, False))
    noter("aucun champ interne après la bascule", *verdict_fuite(public2))
    time.sleep(PACE)

    # ── 4. Le réordonnancement refuse ────────────────────────────────────────
    print("\n── 3. réordonnancement : deux refus attendus ──")
    st, d = appeler("POST", "/admin/highlight/reorder", ja, {"ids": [hid]})
    noter("ordre partiel refusé",
          *verdict_refus(st, d.get("code"), "HIGHLIGHT_REORDER_MISMATCH"))
    time.sleep(PACE)

    st, d = appeler("POST", "/admin/highlight/reorder", ja,
                    {"ids": [hid, hid]})
    noter("identifiant en double refusé",
          *verdict_refus(st, d.get("code"), "HIGHLIGHT_REORDER_MISMATCH"))
    time.sleep(PACE)

    # ── 5. Nettoyage, vérifié et non supposé ─────────────────────────────────
    print("\n── 4. nettoyage ──")
    appeler("DELETE", "/admin/highlight/%s" % hid, ja)
    time.sleep(PACE)
    _, apres = appeler("GET", "/admin/highlight", ja)
    if hid in ids(apres):
        noter("diapositive supprimée", "echec",
              "toujours présente après DELETE")
    else:
        noter("diapositive supprimée", "ok", "absente de la liste admin")

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
