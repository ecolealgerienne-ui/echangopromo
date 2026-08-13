#!/usr/bin/env python3
"""Banc des notifications — compteur, projection, et cloisonnement.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

**Module entier sans aucune couverture** jusqu'ici (T3). Quatre règles sondées,
chacune ancrée sur un défaut déjà survenu — ici ou juste à côté.

1. **Le compteur égale la file.** `GET /notifications/unread/count` doit rendre
   exactement ce que `GET /notifications/unread` contient. C'est la classe de
   défaut qui a réellement frappé `countPendingModeration` : un `getCount()`
   sur une requête groupée comptait des LIGNES là où la file comptait des
   entités, et annonçait 6 pour 2. Un compteur faux ne se voit nulle part — il
   pose un badge, et le badge a toujours l'air juste.

2. **Le cloisonnement par destinataire.** Un agent ne doit voir aucune
   notification adressée à un commerçant, et **ne doit pas pouvoir en marquer
   une comme lue**. La seconde moitié est la plus importante : lire la liste
   d'autrui est une fuite, agir dessus est un IDOR — exactement la faille
   critique de l'audit V0, où le rôle suffisait sans vérification
   d'appartenance (règle 1).

3. **`promoDescription` est servi.** Le champ a remplacé une phrase
   pré-composée le 2026-08-05 : le serveur ne compose plus de texte, il sert la
   donnée et l'app la localise. Une capacité servie sans appelant, ou un
   appelant sans capacité, ne produit aucune erreur — juste un écran vide
   (règle 31).

4. **Ni `recipientId` ni `recipientType` dans la projection.** Le contrôleur a
   un DTO de sortie explicite depuis le 2026-08-05, précisément pour ne pas
   retomber sur le `{...entity}` qui désactive les `@Exclude()` (règle 4).

── Ce qu'il n'éprouve PAS, et pourquoi ─────────────────────────────────────

La notification « expire bientôt » est posée par un cron quotidien à 1h. La
déclencher demanderait de manipuler l'horloge ou d'appeler le cron en direct —
et un banc qui appelle une méthode interne n'éprouve plus le chemin réel. Elle
reste non couverte, et c'est écrit plutôt que sous-entendu.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/notifications.py --self-test
    ./scripts/test-notifications.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.1"))
DEVICE_ID = "banc-notifications-0001"

# Champs qui ne doivent jamais quitter le serveur : ils désignent le
# destinataire, pas le contenu.
CHAMPS_INTERNES = ("recipientId", "recipientType")


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_compteur(compte, non_lues):
    """Le compteur doit égaler la file, pas s'en approcher."""
    if compte is None:
        return "non_concluant", "compteur illisible — pas de verdict"
    if compte != non_lues:
        return ("echec",
                "compteur=%d mais %d non lue(s) dans la file — un badge faux a "
                "toujours l'air juste" % (compte, non_lues))
    return "ok", "%d = %d" % (compte, non_lues)


def verdict_cloisonnement(vues_autrui, statut_action):
    """L'agent ne voit rien du commerçant, et ne peut rien y faire.

    ⚠️ Les deux moitiés comptent. Ne vérifier que la lecture laisserait passer
    un IDOR : la liste est vide, mais l'identifiant deviné reste actionnable.
    """
    if vues_autrui:
        return ("echec",
                "%d notification(s) d'un autre destinataire visibles" % vues_autrui)
    if statut_action in (200, 201):
        return ("echec",
                "marquer lue la notification d'autrui a RÉUSSI (HTTP %s) — "
                "la liste est cloisonnée, l'action ne l'est pas"
                % statut_action)
    if statut_action == 429:
        return "non_concluant", "429 sur l'action — ce n'est pas un verdict"
    if statut_action is None:
        return "echec", "pas de réponse sur l'action"
    return "ok", "liste vide, action refusée en %s" % statut_action


