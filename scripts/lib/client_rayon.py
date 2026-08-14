#!/usr/bin/env python3
"""Banc du rayon client — le cadre n'est pas le cercle.

── Ce que ce banc éprouve, et pourquoi il existe à part ─────────────────────

`client_liste.py` couvre la **visibilité** (« ce que la liste montre et ce que
le détail sert sont le même ensemble »). C'est un autre sujet, avec un autre
décor : celui-ci a besoin de deux commerçants **placés à des distances
choisies**, ce que l'autre n'a aucune raison de fabriquer. Les fusionner aurait
obligé chacun à monter le décor de l'autre.

── Le cas décisif, et lui seul justifie ce banc ─────────────────────────────

La recherche par rayon se fait en deux temps côté serveur : un **cadre
rectangulaire** (qui seul peut emprunter l'index `IDX_commercant_position`),
puis une **distance haversine** qui rogne les coins de ce cadre.

⚠️ **Une implémentation qui oublie le rognage rend vert sur presque tous les
jeux d'essai.** Un commerce « dedans » est dedans dans les deux cas ; un
commerce « très loin » est dehors dans les deux cas. La seule mesure qui les
distingue est un point **dans le carré et hors du cercle** — en diagonale, à
environ 1,41 fois le rayon. Sans ce cas, le banc mesure une bbox en croyant
mesurer un rayon, et le produit servirait des commerces jusqu'à 41 % trop loin.

── Comment la prémisse est établie, pas supposée (règle #38) ────────────────

Constater que le commerce du coin est **absent** au rayon R ne prouve rien
tout seul : il pourrait être absent parce que sa promo n'est pas visible, parce
que sa création a échoué, ou parce que le décor a visé à côté. Le contrôle 2
lui redemande donc la **même** liste avec un rayon plus large et exige qu'il
**apparaisse**. Une seule chose change entre les deux : le rayon.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/client_rayon.py --self-test   # d'abord, bloquant
    ./scripts/test-client-rayon.sh

⚠️ Ce banc ÉCRIT : il crée SES PROPRES commerçants via l'agent, et leurs
promos. Il ne touche à aucun compte existant.
"""

import base64
import json
import math
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.2"))
DEVICE_ID = "banc-rayon-0001"
PIN = "654321"

# Point de référence du banc — Djelfa. Il n'a pas à être exact : tout est
# mesuré **relativement** à lui.
REF_LAT, REF_LNG = 34.6703, 3.2630

# Rayon éprouvé, et rayon élargi qui sert à établir la prémisse.
RAYON_KM = 3.0
RAYON_LARGE_KM = 10.0

JPEG_1x1 = base64.b64decode(
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof"
    "Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB"
    "AAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q=="
)


# ─────────────────────────────────────────────────────────────────────────────
# Géométrie — isolée du réseau pour être éprouvée par `--self-test`.
# ─────────────────────────────────────────────────────────────────────────────

def decaler(lat, lng, km_nord, km_est):
    """Déplace un point de tant de kilomètres vers le nord et vers l'est.

    ⚠️ Le degré de longitude rétrécit avec le cosinus de la latitude : à Djelfa
    (34,7°) il ne vaut plus que ~91 km. L'ignorer placerait le commerce d'essai
    bien plus près qu'on ne le croit, et le banc mesurerait autre chose que ce
    qu'il annonce.
    """
    dlat = km_nord / 111.32
    dlng = km_est / (111.32 * math.cos(math.radians(lat)))
    return lat + dlat, lng + dlng


def distance_km(lat1, lng1, lat2, lng2):
    """Haversine — la même formule que le serveur, pour VÉRIFIER le décor.

    ⚠️ Ce n'est pas une duplication de la règle métier (règle #30) : le serveur
    l'utilise pour *filtrer*, ce banc pour *constater où il a posé ses points*.
    Si les deux divergeaient, c'est justement ce banc qui le montrerait — un
    décor qui se croit à 3,9 km alors qu'il est à 2 km rendrait vert un
    serveur cassé.
    """
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(a)))


def point_du_coin(lat, lng, rayon_km):
    """Un point DANS le cadre et HORS du cercle, quelle que soit la constante
    exacte que le serveur utilise pour dériver son cadre.

    À 45°, une distance de 1,3·R donne un décalage de 1,3·R·cos(45°) ≈ 0,92·R
    sur chaque axe — donc strictement **inférieur à R**, donc à l'intérieur du
    cadre sur les deux axes ; et 1,3·R > R, donc à l'extérieur du cercle.

    ⚠️ Volontairement pas 1,41·R (le coin exact) : un point posé pile sur la
    frontière du cadre serait à la merci d'un arrondi, et un banc qui dépend
    d'un epsilon n'est pas un banc.
    """
    diagonale = 1.3 * rayon_km
    cote = diagonale * math.cos(math.radians(45))
    return decaler(lat, lng, cote, cote)


