#!/usr/bin/env python3
"""Banc de la recherche — elle respecte le cadre, et rend le proche d'abord.

── L'observation qui a fait écrire ce banc ─────────────────────────────────

Le 2026-08-14, sur un téléphone réel, depuis Alger : « quand je fais la
recherche il me montre aussi les promos de Djelfa ». Mesuré alors sur le décor,
`search=promo` autour du point serveur : **65 résultats de 0,1 km à 245 km**,
dont 38 hors du rayon de 5 km.

⚠️ **Ce comportement était une décision, pas un défaut** — `promo.service.ts`
levait le rayon sur une recherche textuelle : « chercher est un acte
intentionnel avec une cible ». La décision tenait par une contrepartie écrite
juste en dessous : « le tri par distance reste actif, donc le proche remonte
quand même en tête ».

**Deux mesures l'ont défaite, et la décision a été inversée le même jour.** La
contrepartie était fausse à l'écran (l'app re-triait par date par-dessus l'ordre
du serveur : 231,7 km en 5ᵉ position, devant des dizaines à 100 mètres). Et le
rayon ne venait pas du client : il valait le défaut serveur quel que soit le
cadrage. Depuis, **le rayon est déduit du zoom de la carte** — chercher large ne
demande plus de lever la borne, il suffit de dézoomer.

⚠️ **Ce banc encode donc une décision produit, et c'est fragile par nature.**
Si la règle rebascule, le contrôle 3 doit être réécrit dans le même commit :
un banc qui défend une décision morte est pire qu'un banc absent, parce qu'il
échouera en accusant un produit correct (règle 38).

⚠️ **Ce banc ne peut pas voir les défauts de l'app**, et il faut le dire : le
serveur, lui, a toujours eu raison sur l'ordre. Ce qu'il tient, c'est la
**prémisse** dont l'app dépend — si l'ordre serveur cessait d'être par distance,
le tri local ne trierait plus qu'un sous-ensemble arbitraire (la page 1 vaut 50
résultats). Le versant app est tenu par
`test/features/client/tri_proximite_test.dart` (le tri) et
`test/features/client/rayon_depuis_la_vue_test.dart` (le rayon déduit du zoom).

── La sonde qui vaut le plus cher ─────────────────────────────────────────

`?search=<chaîne absurde>` doit rendre **0**. `main.ts` monte le
`ValidationPipe` avec `whitelist: true` **sans** `forbidNonWhitelisted` : un
paramètre inconnu est **effacé en silence**, sans erreur ni journal. Une
recherche non branchée rendrait donc le catalogue entier au lieu de rien — le
défaut est déjà arrivé côté app (voir le commentaire de `visiblePromosProvider`,
qui refiltre localement précisément à cause de ça).

── Usage ──────────────────────────────────────────────────────────────────

    python3 scripts/lib/recherche_globale.py --self-test
    ./scripts/test-recherche-globale.sh
"""

import json
import math
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")

# Terme cherché par défaut. ⚠️ Il doit exister dans le décor ET porter loin :
# un terme qui ne matche qu'un commerce voisin rendrait ce banc incapable de
# distinguer « le rayon est levé » de « il n'y avait rien de loin ».
TERME = os.environ.get("TERME_RECHERCHE", "promo")

# Chaîne qui ne doit rien trouver. Pas un mot rare — un mot rare finit par
# exister le jour où quelqu'un le tape dans une description.
TERME_ABSURDE = "zzq-terme-qui-nexiste-pas-9f3a"

# Tolérance sur la comparaison au rayon : le serveur calcule sa distance en SQL,
# ce banc la recalcule en Python. Les deux ne tombent pas au bit près, et un
# commerce pile sur la frontière ferait clignoter le verdict.
TOLERANCE = 1.02


