#!/usr/bin/env python3
"""Banc du journal d'audit — une action tracée laisse-t-elle vraiment une trace ?

── Ce que ce banc éprouve ───────────────────────────────────────────────────

`AuditLogModule` est le **cas fondateur de la règle 11** : il existait, bien
conçu, depuis le premier commit du backend — et n'a **jamais tracé une seule
action**, alors que les transferts de commune et la modération, exactement ce
qu'il devait couvrir, fonctionnaient déjà. Un module non branché ne produit
aucune erreur : il produit une fausse impression de couverture, pire qu'une
absence déclarée.

D'où le seul contrôle qui compte ici : **faire l'action, puis regarder si elle
est dans le journal**. Pas « le module existe », pas « la route répond ».

Quatre règles sondées :

1. **Une action tracée laisse une trace**, avec la bonne cible.
2. **La trace nomme son auteur.** Un journal qui dit « quelqu'un a suspendu ce
   commerce » ne sert à rien le jour où l'on cherche qui.
3. **Le filtre `actorType` filtre réellement.** Un filtre qui ne filtre pas est
   de la même famille qu'un compteur qui ne compte pas : il rassure sans rien
   garantir. C'est la classe de défaut qui a frappé `countPendingModeration`.
4. **Aucun secret dans le journal.** Il est lisible par tout admin et conservé
   longtemps ; y écrire un PIN ou un jeton en ferait le pire endroit du
   système. Aujourd'hui `metadata` ne porte que des identifiants de commune —
   cette sonde est là pour que ça le reste.

⚠️ **L'ordre est vérifié, pas supposé** : deux actions sont faites dans un ordre
connu, la seconde doit précéder la première. Sans ça, la première page d'un
journal qui grossit devient inutile — et personne ne s'en aperçoit tant qu'on
ne cherche rien.

── Ce qu'il n'éprouve PAS, et pourquoi ─────────────────────────────────────

Les 14 actions tracées ne sont pas toutes jouées : `commercant_reset_pin`
changerait le PIN du décor sous les autres bancs, `revoke_own_token` couperait
la session au milieu du banc, `registre_valider` porte sur un registre déjà
validé. Deux actions suffisent à répondre à la question posée — le module
est-il branché — et le reste coûterait plus cher que ce qu'il rapporte.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/audit_log.py --self-test
    ./scripts/test-admin-audit-log.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.1"))
DEVICE_ID = "banc-audit-0001"

# ⚠️ Noms de champs qui n'ont rien à faire dans un journal lisible par tout
# admin et conservé longtemps. La liste vise le NOM, pas la valeur : chercher
# « ce qui ressemble à un PIN » attraperait des identifiants légitimes.
NOMS_SECRETS = ("pin", "password", "motdepasse", "secret", "token", "hash",
                "accesstoken", "pinhash", "passwordhash")


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_trace(entrees, action, target_id, ids_avant):
    """L'action vient d'être faite : une entrée NEUVE doit la porter.

    ⚠️ **`ids_avant` n'est pas un raffinement, c'est ce qui rend la sonde
    valide.** Sans lui, on cherchait « une entrée portant cette action » —
    et le journal en contient de toutes les exécutions passées, y compris
    celles des autres bancs qui suspendent et réactivent le même commerçant.
    La sonde passait donc au vert sur une trace vieille de plusieurs heures.

    Constaté par mutation le 2026-08-05 : en retirant l'appel `record()` de
    `commercant_reactivate`, « réactivation tracée » restait verte. Ce qui a
    signalé la mutation, c'est une AUTRE sonde (l'ordre), pour une raison sans
    rapport avec ce qu'elle mesure. Un banc peut donc détecter un défaut tout
    en ayant tort sur lequel.

    Les identifiants plutôt qu'un horodatage : aucune comparaison d'horloge,
    donc aucune tolérance à choisir, et aucune dépendance au tri — qui est
    lui-même l'objet d'une des sondes.
    """
    candidates = [e for e in entrees if e.get("action") == action]
    if not candidates:
        return ("echec",
                "aucune entrée « %s » — le module est-il branché sur cette "
                "action ? (règle 11)" % action)
    neuves = [e for e in candidates if e.get("id") not in ids_avant]
    if not neuves:
        return ("echec",
                "« %s » n'apparaît que dans des entrées ANTÉRIEURES à l'action "
                "— rien n'a été tracé cette fois (règle 11)" % action)
    bonnes = [e for e in neuves if e.get("targetId") == target_id]
    if not bonnes:
        return ("echec",
                "« %s » tracée, mais sur une autre cible que %s — la trace "
                "existe et ne dit pas quoi" % (action, target_id))
    return "ok", "%s → %s (entrée neuve)" % (action, target_id[:8])


def verdict_auteur(entree, acteur_attendu):
    """La trace doit nommer QUI a agi."""
    if entree is None:
        return "non_concluant", "pas d'entrée à examiner"
    if not entree.get("actorId"):
        return "echec", "trace sans actorId — le journal ne dit pas qui a agi"
    if entree.get("actorType") != acteur_attendu:
        return ("echec", "actorType=%r, attendu %r"
                % (entree.get("actorType"), acteur_attendu))
    return "ok", "%s %s" % (entree["actorType"], entree["actorId"][:8])


def verdict_filtre(entrees, actor_type_demande):
    """Un filtre qui ne filtre pas rassure sans rien garantir."""
    intrus = sorted({e.get("actorType") for e in entrees
                     if e.get("actorType") != actor_type_demande})
    if intrus:
        return ("echec",
                "filtre actorType=%s, mais %s remonte(nt) aussi"
                % (actor_type_demande, ", ".join(map(str, intrus))))
    return "ok", "%d entrée(s), toutes %s" % (len(entrees), actor_type_demande)


def verdict_secrets(entrees):
    """Aucun nom de champ évoquant un secret, à quelque profondeur que ce soit."""
    trouves = sorted(set(_noms_suspects(entrees)))
    if trouves:
        return "echec", "champs sensibles dans le journal : %s" % ", ".join(trouves)
    return "ok", "aucun champ sensible"


def _noms_suspects(noeud):
    if isinstance(noeud, dict):
        for cle, valeur in noeud.items():
            if cle.lower().replace("_", "") in NOMS_SECRETS:
                yield cle
            yield from _noms_suspects(valeur)
    elif isinstance(noeud, list):
        for e in noeud:
            yield from _noms_suspects(e)


def verdict_ordre(entrees, action_recente, action_ancienne):
    """Le plus récent d'abord — vérifié sur deux actions d'ordre connu."""
    rangs = {}
    for i, e in enumerate(entrees):
        a = e.get("action")
        if a in (action_recente, action_ancienne) and a not in rangs:
            rangs[a] = i
    if action_recente not in rangs or action_ancienne not in rangs:
        return "non_concluant", "les deux actions ne sont pas dans la page lue"
    if rangs[action_recente] > rangs[action_ancienne]:
        return ("echec",
                "« %s » (faite après) apparaît APRÈS « %s » — la première page "
                "d'un journal qui grossit devient inutile"
                % (action_recente, action_ancienne))
    return "ok", "%s avant %s" % (action_recente, action_ancienne)


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
    entree = {"id": "e-neuve", "action": "commercant_suspend",
              "targetId": "c1", "actorType": "admin", "actorId": "a1"}
    ancienne = dict(entree, id="e-vieille")

    # ── Doivent PASSER ───────────────────────────────────────────────────────
    _v("trace présente et NEUVE",
       verdict_trace([entree], "commercant_suspend", "c1", set())[0], "ok")
    _v("auteur nommé", verdict_auteur(entree, "admin")[0], "ok")
    _v("filtre propre",
       verdict_filtre([{"actorType": "admin"}], "admin")[0], "ok")
    _v("journal sans secret",
       verdict_secrets([{"metadata": {"communeIds": ["x"]}}])[0], "ok")
    _v("ordre respecté",
       verdict_ordre([{"action": "b"}, {"action": "a"}], "b", "a")[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le cas fondateur (règle 11) : l'action a eu lieu, le journal est vide.
    _v("action non tracée",
       verdict_trace([], "commercant_suspend", "c1", set())[0], "echec")
    _v("trace sur la mauvaise cible",
       verdict_trace([entree], "commercant_suspend", "AUTRE", set())[0], "echec")
    # ⚠️ LE cas trouvé par mutation : le journal contient bien cette action,
    # mais uniquement dans des entrées d'exécutions précédentes.
    _v("seulement des traces ANCIENNES",
       verdict_trace([ancienne], "commercant_suspend", "c1",
                     {"e-vieille"})[0], "echec")
    _v("trace anonyme",
       verdict_auteur({"actorType": "admin", "actorId": ""}, "admin")[0], "echec")
    _v("mauvais type d'acteur",
       verdict_auteur({"actorType": "agent", "actorId": "a1"}, "admin")[0], "echec")
    _v("filtre qui ne filtre pas",
       verdict_filtre([{"actorType": "admin"}, {"actorType": "agent"}],
                      "agent")[0], "echec")
    _v("PIN dans les métadonnées",
       verdict_secrets([{"metadata": {"pin": "1234"}}])[0], "echec")
    _v("secret imbriqué profond",
       verdict_secrets([{"a": {"b": {"passwordHash": "x"}}}])[0], "echec")
    _v("ordre inversé",
       verdict_ordre([{"action": "a"}, {"action": "b"}], "b", "a")[0], "echec")
    _v("actions absentes de la page → non concluant",
       verdict_ordre([{"action": "z"}], "b", "a")[0], "non_concluant")
    _v("pas d'entrée à examiner → non concluant",
       verdict_auteur(None, "admin")[0], "non_concluant")

    refus = 11
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
    cid = _exiger("COMMERCANT_ID")

    print("═" * 64)
    print("  Journal d'audit — une action tracée laisse-t-elle une trace ?")
    print("═" * 64)

    st, d = appeler("POST", "/admin/login",
                    corps={"email": admin_email, "password": admin_password})
    ja = d.get("accessToken")
    if not ja:
        print("❌ connexion admin impossible (HTTP %s, %s)" % (st, d.get("code")))
        print("   ⚠️ un 429 se déguise en « identifiants incorrects ».")
        return 2
    time.sleep(PACE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-42s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    # ── Deux actions, dans un ordre connu ───────────────────────────────────
    #
    # Suspendre puis réactiver : l'état du décor est restauré à la fin, et
    # l'ordre des deux est certain — ce qui permet d'éprouver le tri sans
    # dépendre de ce qui traîne déjà dans le journal.
    print("\n── 1. deux actions tracées, dans un ordre connu ──")
    # ⚠️ Relevé AVANT d'agir : c'est lui qui distingue une trace posée
    # maintenant d'une trace laissée par une exécution précédente. Le journal
    # est cumulatif, et les autres bancs suspendent le même commerçant.
    _, avant = appeler("GET", "/admin/audit-log?limit=100", ja)
    ids_avant = {e.get("id") for e in avant.get("items", [])}
    time.sleep(PACE)

    st, d = appeler("POST", "/admin/commercant/%s/suspend" % cid, ja,
                    {"reason": "banc audit"})
    if st not in (200, 201):
        noter("suspension", "non_concluant",
              "HTTP %s %s — rien à tracer" % (st, d.get("code")))
        return 1
    time.sleep(PACE)
    st, d = appeler("POST", "/admin/commercant/%s/reactivate" % cid, ja)
    if st not in (200, 201):
        noter("réactivation", "non_concluant",
              "HTTP %s %s — le décor reste suspendu !" % (st, d.get("code")))
        return 1
    noter("suspension puis réactivation", "ok", "décor restauré")
    time.sleep(PACE)

    # ── Le journal ──────────────────────────────────────────────────────────
    print("\n── 2. le journal ──")
    _, journal = appeler("GET", "/admin/audit-log?limit=100", ja)
    entrees = journal.get("items", [])
    if not entrees:
        noter("le journal répond", "echec",
              "aucune entrée — module non branché ? (règle 11)")
        return 1

    noter("suspension tracée",
          *verdict_trace(entrees, "commercant_suspend", cid, ids_avant))
    noter("réactivation tracée",
          *verdict_trace(entrees, "commercant_reactivate", cid, ids_avant))

    recente = next((e for e in entrees
                    if e.get("action") == "commercant_reactivate"
                    and e.get("id") not in ids_avant), None)
    noter("la trace nomme son auteur", *verdict_auteur(recente, "admin"))
    noter("le plus récent d'abord",
          *verdict_ordre(entrees, "commercant_reactivate", "commercant_suspend"))
    noter("aucun secret dans le journal", *verdict_secrets(entrees))
    time.sleep(PACE)

    # ── Le filtre ───────────────────────────────────────────────────────────
    print("\n── 3. le filtre actorType ──")
    _, filtre = appeler("GET", "/admin/audit-log?limit=100&actorType=agent", ja)
    noter("actorType=agent ne rend que des agents",
          *verdict_filtre(filtre.get("items", []), "agent"))

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