# ─────────────────────────────────────────────────────────────────────────────
# Réseau
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


def televerser(jeton, purpose):
    frontiere = "----banc%s" % uuid.uuid4().hex
    corps = b"".join([
        ('--%s\r\nContent-Disposition: form-data; name="purpose"\r\n\r\n%s\r\n'
         % (frontiere, purpose)).encode(),
        ('--%s\r\nContent-Disposition: form-data; name="file"; '
         'filename="promo.jpg"\r\nContent-Type: image/jpeg\r\n\r\n'
         % frontiere).encode(),
        JPEG_1x1,
        ("\r\n--%s--\r\n" % frontiere).encode(),
    ])
    req = urllib.request.Request(API_URL + "/storage/upload", data=corps,
                                 method="POST")
    req.add_header("Content-Type",
                   "multipart/form-data; boundary=%s" % frontiere)
    req.add_header("X-Device-Id", DEVICE_ID)
    req.add_header("Authorization", "Bearer " + jeton)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read())
        except Exception:
            return e.code, {}
    except Exception as e:
        return None, {"code": "RESEAU: %s" % e}


# ─────────────────────────────────────────────────────────────────────────────
# Verdicts
# ─────────────────────────────────────────────────────────────────────────────

def verdict_presence(items, cible_id, doit_etre_la, quoi):
    """Présence/absence d'un commerçant dans une liste de promos."""
    if items is None:
        return "non_concluant", "%s : liste illisible" % quoi
    presents = {p.get("commercantId") for p in items}
    y_est = cible_id in presents
    if y_est == doit_etre_la:
        return "ok", "%s : %s" % (quoi, "présent" if y_est else "absent")
    if doit_etre_la:
        return "echec", ("%s : ABSENT alors qu'il devait y être — %d promo(s) "
                         "rendue(s)" % (quoi, len(items)))
    return "echec", ("%s : PRÉSENT alors qu'il est hors du cercle — le rayon "
                     "n'est qu'un cadre, les coins ne sont pas rognés" % quoi)


def verdict_ordre(items, premier_id, second_id, quoi):
    """Le plus proche doit précéder le plus lointain."""
    if items is None:
        return "non_concluant", "%s : liste illisible" % quoi
    rangs = {}
    for i, p in enumerate(items):
        rangs.setdefault(p.get("commercantId"), i)
    if premier_id not in rangs or second_id not in rangs:
        return "non_concluant", ("%s : les deux commerces ne sont pas tous les "
                                 "deux dans la liste" % quoi)
    if rangs[premier_id] < rangs[second_id]:
        return "ok", "%s : le proche avant le lointain" % quoi
    return "echec", ("%s : le lointain (rang %d) précède le proche (rang %d) — "
                     "le tri par distance ne s'applique pas"
                     % (quoi, rangs[second_id], rangs[premier_id]))


def _v(libelle, obtenu, attendu):
    if obtenu != attendu:
        print("  ❌ auto-test : %s → %r au lieu de %r" % (libelle, obtenu, attendu))
        return False
    return True