def distance_km(lat1, lng1, lat2, lng2):
    """Haversine. Rend `None` dès qu'une coordonnée manque — jamais 0.

    ⚠️ Un `?? 0` ici placerait un commerce sans position à l'origine, donc en
    tête d'un tri par distance et à l'intérieur de tout rayon (règle 29).
    """
    if None in (lat1, lng1, lat2, lng2):
        return None
    r = 6371.0
    p = math.pi / 180
    h = (0.5 - math.cos((lat2 - lat1) * p) / 2
         + math.cos(lat1 * p) * math.cos(lat2 * p)
         * (1 - math.cos((lng2 - lng1) * p)) / 2)
    return 2 * r * math.asin(math.sqrt(h))


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_decor(distances, rayon):
    """⚠️ Le décor permet-il seulement de juger ? (règle 38)

    Sans un résultat DEDANS et un résultat DEHORS, « la recherche lève le
    rayon » et « la recherche applique le rayon » rendent exactement les mêmes
    chiffres. Le banc ne pourrait alors rien affirmer, et son vert serait un
    vert menteur.
    """
    if distances is None:
        return "non_concluant", "distances illisibles"
    connues = [d for d in distances if d is not None]
    if not connues:
        return "non_concluant", "aucune promo positionnée dans le décor"
    dedans = [d for d in connues if d <= rayon]
    dehors = [d for d in connues if d > rayon * TOLERANCE]
    if not dedans or not dehors:
        return ("non_concluant",
                "le décor n'a que du %s (%d résultats, %.1f à %.1f km, rayon "
                "%.0f km) : un serveur qui appliquerait le rayon et un serveur "
                "qui l'ignore rendraient la même chose"
                % ("proche" if not dehors else "lointain",
                   len(connues), min(connues), max(connues), rayon))
    return ("ok",
            "%d dedans, %d dehors (%.1f à %.1f km) — le rayon a de quoi se voir"
            % (len(dedans), len(dehors), min(connues), max(connues)))


def verdict_rayon_applique(distances, rayon):
    """Le témoin : **sans** recherche, le rayon doit borner.

    ⚠️ Sans ce contrôle, `verdict_rayon_leve` ne prouve rien — on ne saurait pas
    si le rayon est levé PAR la recherche ou s'il n'a jamais borné quoi que ce
    soit.
    """
    if distances is None:
        return "non_concluant", "distances illisibles"
    connues = [d for d in distances if d is not None]
    if not connues:
        return "non_concluant", "aucune promo positionnée"
    hors = [d for d in connues if d > rayon * TOLERANCE]
    if hors:
        return ("echec",
                "sans recherche, %d résultat(s) au-delà du rayon de %.0f km "
                "(jusqu'à %.1f km) — le cadrage géographique ne borne pas"
                % (len(hors), rayon, max(hors)))
    return "ok", "%d résultats, tous dans %.0f km" % (len(connues), rayon)


def verdict_plafond_de_proximite(rayon_max, rayon_defaut):
    """⚠️ **Le plafond annoncé respecte-t-il la règle de proximité ?**

    Sans cette sonde, `verdict_frontiere_refuse` est **auto-référentiel** : il
    lit le maximum sur le serveur, demande maximum + 1, et constate un refus.
    Il resterait donc vert si quelqu'un remontait `CLIENT_MAX_RADIUS_KM` à 500 —
    le serveur refuserait 501, et le banc applaudirait.

    *Trouvé en mutant le vrai `.env` le 2026-08-14 : plafond remis à 50, le
    contrôle a testé 51 et rendu vert. La mutation devait faire échouer le banc ;
    elle a montré que le banc regardait ailleurs.*

    La règle produit ne se dit pas « 5 km » — un chiffre en dur ici mourrait au
    premier changement de pilote. Elle se dit : **aucun client ne peut demander
    plus large que ce que le serveur applique par défaut.** C'est cette relation
    qui porte « promos de proximité, pas annonces nationales », et elle se
    vérifie sans connaître aucun chiffre.
    """
    if rayon_max is None or rayon_defaut is None:
        return "non_concluant", "/promo/config ne sert pas les deux rayons"
    if rayon_max > rayon_defaut:
        return ("echec",
                "le maximum accepté (%.0f km) dépasse le rayon par défaut "
                "(%.0f km) : un appelant peut demander plus large que ce que le "
                "produit sert, et la règle de proximité n'est plus une frontière"
                % (rayon_max, rayon_defaut))
    return ("ok",
            "maximum %.0f km ≤ défaut %.0f km — nul ne peut cadrer plus large "
            "que le voisinage" % (rayon_max, rayon_defaut))


