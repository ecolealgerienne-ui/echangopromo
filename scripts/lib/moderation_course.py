#!/usr/bin/env python3
"""Banc de la course de modération — deux modérateurs, une seule promo.

── Le défaut que ce banc éprouve ────────────────────────────────────────────

Les trois résolutions de modération étaient des `UPDATE … WHERE id = ?`
**inconditionnels**. Deux modérateurs sur la même promo produisaient une perte
de décision **silencieuse** :

    A masque la promo.                       → MASQUEE, retirée du public
    B, dont l'écran datait d'avant, vérifie. → VERIFIEE_OK, remise en ligne
                                               + fenêtre d'ignore de 30 jours

Les deux reçoivent `200`. Les deux gestes entrent au journal d'audit comme deux
succès indépendants. **Rien, nulle part, ne dit que la décision de A a été
annulée** — ni un écran, ni une notification, ni une ligne de journal. La promo
retirée est de nouveau publique, et protégée un mois contre les signalements
suivants.

⚠️ **Ce n'était pas théorique depuis le 2026-08-13.** La suppression du
découpage administratif a rendu la file de modération **nationale et non
partitionnée** : tous les agents du pays voient la même liste, et rien ne leur
attribue un lot. C'était le seul point du chantier « agent global » capable de
corrompre des données sans qu'aucun écran ni aucun journal ne le montre.

── Le correctif, et pourquoi ce n'est pas un verrou ────────────────────────

Chaque décision porte désormais l'état que le modérateur avait **à l'écran**
(`expectedModerationStatus`), et l'écriture est conditionnée à cet état :
`UPDATE … WHERE id = ? AND "moderationStatus" = ?`. Si personne n'est passé,
`affected = 1`. Sinon `affected = 0` et le serveur refuse en
`409 MODERATION_STATE_CHANGED`.

⚠️ Un **verrou** n'aurait rien réglé. Il sérialise, il n'arbitre pas : deux
`UPDATE` inconditionnels sérialisés s'écrasent tout aussi bien, simplement l'un
après l'autre. C'est la comparaison qui manquait, pas l'exclusion mutuelle.

── ⚠️ Ce que ce banc doit prouver DANS LES DEUX SENS ───────────────────────

Un banc qui ne montrerait que le refus serait vert sur un produit qui refuse
**tout** — c'est-à-dire sur un produit où plus aucun modérateur ne peut rien
faire. Il éprouve donc les deux polarités, et la seconde est la plus importante
parce qu'elle est celle qu'un correctif trop zélé casse (règle 38) :

1. **La course est perdue par un seul** — deux `masquer` simultanés, exactement
   un `2xx` et un `409`.
2. **La correction délibérée passe toujours** — revenir sur son propre masquage
   par un avertissement, en envoyant l'état qu'on voit (`masquee`). C'est le
   flux corrigé le 2026-08-05, et le refuser serait une régression.
3. **Une décision périmée est refusée** — le même geste avec un état qui n'est
   plus le bon.
4. **Et elle n'a rien écrit.** Le refus ne vaut que si l'état n'a pas bougé : un
   `409` rendu après avoir tout de même écrit serait le pire des deux mondes.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/moderation_course.py --self-test
    ./scripts/test-moderation-course.sh
"""

import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "2.5"))
DEVICE_ID = "banc-course-0001"
# Le seuil d'entrée en file (`MODERATION_REPORT_THRESHOLD`, plancher 2, défaut
# 3) se compte en **appareils distincts**. Un seul `X-Device-Id` répété ne fait
# jamais entrer une promo en modération, quel qu'en soit le nombre.
APPAREILS = ["banc-course-a", "banc-course-b", "banc-course-c"]


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_course(resultats):
    """Deux décisions simultanées : exactement une passe, exactement une perd.

    ⚠️ Les trois façons de se tromper, et elles sont toutes vertes ailleurs :
    - **deux succès** — c'est le défaut d'origine, la décision du premier est
      écrasée sans un mot ;
    - **deux refus** — le correctif est trop strict, plus personne ne modère ;
    - **un refus qui n'est pas le bon code** — indiscernable d'un plafond de
      requêtes ou d'une panne.
    """
    if len(resultats) != 2:
        return "non_concluant", "%d réponse(s) au lieu de 2" % len(resultats)
    if any(statut is None for statut, _ in resultats):
        return "non_concluant", "une des deux requêtes n'a pas abouti"
    if 429 in [statut for statut, _ in resultats]:
        return "non_concluant", "429 — plafond de requêtes, pas un verdict"
    succes = [s for s, _ in resultats if s in (200, 201)]
    conflits = [(s, c) for s, c in resultats
                if s == 409 and c == "MODERATION_STATE_CHANGED"]
    if len(succes) == 2:
        return ("echec",
                "les DEUX décisions ont été acceptées — la seconde a écrasé la "
                "première en silence, et personne ne l'apprendra jamais")
    if len(succes) == 0:
        return ("echec",
                "AUCUNE des deux n'est passée (%s) — un correctif qui refuse "
                "tout n'est pas un correctif"
                % ", ".join("%s/%s" % r for r in resultats))
    if len(conflits) != 1:
        return ("echec",
                "une passe, mais l'autre est refusée autrement : %s — "
                "indiscernable d'une panne ou d'un plafond"
                % ", ".join("%s/%s" % r for r in resultats))
    return "ok", "1 acceptée, 1 refusée en 409 MODERATION_STATE_CHANGED"