def self_test():
    """⚠️ Autant de cas qui doivent REFUSER que de cas qui passent (règle #28)."""
    ok = True

    # ── La géométrie du décor, d'abord : sans elle, tout le reste ment ──────
    coin_lat, coin_lng = point_du_coin(REF_LAT, REF_LNG, RAYON_KM)
    d = distance_km(REF_LAT, REF_LNG, coin_lat, coin_lng)
    ok &= _v("le point du coin est HORS du cercle", d > RAYON_KM, True)
    ok &= _v("le point du coin est DANS le cadre",
             abs(coin_lat - REF_LAT) < RAYON_KM / 111.32
             and abs(coin_lng - REF_LNG)
             < RAYON_KM / (111.32 * math.cos(math.radians(REF_LAT))), True)
    ok &= _v("le point du coin reste sous le rayon large", d < RAYON_LARGE_KM, True)
    # Le cosinus de latitude est appliqué : à 34,7° un décalage d'un degré de
    # longitude vaut ~91 km, pas 111.
    _, est = decaler(REF_LAT, REF_LNG, 0, 100)
    ok &= _v("le cosinus de latitude est appliqué",
             round(distance_km(REF_LAT, REF_LNG, REF_LAT, est)) == 100, True)

    # ── Doivent PASSER ──────────────────────────────────────────────────────
    ok &= _v("présent et attendu présent",
             verdict_presence([{"commercantId": "a"}], "a", True, "x")[0], "ok")
    ok &= _v("absent et attendu absent",
             verdict_presence([{"commercantId": "b"}], "a", False, "x")[0], "ok")
    ok &= _v("ordre respecté",
             verdict_ordre([{"commercantId": "a"}, {"commercantId": "b"}],
                           "a", "b", "x")[0], "ok")

    # ── Doivent REFUSER ─────────────────────────────────────────────────────
    # ⚠️ LE cas du banc : un serveur qui ne rognerait pas les coins rendrait le
    # commerce du coin, et ce verdict doit le voir.
    ok &= _v("coin rendu alors qu'il est hors du cercle",
             verdict_presence([{"commercantId": "a"}], "a", False, "x")[0], "echec")
    ok &= _v("proche absent alors qu'il devait y être",
             verdict_presence([], "a", True, "x")[0], "echec")
    ok &= _v("ordre inversé",
             verdict_ordre([{"commercantId": "b"}, {"commercantId": "a"}],
                           "a", "b", "x")[0], "echec")
    # ── Ne doivent RIEN conclure ────────────────────────────────────────────
    ok &= _v("liste illisible",
             verdict_presence(None, "a", True, "x")[0], "non_concluant")
    ok &= _v("ordre indécidable si l'un manque",
             verdict_ordre([{"commercantId": "a"}], "a", "b", "x")[0],
             "non_concluant")

    if ok:
        print("  ✅ auto-test : 11 cas, dont 5 qui doivent refuser ou ne pas conclure")
        print("     (dont la géométrie du décor : le coin est bien dans le "
              "cadre ET hors du cercle)")
    return ok


def _exiger(nom):
    valeur = os.environ.get(nom)
    if not valeur:
        print("❌ %s absent de l'environnement — coller le bloc export du décor."
              % nom)
        sys.exit(2)
    return valeur


