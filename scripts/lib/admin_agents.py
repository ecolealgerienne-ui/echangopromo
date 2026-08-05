#!/usr/bin/env python3
"""Banc des agents — assignation et transfert de communes, effets vérifiés.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

`PATCH /admin/agent/:id/communes` et `POST /admin/agent/transfer-communes`
**élargissent le périmètre IDOR** consommé ensuite par `assertCommuneMatches` :
tout ce qu'un agent peut faire découle de sa liste de communes. Ce sont les
deux gestes les plus lourds de conséquence de l'interface admin, et les deux
que `AuditLogModule` devait tracer depuis le premier commit sans jamais le
faire (règle 11).

Le défaut fondateur de ce banc a été trouvé le 2026-08-05, et il portait sur le
**décor**, pas sur le serveur : `provision-decor.sh` annonçait le rattachement
d'un agent sans jamais le vérifier, et agent A avait accumulé quatre communes
au fil des sessions. La leçon est générale — **l'assignation se constate, elle
ne se déclare pas** — et c'est ce que ce banc applique.

Quatre sondes :

1. **L'assignation REMPLACE, elle n'ajoute pas.** Assigner `{A}` à un agent qui
   portait `{A, B}` doit lui laisser `{A}` seul. Une sémantique d'ajout
   déguisée en remplacement fait grossir les territoires sans que personne ne
   le demande.
2. **L'état est relu APRÈS écriture**, jamais déduit du code de sortie.
3. **Le transfert déplace : il retire à l'un ce qu'il donne à l'autre.** Un
   transfert qui n'enlève rien duplique le territoire, et deux agents se
   marchent dessus sans conflit visible.
4. **Chacun de ces gestes laisse une trace nommant son auteur** — c'est
   exactement ce que la règle 11 exige, et la seule façon de savoir plus tard
   qui a élargi quoi.

⚠️ Le banc rétablit le territoire d'origine à la fin. S'il s'interrompt au
milieu, relancer `provision-decor.sh` remet tout d'aplomb — c'est désormais son
rôle.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/admin_agents.py --self-test
    ./scripts/test-admin-agents.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.2"))
DEVICE_ID = "banc-admin-agents-0001"


def verdict_remplacement(obtenu, attendu):
    """Assigner REMPLACE. Un ajout déguisé fait grossir les territoires."""
    if obtenu is None:
        return "non_concluant", "état illisible après écriture"
    if obtenu == attendu:
        return "ok", "%d commune(s), exactement celles demandées" % len(attendu)
    en_trop = sorted(obtenu - attendu)
    manquantes = sorted(attendu - obtenu)
    if en_trop and not manquantes:
        return ("echec",
                "%d commune(s) EN TROP (%s…) — l'assignation ajoute au lieu de "
                "remplacer, et les territoires grossissent tout seuls"
                % (len(en_trop), en_trop[0][:8]))
    return ("echec",
            "état final inattendu : %d en trop, %d manquante(s)"
            % (len(en_trop), len(manquantes)))


def verdict_transfert(source_apres, cible_apres, deplacees):
    """Transférer, c'est retirer à l'un ce qu'on donne à l'autre."""
    if source_apres is None or cible_apres is None:
        return "non_concluant", "état illisible après transfert"
    non_donnees = deplacees - cible_apres
    if non_donnees:
        return ("echec",
                "%d commune(s) non reçues par la cible" % len(non_donnees))
    non_retirees = deplacees & source_apres
    if non_retirees:
        return ("echec",
                "%d commune(s) TOUJOURS chez la source (%s…) — le transfert "
                "duplique au lieu de déplacer, et deux agents se marchent "
                "dessus sans conflit visible"
                % (len(non_retirees), sorted(non_retirees)[0][:8]))
    return "ok", "%d commune(s) déplacées" % len(deplacees)


def verdict_trace(entrees, action, ids_avant):
    """Le geste doit laisser une trace NEUVE nommant son auteur (règle 11)."""
    neuves = [e for e in entrees
              if e.get("action") == action and e.get("id") not in ids_avant]
    if not neuves:
        return ("echec",
                "aucune trace neuve « %s » — le geste qui élargit un périmètre "
                "IDOR n'est pas journalisé (règle 11)" % action)
    if not neuves[0].get("actorId"):
        return "echec", "trace sans actorId — on ne saura pas qui a élargi"
    return "ok", "%s par %s" % (action, neuves[0]["actorId"][:8])


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
    _v("remplacement exact",
       verdict_remplacement({"a"}, {"a"})[0], "ok")
    _v("transfert propre",
       verdict_transfert(set(), {"b"}, {"b"})[0], "ok")
    _v("trace présente",
       verdict_trace([{"id": "n", "action": "x", "actorId": "a1"}], "x",
                     set())[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le cas du décor : l'assignation ajoute, et les territoires grossissent.
    _v("assignation qui ajoute",
       verdict_remplacement({"a", "b"}, {"a"})[0], "echec")
    _v("assignation incomplète",
       verdict_remplacement({"a"}, {"a", "b"})[0], "echec")
    _v("état illisible → non concluant",
       verdict_remplacement(None, {"a"})[0], "non_concluant")
    # ⚠️ Le transfert qui duplique : deux agents sur le même territoire.
    _v("transfert qui ne retire rien",
       verdict_transfert({"b"}, {"b"}, {"b"})[0], "echec")
    _v("transfert qui ne donne rien",
       verdict_transfert(set(), set(), {"b"})[0], "echec")
    _v("transfert illisible → non concluant",
       verdict_transfert(None, {"b"}, {"b"})[0], "non_concluant")
    _v("geste non tracé", verdict_trace([], "x", set())[0], "echec")
    _v("trace ancienne seulement",
       verdict_trace([{"id": "v", "action": "x", "actorId": "a"}], "x",
                     {"v"})[0], "echec")
    _v("trace anonyme",
       verdict_trace([{"id": "n", "action": "x", "actorId": ""}], "x",
                     set())[0], "echec")

    refus = 9
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


def main():
    admin_email = _exiger("ADMIN_EMAIL")
    admin_password = _exiger("ADMIN_PASSWORD")
    agent_email = _exiger("AGENT_EMAIL")
    agent_b_email = _exiger("AGENT_B_EMAIL")

    print("═" * 64)
    print("  Agents — assignation et transfert de communes, effets vérifiés")
    print("═" * 64)

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
        print("  %s %-42s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    def agents():
        _, d = appeler("GET", "/admin/agent?limit=100", ja)
        return {a["email"]: a for a in d.get("items", [])}

    def communes_de(email):
        a = agents().get(email)
        if not a:
            return None
        return {c["id"] for c in (a.get("communes") or [])}

    def journal_ids():
        _, d = appeler("GET", "/admin/audit-log?limit=100", ja)
        return {e.get("id") for e in d.get("items", [])}

    tous = agents()
    if agent_email not in tous or agent_b_email not in tous:
        print("❌ les agents du décor sont introuvables dans /admin/agent.")
        return 2
    id_a, id_b = tous[agent_email]["id"], tous[agent_b_email]["id"]
    origine_a = communes_de(agent_email)
    origine_b = communes_de(agent_b_email)
    if not origine_a or not origine_b:
        print("❌ un des agents n'a aucune commune — relancer le décor.")
        return 2
    time.sleep(PACE)

    # ── 1. L'assignation remplace ───────────────────────────────────────────
    print("\n── 1. assigner REMPLACE, et l'état est relu après écriture ──")
    cible = origine_a | origine_b
    avant_journal = journal_ids()
    time.sleep(PACE)
    st, d = appeler("PATCH", "/admin/agent/%s/communes" % id_a, ja,
                    {"communeIds": sorted(cible)})
    if st not in (200, 201):
        noter("assignation élargie", "non_concluant",
              "HTTP %s %s" % (st, d.get("code")))
        return 1
    time.sleep(PACE)
    noter("élargi à l'union des deux", *verdict_remplacement(
        communes_de(agent_email), cible))
    time.sleep(PACE)

    # Puis on RÉTRÉCIT : c'est le sens qui distingue « remplacer » d'« ajouter ».
    st, d = appeler("PATCH", "/admin/agent/%s/communes" % id_a, ja,
                    {"communeIds": sorted(origine_a)})
    time.sleep(PACE)
    noter("rétréci à son territoire d'origine",
          *verdict_remplacement(communes_de(agent_email), origine_a))
    time.sleep(PACE)

    _, journal = appeler("GET", "/admin/audit-log?limit=100", ja)
    noter("l'assignation est tracée",
          *verdict_trace(journal.get("items", []), "assign_agent_communes",
                         avant_journal))
    time.sleep(PACE)

    # ── 2. Le transfert déplace ─────────────────────────────────────────────
    print("\n── 2. transférer RETIRE à la source ce qu'il donne à la cible ──")
    avant_journal = journal_ids()
    time.sleep(PACE)
    st, d = appeler("POST", "/admin/agent/transfer-communes", ja, {
        "fromAgentId": id_b, "toAgentId": id_a,
        "communeIds": sorted(origine_b)})
    if st not in (200, 201):
        noter("transfert B → A", "non_concluant",
              "HTTP %s %s" % (st, d.get("code")))
    else:
        time.sleep(PACE)
        noter("B → A", *verdict_transfert(communes_de(agent_b_email),
                                          communes_de(agent_email),
                                          origine_b))
        time.sleep(PACE)
        _, journal = appeler("GET", "/admin/audit-log?limit=100", ja)
        noter("le transfert est tracé",
              *verdict_trace(journal.get("items", []), "transfer_communes",
                             avant_journal))
        time.sleep(PACE)

    # ── 3. Remise en état ───────────────────────────────────────────────────
    print("\n── 3. remise en état du décor ──")
    appeler("PATCH", "/admin/agent/%s/communes" % id_a, ja,
            {"communeIds": sorted(origine_a)})
    time.sleep(PACE)
    appeler("PATCH", "/admin/agent/%s/communes" % id_b, ja,
            {"communeIds": sorted(origine_b)})
    time.sleep(PACE)
    ok_a = communes_de(agent_email) == origine_a
    ok_b = communes_de(agent_b_email) == origine_b
    if ok_a and ok_b:
        noter("territoires rétablis", "ok", "A et B comme avant")
    else:
        noter("territoires rétablis", "echec",
              "A=%s B=%s — relancer provision-decor.sh" % (ok_a, ok_b))

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