def verdict_frontiere_refuse(statut, rayon_demande, rayon_max):
    """⚠️ **La frontière sait-elle refuser ?** (règle 28)

    Le contrôle 3 seul ne prouve rien de la borne : un serveur qui rendrait
    toujours peu de résultats le satisferait. Ce qui fait d'un plafond une
    frontière, c'est qu'il **rejette** ce qui le dépasse — sinon un appelant
    direct de l'API obtient ce que l'app s'interdit, et la borne n'est qu'un
    confort d'affichage déguisé en règle.

    ⚠️ Cette sonde a remplacé « la borne suit le paramètre » le 2026-08-14,
    quand `CLIENT_MAX_RADIUS_KM` est passé de 50 à 5 : le défaut et le maximum
    étant devenus égaux, il n'existe plus de rayon intermédiaire à demander, et
    l'ancienne sonde ne pouvait plus varier. Elle est **remplacée, pas
    supprimée** — un contrôle qu'on retire en silence laisse un trou qui
    ressemble à une couverture.
    """
    if statut is None:
        return "non_concluant", "aucune réponse"
    if statut == 400:
        return ("ok",
                "400 sur %.0f km (maximum %.0f) — la frontière refuse"
                % (rayon_demande, rayon_max))
    if statut == 200:
        return ("echec",
                "200 sur un rayon de %.0f km alors que le maximum annoncé est "
                "%.0f : le plafond est déclaré mais pas appliqué, et un appel "
                "direct contourne la règle de proximité"
                % (rayon_demande, rayon_max))
    return ("non_concluant",
            "statut %d — ni un refus de validation ni un service" % statut)


def verdict_ordre_distance(distances):
    """**La contrepartie de la décision** : le proche d'abord.

    ⚠️ C'est la prémisse dont dépend l'app. Si elle tombe, la page 1 cesse
    d'être « les 50 plus proches » et devient un sous-ensemble arbitraire —
    qu'aucun tri local ne pourra rattraper, puisqu'il ne trie que ce qui est
    chargé.
    """
    if distances is None:
        return "non_concluant", "distances illisibles"
    connues = [d for d in distances if d is not None]
    if len(connues) < 2:
        return ("non_concluant",
                "%d résultat positionné : un ordre ne se juge pas sur moins de "
                "deux" % len(connues))
    for i in range(1, len(connues)):
        if connues[i] < connues[i - 1] - 0.001:
            return ("echec",
                    "l'ordre n'est pas croissant : %.1f km arrive après "
                    "%.1f km (position %d) — le proche ne remonte plus, et la "
                    "recherche globale n'a plus sa contrepartie"
                    % (connues[i], connues[i - 1], i + 1))
    return ("ok",
            "%d résultats, de %.1f à %.1f km, strictement croissant"
            % (len(connues), connues[0], connues[-1]))


def verdict_recherche_honoree(total_absurde, total_sans_recherche):
    """⚠️ Le paramètre `search` est-il seulement lu ?

    `whitelist: true` sans `forbidNonWhitelisted` efface un paramètre inconnu
    **sans erreur**. Un `search` non branché rendrait donc le catalogue entier
    au lieu de zéro, et la seule chose qu'on verrait est « beaucoup de
    résultats » — ce qui ressemble à un succès.
    """
    if total_absurde is None or total_sans_recherche is None:
        return "non_concluant", "totaux illisibles"
    if total_sans_recherche == 0:
        return ("non_concluant",
                "le décor ne sert aucune promo : un `search` ignoré rendrait "
                "zéro lui aussi, on ne peut rien distinguer")
    if total_absurde == 0:
        return "ok", "0 résultat sur un terme absurde — `search` est bien lu"
    if total_absurde >= total_sans_recherche:
        return ("echec",
                "un terme absurde rend %d résultats, autant que sans recherche "
                "(%d) : le paramètre est effacé en silence et la recherche ne "
                "filtre rien" % (total_absurde, total_sans_recherche))
    return ("echec",
            "%d résultat(s) sur un terme qui ne devrait rien trouver"
            % total_absurde)


def verdict_perimetre_explicite(distances, rayon):
    """`commercantId` désigne une fiche, pas un voisinage.

    Un commerce lointain doit rendre ses promos même hors rayon : les recadrer
    ferait disparaître « autres promos du magasin » dès qu'on regarde une fiche
    éloignée.
    """
    if distances is None:
        return "non_concluant", "distances illisibles"
    connues = [d for d in distances if d is not None]
    if not connues:
        return "non_concluant", "aucune promo positionnée pour ce commerce"
    if max(connues) <= rayon * TOLERANCE:
        return ("non_concluant",
                "le commerce interrogé est à %.1f km, dans le rayon : ce "
                "contrôle ne peut rien distinguer" % max(connues))
    return ("ok",
            "%d promo(s) servies pour un commerce à %.1f km — la fiche n'est "
            "pas recadrée" % (len(connues), max(connues)))


