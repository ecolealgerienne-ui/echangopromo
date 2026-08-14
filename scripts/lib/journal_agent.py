#!/usr/bin/env python3
"""Banc du journal d'audit côté agent — qui a fait quoi, et pas seulement quoi.

── Pourquoi ce banc existe ──────────────────────────────────────────────────

Le 2026-08-13, quatorze gardes d'appartenance ont été retirées : un agent agit
sur tout le parc. `CLAUDE.md` en tire la conséquence noir sur blanc — le journal
d'audit **« est devenu le seul contrepoids à la portée globale »**.

Ce contrepoids n'était éprouvé pour personne d'autre que l'admin.
`audit_log.py` se connecte en admin, agit en admin, et n'assertent que
`actorType == "admin"` ; son auto-test compte même une entrée `agent` comme un
échec, parce qu'il vérifie le chemin admin. **Aucun banc ne montrait qu'une
action d'agent laisse une trace.**

── ⚠️ Il y a TROIS mécanismes d'enregistrement, pas un ─────────────────────

C'est la raison d'être de ce banc, et la raison pour laquelle « le journal
marche » ne veut rien dire tant qu'on ne dit pas *lequel* :

1. `PromoController.auditStaffWrite` — **branché le 2026-08-13**, le jour même
   où les gardes sont tombées. Le plus neuf, donc le moins éprouvé.
2. `ModerationService.record` — les trois décisions de modération.
3. `AdminController`, **onze appels en ligne** à `auditLogService.record`, un par
   route destructrice.

Trois implémentations, trois endroits où l'on peut oublier `actorType`. Une
sonde par mécanisme, au minimum.

── ⚠️ Ce que ce banc éprouve VRAIMENT : l'attribution ──────────────────────

« Une entrée existe » est la partie facile. **Un journal qui dit « un agent » sans
dire *lequel* ne vaut rien quand tous les agents sont globaux** : c'est
exactement la situation créée par le chantier. Le décor porte deux agents, et
c'est ici qu'ils servent le plus — la même action, faite par A puis par B, doit
produire deux entrées portant deux `actorId` différents. Sans cette sonde, un
`actorId` figé, recopié, ou pris sur le mauvais utilisateur passerait
inaperçu : `actorType` serait juste, et le journal désignerait le mauvais
responsable.

── ⚠️ Le témoin négatif, et il est élégant ─────────────────────────────────

Un banc qui ne cherche que des traces est vert si **tout** est tracé — et un
journal qui enregistre tout n'identifie personne. `auditStaffWrite` commence
par `if (user.role === 'commercant') return;` : le commerçant qui modifie sa
propre promo ne laisse **aucune** trace.

D'où la paire au cœur du banc : **la même route, le même corps, deux acteurs**.
`PATCH /promo/:id` par l'agent doit laisser une entrée ; le même appel par le
commerçant propriétaire ne doit rien laisser. Ça prouve que la sélectivité porte
sur **l'acteur**, pas sur la route — ce qu'aucune sonde positive ne peut établir.

── ⚠️ L'agent ne peut pas lire ce journal, et c'est voulu ──────────────────

`GET /admin/audit-log` est `@Roles('admin')` **seul** : « un agent ne voit pas ce
journal, seul l'admin doit pouvoir retracer qui a fait quoi ». Ce banc agit donc
en **agent** et lit en **admin** — les deux jetons sont nécessaires, et leur
séparation est la propriété même qu'on protège. (`portee_agent.py` éprouve le
refus de lecture ; ici on éprouve ce que ce refus protège.)

── Ce que ce banc laisse derrière lui ──────────────────────────────────────

Une promo à lui, masquée puis arrêtée. Elle n'est visible de personne et
n'entre dans aucune file. Il ne touche ni au commerçant du décor (la validation
de registre qu'il rejoue est idempotente — le registre était déjà valide) ni à
sa promo.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/journal_agent.py --self-test
    ./scripts/test-journal-agent.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "2.5"))
DEVICE_ID = "banc-journal-0001"


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_trace(neuves, action, acteur_id, cible):
    """Une action d'agent laisse UNE entrée, à SON nom, sur LA bonne cible.

    ⚠️ Les quatre champs sont vérifiés ensemble et volontairement : chacun pris
    seul laisse passer un défaut réel.
    - pas d'entrée → le mécanisme n'est pas branché (règle 11, cas fondateur) ;
    - `actorType` faux → l'action est imputée à un admin, et l'agent devient
      intraçable au moment précis où il est devenu global ;
    - `actorId` faux → le journal désigne quelqu'un d'autre. **Pire que rien.**
    - `targetId` faux → la trace existe mais ne dit pas sur quoi.
    """
    candidates = [e for e in neuves if e.get("action") == action]
    if not candidates:
        actions = sorted({e.get("action") for e in neuves})
        return ("echec",
                "aucune entrée %r — le mécanisme n'enregistre pas (vu : %s)"
                % (action, ", ".join(actions) if actions else "rien"))
    if len(candidates) > 1:
        return ("non_concluant",
                "%d entrées %r pour un seul geste : impossible de dire "
                "laquelle est la nôtre" % (len(candidates), action))
    e = candidates[0]
    if e.get("actorType") != "agent":
        return ("echec",
                "actorType=%r — l'action d'un agent est imputée à autre chose, "
                "et il devient intraçable" % e.get("actorType"))
    if e.get("actorId") != acteur_id:
        return ("echec",
                "actorId=%s, attendu %s — le journal désigne le mauvais "
                "responsable, ce qui est pire que pas de journal"
                % (str(e.get("actorId"))[:8], str(acteur_id)[:8]))
    if cible is not None and e.get("targetId") != cible:
        return ("echec",
                "targetId=%s, attendu %s — la trace existe mais ne dit pas sur "
                "quoi" % (str(e.get("targetId"))[:8], str(cible)[:8]))
    return "ok", "%s par agent %s" % (action, str(acteur_id)[:8])


def verdict_aucune_trace(neuves, cible):
    """Le commerçant qui agit sur SA promo ne laisse rien (auditStaffWrite).

    ⚠️ Sans cette sonde, « il y a une entrée » serait vrai par accident sur un
    journal qui enregistre tout — et un journal qui enregistre tout n'identifie
    personne.
    """
    intruses = [e for e in neuves if e.get("targetId") == cible]
    if intruses:
        return ("echec",
                "%d entrée(s) pour un geste du COMMERÇANT (%s) — le journal "
                "n'est pas sélectif, donc « une entrée existe » ne prouve plus "
                "rien nulle part"
                % (len(intruses), ", ".join(sorted(
                    {str(e.get("action")) for e in intruses}))))
    return "ok", "aucune entrée, comme prévu"


def verdict_attribution(id_a, id_b):
    """Deux agents distincts doivent produire deux `actorId` distincts."""
    if id_a is None or id_b is None:
        return "non_concluant", "une des deux traces manque"
    if id_a == id_b:
        return ("echec",
                "les deux agents portent le MÊME actorId (%s) — le journal dit "
                "« un agent » sans dire lequel, et tous sont globaux"
                % str(id_a)[:8])
    return "ok", "A=%s ≠ B=%s" % (str(id_a)[:8], str(id_b)[:8])


def verdict_libelle(entree, champ, attendu_dans, quoi):
    """Le libellé lisible servi à côté de l'UUID (2026-08-13).

    ⚠️ **Un UUID n'est pas une trace exploitable.** L'écran affichait
    `agent 3f2a…` : personne ne retrace « qui a fait quoi » sans ouvrir la base
    à côté. C'était supportable tant que l'agent était borné ; depuis que ce
    journal est le seul contrepoids à sa portée globale, une trace illisible est
    un contrepaids qu'on croit avoir.

    ⚠️ **Le champ ABSENT et le champ NULL ne disent pas la même chose**, et cette
    sonde les sépare. Absent ⇒ le serveur ne le sert pas du tout (la
    modification n'est pas déployée). `null` ⇒ il l'a servi et n'a pas su
    résoudre — légitime pour une cible détruite, suspect pour l'acteur d'une
    action qu'on vient de faire.
    """
    if entree is None:
        return "non_concluant", "%s : pas d'entrée à examiner" % quoi
    if champ not in entree:
        return ("echec",
                "%s : `%s` n'est pas servi du tout — l'écran ne peut afficher "
                "qu'un UUID" % (quoi, champ))
    valeur = entree.get(champ)
    if valeur is None:
        return ("echec",
                "%s : libellé null pour un acteur qui vient d'agir — il existe, "
                "il n'a simplement pas été résolu" % quoi)
    if attendu_dans not in valeur:
        return ("echec",
                "%s : libellé %r, on n'y retrouve pas %r — il désigne quelqu'un "
                "d'autre, ce qui est pire qu'un UUID honnête"
                % (quoi, valeur, attendu_dans))
    return "ok", valeur


def verdict_filtre(entrees, attendu):
    """`?actorType=agent` ne doit rendre que des entrées d'agent."""
    if entrees is None:
        return "non_concluant", "journal illisible"
    if not entrees:
        return ("non_concluant",
                "aucune entrée rendue : un filtre qui ne rend rien a l'air "
                "juste, il n'a rien filtré")
    intrus = sorted({e.get("actorType") for e in entrees
                     if e.get("actorType") != attendu})
    if intrus:
        return ("echec",
                "filtre actorType=%s, mais %s remonte(nt) aussi"
                % (attendu, ", ".join(map(str, intrus))))
    return "ok", "%d entrée(s), toutes %s" % (len(entrees), attendu)


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


def _e(action="promo_create_by_staff", actor_type="agent", actor_id="A",
       target="p1"):
    return {"action": action, "actorType": actor_type, "actorId": actor_id,
            "targetId": target}


def self_test():
    # ── Doivent PASSER ───────────────────────────────────────────────────────
    _v("trace correcte",
       verdict_trace([_e()], "promo_create_by_staff", "A", "p1")[0], "ok")
    _v("trace parmi d'autres actions",
       verdict_trace([_e(action="autre"), _e()], "promo_create_by_staff",
                     "A", "p1")[0], "ok")
    _v("aucune trace pour le commerçant",
       verdict_aucune_trace([_e(target="p9")], "p1")[0], "ok")
    _v("attribution distincte", verdict_attribution("A", "B")[0], "ok")
    _v("libellé lisible",
       verdict_libelle({"actorLabel": "Agent Décor (decor-agent@echango.local)"},
                       "actorLabel", "decor-agent@echango.local", "A")[0], "ok")
    _v("filtre propre",
       verdict_filtre([{"actorType": "agent"}], "agent")[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le mécanisme non branché — règle 11, dont AuditLogModule fut le cas
    # fondateur : bien conçu, jamais appelé, et personne ne s'en apercevait.
    _v("aucune entrée",
       verdict_trace([], "promo_create_by_staff", "A", "p1")[0], "echec")
    _v("entrée d'une autre action",
       verdict_trace([_e(action="autre")], "promo_create_by_staff",
                     "A", "p1")[0], "echec")
    # ⚠️ L'agent imputé à un admin : intraçable au moment où il devient global.
    _v("actorType admin",
       verdict_trace([_e(actor_type="admin")], "promo_create_by_staff",
                     "A", "p1")[0], "echec")
    # ⚠️ Le pire cas : la trace désigne quelqu'un d'autre.
    _v("mauvais actorId",
       verdict_trace([_e(actor_id="B")], "promo_create_by_staff",
                     "A", "p1")[0], "echec")
    _v("mauvaise cible",
       verdict_trace([_e(target="p2")], "promo_create_by_staff",
                     "A", "p1")[0], "echec")
    # ⚠️ Le journal qui enregistre tout n'identifie personne.
    _v("le commerçant a laissé une trace",
       verdict_aucune_trace([_e(action="promo_update_by_staff")], "p1")[0],
       "echec")
    # ⚠️ Le journal qui dit « un agent » sans dire lequel.
    _v("même actorId pour deux agents",
       verdict_attribution("A", "A")[0], "echec")
    _v("filtre qui laisse passer",
       verdict_filtre([{"actorType": "agent"}, {"actorType": "admin"}],
                      "agent")[0], "echec")
    # ⚠️ Un filtre vide a l'air juste : il n'a rien filtré.
    _v("filtre vide → non concluant", verdict_filtre([], "agent")[0],
       "non_concluant")
    _v("journal illisible → non concluant",
       verdict_filtre(None, "agent")[0], "non_concluant")
    _v("deux entrées pour un geste → non concluant",
       verdict_trace([_e(), _e()], "promo_create_by_staff", "A", "p1")[0],
       "non_concluant")
    _v("trace manquante → non concluant",
       verdict_attribution("A", None)[0], "non_concluant")
    # ⚠️ Champ absent ≠ champ null : le premier dit « pas déployé », le second
    # « pas résolu ». Les confondre ferait passer une régression pour un cas
    # limite.
    _v("libellé non servi",
       verdict_libelle({"actorId": "x"}, "actorLabel", "@", "A")[0], "echec")
    _v("libellé null pour un acteur vivant",
       verdict_libelle({"actorLabel": None}, "actorLabel", "@", "A")[0], "echec")
    _v("libellé d'un autre",
       verdict_libelle({"actorLabel": "Agent B (b@x)"}, "actorLabel",
                       "a@x", "A")[0], "echec")
    _v("pas d'entrée → non concluant",
       verdict_libelle(None, "actorLabel", "@", "A")[0], "non_concluant")

    refus = 15
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
    tel = _exiger("COMMERCANT_TEL")
    pin = _exiger("COMMERCANT_PIN")
    cid = _exiger("COMMERCANT_ID")

    print("═" * 64)
    print("  Journal d'audit — qui a fait quoi, pas seulement quoi")
    print("═" * 64)
    print("  ⚠️ agit en AGENT, lit en ADMIN : l'agent n'a pas accès au journal")
    print("  ⚠️ laisse derrière lui une promo à lui, masquée puis arrêtée")

    def connecter(chemin, corps, qui):
        st, d = appeler("POST", chemin, corps=corps)
        j = d.get("accessToken")
        if not j:
            print("❌ connexion %s impossible (HTTP %s, %s)"
                  % (qui, st, d.get("code")))
            sys.exit(2)
        time.sleep(PACE)
        return j

    ja = connecter("/admin/login",
                   {"email": admin_email, "password": admin_password}, "admin")
    jg = connecter("/agent/login",
                   {"email": agent_email, "password": agent_password}, "agent A")
    jb = connecter("/agent/login",
                   {"email": agent_b_email, "password": agent_b_password},
                   "agent B")
    jc = connecter("/commercant/login", {"telephone": tel, "pin": pin},
                   "commerçant")

    # ⚠️ L'identité des deux agents se LIT, elle ne se devine pas : c'est elle
    # que le journal doit reproduire, et la comparer à une valeur inventée ne
    # prouverait rien.
    _, d = appeler("GET", "/agent/me", jg)
    id_a = d.get("id")
    _, d = appeler("GET", "/agent/me", jb)
    id_b = d.get("id")
    if not id_a or not id_b:
        print("❌ identité des agents illisible — rien ne serait comparable.")
        sys.exit(2)
    time.sleep(PACE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-42s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    def journal(params=""):
        st, d = appeler("GET", "/admin/audit-log?limit=100" + params, ja)
        if st != 200:
            return None
        return d.get("items", [])

    def ids(entrees):
        return {e.get("id") for e in (entrees or [])}

    def neuves_depuis(avant):
        apres = journal()
        if apres is None:
            return []
        return [e for e in apres if e.get("id") not in avant]

    # ── 1. `auditStaffWrite` — le mécanisme le plus neuf ────────────────────
    print("\n── 1. PromoController.auditStaffWrite (branché le 2026-08-13) ──")
    avant = ids(journal())
    time.sleep(PACE)
    st, d = appeler("POST", "/promo/agent/%s" % cid, jg, {
        "description": "Promo du banc journal", "prixAvant": 900,
        "prixApres": 600, "categorie": "alimentation",
        "photoKeys": ["promo-photos/%s/journal.jpg" % cid]})
    pid = d.get("id")
    if not pid:
        print("❌ création refusée (HTTP %s, %s) — rien à tracer."
              % (st, d.get("code")))
        return 2
    time.sleep(PACE)
    noter("création par agent A tracée",
          *verdict_trace(neuves_depuis(avant), "promo_create_by_staff",
                         id_a, pid))
    time.sleep(PACE)

    # ── 2. Le témoin négatif — même route, autre acteur ─────────────────────
    #
    # ⚠️ **La sonde qui donne du sens à toutes les autres.** `auditStaffWrite`
    # sort immédiatement pour un commerçant : le propriétaire qui modifie sa
    # propre promo ne laisse rien. Si le journal enregistrait tout, « une entrée
    # existe » serait vrai par accident partout ailleurs dans ce banc.
    print("\n── 2. témoin : le COMMERÇANT sur la même route ne laisse rien ──")
    avant = ids(journal())
    time.sleep(PACE)
    st, d = appeler("PATCH", "/promo/%s" % pid, jc,
                    {"description": "Modifiée par le commerçant"})
    if st not in (200, 201):
        noter("le commerçant modifie sa promo", "non_concluant",
              "HTTP %s %s — le geste n'a pas eu lieu, son absence de trace ne "
              "prouve rien (règle 38)" % (st, d.get("code")))
    else:
        time.sleep(PACE)
        noter("aucune trace pour le commerçant",
              *verdict_aucune_trace(neuves_depuis(avant), pid))
    time.sleep(PACE)

    # ── 3. La même route, par l'agent ───────────────────────────────────────
    print("\n── 3. la MÊME route, par l'agent : elle laisse une trace ──")
    avant = ids(journal())
    time.sleep(PACE)
    appeler("PATCH", "/promo/%s" % pid, jg,
            {"description": "Modifiée par l'agent"})
    time.sleep(PACE)
    noter("modification par agent A tracée",
          *verdict_trace(neuves_depuis(avant), "promo_update_by_staff",
                         id_a, pid))
    time.sleep(PACE)

    # ── 4. `ModerationService.record` ───────────────────────────────────────
    print("\n── 4. ModerationService.record ──")
    avant = ids(journal())
    time.sleep(PACE)
    appeler("POST", "/admin/moderation/%s/masquer" % pid, jg,
            {"expectedModerationStatus": "normale"})
    time.sleep(PACE)
    noter("masquage par agent A tracé",
          *verdict_trace(neuves_depuis(avant), "moderation_masquer",
                         id_a, pid))
    time.sleep(PACE)

    # ── 5. `AdminController`, en ligne ──────────────────────────────────────
    #
    # `registre/valider` est choisie parce qu'elle est **idempotente** : le
    # registre du décor est déjà validé, la rejouer ne change rien à la fiche.
    # Une sonde qui suspendrait le commerçant du décor casserait tous les bancs
    # qui le lisent.
    print("\n── 5. AdminController (11 appels en ligne) ──")
    avant = ids(journal())
    time.sleep(PACE)
    appeler("POST", "/admin/commercant/%s/registre/valider" % cid, jg)
    time.sleep(PACE)
    noter("validation de registre par agent A tracée",
          *verdict_trace(neuves_depuis(avant), "registre_valider", id_a, cid))
    time.sleep(PACE)

    # ── 6. L'attribution — la sonde qui compte le plus ──────────────────────
    #
    # ⚠️ La MÊME action, par l'autre agent. Un `actorId` figé, recopié, ou pris
    # sur le mauvais utilisateur passerait toutes les sondes ci-dessus :
    # `actorType` serait juste, et le journal désignerait le mauvais
    # responsable. Avec un seul agent, « il trace » et « il trace toujours la
    # même chose » sont indiscernables.
    print("\n── 6. deux agents, deux identités ──")
    avant = ids(journal())
    time.sleep(PACE)
    appeler("POST", "/admin/commercant/%s/registre/valider" % cid, jb)
    time.sleep(PACE)
    neuves = neuves_depuis(avant)
    noter("la même action par agent B est tracée",
          *verdict_trace(neuves, "registre_valider", id_b, cid))
    entrees_b = [e for e in neuves if e.get("action") == "registre_valider"]
    noter("… et à un autre nom que A",
          *verdict_attribution(id_a, entrees_b[0].get("actorId")
                               if entrees_b else None))
    time.sleep(PACE)

    # ── 7. Le libellé lisible — un UUID n'est pas une trace exploitable ─────
    #
    # ⚠️ Ajouté le 2026-08-13 avec `actorLabel`/`targetLabel` : l'écran
    # affichait `agent 3f2a…` et `commercant 9c11…`. On vérifie sur l'entrée
    # d'agent B qu'on vient d'obtenir — donc sur un acteur dont on connaît
    # l'e-mail par ailleurs, et pas sur une chaîne quelconque.
    print("\n── 7. le journal est lisible, pas seulement exact ──")
    entree_b = entrees_b[0] if entrees_b else None
    noter("le libellé de l'acteur nomme l'agent B",
          *verdict_libelle(entree_b, "actorLabel", agent_b_email, "acteur"))
    # La cible est le commerçant du décor : son libellé doit porter son numéro.
    noter("le libellé de la cible nomme le commerçant",
          *verdict_libelle(entree_b, "targetLabel", tel, "cible"))
    time.sleep(PACE)

    # ── 8. Le filtre ────────────────────────────────────────────────────────
    print("\n── 8. le filtre actorType=agent filtre réellement ──")
    noter("?actorType=agent", *verdict_filtre(journal("&actorType=agent"),
                                              "agent"))
    time.sleep(PACE)
    noter("?actorType=admin", *verdict_filtre(journal("&actorType=admin"),
                                              "admin"))
    time.sleep(PACE)

    # ── Rangement : la promo du banc ne reste pas en ligne ──────────────────
    appeler("POST", "/promo/%s/stop" % pid, jg)

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
