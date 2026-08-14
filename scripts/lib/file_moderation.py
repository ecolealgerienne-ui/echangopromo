#!/usr/bin/env python3
"""Banc de la file de modération — ce que l'agent a réellement sous les yeux.

── Le trou que ce banc comble ──────────────────────────────────────────────

`GET /admin/moderation/queue` est **l'écran principal de l'agent** : c'est là
qu'arrive son travail. Deux bancs seulement la touchaient, et aucun ne regardait
ce qu'elle contient :

  · `admin_dashboard` la lit pour comparer que l'admin et l'agent voient la
    **même chose** — une égalité, vraie même si les deux voient une liste
    fausse ;
  · `pentest_dynamique` y envoie une sonde d'autorisation, qui ne lit rien.

**Une file qui rendrait toujours la même liste passerait les deux.** Personne
n'éprouvait qu'une promo signalée y ENTRE, ni qu'une promo résolue en SORTE —
c'est-à-dire la boucle de travail complète.

── L'ordre des sondes, et pourquoi il n'est pas interchangeable ────────────

On établit d'abord que la promo **existe** et qu'elle est **absente** de la
file, puis on la fait entrer, puis sortir. L'absence de départ ne vaut que
parce que l'existence est établie : « elle n'est pas dans la file » est vrai
d'une promo qui n'existe pas, d'une file vide, et d'une requête qui a échoué
(règle 28).

⚠️ Et la sortie de file se mesure **après** avoir vu l'entrée. Une file qui
n'aurait jamais rien contenu satisferait « elle n'y est plus » sans rien
prouver.

── ⚠️ Ce banc crée SA promo ────────────────────────────────────────────────

Il ne signale ni ne masque jamais une promo du décor : il la retirerait pour
tous les autres bancs et pour vos tests manuels. Il fabrique la sienne sur le
commerçant du décor, la signale, la masque, et laisse le décor intact.

── Usage ───────────────────────────────────────────────────────────────────

    python3 scripts/lib/file_moderation.py --self-test
    ./scripts/test-file-moderation.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.2"))
DEVICE_ID = "banc-file-moderation-0001"

# Trois appareils distincts : un signalement se compte par appareil, et trois
# suffisent à retirer la promo du public. On en envoie **trois** pour éprouver
# le décompte, pas un seul.
APPAREILS = ["banc-file-app-a", "banc-file-app-b", "banc-file-app-c"]


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_absente_au_depart(ids_file, pid, existe):
    """La promo neuve ne doit PAS être dans la file — et elle doit exister.

    ⚠️ Sans la seconde moitié, ce contrôle serait satisfait par une promo qui
    n'a jamais été créée, par une file vide, et par une requête en échec
    (règle 28 : une absence ne vaut qu'après une présence établie).
    """
    if ids_file is None:
        return "non_concluant", "file illisible"
    if not existe:
        return ("non_concluant",
                "la promo n'existe pas côté public : son absence de la file "
                "ne prouverait rien")
    if pid in ids_file:
        return ("echec",
                "une promo qui n'a reçu aucun signalement est déjà dans la "
                "file de modération — l'agent traite du bruit")
    return "ok", "absente de la file, et bien servie au public"


def verdict_seuil_non_atteint(ids_file, pid, nb_signalements):
    """⚠️ **Le seuil est de TROIS appareils distincts**, et il se mesure.

    Un signalement isolé ne doit créer aucun travail : sinon `POST /report` — la
    route publique protégée par un simple en-tête déclaratif — deviendrait un
    moyen de noyer la file de l'agent avec trois requêtes (règle 7).

    Ce banc a commencé par exiger l'entrée dès le PREMIER signalement, et il a
    rendu rouge sur un produit correct. C'était la règle 38 dans le banc même :
    une contre-mesure sur une prémisse fausse accuse le produit.
    """
    if ids_file is None:
        return "non_concluant", "file illisible"
    if pid in ids_file:
        return ("echec",
                "%d signalement(s) suffisent à faire entrer une promo dans la "
                "file : le seuil de trois appareils distincts ne tient plus, "
                "et trois requêtes suffisent à noyer le travail de l'agent"
                % nb_signalements)
    return "ok", "%d signalement(s) : toujours hors file, seuil tenu" % (
        nb_signalements,)


def verdict_entre_dans_la_file(ids_file, pid, nb_signalements):
    """⚠️ **La sonde centrale** : un signalement fait entrer la promo.

    Si elle n'entre pas, le signalement d'un client ne produit **aucun travail
    visible** — il disparaît, et personne ne s'en aperçoit.
    """
    if ids_file is None:
        return "non_concluant", "file illisible"
    if pid not in ids_file:
        return ("echec",
                "%d signalement(s) envoyé(s) et la promo n'est PAS dans la "
                "file : le signalement d'un client ne produit aucun travail, "
                "et rien ne le signale" % nb_signalements)
    return "ok", "entrée dans la file après %d signalement(s)" % nb_signalements


def verdict_decompte(observe, attendu):
    """Le nombre de signalements actifs affiché doit être le vrai.

    ⚠️ C'est ce chiffre qui fait décider l'agent : masquer ou vérifier-ok. Un
    décompte faux ne lève rien et oriente toutes les décisions.
    """
    if observe is None:
        return "non_concluant", "activeReportCount absent de la réponse"
    if observe != attendu:
        return ("echec",
                "la file annonce %d signalement(s), il y en a %d — c'est ce "
                "chiffre qui fait décider l'agent" % (observe, attendu))
    return "ok", "%d signalements, comptés juste" % observe


def verdict_sort_de_la_file(ids_file, pid, etait_dedans):
    """Une promo résolue doit QUITTER la file.

    ⚠️ `etait_dedans` n'est pas décoratif : si elle n'y était jamais entrée,
    « elle n'y est plus » est vrai sans que la résolution ait rien fait
    (règle 38).
    """
    if ids_file is None:
        return "non_concluant", "file illisible"
    if not etait_dedans:
        return ("non_concluant",
                "la promo n'était pas dans la file avant la résolution : sa "
                "sortie ne prouverait rien")
    if pid in ids_file:
        return ("echec",
                "la promo masquée est TOUJOURS dans la file : le travail "
                "résolu revient indéfiniment, et deux agents se marchent "
                "dessus sur la même promo")
    return "ok", "sortie de la file après résolution"


def verdict_file_lisible(reponse):
    """La file doit porter les champs sur lesquels l'écran agent s'appuie."""
    if reponse is None:
        return "non_concluant", "aucune réponse"
    items = reponse.get("items")
    if items is None:
        return "echec", "la réponse ne porte pas d'« items »"
    if not items:
        return ("non_concluant",
                "file vide — les champs ne peuvent pas être vérifiés")
    manquants = [c for c in ("id", "activeReportCount", "reasonBreakdown")
                 if c not in items[0]]
    if manquants:
        return ("echec",
                "champs absents de la file : %s — l'écran de l'agent ne peut "
                "pas afficher de quoi décider" % ", ".join(manquants))
    return "ok", "id, activeReportCount et reasonBreakdown servis"


# ─────────────────────────────────────────────────────────────────────────────

def appeler(methode, chemin, jeton=None, corps=None, device=None):
    donnees = json.dumps(corps).encode() if corps is not None else None
    req = urllib.request.Request(API_URL + chemin, data=donnees, method=methode)
    req.add_header("Content-Type", "application/json")
    req.add_header("X-Device-Id", device or DEVICE_ID)
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
    pleine = {"p1", "p2"}

    # ── Doivent PASSER ───────────────────────────────────────────────────────
    _v("absente au départ",
       verdict_absente_au_depart({"autre"}, "p1", True)[0], "ok")
    _v("entre au 3e signalement",
       verdict_entre_dans_la_file(pleine, "p1", 3)[0], "ok")
    # ⚠️ Le seuil : un signalement isolé laisse la promo hors file.
    _v("seuil tenu à 1",
       verdict_seuil_non_atteint({"autre"}, "p1", 1)[0], "ok")
    _v("décompte juste", verdict_decompte(3, 3)[0], "ok")
    _v("sort après résolution",
       verdict_sort_de_la_file({"p2"}, "p1", True)[0], "ok")
    _v("file lisible",
       verdict_file_lisible({"items": [{"id": "p1", "activeReportCount": 1,
                                        "reasonBreakdown": {}}]})[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le défaut visé : un signalement qui ne produit aucun travail.
    _v("n'entre jamais",
       verdict_entre_dans_la_file({"autre"}, "p1", 3)[0], "echec")
    # ⚠️ Le défaut visé : le travail résolu revient indéfiniment.
    _v("ne sort jamais",
       verdict_sort_de_la_file(pleine, "p1", True)[0], "echec")
    _v("bruit dans la file",
       verdict_absente_au_depart(pleine, "p1", True)[0], "echec")
    _v("décompte faux", verdict_decompte(1, 3)[0], "echec")
    # ⚠️ Le défaut visé : trois requêtes suffiraient à noyer la file de l'agent.
    _v("seuil effondré", verdict_seuil_non_atteint(pleine, "p1", 1)[0], "echec")
    _v("champs manquants",
       verdict_file_lisible({"items": [{"id": "p1"}]})[0], "echec")
    _v("réponse sans items", verdict_file_lisible({})[0], "echec")

    # ── Doivent rester NON CONCLUANTS ────────────────────────────────────────
    # ⚠️ Une absence sur une promo inexistante ne prouve rien.
    _v("promo inexistante",
       verdict_absente_au_depart({"autre"}, "p1", False)[0], "non_concluant")
    # ⚠️ Sortir d'une file où l'on n'est jamais entré (règle 38).
    _v("jamais entrée",
       verdict_sort_de_la_file({"p2"}, "p1", False)[0], "non_concluant")
    _v("seuil illisible",
       verdict_seuil_non_atteint(None, "p1", 1)[0], "non_concluant")
    _v("file illisible au départ",
       verdict_absente_au_depart(None, "p1", True)[0], "non_concluant")
    _v("file illisible à l'entrée",
       verdict_entre_dans_la_file(None, "p1", 1)[0], "non_concluant")
    _v("file illisible à la sortie",
       verdict_sort_de_la_file(None, "p1", True)[0], "non_concluant")
    _v("décompte absent", verdict_decompte(None, 3)[0], "non_concluant")
    _v("file vide", verdict_file_lisible({"items": []})[0], "non_concluant")
    _v("aucune réponse", verdict_file_lisible(None)[0], "non_concluant")

    refus = 16
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

    print("═" * 70)
    print("  File de modération — ce que l'agent a réellement sous les yeux")
    print("═" * 70)
    print("  ⚠️ ce banc crée SA promo et la signale : il ne touche jamais")
    print("     à celle du décor, qu'il masquerait pour tous les autres")

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

    def file_moderation():
        """(ids, réponse brute) — `None` si la file est illisible."""
        st, d = appeler("GET", "/admin/moderation/queue?limit=100", jg)
        if st != 200 or d.get("items") is None:
            return None, None
        return {i.get("id") for i in d["items"]}, d

    def entree_de(pid, reponse):
        for i in (reponse or {}).get("items", []):
            if i.get("id") == pid:
                return i
        return None

    # ── La promo du banc ────────────────────────────────────────────────────
    st, d = appeler("POST", "/promo/agent/%s" % cid, jg, {
        "description": "Promo du banc de file", "prixAvant": 900,
        "prixApres": 600, "categorie": "alimentation",
        "photoKeys": ["promo-photos/%s/file.jpg" % cid]})
    pid = d.get("id")
    if not pid:
        print("❌ création refusée (HTTP %s, %s)" % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    # ── 1. Au départ : elle existe, et elle n'est pas dans la file ──────────
    print("\n── 1. une promo neuve existe et n'encombre pas la file ──")
    ids, _ = file_moderation()
    st_pub, _ = appeler("GET", "/promo/%s" % pid)
    noter("absente de la file",
          *verdict_absente_au_depart(ids, pid, st_pub == 200))
    time.sleep(PACE)

    # ── 2. Un signalement isolé ne crée aucun travail ───────────────────────
    #
    # ⚠️ Mesuré le 2026-08-13 : le seuil est de TROIS appareils distincts. Ce
    # banc exigeait d'abord l'entrée dès le premier signalement et rendait rouge
    # sur un produit correct — la règle 38 appliquée au banc lui-même.
    print("\n── 2. un signalement isolé ne crée aucun travail ──")
    appeler("POST", "/report", corps={"promoId": pid, "reason": "arnaque"},
            device=APPAREILS[0])
    time.sleep(PACE)
    ids, _ = file_moderation()
    noter("1 signalement : toujours hors file",
          *verdict_seuil_non_atteint(ids, pid, 1))
    time.sleep(PACE)

    # ── 3. Au troisième, la promo entre, et le décompte est juste ───────────
    print("\n── 3. au troisième appareil, la promo entre dans la file ──")
    for appareil in APPAREILS[1:]:
        appeler("POST", "/report", corps={"promoId": pid, "reason": "arnaque"},
                device=appareil)
        time.sleep(0.4)
    time.sleep(PACE)
    ids, brut = file_moderation()
    noter("entrée dans la file", *verdict_entre_dans_la_file(ids, pid, 3))
    entree = entree_de(pid, brut)
    noter("décompte après 3 signalements",
          *verdict_decompte(entree and entree.get("activeReportCount"), 3))
    noter("la file porte de quoi décider", *verdict_file_lisible(brut))
    etait_dedans = ids is not None and pid in ids
    time.sleep(PACE)

    # ── 4. Résolue, elle sort ───────────────────────────────────────────────
    print("\n── 4. la promo résolue quitte la file ──")
    st, d = appeler("POST", "/admin/moderation/%s/masquer" % pid, jg,
                    {"expectedModerationStatus": "signalee"})
    if st not in (200, 201):
        noter("masquage accepté", "non_concluant",
              "HTTP %s %s — sans résolution, la sortie de file n'a pas d'objet"
              % (st, d.get("code")))
        return 1
    noter("masquage accepté", "ok", "POST masquer")
    time.sleep(PACE)
    ids, _ = file_moderation()
    noter("sortie de la file",
          *verdict_sort_de_la_file(ids, pid, etait_dedans))

    print("\n" + "═" * 70)

    # ── ⚠️ Rendre le décor tel qu'on l'a trouvé ─────────────────────────────
    #
    # Ce banc crée une promo sur le commerçant du décor et ne peut pas la
    # laisser en ligne : le plafond est de 5 promos actives, et cinq bancs qui
    # font pareil ferment la porte à tous les suivants. Découvert au premier
    # lot complet du 2026-08-13 — chacun passait seul, aucun ne passait à la
    # suite des autres.
    #
    # ⚠️ Sans verdict : le nettoyage n'est pas ce que ce banc éprouve, et
    # l'échouer ferait accuser le produit pour un ménage mal fait. S'il rate,
    # c'est le banc SUIVANT qui le dira, sur un refus de plafond parfaitement
    # lisible.
    if pid:
        appeler("POST", "/promo/%s/stop" % pid, jg)

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
