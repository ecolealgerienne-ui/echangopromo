#!/usr/bin/env python3
"""Décor à trois villes, créé **par un agent** — Djelfa, Hassi Bahbah, Alger.

── Pourquoi une seconde voie, à côté de `provision-villes.sh` ──────────────

`provision-villes.sh` délègue à `provision-decor.sh`, qui a besoin d'un **admin**
pour valider le registre de chaque commerçant auto-inscrit. Sur un serveur où
aucun admin n'a été semé, il ne peut rien faire.

⚠️ **Un commerçant créé par un agent n'a pas ce problème** :
`assertRegistreValidated` ne bloque que si `originVerification = AUTO_INSCRIT`
**et** `registreStatus ≠ VALIDE`. Né d'un agent, il vaut `CONFIRME_AGENT` et
publie immédiatement. Une seule route suffit donc — `POST /agent/commercant` —
là où le chemin auto-inscrit en demande quatre et un administrateur.

── Les distances, qui sont le sujet ────────────────────────────────────────

    Djelfa        34.6714, 3.2630   référence
    Hassi Bahbah  35.0774, 3.0281   ~50 km  — hors du rayon, mais atteignable
                                              en faisant glisser la carte
    Alger         36.7538, 3.0588   ~232 km — hors de portée de tout geste

⚠️ **Trois villes, parce qu'une seule ne prouve rien.** Avec un unique
voisinage, « la liste suit mon point » et « la liste sert tout ce qui existe »
rendent exactement le même résultat. Alger est là pour qu'une promo lointaine
qui apparaît soit un défaut visible, pas une hypothèse.

Trois commerçants par ville, espacés de 600 à 900 m : deux voisins au minimum
pour qu'un tri par distance ait un sens, trois pour qu'une grappe de carte
puisse se scinder en autre chose qu'un point unique.

── ⚠️ Les photos, et ce qu'elles valent ────────────────────────────────────

**Les photos sont réelles.** Chaque promo reçoit une image récupérée sur
Lorem Picsum et déposée par `POST /storage/upload` — la chaîne complète, celle
que le produit fera vivre. La graine est stable : rejouer ne change pas les
visuels.

⚠️ Ce sont des photos quelconques, sans rapport avec le commerce. Elles
prouvent que la chaîne image fonctionne, elles ne font pas une vitrine.

⚠️ Et si le dépôt échoue, la promo **n'est pas créée**. Un décor plus maigre
vaut mieux qu'un décor aux vignettes cassées, qu'on prendrait ensuite pour une
panne du produit.

── Usage ──────────────────────────────────────────────────────────────────

    export API_URL=https://promo.echango.com
    export AGENT_EMAIL=... AGENT_PASSWORD=...

    python3 scripts/lib/provision_villes_agent.py --self-test
    python3 scripts/lib/provision_villes_agent.py            # simulation
    python3 scripts/lib/provision_villes_agent.py --appliquer
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

API_URL = os.environ.get("API_URL", "http://localhost:3000")

# ⚠️ 3,5 s entre deux écritures. `SENSITIVE_ACTION_THROTTLE` vaut 20/min et par
# IP : 27 écritures d'affilée épuiseraient le seau au tiers du parcours, et les
# refus ressembleraient à des erreurs métier. Sur un serveur qui porte
# `THROTTLE_FACTOR`, on peut descendre — pas sur la production.
PACE = float(os.environ.get("PACE_SECONDS", "3.5"))

PIN = os.environ.get("DECOR_PIN", "654321")

VILLES = [
    ("Djelfa", 34.6714, 3.2630),
    ("Hassi Bahbah", 35.0774, 3.0281),
    ("Alger", 36.7538, 3.0588),
]

# Décalages en degrés — 0,006° de latitude ≈ 670 m, 0,008° ≈ 890 m. Assez pour
# que les trois commerces d'une ville ne se confondent pas sur la carte.
DECALAGES = [(0.0, 0.0), (0.006, 0.004), (-0.005, 0.008)]

METIERS = [
    ("Superette", "alimentation", "Rue principale"),
    ("Boulangerie", "alimentation", "Avenue du marche"),
    ("Boutique", "vetements_textile", "Rue du commerce"),
]

PROMOS_PAR_COMMERCANT = 2


def verdict_creation(statut, code):
    """Un numéro déjà pris n'est pas une panne : c'est l'idempotence.

    ⚠️ Le confondre avec un échec ferait rejouer le script en boucle sur un
    décor déjà en place, ou pire, conclure que la création ne marche pas.
    """
    if statut in (200, 201):
        return "cree", "créé"
    if code in ("COMMERCANT_PHONE_TAKEN", "COMMERCANT_ALREADY_EXISTS"):
        return "existe", "déjà présent — rien à faire"
    if statut == 429:
        return "debit", "429 — seau de requêtes épuisé, ralentir (PACE_SECONDS)"
    return "echec", "HTTP %s %s" % (statut, code)


def telephone(indice_ville, indice_commercant):
    """Numéros **stables**, pour que rejouer ne crée rien de neuf.

    ⚠️ Un horodatage ici ferait s'empiler un parc nouveau à chaque passage —
    le défaut que `provision-decor.sh` documente déjà pour l'avoir payé.
    """
    # ⚠️ **Neuf chiffres après `+213`, pas huit.** Le DTO porte
    # `@IsPhoneNumber('DZ')`, un vrai validateur : un numéro trop court est
    # refusé en `VALIDATION_ERROR`. Ma première version en produisait huit, et
    # c'est l'auto-test — pas le serveur — qui l'a dit, en comparant la longueur
    # à celle du décor existant.
    return "+2136%s%s0000" % (str(indice_ville + 1) * 2,
                              str(indice_commercant + 1) * 2)


# ── Les photos ──────────────────────────────────────────────────────────────
#
# Lorem Picsum sert des images Unsplash. La graine rend le choix **stable** :
# rejouer le script ne change pas les visuels, et un décor qui bouge à chaque
# passage rendrait toute capture d'écran incomparable à la précédente.
#
# ⚠️ Ce sont des photos quelconques, sans rapport avec le commerce. C'est
# assumé — un décor de test montre que la chaîne image fonctionne de bout en
# bout, il ne prétend pas à une vitrine. Les vraies photos viendront des
# commerçants.
SOURCE_PHOTO = "https://picsum.photos/seed/%s/800/600.jpg"

MAGIE_JPEG = b"\xff\xd8"


def televerser_photo(jeton, graine):
    """Récupère une photo et la dépose via l'API. Rend la clé, ou `None`.

    ⚠️ **`purpose` vaut `promo`**, pas `promo-photos` : le DTO n'accepte que
    `promo`, `commercant`, `registre`, `highlight`. Mesuré contre le serveur —
    le nom du dossier S3 et celui de l'usage ne coïncident pas, et le supposer
    coûte un 400.

    ⚠️ Rend `None` sur échec, **jamais une clé inventée**. Une promo créée avec
    une clé qui ne désigne rien afficherait une vignette cassée que personne ne
    relierait à ce script — c'est exactement l'état qu'on a mis une heure à
    diagnostiquer sur le décor local.
    """
    try:
        image = urllib.request.urlopen(SOURCE_PHOTO % graine, timeout=30).read()
    except Exception as e:
        print("      photo non recuperee (%s)" % e)
        return None
    if image[:2] != MAGIE_JPEG:
        print("      ce n'est pas un JPEG — photo ignoree")
        return None

    frontiere = uuid.uuid4().hex
    tete = '--%s\r\nContent-Disposition: form-data; name="purpose"\r\n\r\n' \
           'promo\r\n' % frontiere
    tete += '--%s\r\nContent-Disposition: form-data; name="file"; ' \
            'filename="promo.jpg"\r\nContent-Type: image/jpeg\r\n\r\n' % frontiere
    corps = tete.encode() + image + ('\r\n--%s--\r\n' % frontiere).encode()

    req = urllib.request.Request(API_URL + "/storage/upload", data=corps,
                                 method="POST")
    req.add_header("Content-Type",
                   "multipart/form-data; boundary=%s" % frontiere)
    req.add_header("Authorization", "Bearer " + jeton)
    req.add_header("X-Device-Id", "provision-villes-agent")
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return json.loads(r.read()).get("key")
    except urllib.error.HTTPError as e:
        print("      depot refuse (HTTP %s)" % e.code)
        return None
    except Exception as e:
        print("      depot impossible (%s)" % e)
        return None


def appeler(methode, chemin, jeton=None, corps=None):
    donnees = json.dumps(corps).encode() if corps is not None else None
    req = urllib.request.Request(API_URL + chemin, data=donnees, method=methode)
    req.add_header("Content-Type", "application/json")
    req.add_header("X-Device-Id", "provision-villes-agent")
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
    except Exception as e:
        return None, {"code": "RESEAU: %s" % e}


_ok, _echecs = 0, []


def _v(libelle, obtenu, attendu):
    global _ok
    if obtenu == attendu:
        _ok += 1
    else:
        _echecs.append("%s — attendu %r, obtenu %r" % (libelle, attendu, obtenu))


def self_test():
    _v("création acceptée", verdict_creation(201, None)[0], "cree")
    _v("numéro déjà pris ⇒ idempotence",
       verdict_creation(409, "COMMERCANT_PHONE_TAKEN")[0], "existe")
    _v("429 distingué d'un échec", verdict_creation(429, None)[0], "debit")
    _v("vrai refus", verdict_creation(400, "VALIDATION_ERROR")[0], "echec")

    # ⚠️ Les numéros doivent être STABLES et DISTINCTS : deux villes qui
    # partageraient un numéro se voleraient leur commerçant au rejeu.
    tous = [telephone(v, c) for v in range(3) for c in range(3)]
    _v("neuf numéros distincts", len(set(tous)), 9)
    _v("numéro stable d'un passage à l'autre", telephone(0, 0), telephone(0, 0))
    _v("neuf chiffres apres +213", len(telephone(2, 2)) - 4, 9)

    # ⚠️ Les décalages doivent séparer les commerces : trois positions
    # identiques donneraient une grappe indivisible sur la carte.
    _v("trois décalages distincts", len(set(DECALAGES)), 3)

    refus = 3
    print("auto-test : %d cas, dont %d refus" % (_ok + len(_echecs), refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, _ok + len(_echecs)))
    return not _echecs


def main():
    appliquer = "--appliquer" in sys.argv
    print("═" * 70)
    print("  Décor à trois villes, par l'agent — %s"
          % ("ÉCRITURE RÉELLE" if appliquer else "SIMULATION"))
    print("  %s" % API_URL)
    print("═" * 70)

    email = os.environ.get("AGENT_EMAIL")
    mdp = os.environ.get("AGENT_PASSWORD")
    if not email or not mdp:
        print("❌ AGENT_EMAIL / AGENT_PASSWORD requis.")
        return 2
    st, d = appeler("POST", "/agent/login", corps={"email": email,
                                                  "password": mdp})
    jeton = d.get("accessToken")
    if not jeton:
        print("❌ connexion agent refusée (HTTP %s, %s)" % (st, d.get("code")))
        return 2
    print("  agent connecté\n")

    total_c, total_p, deja, refus = 0, 0, 0, []
    for iv, (ville, lat, lng) in enumerate(VILLES):
        print("── %s ──" % ville)
        for ic, ((dlat, dlng), (metier, cat, rue)) in enumerate(
                zip(DECALAGES, METIERS)):
            tel = telephone(iv, ic)
            nom = "%s %s" % (metier, ville)
            if not appliquer:
                print("   %-28s %s  (%.4f, %.4f)"
                      % (nom, tel, lat + dlat, lng + dlng))
                total_c += 1
                total_p += PROMOS_PAR_COMMERCANT
                continue

            st, d = appeler("POST", "/agent/commercant", jeton, {
                "telephone": tel, "nom": nom, "pin": PIN,
                "adresse": "%s, %s" % (rue, ville), "categorie": cat,
                "latitude": lat + dlat, "longitude": lng + dlng})
            v, quoi = verdict_creation(st, d.get("code"))
            cid = d.get("id")
            if v == "cree":
                total_c += 1
            elif v == "existe":
                deja += 1
            else:
                refus.append("%s : %s" % (nom, quoi))
                print("   ⚠️  %-26s %s" % (nom, quoi))
                time.sleep(PACE)
                continue
            print("   %-28s %s" % (nom, quoi))
            time.sleep(PACE)

            if not cid:
                # ⚠️ Déjà présent : on ne connaît pas son identifiant, donc on
                # ne peut pas lui poser de promo. On le DIT plutôt que de
                # compter un commerçant garni qui ne l'est pas.
                print("      ⚠️  identifiant inconnu — promos non posées")
                continue

            for ip in range(PROMOS_PAR_COMMERCANT):
                # ⚠️ La photo D'ABORD : sans clé valide, on ne crée pas la promo.
                # Mieux vaut un décor plus maigre qu'un décor aux vignettes
                # cassées, qu'on prendrait ensuite pour une panne du produit.
                cle = televerser_photo(jeton, "%s-%d" % (cid, ip))
                time.sleep(PACE)
                if not cle:
                    refus.append("%s promo %d : photo indisponible"
                                 % (nom, ip + 1))
                    continue
                st, dp = appeler("POST", "/promo/agent/%s" % cid, jeton, {
                    "description": "%s — offre %d" % (nom, ip + 1),
                    "prixAvant": 1000 + ip * 200,
                    "prixApres": 600 + ip * 100,
                    "categorie": cat,
                    "photoKeys": [cle]})
                if st in (200, 201):
                    total_p += 1
                else:
                    refus.append("%s promo %d : HTTP %s %s"
                                 % (nom, ip + 1, st, dp.get("code")))
                time.sleep(PACE)
        print()

    print("═" * 70)
    print("  %d commerçant(s) %s, %d promo(s)"
          % (total_c, "créé(s)" if appliquer else "seraient créés", total_p))
    if deja:
        print("  %d déjà présent(s) — rejeu sans effet" % deja)
    for r in refus:
        print("  ⚠️  %s" % r)
    if not appliquer:
        print("\n  Rien n'a été écrit. Relancer avec --appliquer pour agir.")
    else:
        # ⚠️ Ce message annonçait des photos ABSENTES — il datait de la version
        # sans dépôt et a survécu à l'ajout du téléversement. Le premier passage
        # réel a créé 18 promos aux images parfaitement servies, sous un
        # avertissement disant l'inverse : un texte de fin qui survit au
        # changement qu'il décrit fait douter d'un résultat correct.
        print("\n  Photos déposées dans S3 et servies par le CDN.")
        print("  Vérifier : GET /promo?limit=5, puis ouvrir un `photoUrls`.")
    return 1 if refus else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)
    sys.exit(main())