def verdict_acceptee(statut, code, quoi):
    """La décision prise contre l'état affiché doit passer (règle 38)."""
    if statut is None:
        return "non_concluant", "%s : pas de réponse (%s)" % (quoi, code)
    if statut == 429:
        return "non_concluant", "%s : 429, pas un verdict" % quoi
    if code == "VALIDATION_ERROR":
        return ("non_concluant",
                "%s : VALIDATION_ERROR — le corps de la sonde est en cause, "
                "pas le produit" % quoi)
    if statut in (200, 201):
        return "ok", "%s acceptée" % quoi
    if code == "MODERATION_STATE_CHANGED":
        return ("echec",
                "%s refusée en MODERATION_STATE_CHANGED alors que l'état "
                "envoyé était bien celui de la promo — la garde refuse une "
                "correction légitime" % quoi)
    return "echec", "%s : HTTP %s %s" % (quoi, statut, code or "")


def verdict_refusee(statut, code, quoi):
    """La décision prise contre un état périmé doit être refusée, et nommément."""
    if statut is None:
        return "non_concluant", "%s : pas de réponse (%s)" % (quoi, code)
    if statut == 429:
        return "non_concluant", "%s : 429, pas un verdict" % quoi
    if code == "VALIDATION_ERROR":
        return ("non_concluant",
                "%s : VALIDATION_ERROR — refusée avant la garde, le refus "
                "observé n'est pas celui qu'on mesure" % quoi)
    if statut in (200, 201):
        return ("echec",
                "%s ACCEPTÉE sur un état périmé — la course est rouverte" % quoi)
    if statut == 409 and code == "MODERATION_STATE_CHANGED":
        return "ok", "%s : 409 MODERATION_STATE_CHANGED" % quoi
    return ("echec",
            "%s refusée mais en %s/%s — un refus qu'on ne peut pas attribuer à "
            "la garde ne prouve pas qu'elle existe" % (quoi, statut, code or ""))


def verdict_contexte(entree, signalements_attendus):
    """La décision enregistre SUR QUOI elle a été prise (2026-08-13).

    ⚠️ **Le piège est un piège d'ORDRE, et il ne se voit pas dans le résultat.**
    `resolveVerifieOk` pose `verifiedOkAt = now`, et les deux requêtes qui
    comptent les signalements filtrent sur ce champ (fenêtre d'ignore de 30
    jours). Mesuré APRÈS la résolution, le contexte d'un « vérifier OK » vaut
    donc toujours **zéro signalement, aucun motif** — le journal dirait que le
    modérateur a tranché sur rien, au moment précis où il vient de trancher sur
    trois signalements. Aucune erreur, aucun champ manquant : juste un chiffre
    faux, et le seul qui compte pour un audit.

    D'où une sonde qui exige un **compte non nul**, pas seulement un champ
    présent. Un `metadata: {}` passerait le premier contrôle et raterait tout.
    """
    if entree is None:
        return "non_concluant", "pas d'entrée de journal à examiner"
    meta = entree.get("metadata")
    if meta is None:
        return ("echec",
                "aucune metadata — la décision est tracée sans ce sur quoi "
                "elle a été prise")
    compte = meta.get("signalementsActifs")
    if compte is None:
        return "echec", "metadata sans `signalementsActifs` : %r" % meta
    if compte != signalements_attendus:
        return ("echec",
                "signalementsActifs=%r, attendu %d — mesuré du mauvais côté de "
                "la résolution (voir `contexteDeDecision`)"
                % (compte, signalements_attendus))
    if not meta.get("motifs"):
        return ("echec",
                "`motifs` vide alors que %d signalement(s) sont comptés : les "
                "deux mesures ne viennent pas du même instant"
                % signalements_attendus)
    return "ok", "%d signalement(s), motifs %s" % (compte, meta.get("motifs"))