# ─────────────────────────────────────────────────────────────────────────────

def appeler(chemin):
    req = urllib.request.Request(API_URL + chemin)
    req.add_header("X-Device-Id", "banc-recherche-0001")
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


def distances_de(items, lat, lng, cles=("commercantLatitude",
                                        "commercantLongitude")):
    """⚠️ **Les deux routes ne nomment pas les coordonnées pareil**, et le
    découvrir en silence coûte cher : `/promo` sert des promos qui portent
    `commercantLatitude`, `/promo/map` sert des commerçants qui portent
    `latitude`. Lire la mauvaise clé rend `None` partout, donc « aucune promo
    positionnée » — un non-concluant qui accuse le décor alors que la sonde
    regardait à côté. C'est arrivé ici même.

    Les clés sont donc un paramètre explicite, jamais devinées : essayer l'une
    puis l'autre masquerait un vrai changement de contrat côté serveur.
    """
    if items is None:
        return None
    return [distance_km(lat, lng, i.get(cles[0]), i.get(cles[1]))
            for i in items]


_ok = 0
_echecs = []


def _v(libelle, obtenu, attendu):
    global _ok
    if obtenu == attendu:
        _ok += 1
    else:
        _echecs.append("%s — attendu %r, obtenu %r" % (libelle, attendu, obtenu))


