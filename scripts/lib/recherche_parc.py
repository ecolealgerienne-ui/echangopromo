#!/usr/bin/env python3
"""Banc de la recherche dans le parc — le geste de l'agent en tournée.

── Pourquoi ce banc, et pourquoi maintenant ────────────────────────────────

`GET /admin/commercant` est la façon dont un agent retrouve un commerce sur le
terrain. **Sept bancs l'appellent, tous en `?limit=100` sec** : le paramètre
`search` du DTO n'est exercé par personne. Une recherche qui ignorerait son
terme et rendrait la première page passerait le parc entier de bancs.

Et depuis le 2026-08-13 l'agent voit **tout le parc** : la recherche n'est plus
un confort, c'est le seul moyen de retrouver quelque chose dans une liste qui
n'a plus de frontière.

── ⚠️ Les deux pièges, tous deux payés le 2026-08-13 ───────────────────────

**1. La troncature.** `?limit=100` est le plafond serveur, et la base porte plus
de commerçants que ça. `provision-decor.sh` cherchait un commerçant dans la
première page et concluait « introuvable » sur un parc qui le contenait — le
défaut exact que la règle 15 décrit. Ce banc va donc chercher **un commerçant
situé au-delà de la première page**, et exige que la recherche le trouve. C'est
la seule sonde qui distingue « la recherche marche » de « il était dans les
cent premiers ».

**2. Le `+` d'un numéro de téléphone.** Dans une chaîne de requête, `+` non
encodé se décode en **espace**. `?search=+213555…` cherche donc « 213555… »
précédé d'une espace, silencieusement. Le banc éprouve les deux formes et
**nomme** celle qui ment, au lieu de laisser le prochain script le redécouvrir.

── Ce que ce banc ne fait pas ──────────────────────────────────────────────

Aucune écriture : il lit une route d'administration avec le jeton de l'agent du
décor. Il peut se relancer sans précaution.

── Usage ───────────────────────────────────────────────────────────────────

    python3 scripts/lib/recherche_parc.py --self-test
    ./scripts/test-recherche-parc.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.2"))
DEVICE_ID = "banc-recherche-parc-0001"

# Le plafond serveur, mesuré : `limit=200` rend 400 VALIDATION_ERROR.
PAGE_MAX = 100


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_parc_assez_grand(total):
    """⚠️ Sans un parc débordant d'une page, le piège de troncature est hors
    de portée — et le banc le dit plutôt que de rendre vert (règle 38)."""
    if total is None:
        return "non_concluant", "total du parc illisible"
    if total <= PAGE_MAX:
        return ("non_concluant",
                "le parc tient en une page (%d ≤ %d) : une recherche qui "
                "rendrait bêtement la première page passerait ce banc"
                % (total, PAGE_MAX))
    return "ok", "%d commerçants, soit plus d'une page" % total


def verdict_trouve_hors_page(ids_trouves, cible):
    """⚠️ **La sonde centrale.** Un commerçant absent de la première page doit
    être trouvé par la recherche.

    C'est le seul contrôle qui distingue une vraie recherche d'une liste
    tronquée qu'on filtrerait côté client.
    """
    if ids_trouves is None:
        return "non_concluant", "réponse de recherche illisible"
    if cible is None:
        return "non_concluant", "aucune cible hors première page identifiée"
    if cible not in ids_trouves:
        return ("echec",
                "un commerçant situé au-delà de la première page n'est PAS "
                "trouvé par la recherche : elle filtre une page, elle "
                "n'interroge pas le parc (règle 15)")
    return "ok", "trouvé hors de la première page"


def verdict_filtre_vraiment(total_recherche, total_parc):
    """Une recherche doit **réduire**. Si elle rend tout, elle ne filtre pas."""
    if total_recherche is None or total_parc is None:
        return "non_concluant", "totaux illisibles"
    if total_recherche >= total_parc:
        return ("echec",
                "la recherche rend %d résultats sur un parc de %d : le terme "
                "est ignoré, et l'agent croit avoir restreint"
                % (total_recherche, total_parc))
    return "ok", "%d résultats sur %d" % (total_recherche, total_parc)


def verdict_resultats_pertinents(items, terme):
    """Chaque résultat doit porter le terme — dans le nom ou le téléphone.

    ⚠️ Un bon nombre de résultats ne dit pas que ce sont les bons : une requête
    qui ignore le terme et tronque à la bonne longueur passerait un simple
    comptage.
    """
    if items is None:
        return "non_concluant", "réponse illisible"
    if not items:
        return "non_concluant", "aucun résultat — rien à vérifier"
    t = terme.lower()
    intrus = [i.get("nom") for i in items
              if t not in (i.get("nom") or "").lower()
              and t not in (i.get("telephone") or "").lower()]
    if intrus:
        return ("echec",
                "%d résultat(s) ne portent pas « %s » (ex. « %s ») — la "
                "recherche ne filtre pas, elle tronque"
                % (len(intrus), terme, intrus[0]))
    return "ok", "les %d résultats portent le terme" % len(items)


def verdict_terme_absurde(total):
    """Un terme qui n'existe pas doit rendre **zéro**, pas le parc entier.

    ⚠️ Retomber sur « tout » quand on ne comprend pas est le cas d'école de la
    règle 29 : l'agent croit avoir cherché, il obtient plus que ce qu'il a
    demandé, et rien ne le détrompe.
    """
    if total is None:
        return "non_concluant", "réponse illisible"
    if total != 0:
        return ("echec",
                "un terme inexistant rend %d résultat(s) : la recherche est "
                "ignorée en silence" % total)
    return "ok", "0 résultat — le terme est bien appliqué"


def verdict_piege_du_plus(total_encode, total_brut):
    """⚠️ Le `+` non encodé se décode en **espace** dans une chaîne de requête.

    On ne juge pas le serveur : il applique la norme. On **établit l'écart**,
    pour que le prochain script ne le redécouvre pas à ses frais — c'est
    exactement ce qui a coûté une soirée à `provision-decor.sh`.
    """
    if total_encode is None or total_brut is None:
        return "non_concluant", "une des deux recherches est illisible"
    if total_encode == 0:
        return ("non_concluant",
                "même correctement encodé (%%2B), le numéro ne trouve rien : "
                "la cible n'a pas le numéro attendu, ce contrôle n'a pas "
                "d'objet")
    if total_brut == total_encode:
        return ("ok",
                "les deux formes rendent %d résultat(s) — ce serveur n'est "
                "pas sensible au piège du « + »" % total_encode)
    return ("ok",
            "⚠️ piège confirmé : « %%2B » trouve %d, « + » brut en trouve %d — "
            "un « + » non encodé est lu comme une espace, silencieusement"
            % (total_encode, total_brut))


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
    resultats = [{"nom": "Épicerie Test", "telephone": "+213555000000"}]

    # ── Doivent PASSER ───────────────────────────────────────────────────────
    _v("parc débordant", verdict_parc_assez_grand(129)[0], "ok")
    _v("trouvé hors page", verdict_trouve_hors_page({"c9"}, "c9")[0], "ok")
    _v("la recherche réduit", verdict_filtre_vraiment(3, 129)[0], "ok")
    _v("résultats pertinents",
       verdict_resultats_pertinents(resultats, "Épicerie")[0], "ok")
    # ⚠️ Le terme peut porter sur le téléphone, pas seulement sur le nom.
    _v("pertinent par téléphone",
       verdict_resultats_pertinents(resultats, "213555")[0], "ok")
    _v("terme absurde", verdict_terme_absurde(0)[0], "ok")
    _v("piège du + confirmé", verdict_piege_du_plus(1, 0)[0], "ok")
    _v("pas de piège ici", verdict_piege_du_plus(1, 1)[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le défaut visé : la recherche filtre une page au lieu du parc.
    _v("introuvable hors page",
       verdict_trouve_hors_page({"c1"}, "c9")[0], "echec")
    # ⚠️ Le défaut visé : le terme est ignoré et la liste sert tout.
    _v("ne réduit rien", verdict_filtre_vraiment(129, 129)[0], "echec")
    _v("rend plus que le parc", verdict_filtre_vraiment(200, 129)[0], "echec")
    _v("résultat hors sujet",
       verdict_resultats_pertinents(
           [{"nom": "Autre chose", "telephone": "+213111"}], "Épicerie")[0],
       "echec")
    _v("terme absurde servi", verdict_terme_absurde(129)[0], "echec")

    # ── Doivent rester NON CONCLUANTS ────────────────────────────────────────
    # ⚠️ Un parc d'une page ne peut pas démasquer une recherche tronquée.
    _v("parc trop petit", verdict_parc_assez_grand(40)[0], "non_concluant")
    _v("total illisible", verdict_parc_assez_grand(None)[0], "non_concluant")
    _v("aucune cible", verdict_trouve_hors_page({"c1"}, None)[0],
       "non_concluant")
    _v("recherche illisible", verdict_trouve_hors_page(None, "c9")[0],
       "non_concluant")
    _v("totaux illisibles", verdict_filtre_vraiment(None, 129)[0],
       "non_concluant")
    _v("aucun résultat à juger",
       verdict_resultats_pertinents([], "x")[0], "non_concluant")
    _v("items illisibles",
       verdict_resultats_pertinents(None, "x")[0], "non_concluant")
    _v("terme absurde illisible",
       verdict_terme_absurde(None)[0], "non_concluant")
    # ⚠️ Si même la forme encodée ne trouve rien, la comparaison n'a pas d'objet.
    _v("cible sans numéro", verdict_piege_du_plus(0, 0)[0], "non_concluant")
    _v("comparaison illisible",
       verdict_piege_du_plus(None, 0)[0], "non_concluant")

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

    print("═" * 70)
    print("  Recherche dans le parc — le geste de l'agent en tournée")
    print("═" * 70)

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

    def chercher(terme_encode):
        st, d = appeler("GET", "/admin/commercant?limit=%d&search=%s"
                        % (PAGE_MAX, terme_encode), jg)
        if st != 200 or d.get("items") is None:
            return None, None
        return d.get("total"), d["items"]

    # ── 1. Le parc déborde-t-il d'une page ? ────────────────────────────────
    print("\n── 1. le parc déborde-t-il d'une page ? ──")
    st, page1 = appeler("GET", "/admin/commercant?limit=%d" % PAGE_MAX, jg)
    total_parc = page1.get("total") if st == 200 else None
    noter("GET /admin/commercant", *verdict_parc_assez_grand(total_parc))
    time.sleep(PACE)

    # ── 2. Une cible située AU-DELÀ de la première page ─────────────────────
    #
    # ⚠️ C'est tout l'intérêt : chercher quelqu'un qu'une recherche paresseuse
    # (filtrer la première page) ne pourrait pas trouver.
    print("\n── 2. la recherche trouve au-delà de la première page ──")
    cible = None
    st, page2 = appeler("GET", "/admin/commercant?limit=%d&page=2" % PAGE_MAX,
                        jg)
    if st == 200 and page2.get("items"):
        ids_page1 = {c.get("id") for c in page1.get("items", [])}
        for c in page2["items"]:
            if c.get("id") not in ids_page1 and c.get("nom"):
                cible = c
                break
    if cible is None:
        noter("cible hors première page", "non_concluant",
              "aucun commerçant lisible en page 2 — la sonde de troncature "
              "n'a pas d'objet")
    else:
        print("     cible : « %s »" % cible["nom"])
        time.sleep(PACE)
        total_r, items_r = chercher(urllib.parse.quote(cible["nom"]))
        noter("trouvé par son nom",
              *verdict_trouve_hors_page(
                  {c.get("id") for c in items_r} if items_r is not None
                  else None, cible.get("id")))
        noter("la recherche réduit le parc",
              *verdict_filtre_vraiment(total_r, total_parc))
        noter("les résultats portent le terme",
              *verdict_resultats_pertinents(items_r, cible["nom"]))
        time.sleep(PACE)

    # ── 3. Un terme qui n'existe pas rend zéro ──────────────────────────────
    print("\n── 3. un terme inexistant ne rend pas le parc entier ──")
    total_r, _ = chercher(urllib.parse.quote("zzz-aucun-commerce-zzz"))
    noter("terme absurde", *verdict_terme_absurde(total_r))
    time.sleep(PACE)

    # ── 4. ⚠️ Le piège du « + » dans une chaîne de requête ──────────────────
    print("\n── 4. ⚠️ le « + » d'un numéro, encodé et brut ──")
    tel = (cible or {}).get("telephone")
    if not tel or not tel.startswith("+"):
        noter("le piège du « + »", "non_concluant",
              "la cible n'a pas de numéro commençant par « + » — rien à "
              "comparer")
    else:
        total_encode, _ = chercher(urllib.parse.quote(tel, safe=""))
        time.sleep(PACE)
        # ⚠️ Volontairement NON encodé : c'est la forme qui ment.
        total_brut, _ = chercher(tel)
        noter("« %%2B » contre « + » brut",
              *verdict_piege_du_plus(total_encode, total_brut))

    print("\n" + "═" * 70)
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