def verdict_etat(observe, attendu, quoi):
    """⚠️ Un refus ne vaut que s'il n'a rien écrit."""
    if observe is None:
        return "non_concluant", "%s : état illisible" % quoi
    if observe != attendu:
        return ("echec",
                "%s vaut %r au lieu de %r — la requête a été refusée ET a "
                "écrit : le pire des deux mondes" % (quoi, observe, attendu))
    return "ok", "%s = %r" % (quoi, attendu)


# ─────────────────────────────────────────────────────────────────────────────

def appeler(methode, chemin, jeton=None, corps=None, device=DEVICE_ID):
    donnees = json.dumps(corps).encode() if corps is not None else None
    req = urllib.request.Request(API_URL + chemin, data=donnees, method=methode)
    req.add_header("Content-Type", "application/json")
    req.add_header("X-Device-Id", device)
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
        print("❌ %s absent — lancer ./scripts/provision-decor.sh." % nom)
        sys.exit(2)
    return v


# ─────────────────────────────────────────────────────────────────────────────
# Auto-test — autant de cas qui doivent REFUSER que de cas qui passent
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
    C = "MODERATION_STATE_CHANGED"
    # ── Doivent PASSER ───────────────────────────────────────────────────────
    _v("course arbitrée", verdict_course([(201, None), (409, C)])[0], "ok")
    _v("course arbitrée, ordre inverse",
       verdict_course([(409, C), (200, None)])[0], "ok")
    _v("correction acceptée", verdict_acceptee(201, None, "avertir")[0], "ok")
    _v("périmée refusée", verdict_refusee(409, C, "verifier-ok")[0], "ok")
    _v("état inchangé", verdict_etat("normale", "normale", "statut")[0], "ok")
    _v("contexte enregistré", verdict_contexte(
        {"metadata": {"signalementsActifs": 3, "motifs": {"arnaque": 3}}},
        3)[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le défaut d'origine : deux succès, décision écrasée en silence.
    _v("deux succès", verdict_course([(201, None), (200, None)])[0], "echec")
    # ⚠️ Le sur-correctif : plus personne ne modère, et le banc serait vert
    # si l'on ne cherchait qu'un refus.
    _v("deux refus", verdict_course([(409, C), (409, C)])[0], "echec")
    # ⚠️ Un refus qu'on ne peut pas attribuer à la garde ne la prouve pas.
    _v("refus non attribuable",
       verdict_course([(201, None), (500, "INTERNAL_ERROR")])[0], "echec")
    _v("refus périmé mais mauvais code",
       verdict_refusee(400, "PROMO_NOT_FOUND", "verifier-ok")[0], "echec")
    # ⚠️ La régression que le correctif peut introduire (règle 38).
    _v("correction refusée à tort",
       verdict_acceptee(409, C, "avertir")[0], "echec")
    # ⚠️ Accepter un état périmé, c'est rouvrir la course.
    _v("périmée acceptée", verdict_refusee(200, None, "verifier-ok")[0], "echec")
    # ⚠️ Refuser ET écrire.
    _v("refusée mais écrite",
       verdict_etat("verifiee_ok", "normale", "statut")[0], "echec")
    # ⚠️ Le piège d'ORDRE : mesuré après `verifier-ok`, le contexte vaut zéro.
    # C'est un chiffre faux, pas un champ manquant — d'où une sonde qui exige
    # une VALEUR, pas seulement une présence.
    _v("contexte mesuré du mauvais côté", verdict_contexte(
        {"metadata": {"signalementsActifs": 0, "motifs": {}}}, 3)[0], "echec")
    _v("aucune metadata", verdict_contexte({"metadata": None}, 3)[0], "echec")
    _v("metadata sans le compte",
       verdict_contexte({"metadata": {"motifs": {}}}, 3)[0], "echec")
    # ⚠️ Compte juste mais motifs vides : les deux mesures ne viennent pas du
    # même instant, et une seule des deux a été prise du bon côté.
    _v("compte juste, motifs vides", verdict_contexte(
        {"metadata": {"signalementsActifs": 3, "motifs": {}}}, 3)[0], "echec")
    _v("pas d'entrée → non concluant",
       verdict_contexte(None, 3)[0], "non_concluant")
    # ⚠️ Les indéterminés ne sont jamais des réussites.
    _v("429 → non concluant", verdict_course([(429, None), (201, None)])[0],
       "non_concluant")
    _v("une seule réponse → non concluant",
       verdict_course([(201, None)])[0], "non_concluant")
    _v("validation → non concluant",
       verdict_acceptee(400, "VALIDATION_ERROR", "avertir")[0], "non_concluant")
    _v("état illisible → non concluant",
       verdict_etat(None, "normale", "statut")[0], "non_concluant")

    refus = 15
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
    print("  Course de modération — deux modérateurs, une seule promo")
    print("═" * 64)
    print("  ⚠️ ce banc crée SA promo et la signale 3 fois : il ne touche")
    print("     jamais à celle du décor, qu'il masquerait pour les autres")

    st, d = appeler("POST", "/agent/login",
                    corps={"email": agent_email, "password": agent_password})
    jg = d.get("accessToken")
    if not jg:
        print("❌ connexion agent impossible (HTTP %s, %s)" % (st, d.get("code")))
        sys.exit(2)
    time.sleep(PACE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-40s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    def statut_moderation(pid):
        st, d = appeler("GET", "/admin/promo?limit=100", jg)
        if st != 200:
            return None
        item = next((p for p in d.get("items", []) if p.get("id") == pid), None)
        return item.get("moderationStatus") if item else None

    # ── 1. Une promo à modérer, signalée jusqu'au seuil ─────────────────────
    print("\n── 1. décor : une promo signalée par trois appareils ──")
    st, d = appeler("POST", "/promo/agent/%s" % cid, jg, {
        "description": "Promo du banc de course", "prixAvant": 900,
        "prixApres": 600, "categorie": "alimentation",
        "photoKeys": ["promo-photos/%s/course.jpg" % cid]})
    pid = d.get("id")
    if not pid:
        print("❌ création refusée (HTTP %s, %s)" % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    for appareil in APPAREILS:
        appeler("POST", "/report", corps={"promoId": pid, "reason": "arnaque"},
                device=appareil)
        time.sleep(0.4)
    time.sleep(PACE)

    # ⚠️ La prémisse se vérifie (règle 38). Si la promo n'est pas SIGNALEE, la
    # course qui suit ne serait pas celle de deux modérateurs devant une file :
    # elle mesurerait autre chose, et son verdict n'aurait aucune portée.
    depart = statut_moderation(pid)
    if depart != "signalee":
        noter("la promo est en file de modération", "non_concluant",
              "statut %r au lieu de 'signalee' — seuil non atteint ? la suite "
              "ne prouverait rien" % depart)
        return 1
    noter("la promo est en file de modération", "ok", pid[:8])
    time.sleep(PACE)

    # ── 2. La course ────────────────────────────────────────────────────────
    #
    # Deux `masquer` **vraiment simultanés**, tous deux annonçant l'état qu'ils
    # ont vu (`signalee`) — exactement les deux agents devant la même file.
    print("\n── 2. deux modérateurs masquent la même promo en même temps ──")
    reponses = []
    verrou = threading.Lock()

    def masquer():
        r = appeler("POST", "/admin/moderation/%s/masquer" % pid, jg,
                    {"expectedModerationStatus": "signalee"})
        with verrou:
            reponses.append((r[0], r[1].get("code")))

    fils = [threading.Thread(target=masquer) for _ in range(2)]
    for f in fils:
        f.start()
    for f in fils:
        f.join()
    noter("une seule des deux passe", *verdict_course(reponses))
    time.sleep(PACE)
    noter("… et la promo est masquée",
          *verdict_etat(statut_moderation(pid), "masquee", "moderationStatus"))
    time.sleep(PACE)

    # ⚠️ La décision doit dire SUR QUOI elle a été prise. Trois signalements
    # d'appareils distincts ont fait entrer cette promo en file : le journal
    # doit les porter. Lu en ADMIN — l'agent n'a pas accès au journal.
    st, d = appeler("POST", "/admin/login",
                    corps={"email": _exiger("ADMIN_EMAIL"),
                           "password": _exiger("ADMIN_PASSWORD")})
    ja = d.get("accessToken")
    time.sleep(PACE)
    entree = None
    if ja:
        _, j = appeler("GET", "/admin/audit-log?limit=100", ja)
        entree = next((e for e in j.get("items", [])
                       if e.get("action") == "moderation_masquer"
                       and e.get("targetId") == pid), None)
    noter("… et le journal dit sur quoi",
          *verdict_contexte(entree, len(APPAREILS)))
    time.sleep(PACE)

    # ── 3. La correction délibérée passe toujours ───────────────────────────
    #
    # ⚠️ **C'est la sonde la plus importante du banc.** Une garde de concurrence
    # trop stricte (« on ne tranche que ce qui est SIGNALEE ») refuserait ceci,
    # et casserait le flux corrigé le 2026-08-05 : un admin qui a masqué décide
    # qu'un avertissement suffit. Il voit `masquee` à l'écran, il l'envoie, ça
    # doit passer.
    print("\n── 3. revenir sur sa propre décision reste possible ──")
    st, d = appeler("POST", "/admin/moderation/%s/avertir" % pid, jg,
                    {"expectedModerationStatus": "masquee"})
    noter("avertir depuis masquee", *verdict_acceptee(st, d.get("code"),
                                                      "avertir"))
    time.sleep(PACE)
    noter("… et le masque est levé",
          *verdict_etat(statut_moderation(pid), "normale", "moderationStatus"))
    time.sleep(PACE)

    # ── 3 bis. Le piège d'ORDRE, et il ne se déclenche QUE sur verifier-ok ──
    #
    # ⚠️ `resolveVerifieOk` pose `verifiedOkAt = now`, et les deux requêtes qui
    # comptent les signalements filtrent dessus (fenêtre d'ignore de 30 jours).
    # Mesuré du mauvais côté de la résolution, le contexte de CETTE décision
    # vaudrait `0 signalement, aucun motif` — alors que trois appareils l'ont
    # signalée. Aucune erreur, aucun champ manquant : juste le seul chiffre qui
    # compte pour un audit, et il serait faux.
    #
    # Les autres résolutions ne touchent pas `verifiedOkAt` : la sonde du § 2
    # resterait verte même en mesurant après. C'est ici, et nulle part ailleurs,
    # que l'ordre s'éprouve.
    print("\n── 3 bis. vérifier OK enregistre les signalements qu'il efface ──")
    st, d = appeler("POST", "/admin/moderation/%s/verifier-ok" % pid, jg,
                    {"expectedModerationStatus": "normale"})
    noter("verifier-ok depuis normale",
          *verdict_acceptee(st, d.get("code"), "verifier-ok"))
    time.sleep(PACE)
    entree_ok = None
    if ja:
        _, j = appeler("GET", "/admin/audit-log?limit=100", ja)
        entree_ok = next((e for e in j.get("items", [])
                          if e.get("action") == "moderation_verifier_ok"
                          and e.get("targetId") == pid), None)
    noter("… et le journal les a comptés AVANT",
          *verdict_contexte(entree_ok, len(APPAREILS)))
    time.sleep(PACE)

    # ── 4. Une décision périmée est refusée, et n'écrit rien ────────────────
    #
    # L'écran de ce modérateur-ci affiche encore `masquee` : il n'a vu ni
    # l'avertissement ni la vérification. C'est le cas exact du défaut d'origine, et le plus cher —
    # `verifier-ok` remettrait la promo en ligne ET ouvrirait une fenêtre
    # d'ignore de 30 jours.
    print("\n── 4. une décision prise sur un écran périmé est refusée ──")
    st, d = appeler("POST", "/admin/moderation/%s/verifier-ok" % pid, jg,
                    {"expectedModerationStatus": "masquee"})
    noter("verifier-ok sur un état périmé",
          *verdict_refusee(st, d.get("code"), "verifier-ok"))
    time.sleep(PACE)
    # ⚠️ Le refus ne vaut que s'il n'a rien écrit — un 409 rendu après l'UPDATE
    # laisserait la promo en VERIFIEE_OK, donc publique et protégée 30 jours,
    # tout en affichant un refus.
    noter("… et rien n'a été écrit",
          *verdict_etat(statut_moderation(pid), "verifiee_ok",
                        "moderationStatus"))

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