def main():
    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-44s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    agent_email = _exiger("AGENT_EMAIL")
    agent_password = _exiger("AGENT_PASSWORD")

    st, d = appeler("POST", "/agent/login",
                    corps={"email": agent_email, "password": agent_password})
    jeton = d.get("accessToken")
    if not jeton:
        print("  ⚠️  connexion agent impossible (%s %s)" % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    st, up = televerser(jeton, "promo")
    cle = up.get("key")
    if not cle:
        print("  ⚠️  téléversement impossible (%s)" % st)
        return 2
    time.sleep(PACE)

    crees = []

    def poser_commerce(nom, lat, lng, base):
        """Crée un commerçant positionné et lui publie une promo.

        ⚠️ La position est **obligatoire** sur cette route depuis le
        2026-08-12 : un décor qui l'oublierait serait refusé ici, franchement,
        au lieu de produire un commerce invisible qu'on chercherait plus tard.
        """
        st, d = appeler("POST", "/agent/commercant", jeton, {
            "telephone": "+213556%s" % base, "nom": nom, "pin": PIN,
            "categorie": "alimentation",
            "latitude": lat, "longitude": lng})
        if st not in (200, 201):
            return None, "création refusée (%s %s)" % (st, d.get("code"))
        cid = d.get("id")
        crees.append(("+213556%s" % base, cid))
        time.sleep(PACE)
        st, d = appeler("POST", "/promo/agent/%s" % cid, jeton, {
            "description": "Banc rayon — %s" % nom,
            "prixAvant": 1000, "prixApres": 700,
            "categorie": "alimentation", "photoKeys": [cle]})
        if st not in (200, 201):
            return None, "promo refusée (%s %s)" % (st, d.get("code"))
        time.sleep(PACE)
        return cid, None

    print("── 1. deux commerces posés à des distances CHOISIES ──")
    base = time.strftime("%H%M%S")
    proche_lat, proche_lng = decaler(REF_LAT, REF_LNG, 1.0, 0.0)
    coin_lat, coin_lng = point_du_coin(REF_LAT, REF_LNG, RAYON_KM)

    d_proche = distance_km(REF_LAT, REF_LNG, proche_lat, proche_lng)
    d_coin = distance_km(REF_LAT, REF_LNG, coin_lat, coin_lng)
    print("  ⓘ  proche à %.2f km, coin à %.2f km — rayon éprouvé %.0f km"
          % (d_proche, d_coin, RAYON_KM))
    # ⚠️ La prémisse géométrique, vérifiée et non supposée : si le décor visait
    # à côté, tout ce qui suit mesurerait autre chose (règle #38).
    if not (d_proche < RAYON_KM < d_coin < RAYON_LARGE_KM):
        print("  ⚠️  décor incohérent — les distances ne encadrent pas le rayon")
        return 2

    id_proche, err = poser_commerce("Rayon Proche", proche_lat, proche_lng, base)
    if err:
        print("  ⚠️  commerce proche : %s" % err)
        return 2
    # ⚠️ **`%06d`, et ce n'est pas cosmétique.** Le suffixe s'écrivait
    # `str(int(base) + 1)` : `base` vient de `%H%M%S`, donc entre minuit et
    # 10 h il commence par un zéro — `int("023059") + 1` rend `23060`, et
    # `str()` le sert sur **cinq** chiffres. Le numéro devenait trop court et la
    # création était refusée en `VALIDATION_ERROR`.
    #
    # Ce banc échouait donc **selon l'heure de la journée**, sur un produit
    # parfaitement sain, et son message accusait la création (règle #38).
    # Trouvé le 2026-08-13 à 2 h du matin — il aurait pu ne jamais l'être en
    # ne le lançant qu'aux heures ouvrables.
    id_coin, err = poser_commerce("Rayon Coin", coin_lat, coin_lng,
                                  "%06d" % (int(base) + 1))
    if err:
        print("  ⚠️  commerce du coin : %s" % err)
        return 2
    print("  ⓘ  décor posé")

    def lister(rayon, extra=""):
        """Items servis, ou `None` si la réponse est illisible OU TRONQUÉE.

        ⚠️ **`limit=50` a fait échouer ce banc le 2026-08-13**, sur un produit
        correct. La liste est triée par distance et plafonnée : le décor ayant
        grossi, plus de cinquante promos se trouvaient plus près que le commerce
        du coin à 3,9 km, qui tombait donc hors de la page. Le banc lisait une
        page tronquée comme une absence et accusait le rayon.

        C'est la règle 15 retournée contre un banc — le piège même que
        `recherche_parc` a été écrit pour attraper ailleurs. On demande donc le
        maximum serveur, **et on refuse de conclure si le total le dépasse** :
        une troncature ne peut pas prouver une absence.
        """
        st, d = appeler(
            "GET", "/promo?latitude=%s&longitude=%s&radiusKm=%s&limit=100%s"
            % (REF_LAT, REF_LNG, rayon, extra))
        if st != 200:
            return None
        items = d.get("items")
        total = d.get("total")
        if items is not None and total is not None and total > len(items):
            print("     ⚠️  %d promos annoncées, %d lues : page tronquée, "
                  "aucune absence n'y est démontrable" % (total, len(items)))
            return None
        return items

    print("\n── 2. au rayon %.0f km : le proche est là, le coin ne l'est pas ──"
          % RAYON_KM)
    items = lister(RAYON_KM)
    noter("le commerce proche est rendu",
          *verdict_presence(items, id_proche, True, "proche"))
    # ⚠️ LE contrôle qui justifie ce banc : dans le carré, hors du cercle.
    noter("le commerce du coin est écarté",
          *verdict_presence(items, id_coin, False, "coin"))
    time.sleep(PACE)

    print("\n── 3. au rayon %.0f km : le coin apparaît — il POUVAIT apparaître ──"
          % RAYON_LARGE_KM)
    larges = lister(RAYON_LARGE_KM)
    noter("le coin est rendu quand le rayon s'élargit",
          *verdict_presence(larges, id_coin, True, "coin élargi"))
    noter("le tri par distance place le proche devant",
          *verdict_ordre(larges, id_proche, id_coin, "ordre"))
    time.sleep(PACE)

    print("\n── 4. une recherche textuelle IGNORE le rayon ──")
    # R8 du plan : chercher est un acte intentionnel avec une cible ; le borner
    # au voisinage rendrait le produit moins capable qu'avant la bascule.
    cherchees = lister(RAYON_KM, "&search=Banc%20rayon")
    noter("le coin ressort malgré le rayon serré",
          *verdict_presence(cherchees, id_coin, True, "recherche"))

    # ── Nettoyage : ne pas laisser deux commerces de plus à chaque passage ──
    #
    # ⚠️ Ce n'est pas de la coquetterie. Sans lui, chaque exécution ajoutait deux
    # commerces au voisinage du décor — et le 2026-08-12 le parcours « carte » a
    # fini par échouer parce que la carte les regroupait tous en grappes au lieu
    # d'afficher le marqueur qu'il cherchait. Un banc qui laisse des traces finit
    # par faire échouer un AUTRE banc, et l'échec accuse alors le mauvais endroit.
    #
    # Auto-suppression : le banc connaît le PIN qu'il a posé, donc pas besoin
    # d'identifiants admin.
    for tel, _cid in crees:
        time.sleep(PACE)
        _, d = appeler("POST", "/commercant/login",
                       corps={"telephone": tel, "pin": PIN})
        jc = d.get("accessToken")
        if jc:
            appeler("DELETE", "/commercant/me", jc)

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
