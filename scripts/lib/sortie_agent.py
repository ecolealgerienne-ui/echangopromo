#!/usr/bin/env python3
"""Banc de la sortie d'un agent — comment on arrête celui qui peut tout faire.

── Pourquoi ce banc existe, et pourquoi maintenant ─────────────────────────

Depuis le 2026-08-13, un agent agit sur **tout le parc** : les quatorze gardes
d'appartenance sont tombées avec le découpage administratif. Il n'existe plus
aucune limite *a priori* à ce qu'un agent peut faire — seulement une trace *a
posteriori* dans le journal d'audit.

La question devient donc : **comment un admin arrête-t-il un agent ?** Un départ,
un mot de passe compromis, un compte à fermer.

Mesuré sur l'entité `Agent` : elle ne porte **aucun drapeau d'activation**,
seulement `tokenVersion`. Il n'existe **aucune route de suppression d'agent**.
Restent deux gestes, et ce banc établit ce que chacun fait réellement.

── ⚠️ Le résultat qui compte : `revoke-token` n'est pas un verrou ──────────

`POST /admin/agent/:id/revoke-token` incrémente `tokenVersion` : les jetons déjà
émis deviennent invalides. **Mais le compte reste ouvert** — l'agent se
reconnecte dans la seconde avec le même mot de passe, et repart avec un jeton
neuf. C'est conforme à ce que la route promet ; ce n'est simplement pas ce
qu'on croit avoir fait en la déclenchant.

Le seul verrouillage réel est `POST /admin/agent/:id/reset-password` : il change
le secret, donc l'ancien ne fonctionne plus. Et **c'est précisément ce que
`admin_agents.py` n'éprouvait pas** — il ne vérifiait que la trace au journal,
jamais l'effet. Un `resetPassword` devenu inopérant (hachage non enregistré,
transaction annulée) aurait laissé ce banc au vert, et l'admin aurait cru avoir
fermé une porte restée ouverte.

── Ce que ce banc n'invente pas ────────────────────────────────────────────

Il **ne juge pas** que l'absence de désactivation soit un défaut : c'est une
décision produit, et `CLAUDE.md` la porte déjà comme point ouvert. Il mesure ce
qui est, et le nomme — pour que le jour où quelqu'un ajoute un vrai verrou, on
voie ce banc changer d'avis.

── ⚠️ Aucun nettoyage possible ─────────────────────────────────────────────

Il n'existe aucune route de suppression d'agent : chaque passage laisse un
compte de plus dans `/admin/agent`. Les noms portent l'heure pour rester
reconnaissables. C'est une dette du produit, pas du banc, et la taire ferait
croire à une fuite du banc.

── Usage ───────────────────────────────────────────────────────────────────

    python3 scripts/lib/sortie_agent.py --self-test
    ADMIN_EMAIL=… ADMIN_PASSWORD=… ./scripts/test-sortie-agent.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.2"))
DEVICE_ID = "banc-sortie-agent-0001"


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_premisse_connexion(statut, jeton):
    """⚠️ Établir que l'agent PEUT entrer, avant de prouver qu'on l'arrête.

    Sans cette prémisse, tout ce qui suit serait vrai d'un compte qui n'a jamais
    fonctionné (règle 38 : une contre-mesure sur une prémisse fausse accuse le
    produit).
    """
    if statut is None:
        return "non_concluant", "aucune réponse du serveur"
    if statut not in (200, 201) or not jeton:
        return ("non_concluant",
                "l'agent neuf ne peut pas se connecter (HTTP %s) — on ne "
                "mesurerait pas un verrouillage mais un compte mort" % statut)
    return "ok", "l'agent entre et reçoit un jeton"


def verdict_jeton_revoque(statut):
    """`revoke-token` doit invalider le jeton DÉJÀ ÉMIS. Ça, c'est un contrôle.

    ⚠️ Le code attendu est 401 et non « pas 200 » : un 500 ferme aussi la porte,
    mais pour une raison qu'on ne veut pas confondre avec une révocation.
    """
    if statut is None:
        return "non_concluant", "aucune réponse"
    if statut == 401:
        return "ok", "401 — le jeton émis avant la révocation ne vaut plus"
    if statut in (200, 201):
        return ("echec",
                "le jeton d'avant la révocation ouvre encore GET /agent/me : "
                "révoquer n'a rien révoqué, et un jeton volé reste exploitable")
    return ("non_concluant",
            "HTTP %s — refus pour une autre raison qu'une révocation" % statut)


def verdict_revoke_nest_pas_un_verrou(statut, jeton):
    """⚠️ **La mesure qui a motivé ce banc.**

    Après `revoke-token`, l'agent se reconnecte-t-il ? La réponse attendue est
    **oui** : la route invalide des jetons, elle ne ferme pas un compte. On
    l'établit pour que personne ne croie avoir mis un agent dehors.

    Si un jour la connexion échoue ici, ce n'est pas un échec : c'est que le
    produit a gagné un verrou, et ce banc doit être relu — d'où « non
    concluant » plutôt qu'un vert ou un rouge qui mentirait dans les deux sens.
    """
    if statut is None:
        return "non_concluant", "aucune réponse"
    if statut in (200, 201) and jeton:
        return ("ok",
                "l'agent s'est reconnecté aussitôt — révoquer un jeton "
                "N'EST PAS fermer un compte, et rien dans le produit ne le dit")
    return ("non_concluant",
            "la connexion échoue (HTTP %s) après une simple révocation : le "
            "produit a peut-être gagné un verrouillage, ce banc doit être "
            "relu avant d'être cru" % statut)


def verdict_ancien_refuse(statut, code):
    """⚠️ **Le seul verrou réel du produit**, et il doit prouver qu'il refuse.

    Après `reset-password`, l'ancien mot de passe ne doit plus ouvrir. C'est
    exactement ce que `admin_agents.py` ne vérifiait pas : il n'éprouvait que la
    trace au journal, et un `resetPassword` inopérant l'aurait laissé au vert.
    """
    if statut is None:
        return "non_concluant", "aucune réponse"
    # ⚠️ **400, et non 401** : `AgentService.login` lève une
    # `BadRequestAppException`, convention du dépôt qu'`auth_login.py` assertait
    # déjà. J'attendais 401 et ce banc a rendu « non concluant » sur un produit
    # correct — le bon comportement, mais sur un attendu faux (règle 38). On
    # juge donc sur le CODE, qui porte le sens, et on accepte les deux statuts
    # que ce sens peut prendre.
    if statut in (400, 401) and code == "AUTH_INVALID_CREDENTIALS":
        return ("ok",
                "%d AUTH_INVALID_CREDENTIALS — l'ancien secret est mort"
                % statut)
    if statut in (200, 201):
        return ("echec",
                "l'ANCIEN mot de passe ouvre encore la session : "
                "reset-password n'a rien changé, et l'admin croit avoir fermé "
                "une porte restée ouverte")
    if statut == 429:
        return ("non_concluant",
                "429 — seau d'authentification épuisé, un refus de débit "
                "n'est pas un refus d'identifiants")
    return ("non_concluant",
            "HTTP %s %s — refus pour une autre raison" % (statut, code))


def verdict_nouveau_accepte(statut, jeton):
    """Le nouveau secret doit ouvrir — sinon l'admin s'est verrouillé lui-même.

    Un `reset-password` qui ferme sans rouvrir est pire qu'inutile : le compte
    devient irrécupérable, et **il n'existe aucune route pour le supprimer**.
    """
    if statut is None:
        return "non_concluant", "aucune réponse"
    if statut in (200, 201) and jeton:
        return "ok", "le nouveau secret ouvre la session"
    return ("echec",
            "le NOUVEAU mot de passe n'ouvre pas (HTTP %s) : le compte est "
            "irrécupérable, et aucune route ne permet de le supprimer"
            % statut)


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
    _v("prémisse tenue", verdict_premisse_connexion(201, "jwt")[0], "ok")
    _v("jeton révoqué", verdict_jeton_revoque(401)[0], "ok")
    _v("révoquer ne verrouille pas",
       verdict_revoke_nest_pas_un_verrou(201, "jwt")[0], "ok")
    # ⚠️ 400 est la forme RÉELLE du dépôt (`BadRequestAppException`) ; 401 est
    # accepté pour le jour où la convention changerait — le sens est le code.
    _v("ancien secret refusé (400, réel)",
       verdict_ancien_refuse(400, "AUTH_INVALID_CREDENTIALS")[0], "ok")
    _v("ancien secret refusé (401)",
       verdict_ancien_refuse(401, "AUTH_INVALID_CREDENTIALS")[0], "ok")
    # ⚠️ Un 400 pour une AUTRE raison n'est pas un refus d'identifiants : un
    # DTO devenu invalide rendrait 400 VALIDATION_ERROR et ferait croire au
    # verrouillage alors que la connexion n'a même pas été tentée.
    _v("400 pour une autre raison",
       verdict_ancien_refuse(400, "VALIDATION_ERROR")[0], "non_concluant")
    _v("nouveau secret accepté", verdict_nouveau_accepte(201, "jwt")[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le défaut visé : révoquer n'invalide pas le jeton déjà émis.
    _v("jeton toujours valide", verdict_jeton_revoque(200)[0], "echec")
    # ⚠️ Le défaut visé : le seul verrou du produit ne verrouille pas.
    _v("ancien secret toujours bon",
       verdict_ancien_refuse(201, None)[0], "echec")
    _v("compte irrécupérable", verdict_nouveau_accepte(401, None)[0], "echec")
    _v("nouveau secret sans jeton",
       verdict_nouveau_accepte(200, None)[0], "echec")

    # ── Doivent rester NON CONCLUANTS ────────────────────────────────────────
    # ⚠️ Un compte qui n'a jamais fonctionné ne prouve aucun verrouillage.
    _v("agent mort dès la naissance",
       verdict_premisse_connexion(401, None)[0], "non_concluant")
    _v("prémisse sans réponse",
       verdict_premisse_connexion(None, None)[0], "non_concluant")
    # ⚠️ Un 429 n'est pas un refus d'identifiants (piège du parc : le seau).
    _v("seau épuisé", verdict_ancien_refuse(429, None)[0], "non_concluant")
    _v("refus pour autre chose",
       verdict_ancien_refuse(403, "FORBIDDEN")[0], "non_concluant")
    _v("révocation par un 500", verdict_jeton_revoque(500)[0], "non_concluant")
    _v("jeton sans réponse", verdict_jeton_revoque(None)[0], "non_concluant")
    # ⚠️ Si la connexion échoue APRÈS une simple révocation, le produit a
    # peut-être gagné un verrou : ni vert ni rouge, à relire.
    _v("verrou apparu",
       verdict_revoke_nest_pas_un_verrou(401, None)[0], "non_concluant")
    _v("reconnexion sans réponse",
       verdict_revoke_nest_pas_un_verrou(None, None)[0], "non_concluant")
    _v("nouveau secret sans réponse",
       verdict_nouveau_accepte(None, None)[0], "non_concluant")

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

    print("═" * 70)
    print("  Sortie d'un agent — comment on arrête celui qui peut tout faire")
    print("═" * 70)

    st, d = appeler("POST", "/admin/login",
                    corps={"email": admin_email, "password": admin_password})
    ja = d.get("accessToken")
    if not ja:
        print("❌ connexion admin impossible (HTTP %s, %s)" % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-40s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    # ── Un agent jetable, à qui on ne fera de mal qu'à lui ──────────────────
    base = time.strftime("%H%M%S")
    email = "banc-sortie-%s@echango.local" % base
    ancien = "banc-sortie-%s-un" % base
    neuf = "banc-sortie-%s-deux" % base

    st, d = appeler("POST", "/admin/agent", ja,
                    {"email": email, "password": ancien,
                     "nom": "Agent jetable du banc"})
    aid = d.get("id")
    if not aid:
        print("❌ création de l'agent jetable refusée (HTTP %s, %s)"
              % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    # ── 1. La prémisse : cet agent fonctionne ───────────────────────────────
    print("\n── 1. l'agent neuf entre bien (sans quoi rien ne se prouve) ──")
    st, d = appeler("POST", "/agent/login",
                    corps={"email": email, "password": ancien})
    jeton = d.get("accessToken")
    noter("POST /agent/login", *verdict_premisse_connexion(st, jeton))
    if not jeton:
        return 1
    time.sleep(PACE)

    # ── 2. Révoquer invalide le jeton déjà émis ─────────────────────────────
    print("\n── 2. révoquer invalide le jeton DÉJÀ émis ──")
    st, _ = appeler("GET", "/agent/me", jeton)
    if st not in (200, 201):
        noter("le jeton fonctionnait avant", "non_concluant",
              "HTTP %s — un jeton mort d'avance ne prouve aucune révocation"
              % st)
        return 1
    noter("le jeton fonctionnait avant", "ok", "GET /agent/me 200")
    time.sleep(PACE)

    appeler("POST", "/admin/agent/%s/revoke-token" % aid, ja)
    time.sleep(PACE)
    st, _ = appeler("GET", "/agent/me", jeton)
    noter("… et ne fonctionne plus après", *verdict_jeton_revoque(st))
    time.sleep(PACE)

    # ── 3. ⚠️ Mais le compte reste ouvert ───────────────────────────────────
    print("\n── 3. ⚠️ révoquer n'est PAS fermer un compte ──")
    st, d = appeler("POST", "/agent/login",
                    corps={"email": email, "password": ancien})
    jeton2 = d.get("accessToken")
    noter("l'agent se reconnecte aussitôt",
          *verdict_revoke_nest_pas_un_verrou(st, jeton2))
    time.sleep(PACE)

    # ── 4. Le seul verrou réel : changer le secret ──────────────────────────
    print("\n── 4. le seul verrouillage du produit : reset-password ──")
    st, d = appeler("POST", "/admin/agent/%s/reset-password" % aid, ja,
                    {"newPassword": neuf})
    if st not in (200, 201):
        noter("réinitialisation acceptée", "non_concluant",
              "HTTP %s %s — sans elle les deux sondes suivantes n'ont pas "
              "d'objet" % (st, d.get("code")))
        return 1
    noter("réinitialisation acceptée", "ok", "POST reset-password")
    time.sleep(PACE)

    st, d = appeler("POST", "/agent/login",
                    corps={"email": email, "password": ancien})
    noter("l'ANCIEN secret est refusé",
          *verdict_ancien_refuse(st, d.get("code")))
    time.sleep(PACE)

    st, d = appeler("POST", "/agent/login",
                    corps={"email": email, "password": neuf})
    noter("le NOUVEAU secret ouvre",
          *verdict_nouveau_accepte(st, d.get("accessToken")))

    print("\n" + "═" * 70)
    print("⚠️  L'agent « %s » reste en base : aucune route ne supprime un "
          "agent." % email)
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