def verdict_champs(items, requis):
    """Les champs attendus sont là, les champs internes n'y sont pas."""
    if not items:
        return "non_concluant", "aucune notification à examiner"
    manquants = sorted({c for i in items for c in requis if c not in i})
    fuites = sorted({c for i in items for c in CHAMPS_INTERNES if c in i})
    if fuites:
        return "echec", "champs internes exposés : %s" % ", ".join(fuites)
    if manquants:
        return ("echec",
                "champs absents de la projection : %s" % ", ".join(manquants))
    return "ok", "%d champ(s) présents, aucun interne" % len(requis)


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
    _v("compteur juste", verdict_compteur(2, 2)[0], "ok")
    _v("compteur juste à zéro", verdict_compteur(0, 0)[0], "ok")
    _v("cloisonnement tenu", verdict_cloisonnement(0, 404)[0], "ok")
    _v("cloisonnement tenu (403)", verdict_cloisonnement(0, 403)[0], "ok")
    _v("champs complets",
       verdict_champs([{"id": "n1", "promoDescription": "x"}],
                      ("id", "promoDescription"))[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    _v("compteur au-dessus de la file", verdict_compteur(6, 2)[0], "echec")
    _v("compteur en dessous de la file", verdict_compteur(1, 2)[0], "echec")
    _v("compteur illisible → non concluant",
       verdict_compteur(None, 2)[0], "non_concluant")
    _v("liste d'autrui visible", verdict_cloisonnement(3, 404)[0], "echec")
    # ⚠️ Le cas fondateur : la liste est cloisonnée, l'action ne l'est pas.
    _v("action sur la notification d'autrui acceptée",
       verdict_cloisonnement(0, 201)[0], "echec")
    _v("429 sur l'action → non concluant",
       verdict_cloisonnement(0, 429)[0], "non_concluant")
    _v("champ interne exposé",
       verdict_champs([{"id": "n1", "recipientId": "u1"}], ("id",))[0], "echec")
    _v("champ attendu absent",
       verdict_champs([{"id": "n1"}], ("id", "promoDescription"))[0], "echec")
    _v("rien à examiner → non concluant",
       verdict_champs([], ("id",))[0], "non_concluant")

    refus = 9
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

    print("═" * 64)
    print("  Notifications — compteur, projection, cloisonnement")
    print("═" * 64)

    def connecter(chemin, corps, qui):
        st, d = appeler("POST", chemin, corps=corps)
        jeton = d.get("accessToken")
        if not jeton:
            print("❌ connexion %s impossible (HTTP %s, %s)"
                  % (qui, st, d.get("code")))
            print("   ⚠️ un 429 se déguise en « identifiants incorrects » : "
                  "attendre une minute après le décor.")
            sys.exit(2)
        time.sleep(PACE)
        return jeton

    ja = connecter("/admin/login",
                   {"email": admin_email, "password": admin_password}, "admin")
    jg = connecter("/agent/login",
                   {"email": agent_email, "password": agent_password}, "agent")
    jc = connecter("/commercant/login",
                   {"telephone": tel, "pin": pin}, "commerçant")

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-44s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    # ── Décor : on part d'une ardoise propre ────────────────────────────────
    #
    # ⚠️ `read-all` d'abord. Sans ça le compteur partirait d'un état inconnu —
    # hérité d'un autre banc, d'une exécution précédente — et « le compteur
    # égale la file » deviendrait vrai par accident aussi souvent que par
    # justesse.
    print("\n── décor : ardoise remise à zéro ──")
    appeler("POST", "/notifications/read-all", jc)
    time.sleep(PACE)
    _, d = appeler("GET", "/notifications/unread/count", jc)
    if d.get("count") != 0:
        noter("remise à zéro", "non_concluant",
              "compteur = %r après read-all — la suite ne prouverait rien"
              % d.get("count"))
        return 1
    noter("remise à zéro", "ok", "0 non lue")
    time.sleep(PACE)

    # Une promo à modérer — créée par l'agent (exempté du plafond quotidien).
    st, d = appeler("POST", "/promo/agent/%s" % cid, jg, {
        "description": "Promo du banc notifications", "prixAvant": 700,
        "prixApres": 400, "categorie": "alimentation",
        "photoKeys": ["promo-photos/%s/notif.jpg" % cid]})
    pid = d.get("id")
    if not pid:
        print("❌ création de la promo du banc refusée (HTTP %s, %s)"
              % (st, d.get("code")))
        return 2
    noter("promo du banc", "ok", pid)
    time.sleep(PACE)

    # ── Deux notifications, par deux actions de modération distinctes ───────
    print("\n── 1. deux actions de modération, deux notifications ──")
    # ⚠️ `expectedModerationStatus` est **obligatoire** depuis le 2026-08-13
    # (garde de course, voir `ResolveModerationDto`). Ce banc a été le seul des
    # quatre appelants à ne pas être mis à jour dans le même commit : il rendait
    # `VALIDATION_ERROR`, donc « non concluant » — il n'a accusé personne, mais
    # il ne mesurait plus rien.
    #
    # ⚠️ **Le `{"reason": ...}` qu'il envoyait était jeté en silence** par
    # `whitelist: true` : les trois routes ne prenaient aucun corps. Il est
    # retiré plutôt que gardé — un champ qu'on croit envoyer et que personne ne
    # lit est pire qu'un champ absent.
    #
    # Les deux actions partent de `normale` : la promo vient d'être créée, et
    # `avertir` remet `moderationStatus` à `normale` (c'est le retour en
    # brouillon qui porte la sanction, pas le masque).
    for action, attendu in (("avertir", "normale"), ("verifier-ok", "normale")):
        st, d = appeler("POST", "/admin/moderation/%s/%s" % (pid, action), ja,
                        {"expectedModerationStatus": attendu})
        if st not in (200, 201):
            noter("modération : %s" % action, "non_concluant",
                  "HTTP %s %s — pas de notification à examiner"
                  % (st, d.get("code")))
            return 1
        time.sleep(PACE)
    noter("deux actions de modération", "ok", "avertir + verifier-ok")

    # ── 2. Le compteur égale la file ───────────────────────────────────────
    _, liste = appeler("GET", "/notifications/unread?limit=100", jc)
    items = liste.get("items", [])
    _, compte = appeler("GET", "/notifications/unread/count", jc)
    noter("le compteur égale la file",
          *verdict_compteur(compte.get("count"), len(items)))
    time.sleep(PACE)

    # ── 3. La projection ───────────────────────────────────────────────────
    noter("projection : champs servis, aucun interne",
          *verdict_champs(items, ("id", "type", "message", "promoId",
                                  "promoDescription", "createdAt")))

    # ── 4. Le cloisonnement ────────────────────────────────────────────────
    print("\n── 2. cloisonnement : l'agent ne voit ni n'agit ──")
    _, vue_agent = appeler("GET", "/notifications?limit=100", jg)
    ids_commercant = {i["id"] for i in items}
    fuites = len([i for i in vue_agent.get("items", [])
                  if i.get("id") in ids_commercant])
    st_action = None
    if items:
        st_action, _ = appeler("POST", "/notifications/%s/read" % items[0]["id"],
                               jg)
    noter("l'agent ne voit ni ne marque celles du commerçant",
          *verdict_cloisonnement(fuites, st_action))
    time.sleep(PACE)

    # ── 5. Marquer lue : vérifié par l'ÉTAT ────────────────────────────────
    print("\n── 3. marquage : vérifié par l'état, pas par le code de sortie ──")
    avant = len(items)
    if items:
        appeler("POST", "/notifications/%s/read" % items[0]["id"], jc)
        time.sleep(PACE)
    _, compte2 = appeler("GET", "/notifications/unread/count", jc)
    attendu = avant - 1
    if compte2.get("count") == attendu:
        noter("une notification marquée lue", "ok",
              "%d → %d" % (avant, attendu))
    else:
        noter("une notification marquée lue", "echec",
              "compteur = %r, attendu %d" % (compte2.get("count"), attendu))
    time.sleep(PACE)

    appeler("POST", "/notifications/read-all", jc)
    time.sleep(PACE)
    _, compte3 = appeler("GET", "/notifications/unread/count", jc)
    if compte3.get("count") == 0:
        noter("read-all remet à zéro", "ok", "0 non lue")
    else:
        noter("read-all remet à zéro", "echec",
              "compteur = %r après read-all" % compte3.get("count"))

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