def self_test():
    proche_et_loin = [0.1, 0.4, 12.0, 231.7]

    # ── Doivent PASSER ───────────────────────────────────────────────────────
    _v("décor étalé", verdict_decor(proche_et_loin, 5)[0], "ok")
    _v("rayon appliqué sans recherche",
       verdict_rayon_applique([0.1, 4.9], 5)[0], "ok")
    _v("recherche bornée elle aussi",
       verdict_rayon_applique([0.1, 0.9], 5)[0], "ok")
    _v("plafond de proximité tenu",
       verdict_plafond_de_proximite(5, 5)[0], "ok")
    _v("au-delà du maximum, refusé",
       verdict_frontiere_refuse(400, 51, 50)[0], "ok")
    _v("ordre croissant", verdict_ordre_distance(proche_et_loin)[0], "ok")
    _v("terme absurde sans résultat",
       verdict_recherche_honoree(0, 56)[0], "ok")
    _v("fiche lointaine servie",
       verdict_perimetre_explicite([231.7, 231.7], 5)[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le cas exact du 2026-08-14 : 231,7 km affiché avant du 0,1 km.
    _v("ordre rompu (cas du 2026-08-14)",
       verdict_ordre_distance([0.1, 0.5, 231.7, 0.1])[0], "echec")
    _v("rayon qui ne borne pas",
       verdict_rayon_applique([0.1, 231.7], 5)[0], "echec")
    # ⚠️ Le cas exact du 2026-08-14, vu depuis Alger : la recherche ramenait
    # Djelfa à 245 km alors que le cadre valait 5 km.
    _v("recherche qui déborde le cadre (cas d'Alger)",
       verdict_rayon_applique([0.1, 245.4], 5)[0], "echec")
    # ⚠️ Le cas exact que la mutation du 2026-08-14 a révélé : plafond remis
    # à 50 alors que le produit sert 5.
    _v("plafond plus large que le défaut",
       verdict_plafond_de_proximite(50, 5)[0], "echec")
    _v("plafond déclaré mais pas appliqué",
       verdict_frontiere_refuse(200, 51, 50)[0], "echec")
    # ⚠️ Le défaut le plus coûteux : `search` effacé, le catalogue entier servi.
    _v("search effacé en silence",
       verdict_recherche_honoree(56, 56)[0], "echec")
    _v("terme absurde qui trouve quand même",
       verdict_recherche_honoree(3, 56)[0], "echec")

    # ── Doivent rester NON CONCLUANTS ────────────────────────────────────────
    # ⚠️ Un décor tout proche ne distingue pas un rayon levé d'un rayon appliqué.
    _v("décor sans lointain", verdict_decor([0.1, 0.4], 5)[0], "non_concluant")
    _v("décor sans proche", verdict_decor([120.0, 231.7], 5)[0], "non_concluant")
    _v("un seul résultat", verdict_ordre_distance([0.1])[0], "non_concluant")
    # ⚠️ Une position absente ne vaut pas zéro : elle ne compte pas.
    _v("que des positions absentes",
       verdict_ordre_distance([None, None])[0], "non_concluant")
    _v("décor vide", verdict_recherche_honoree(0, 0)[0], "non_concluant")
    _v("distances illisibles", verdict_rayon_applique(None, 5)[0],
       "non_concluant")
    _v("commerce dans le rayon",
       verdict_perimetre_explicite([2.0], 5)[0], "non_concluant")
    # ⚠️ Ni un refus de validation ni un service : on ne conclut pas.
    _v("statut inattendu sur la frontière",
       verdict_frontiere_refuse(500, 51, 50)[0], "non_concluant")
    _v("aucune réponse de la frontière",
       verdict_frontiere_refuse(None, 51, 50)[0], "non_concluant")
    _v("rayons de configuration illisibles",
       verdict_plafond_de_proximite(None, 5)[0], "non_concluant")
    _v("totaux illisibles",
       verdict_recherche_honoree(None, 56)[0], "non_concluant")

    # ── La distance elle-même ────────────────────────────────────────────────
    _v("coordonnée absente ⇒ None, jamais 0",
       distance_km(34.6, 3.2, None, 3.2), None)
    _v("distance nulle sur le même point",
       round(distance_km(34.6, 3.2, 34.6, 3.2), 6), 0.0)
    # Djelfa → Alger, ~230 km à vol d'oiseau.
    _v("Djelfa → Alger dans le bon ordre de grandeur",
       220 < distance_km(34.6703, 3.2630, 36.7538, 3.0588) < 245, True)

    refus = 13
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


# ─────────────────────────────────────────────────────────────────────────────

def main():
    print("═" * 68)
    print("  Recherche — globale par décision, mais le proche d'abord")
    print("═" * 68)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-34s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    # ⚠️ Le point et le rayon viennent du SERVEUR, jamais d'une constante écrite
    # ici : le jour où le pilote déménage, ce banc suit (règle 32).
    st, cfg = appeler("/promo/config")
    if st != 200:
        print("  ❌ /promo/config ne répond pas (%s) — sans point ni rayon de "
              "référence, ce banc ne peut rien mesurer." % st)
        return 2
    lat = cfg.get("defaultLatitude")
    lng = cfg.get("defaultLongitude")
    rayon = cfg.get("defaultRadiusKm")
    if None in (lat, lng, rayon):
        print("  ❌ /promo/config ne sert pas le point ou le rayon par défaut.")
        return 2
    print("  point serveur %.4f, %.4f — rayon %.0f km" % (lat, lng, rayon))

    geo = "latitude=%s&longitude=%s" % (lat, lng)
    q = urllib.parse.quote(TERME)

    s1, sans = appeler("/promo?limit=100&" + geo)
    d_sans = distances_de(sans.get("items"), lat, lng) if s1 == 200 else None

    s2, avec = appeler("/promo?limit=100&%s&search=%s" % (geo, q))
    d_avec = distances_de(avec.get("items"), lat, lng) if s2 == 200 else None

    # ⚠️ **L'échantillon du décor ne peut venir d'AUCUNE requête bornée par un
    # rayon.** Ma première version le tirait de la recherche elle-même : il ne
    # contenait donc que du proche, et le contrôle 1 rendait « décor trop
    # pauvre » en décrivant en réalité le comportement qu'il devait juger. Je
    # l'ai ensuite tiré d'une recherche élargie au maximum serveur — ce qui a
    # cessé de marcher le jour où ce maximum est descendu à 5 km.
    #
    # `/promo/map` travaille en RECTANGLE et n'a pas de rayon : c'est le seul
    # prélèvement du parc qui ne dépende pas de ce qu'on éprouve.
    rmax = cfg.get("maxRadiusKm")
    s5, parc = appeler("/promo/map?north=38&south=18&east=12&west=-9")
    d_parc = (distances_de(parc.get("items"), lat, lng,
                           cles=("latitude", "longitude"))
              if s5 == 200 else None)
    if s5 == 200 and parc.get("truncated"):
        print("  ⚠️  parc tronqué : les contrôles 1 et 7 ne voient qu'une "
              "partie du décor")

    print("\n── 1. le décor permet-il de juger ? ──")
    noter("le parc s'étale-t-il ?", *verdict_decor(d_parc, rayon))

    print("\n── 2. le témoin : sans recherche, le rayon borne ──")
    noter("liste ordinaire ⊂ rayon", *verdict_rayon_applique(d_sans, rayon))

    print("\n── 3. la décision : la recherche respecte le cadre ──")
    noter("« %s » reste dans le cadre" % TERME,
          *verdict_rayon_applique(d_avec, rayon))

    print("\n── 4. le plafond annoncé est celui de la proximité ──")
    noter("maximum ≤ défaut", *verdict_plafond_de_proximite(rmax, rayon))

    print("\n── 5. et la frontière sait refuser ce qui la dépasse ──")
    if rmax is None:
        noter("au-delà du maximum", "non_concluant",
              "/promo/config ne sert pas maxRadiusKm")
    else:
        trop = rmax + 1
        s6, _ = appeler("/promo?limit=1&%s&radiusKm=%s" % (geo, trop))
        noter("radiusKm=%.0f refusé" % trop,
              *verdict_frontiere_refuse(s6, trop, rmax))

    print("\n── 6. sa contrepartie : le proche d'abord ──")
    noter("ordre servi par distance", *verdict_ordre_distance(d_avec))

    print("\n── 7. `search` est-il seulement lu ? ──")
    s3, absurde = appeler("/promo?limit=1&%s&search=%s"
                          % (geo, urllib.parse.quote(TERME_ABSURDE)))
    noter("terme absurde ⇒ 0",
          *verdict_recherche_honoree(
              absurde.get("total") if s3 == 200 else None,
              sans.get("total") if s1 == 200 else None))

    print("\n── 8. une fiche n'est pas un voisinage ──")
    # Le commerce le plus LOIN du décor : c'est celui sur lequel le contrôle a
    # une chance de distinguer quelque chose.
    # ⚠️ Pris dans l'échantillon ÉLARGI, pas dans la recherche : celle-ci est
    # bornée, son commerce « le plus loin » est donc à l'intérieur du rayon et
    # ce contrôle ne pourrait rien distinguer.
    loin = None
    if d_parc and parc.get("items"):
        paires = [(d, i)
                  for d, i in zip(d_parc, parc["items"]) if d is not None]
        if paires:
            loin = max(paires, key=lambda p: p[0])[1]
    if loin is None:
        noter("commercantId lointain", "non_concluant",
              "aucun commerce positionné à interroger")
    else:
        # ⚠️ **Sans coordonnées, et c'est tout le sujet.** `perimetreExplicite`
        # n'entre en jeu que si la requête ne porte AUCUNE position : le
        # ternaire de `promo.service.ts` lit `query.latitude` en premier, donc
        # envoyer un point avec `commercantId` rétablit le rayon et referme la
        # fiche. Ma première version de cette sonde passait `geo` ici — elle
        # rendait 0 résultat et un « non concluant » qui accusait le décor,
        # alors que c'est la sonde qui mesurait autre chose que l'invariant
        # (règle 38 : établir que la mesure pouvait varier).
        s4, fiche = appeler("/promo?limit=100&commercantId=%s"
                            % loin["id"])
        noter("commercantId lointain",
              *verdict_perimetre_explicite(
                  distances_de(fiche.get("items"), lat, lng)
                  if s4 == 200 else None, rayon))

    print("\n" + "═" * 68)
    echecs = resultats.count("echec")
    non_concluants = resultats.count("non_concluant")
    print("%d contrôles, %d échec(s), %d non concluant(s)"
          % (len(resultats), echecs, non_concluants))
    if non_concluants and not echecs:
        print("⚠️  des sondes n'ont pas conclu : ce n'est pas une réussite.")
    print("⚠️  Le versant app — le tri local qui écrasait cet ordre — n'est PAS")
    print("    couvert ici : `test/features/client/tri_proximite_test.dart`.")
    return 1 if (echecs or non_concluants) else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)
    sys.exit(main())
