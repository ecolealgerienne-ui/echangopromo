#!/usr/bin/env python3
"""Banc de la tournée — l'agent crée un commerce, le garnit, et le client voit.

── Le trou que ce banc comble, et il est au milieu ─────────────────────────

Les deux moitiés de la tournée sont éprouvées ; **leur jointure ne l'est pas** :

  · `agent_creation` s'arrête à la naissance du commerçant — il vérifie que la
    position est obligatoire et servie sur la fiche publique, puis s'arrête ;
  · `agent_promo` publie sur un commerçant **du décor**, déjà là — il vérifie à
    qui la promo appartient et quelle clé S3 elle accepte.

Personne ne parcourt la chaîne entière : **créer le commerce, lui publier ses
promos, et vérifier que le client les voit à cet endroit-là.** C'est pourtant le
travail réel d'une tournée, et c'est exactement ce que la garde « position
obligatoire » existe pour rendre possible. Les deux moitiés peuvent être vertes
avec une chaîne cassée au milieu — une promo créée pour un commerce dont la
position n'est pas reprise dans l'index géographique n'apparaîtrait nulle part,
et **rien ne lèverait**.

── ⚠️ La sonde négative n'est pas une décoration ───────────────────────────

Le commerce est créé **loin** du décor à trois villes, et on vérifie ses promos
présentes à son point **et absentes** depuis une ville éloignée. Sans cette
seconde moitié, « le client voit les promos » serait vrai d'un serveur qui sert
tout le parc à tout le monde — le contrôle passerait sur le défaut qu'il est
censé attraper.

── Ce que ce banc laisse derrière lui, et c'est dit ────────────────────────

Un commerçant et ses promos, à un point désert choisi exprès pour ne gêner ni
les autres bancs ni vos tests manuels. Il n'existe pas de route d'agent pour
supprimer un commerçant (`POST /admin/commercant/:id/delete` est admin+agent, et
ce banc n'a pas d'identifiants admin) : la trace est assumée plutôt que cachée.

── Usage ───────────────────────────────────────────────────────────────────

    python3 scripts/lib/tournee_agent.py --self-test
    ./scripts/test-tournee-agent.sh
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://localhost:3000")
PACE = float(os.environ.get("PACE_SECONDS", "1.2"))
DEVICE_ID = "banc-tournee-0001"
# ⚠️ **Six chiffres minimum** : `CreateCommercantDto` exige 6 à 12. Un PIN à
# quatre chiffres rend 400 VALIDATION_ERROR — mesuré, pas supposé.
PIN = os.environ.get("BANC_PIN", "654321")

# ⚠️ **Un point désert, et choisi pour ça.** Le décor vit à Djelfa (34.67, 3.26),
# Hassi Bahbah (35.08, 3.03) et Alger (36.75, 3.06). Celui-ci est à plus de
# 150 km des trois : les promos de ce banc ne peuvent pas polluer une liste
# qu'un autre banc — ou vous — regarde.
TOURNEE_LAT = float(os.environ.get("TOURNEE_LAT", "32.4900"))
TOURNEE_LNG = float(os.environ.get("TOURNEE_LNG", "3.6700"))

# La ville éloignée qui sert de témoin négatif.
LOIN_LAT = float(os.environ.get("LOIN_LAT", "36.7538"))
LOIN_LNG = float(os.environ.get("LOIN_LNG", "3.0588"))

PROMOS_A_CREER = 2


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_naissance(fiche, lat, lng):
    """Le commerce naît AVEC son point, et le point est **servi**.

    ⚠️ Vérifié sur la fiche publique et non sur la réponse de création : un
    point stocké mais non servi produit exactement l'invisibilité que la garde
    cherche à empêcher (40 des 44 commerçants sans position venaient de cette
    route, mesuré le 2026-08-12).
    """
    if not fiche:
        return "non_concluant", "fiche publique illisible"
    f_lat, f_lng = fiche.get("latitude"), fiche.get("longitude")
    # ⚠️ `is None`, jamais une évaluation de vérité : la longitude 0 est valide.
    if f_lat is None or f_lng is None:
        return ("echec",
                "le commerce est né sans position servie : il n'apparaîtra sur "
                "aucune carte et ne sortira d'aucune liste au rayon")
    if abs(f_lat - lat) > 0.001 or abs(f_lng - lng) > 0.001:
        return ("echec",
                "position servie (%s, %s) différente de celle demandée "
                "(%s, %s)" % (f_lat, f_lng, lat, lng))
    return "ok", "(%s, %s), servie sur la fiche publique" % (f_lat, f_lng)


def verdict_promos_creees(ids, attendu):
    """Les promos de la tournée existent-elles toutes ?"""
    if ids is None:
        return "non_concluant", "création illisible"
    if len(ids) != attendu:
        return ("echec",
                "%d promo(s) créée(s) sur %d demandées — une tournée "
                "incomplète ne se voit nulle part" % (len(ids), attendu))
    return "ok", "%d promos publiées pour le commerce neuf" % len(ids)


def verdict_client_voit(ids_servies, ids_attendues):
    """⚠️ **La jointure**, et c'est tout l'objet de ce banc.

    Le client posé au point du commerce doit voir **toutes** ses promos. Une
    seule manquante signale une chaîne cassée entre la création et l'index
    géographique — et rien ne lève dans ce cas.
    """
    if ids_servies is None:
        return "non_concluant", "liste client illisible"
    if not ids_attendues:
        return "non_concluant", "aucune promo attendue — rien à chercher"
    manquantes = ids_attendues - ids_servies
    if manquantes:
        return ("echec",
                "%d promo(s) sur %d absentes de la liste du client posé au "
                "point du commerce : créées, mais introuvables — et aucune "
                "erreur ne le dira"
                % (len(manquantes), len(ids_attendues)))
    return "ok", "les %d promos sont servies au point du commerce" % len(
        ids_attendues)


def verdict_temoin_negatif(ids_servies, ids_tournee, servies_ici):
    """⚠️ Sans lui, « le client voit » serait vrai d'un serveur qui sert tout.

    Depuis une ville à plus de 150 km, aucune promo de la tournée ne doit
    apparaître. Et le témoin ne vaut que si la présence a été établie d'abord
    (règle 28 : une absence seule est satisfaite par n'importe quel chargement).
    """
    if ids_servies is None:
        return "non_concluant", "liste éloignée illisible"
    if not servies_ici:
        return ("non_concluant",
                "la présence au point du commerce n'a pas été établie : "
                "l'absence au loin ne prouverait rien")
    fuites = ids_servies & ids_tournee
    if fuites:
        return ("echec",
                "%d promo(s) de la tournée servie(s) à un client situé à plus "
                "de 150 km : la liste ne suit pas le point, elle sert tout"
                % len(fuites))
    return "ok", "aucune promo de la tournée servie au loin"


def verdict_fiche_garnie(ids_servies, ids_attendues):
    """La fiche du commerce montre-t-elle ses promos ?

    ⚠️ **La fiche publique ne les porte PAS**, et je l'ai supposé avant de le
    mesurer : `GET /commercant/:id/public` ne sert que adresse, categorie, id,
    latitude, longitude, nom, photoUrl, telephone. L'écran les demande par
    `GET /promo?commercantId=…` — le « périmètre explicite » du DTO, où **aucun
    filtre géographique ne s'applique**.

    C'est donc l'autre moitié du produit : la liste suit le point, la fiche
    d'un commerce précis n'a pas à le suivre. Un commerce garni dont la fiche
    reste vide est un commerce mort à l'écran.
    """
    if ids_servies is None:
        return "non_concluant", "GET /promo?commercantId illisible"
    if not ids_attendues:
        return "non_concluant", "aucune promo attendue — rien à chercher"
    manquantes = ids_attendues - ids_servies
    if manquantes:
        return ("echec",
                "%d promo(s) sur %d absentes de la fiche du commerce : le "
                "client qui ouvre le magasin depuis la carte ne les voit pas"
                % (len(manquantes), len(ids_attendues)))
    return "ok", "les %d promos sont servies sur la fiche du commerce" % len(
        ids_attendues)


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
    trois = {"p1", "p2", "p3"}

    # ── Doivent PASSER ───────────────────────────────────────────────────────
    _v("né avec son point",
       verdict_naissance({"latitude": 32.49, "longitude": 3.67},
                         32.49, 3.67)[0], "ok")
    # ⚠️ Longitude 0 : Greenwich est une coordonnée valide, pas une absence.
    _v("longitude zéro acceptée",
       verdict_naissance({"latitude": 51.5, "longitude": 0}, 51.5, 0)[0], "ok")
    _v("promos créées", verdict_promos_creees({"p1", "p2"}, 2)[0], "ok")
    _v("le client les voit", verdict_client_voit(trois, {"p1", "p2"})[0], "ok")
    _v("rien au loin",
       verdict_temoin_negatif({"autre"}, trois, True)[0], "ok")
    _v("fiche garnie",
       verdict_fiche_garnie({"p1", "p2"}, {"p1", "p2"})[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le défaut fondateur : un commerce né sans position, invisible partout.
    _v("né sans position",
       verdict_naissance({"latitude": None, "longitude": 3.67},
                         32.49, 3.67)[0], "echec")
    _v("position déplacée",
       verdict_naissance({"latitude": 30.0, "longitude": 3.67},
                         32.49, 3.67)[0], "echec")
    _v("tournée incomplète", verdict_promos_creees({"p1"}, 2)[0], "echec")
    # ⚠️ La jointure cassée : créées, mais introuvables.
    _v("promo introuvable",
       verdict_client_voit({"p1"}, {"p1", "p2"})[0], "echec")
    # ⚠️ Le serveur qui sert tout à tout le monde.
    _v("fuite au loin",
       verdict_temoin_negatif({"p1"}, trois, True)[0], "echec")
    _v("fiche vide", verdict_fiche_garnie(set(), {"p1", "p2"})[0], "echec")

    # ── Doivent rester NON CONCLUANTS ────────────────────────────────────────
    # ⚠️ Une absence au loin sans présence établie ne prouve rien (règle 28).
    _v("présence non établie",
       verdict_temoin_negatif({"autre"}, trois, False)[0], "non_concluant")
    _v("fiche illisible", verdict_naissance(None, 32.49, 3.67)[0],
       "non_concluant")
    _v("création illisible", verdict_promos_creees(None, 2)[0], "non_concluant")
    _v("liste client illisible",
       verdict_client_voit(None, trois)[0], "non_concluant")
    _v("rien à chercher", verdict_client_voit(trois, set())[0], "non_concluant")
    _v("liste éloignée illisible",
       verdict_temoin_negatif(None, trois, True)[0], "non_concluant")
    _v("fiche illisible",
       verdict_fiche_garnie(None, {"p1"})[0], "non_concluant")
    _v("fiche sans attendu",
       verdict_fiche_garnie({"p1"}, set())[0], "non_concluant")

    refus = 14
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
    print("  Tournée — l'agent crée un commerce, le garnit, et le client voit")
    print("═" * 70)
    print("  point de tournée : %s, %s (désert, à >150 km du décor)"
          % (TOURNEE_LAT, TOURNEE_LNG))

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

    def promos_autour(lat, lng):
        st, d = appeler("GET", "/promo?limit=100&latitude=%s&longitude=%s"
                        % (lat, lng))
        if st != 200 or d.get("items") is None:
            return None
        return {i.get("id") for i in d["items"]}

    # ── 1. Le commerce naît en tournée, avec son point ──────────────────────
    print("\n── 1. l'agent crée le commerce, avec sa position ──")
    base = time.strftime("%H%M%S")
    st, d = appeler("POST", "/agent/commercant", jg, {
        "telephone": "+213557%s" % base, "nom": "Commerce de Tournée",
        "pin": PIN, "adresse": "Piste de tournée", "categorie": "alimentation",
        "latitude": TOURNEE_LAT, "longitude": TOURNEE_LNG})
    cid = d.get("id")
    if not cid:
        print("❌ création refusée (HTTP %s, %s)" % (st, d.get("code")))
        return 2
    time.sleep(PACE)
    _, fiche = appeler("GET", "/commercant/%s/public" % cid)
    noter("le commerce est né avec sa position",
          *verdict_naissance(fiche, TOURNEE_LAT, TOURNEE_LNG))
    time.sleep(PACE)

    # ── 2. L'agent le garnit ────────────────────────────────────────────────
    print("\n── 2. l'agent lui publie ses promos ──")
    ids_tournee = set()
    echec_creation = False
    for i in range(PROMOS_A_CREER):
        st, d = appeler("POST", "/promo/agent/%s" % cid, jg, {
            "description": "Promo de tournée %d" % (i + 1),
            "prixAvant": 1000 + i * 100, "prixApres": 700 - i * 50,
            "categorie": "alimentation" if i == 0 else "autre",
            "photoKeys": ["promo-photos/%s/tournee-%d.jpg" % (cid, i)]})
        if d.get("id"):
            ids_tournee.add(d["id"])
        else:
            echec_creation = True
            print("     ⚠️ promo %d refusée : HTTP %s %s"
                  % (i + 1, st, d.get("code")))
        time.sleep(PACE)
    noter("les promos de la tournée existent",
          *verdict_promos_creees(None if echec_creation and not ids_tournee
                                 else ids_tournee, PROMOS_A_CREER))

    # ── 3. ⚠️ La jointure : le client les voit à ce point ───────────────────
    print("\n── 3. le client posé sur ce point voit les promos ──")
    ids_ici = promos_autour(TOURNEE_LAT, TOURNEE_LNG)
    noter("liste client au point du commerce",
          *verdict_client_voit(ids_ici, ids_tournee))
    servies_ici = ids_ici is not None and ids_tournee <= ids_ici
    time.sleep(PACE)

    # ⚠️ `?commercantId=` est un « périmètre explicite » : aucun filtre
    # géographique ne s'applique, et c'est voulu — ouvrir un magasin précis
    # n'interroge pas un voisinage.
    st, d = appeler("GET", "/promo?limit=100&commercantId=%s" % cid)
    ids_fiche = ({p.get("id") for p in d["items"]}
                 if st == 200 and d.get("items") is not None else None)
    noter("la fiche du commerce porte ses promos",
          *verdict_fiche_garnie(ids_fiche, ids_tournee))
    time.sleep(PACE)

    # ── 4. Et un client éloigné n'en voit aucune ────────────────────────────
    print("\n── 4. … et un client à plus de 150 km n'en voit aucune ──")
    ids_loin = promos_autour(LOIN_LAT, LOIN_LNG)
    noter("liste client au loin",
          *verdict_temoin_negatif(ids_loin, ids_tournee, servies_ici))

    print("\n" + "═" * 70)
    print("⚠️  Ce banc laisse un commerce et %d promos à (%s, %s) — point "
          "désert choisi pour ne gêner ni les autres bancs ni vos tests."
          % (len(ids_tournee), TOURNEE_LAT, TOURNEE_LNG))
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
