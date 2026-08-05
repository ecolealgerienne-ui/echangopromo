#!/usr/bin/env python3
"""Banc de la révocation — un jeton de 30 jours doit pouvoir être coupé.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

`JWT_EXPIRES_IN` vaut **30 jours**. Sans révocation, un jeton volé reste
exploitable un mois entier, sans recours — c'est la **règle 6**, et c'est
pourquoi `tokenVersion` existe. Le mécanisme a été ajouté à l'audit V1 et
**jamais rejoué depuis**.

Trois sondes :

1. **`POST /admin/me/revoke-token` coupe la session en cours.** Le jeton qui a
   servi à demander la révocation doit cesser d'ouvrir — y compris lui, surtout
   lui : c'est le cas « je crois qu'on m'a volé mon accès ».
2. **`POST /admin/agent/:id/revoke-token` coupe celle d'un agent**, sans
   toucher à celle de l'admin qui l'a demandée. Un mécanisme de révocation qui
   déconnecte l'auteur en même temps que sa cible est inutilisable en urgence.
3. **Un jeton révoqué est refusé avec `AUTH_TOKEN_REVOKED`**, pas avec un
   `AUTH_TOKEN_MISSING` ni un `404`. Le code compte : c'est lui qui permet à
   l'app de distinguer « reconnecte-toi » de « tu n'as jamais eu accès ».

⚠️ **La révocation d'un agent est vérifiée sur l'agent lui-même**, pas sur le
code de sortie de la requête d'admin : c'est l'état final qui compte.

⚠️ Ce banc rend le jeton admin du décor inutilisable — c'est précisément son
objet. Il se reconnecte ensuite ; les bancs suivants doivent simplement laisser
retomber le seau de connexions.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/revocation_jwt.py --self-test
    ./scripts/test-revocation-jwt.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.2"))
DEVICE_ID = "banc-revocation-0001"


def verdict_revoque(statut, code):
    """Le jeton doit être refusé, et pour la BONNE raison."""
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if statut is None:
        return "echec", "pas de réponse : %s" % code
    if statut in (200, 201):
        return ("echec",
                "le jeton révoqué fonctionne ENCORE — il reste exploitable "
                "jusqu'à expiration (30 j)")
    if code != "AUTH_TOKEN_REVOKED":
        return ("non_concluant",
                "refusé en %s/%s au lieu de AUTH_TOKEN_REVOKED — l'app ne peut "
                "pas distinguer « reconnecte-toi » de « tu n'as jamais eu "
                "accès »" % (statut, code))
    return "ok", "%s %s" % (statut, code)


def verdict_intact(statut, code):
    """L'auteur de la révocation ne doit PAS être déconnecté avec sa cible."""
    if statut == 429:
        return "non_concluant", "429 — ce n'est pas un verdict"
    if statut in (200, 201):
        return "ok", "toujours valide"
    return ("echec",
            "l'admin a été déconnecté en même temps que sa cible (HTTP %s, %s) "
            "— un mécanisme d'urgence inutilisable en urgence" % (statut, code))


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
    _v("jeton coupé", verdict_revoque(401, "AUTH_TOKEN_REVOKED")[0], "ok")
    _v("auteur intact", verdict_intact(200, None)[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le cas de la règle 6 : le jeton survit à sa révocation.
    _v("jeton toujours valide", verdict_revoque(200, None)[0], "echec")
    _v("pas de réponse", verdict_revoque(None, "RESEAU")[0], "echec")
    # ⚠️ Refusé, mais pour une autre raison — l'app affichera le mauvais message.
    _v("refusé sans le bon code",
       verdict_revoque(401, "AUTH_TOKEN_MISSING")[0], "non_concluant")
    _v("404 au lieu d'une révocation",
       verdict_revoque(404, "NOT_FOUND")[0], "non_concluant")
    _v("429 → non concluant", verdict_revoque(429, None)[0], "non_concluant")
    # ⚠️ L'auteur déconnecté avec sa cible : inutilisable en urgence.
    _v("auteur déconnecté",
       verdict_intact(401, "AUTH_TOKEN_REVOKED")[0], "echec")
    _v("429 sur l'auteur → non concluant",
       verdict_intact(429, None)[0], "non_concluant")

    refus = 7
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
    agent_password = _exiger("AGENT_PASSWORD")

    print("═" * 64)
    print("  Révocation — un jeton de 30 jours doit pouvoir être coupé")
    print("═" * 64)

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
                   {"email": agent_email, "password": agent_password}, "agent")

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-42s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    # ── 1. Révoquer un AGENT sans se couper soi-même ────────────────────────
    print("\n── 1. révoquer un agent, sans se déconnecter soi-même ──")
    aid = None
    _, liste = appeler("GET", "/admin/agent?limit=100", ja)
    for a in liste.get("items", []):
        if a.get("email") == agent_email:
            aid = a["id"]
            break
    if not aid:
        noter("l'agent du décor dans /admin/agent", "non_concluant",
              "introuvable — décor incomplet")
        return 1
    time.sleep(PACE)

    st, d = appeler("POST", "/admin/agent/%s/revoke-token" % aid, ja)
    if st not in (200, 201):
        noter("demande de révocation", "echec",
              "HTTP %s %s" % (st, d.get("code")))
        return 1
    time.sleep(PACE)

    # Vérifié sur l'AGENT, pas sur le code de sortie de la demande.
    st, d = appeler("GET", "/agent/me", jg)
    noter("le jeton de l'agent est coupé", *verdict_revoque(st, d.get("code")))
    time.sleep(PACE)

    st, d = appeler("GET", "/admin/me", ja)
    noter("celui de l'admin ne l'est pas", *verdict_intact(st, d.get("code")))
    time.sleep(PACE)

    # ── 2. Se révoquer soi-même ─────────────────────────────────────────────
    print("\n── 2. se couper soi-même — le cas « on m'a volé mon accès » ──")
    st, d = appeler("POST", "/admin/me/revoke-token", ja)
    if st not in (200, 201):
        noter("auto-révocation", "echec", "HTTP %s %s" % (st, d.get("code")))
        return 1
    time.sleep(PACE)

    st, d = appeler("GET", "/admin/me", ja)
    noter("le jeton qui a demandé la coupure est coupé",
          *verdict_revoque(st, d.get("code")))
    time.sleep(PACE)

    # ── 3. Se reconnecter reste possible ────────────────────────────────────
    print("\n── 3. et se reconnecter reste possible ──")
    st, d = appeler("POST", "/admin/login",
                    corps={"email": admin_email, "password": admin_password})
    if d.get("accessToken"):
        noter("nouvelle connexion admin", "ok", "jeton neuf obtenu")
    else:
        noter("nouvelle connexion admin", "echec",
              "HTTP %s %s — la révocation a fermé le compte, pas la session"
              % (st, d.get("code")))

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
