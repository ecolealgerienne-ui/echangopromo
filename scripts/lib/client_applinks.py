#!/usr/bin/env python3
"""Banc des liens d'application — fichiers bien formés, et redirection muette.

── Ce que ce banc éprouve ───────────────────────────────────────────────────

Trois routes servies sur le sous-domaine de partage, et dont l'échec ne se voit
**nulle part** : ni erreur serveur, ni écran cassé. Un `assetlinks.json`
malformé fait simplement échouer la vérification App Links en silence, et le
lien partagé ouvre le navigateur au lieu de l'app — pendant des mois, sans que
personne ne relie l'un à l'autre.

1. **Les deux fichiers de vérification ont la FORME attendue**, qu'ils soient
   peuplés ou non. En développement la configuration est vide et le contrôleur
   rend `[]` / `{applinks:{apps:[],details:[]}}` — c'est le comportement voulu
   (« tout vide tant que l'app n'est pas publiée »), mais **vide n'est pas
   malformé** : un tableau reste un tableau, un objet garde ses clés.

2. **`/p/:id` ne dit pas si la promo existe.** C'est une redirection de
   croissance, pas une lecture : elle ne consulte aucune promo et doit répondre
   **identiquement** pour un identifiant réel et un identifiant inventé. Sinon
   elle devient un oracle — on énumère les promos sans jamais appeler l'API.

3. **Aucune de ces routes ne casse sur une entrée malformée.**

⚠️ La sonde n°2 compare deux réponses entre elles plutôt qu'à une valeur
attendue : le banc ne sait pas si le store est configuré (302) ou non (200
page d'attente), et n'a pas à le savoir. Ce qui compte est que les deux
réponses soient **indiscernables**.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/client_applinks.py --self-test
    ./scripts/test-client-applinks.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
HOTE = os.environ.get("APPLINKS_HOST", "promo.echango.com")
PACE = float(os.environ.get("PACE_SECONDS", "0.6"))


def verdict_assetlinks(statut, corps):
    """Un tableau, même vide — jamais autre chose."""
    if statut != 200:
        return "echec", "HTTP %s au lieu de 200" % statut
    if not isinstance(corps, list):
        return ("echec",
                "la réponse n'est pas un tableau (%s) — la vérification "
                "Android échouerait en silence" % type(corps).__name__)
    for entree in corps:
        cible = (entree or {}).get("target") or {}
        if not cible.get("package_name") or not cible.get(
                "sha256_cert_fingerprints"):
            return ("echec",
                    "entrée sans package_name ou sans empreinte — un fichier "
                    "à moitié rempli ne vérifie rien")
    return "ok", "tableau valide, %d entrée(s)" % len(corps)


def verdict_apple(statut, corps):
    """Un objet `applinks` avec ses deux clés, même vides."""
    if statut != 200:
        return "echec", "HTTP %s au lieu de 200" % statut
    if not isinstance(corps, dict) or "applinks" not in corps:
        return "echec", "pas d'objet `applinks` — fichier inexploitable"
    al = corps["applinks"]
    if not isinstance(al, dict) or "details" not in al or "apps" not in al:
        return "echec", "`applinks` sans `apps`/`details`"
    return "ok", "objet valide, %d détail(s)" % len(al.get("details") or [])


def verdict_muet(reponse_reelle, reponse_inventee):
    """Deux identifiants doivent donner la MÊME réponse.

    ⚠️ On compare statut ET taille de corps : un 200 dans les deux cas mais
    avec des contenus différents renseignerait tout autant.
    """
    if None in (reponse_reelle[0], reponse_inventee[0]):
        return "non_concluant", "une des deux requêtes n'a pas abouti"
    if reponse_reelle[0] >= 500 or reponse_inventee[0] >= 500:
        return "echec", "HTTP %s / %s — la route casse" % (
            reponse_reelle[0], reponse_inventee[0])
    if reponse_reelle != reponse_inventee:
        return ("echec",
                "réponses différentes (%s vs %s) — la redirection dit si la "
                "promo existe, et devient un oracle d'énumération"
                % (reponse_reelle, reponse_inventee))
    return "ok", "identiques (%s, %d octets)" % reponse_reelle


# ─────────────────────────────────────────────────────────────────────────────

def appeler(chemin, json_attendu=True):
    req = urllib.request.Request(API_URL + chemin, method="GET")
    req.add_header("Host", HOTE)
    req.add_header("X-Device-Id", "banc-applinks-0001")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            brut = r.read()
            if not json_attendu:
                return r.status, len(brut)
            try:
                return r.status, json.loads(brut or b"{}")
            except Exception:
                return r.status, None
    except urllib.error.HTTPError as e:
        brut = e.read()
        return e.code, (len(brut) if not json_attendu else None)
    except Exception as e:
        return None, str(e)


def appeler_sans_suivre(chemin):
    """`/p/:id` redirige : on veut le 302, pas la page du store."""
    class SansRedirection(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **k):
            return None

    opener = urllib.request.build_opener(SansRedirection)
    req = urllib.request.Request(API_URL + chemin, method="GET")
    req.add_header("Host", HOTE)
    try:
        with opener.open(req, timeout=30) as r:
            return r.status, len(r.read())
    except urllib.error.HTTPError as e:
        return e.code, len(e.read())
    except Exception:
        return None, 0


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
    _v("assetlinks vide mais valide", verdict_assetlinks(200, [])[0], "ok")
    _v("assetlinks peuplé",
       verdict_assetlinks(200, [{"target": {"package_name": "p",
                                            "sha256_cert_fingerprints": ["f"]}}])[0],
       "ok")
    _v("apple vide mais valide",
       verdict_apple(200, {"applinks": {"apps": [], "details": []}})[0], "ok")
    _v("redirection muette", verdict_muet((302, 0), (302, 0))[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    _v("assetlinks non tableau", verdict_assetlinks(200, {})[0], "echec")
    # ⚠️ Un fichier à moitié rempli ne vérifie rien, et rien ne le signale.
    _v("assetlinks sans empreinte",
       verdict_assetlinks(200, [{"target": {"package_name": "p"}}])[0], "echec")
    _v("assetlinks en erreur", verdict_assetlinks(500, [])[0], "echec")
    _v("apple sans applinks", verdict_apple(200, {})[0], "echec")
    _v("apple sans details",
       verdict_apple(200, {"applinks": {"apps": []}})[0], "echec")
    # ⚠️ L'oracle : la réponse dit si la promo existe.
    _v("réponses différentes", verdict_muet((302, 0), (404, 12))[0], "echec")
    _v("même statut, corps différents",
       verdict_muet((200, 500), (200, 120))[0], "echec")
    _v("la route casse", verdict_muet((500, 0), (500, 0))[0], "echec")
    _v("requête sans réponse → non concluant",
       verdict_muet((None, 0), (302, 0))[0], "non_concluant")

    refus = 9
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


def main():
    print("═" * 64)
    print("  Liens d'application — fichiers bien formés, redirection muette")
    print("═" * 64)
    print("  hôte simulé : %s" % HOTE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-40s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    print("\n── 1. les fichiers de vérification ──")
    st, corps = appeler("/.well-known/assetlinks.json")
    noter("assetlinks.json", *verdict_assetlinks(st, corps))
    time.sleep(PACE)

    st, corps = appeler("/.well-known/apple-app-site-association")
    noter("apple-app-site-association", *verdict_apple(st, corps))
    time.sleep(PACE)

    print("\n── 2. la redirection ne dit pas si la promo existe ──")
    reelle = appeler_sans_suivre("/p/11111111-2222-4333-8444-555555555555")
    time.sleep(PACE)
    inventee = appeler_sans_suivre("/p/99999999-8888-4777-8666-555555555555")
    noter("identifiant réel vs inventé", *verdict_muet(reelle, inventee))
    time.sleep(PACE)

    st, _ = appeler_sans_suivre("/p/pas-un-uuid")
    if st is None or st >= 500:
        noter("identifiant malformé", "echec",
              "HTTP %s — la route casse sur une URL quelconque" % st)
    else:
        noter("identifiant malformé", "ok", "HTTP %s" % st)

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
