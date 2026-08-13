#!/usr/bin/env python3
"""Banc de portée — un agent agit sur TOUT le parc, et pas au-delà.

── Ce que ce banc éprouve, et pourquoi il remplace `appartenance.py` ────────

Le 2026-08-13, le découpage administratif a disparu et **quatorze gardes
d'appartenance ont été retirées** : un agent n'est plus borné à ses communes,
il agit sur n'importe quel commerçant du pays. `appartenance.py` prouvait que
ces quatorze routes **refusaient** ; son sujet n'existe plus.

⚠️ **Le remplacer par rien aurait été le pire des deux mondes.** Un chantier
qui transforme quatorze refus en acceptations laisse derrière lui quatorze
routes dont personne ne sait si elles fonctionnent : le retrait d'une garde
peut très bien avoir laissé un `COMMERCANT_NOT_FOUND` résiduel, une jointure
sur une table détruite, ou un filtre de portée oublié dans un service. Rien
n'échouerait au démarrage, rien n'échouerait aux tests, et le seul signal
serait un agent qui, sur le terrain, n'y arrive pas.

Ce banc prouve donc l'**acceptation** — l'exact inverse de celui qu'il
remplace, sur les mêmes routes.

── ⚠️ Prouver une acceptation est plus fragile que prouver un refus ────────

Un refus se lit dans un code. Une acceptation, non : un `200` peut venir d'une
route qui n'a rien fait. Trois précautions, chacune contre un faux vert déjà
rencontré dans ce dépôt :

1. **L'effet est constaté, pas le statut** (règle 28). Suspendre se vérifie sur
   `suspended`, valider un registre sur `registreStatus`, publier sur ce que le
   CLIENT voit, réinitialiser un PIN en se connectant avec le nouveau. Là où
   l'effet n'est pas observable, c'est écrit.

2. **Un `VALIDATION_ERROR` n'est JAMAIS une réussite** — c'est « non concluant ».
   La requête est morte à la validation, **avant** d'atteindre la couche
   d'autorisation : elle n'a rien prouvé sur la portée. C'était déjà le piège
   central d'`appartenance.py`, et il se retourne à l'identique.

3. **Un `404` est un ÉCHEC, pas une absence.** Le commerçant existe — le banc
   vient de le créer et le voit dans la liste. Un `COMMERCANT_NOT_FOUND` sur ces
   routes serait très exactement la forme que prendrait une portée résiduelle :
   un service qui cherche encore dans un périmètre.

── Le témoin négatif, et pourquoi il passe EN PREMIER ──────────────────────

**Un banc qui n'observe que des acceptations passe au vert si TOUT est
accepté.** Il ne saurait pas dire qu'une garde qui devait rester est tombée —
et il resterait vert le jour où le rôle agent obtiendrait les droits d'admin
par accident.

La polarité qui subsiste après le chantier est le témoin : trois routes sont
`@Roles('admin')` **seul**, et l'agent doit y être refusé. Elles sont sondées
**avant** toute écriture, pour qu'un banc incapable de refuser soit démasqué
avant d'annoncer quatorze acceptations.

Le témoin est **en lecture** (`GET /admin/agent`, `GET /admin/audit-log`) sauf
pour `plafond-promos`, choisi parce qu'il écrit : si le refus tombe, on veut
l'apprendre sur une route dont l'effet est mesurable et réversible — pas sur
`POST /admin/agent`, qui créerait un agent que **rien ne permet de supprimer**.

── Le sujet : un commerçant que l'agent n'a PAS créé ───────────────────────

⚠️ La prémisse ne se lit pas, elle se **construit** (règle 38). Le banc inscrit
son commerçant par `POST /commercant/register` — l'auto-inscription, sans aucun
jeton d'agent. `createdByAgentId` vaut donc `null` **par construction**, et
aucun agent ne peut prétendre à cette fiche. L'API n'expose pas ce champ ; s'en
remettre à une lecture aurait été plus faible que de le savoir.

Et c'est le cas le plus dur : un auto-inscrit traîne la garde de registre, que
les fiches créées par un agent ne connaissent pas.

── ⚠️ Ce banc est DESTRUCTEUR, et il ne l'était pas avant ──────────────────

`appartenance.py` était sans effet de bord **parce que ses sondes étaient
refusées**. Ici elles passent : suspendre, réinitialiser un PIN, masquer,
**supprimer**. D'où trois règles tenues par la structure du fichier :

- le sujet est **jetable et créé par le banc**, jamais celui du décor ;
- `delete` est la **dernière** sonde, et son effet est justement que la fiche
  disparaisse ;
- l'ordre suit les préconditions métier plutôt que la liste des routes — publier
  exige registre validé, profil validé et position posée. Sonder `publish` avant
  d'avoir satisfait les trois rendrait un refus **légitime** que le banc lirait
  comme une garde résiduelle. C'est la règle 38 dans sa forme la plus coûteuse :
  un banc rouge sur un produit correct.

── ⚠️ Le budget de requêtes, qui dimensionne la temporisation ──────────────

Quatorze écritures sondées, plus le décor, tombent toutes dans
`SENSITIVE_ACTION_THROTTLE` — **20/min/IP, et c'est un seau PARTAGÉ**. Le banc
en émet une vingtaine : à cadence libre il se refuserait lui-même à mi-course.
`PACE` vaut donc 4 s par défaut, ce qui étale la course sur ~100 s et maintient
toute fenêtre de 60 s sous le plafond. Le banc dure environ deux minutes ; c'est
le prix d'un seau partagé, pas une lenteur à optimiser.

Les connexions (50/min depuis le 2026-08-13) et l'unique inscription (5/min) ne
sont pas contraignantes ici.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/portee_agent.py --self-test
    ./scripts/test-portee-agent.sh
"""

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

API_URL = os.environ.get("API_URL", "http://localhost:3000")
# ⚠️ 4 s : voir « budget de requêtes » en en-tête. Baisser cette valeur fait
# échouer le banc sur son propre plafond, pas sur le produit.
PACE = float(os.environ.get("PACE_SECONDS", "4"))
DEVICE_ID = "banc-portee-0001"
PIN = "654321"
PIN_NEUF = "987654"
# Position de décor, à Djelfa. Obligatoire pour publier (`assertPositionSet`) —
# sans elle, `publish` refuserait pour une raison métier parfaitement légitime
# et le banc accuserait une garde qui n'existe plus (règle 38).
DECOR_LAT, DECOR_LNG = 34.6714, 3.2630

JPEG_1x1 = base64.b64decode(
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof"
    "Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB"
    "AAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q=="
)


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_acceptation(statut, code):
    """L'agent doit être ACCEPTÉ : la garde d'appartenance a été retirée.

    ⚠️ Les trois cas non-évidents, chacun contre un faux vert :
    - `VALIDATION_ERROR` → non concluant : la requête est morte AVANT la couche
      d'autorisation, elle n'a rien dit de la portée ;
    - `404` → échec : le commerçant existe, le banc vient de le créer. Un
      « introuvable » est la forme que prendrait une portée résiduelle ;
    - `403` → échec : c'est la garde qu'on croyait retirée.
    """
    if statut is None:
        return "non_concluant", "pas de réponse : %s" % code
    if statut == 429:
        return "non_concluant", "429 — plafond de requêtes, pas un verdict"
    if code == "VALIDATION_ERROR":
        return ("non_concluant",
                "VALIDATION_ERROR — la requête est morte à la validation, "
                "avant toute décision d'autorisation : le corps de la sonde "
                "est en cause, pas le produit")
    if statut in (200, 201, 204):
        return "ok", "HTTP %s" % statut
    if statut == 403:
        return ("echec",
                "403 %s — la garde d'appartenance est TOUJOURS là, alors "
                "qu'elle a été retirée le 2026-08-13" % (code or ""))
    if statut == 404:
        return ("echec",
                "404 %s — le commerçant existe (ce banc l'a créé et le voit "
                "dans la liste). Un « introuvable » ici est une portée "
                "résiduelle, pas une absence" % (code or ""))
    return "echec", "HTTP %s %s" % (statut, code or "")


def verdict_refus_role(statut, code):
    """Le témoin négatif : ces routes sont `@Roles('admin')` SEUL.

    Sans lui, un banc qui n'observe que des acceptations passerait au vert si
    tout était accepté — y compris ce qui ne doit jamais l'être (règle 28).
    """
    if statut is None:
        return "non_concluant", "pas de réponse : %s" % code
    if statut == 429:
        return "non_concluant", "429 — plafond de requêtes, pas un verdict"
    if code == "VALIDATION_ERROR":
        return ("non_concluant",
                "VALIDATION_ERROR — refusée avant le contrôle de rôle, donc "
                "le refus observé n'est pas celui qu'on mesure")
    if statut in (200, 201, 204):
        return ("echec",
                "HTTP %s — un AGENT a été admis sur une route réservée à "
                "l'admin. Le rôle ne borne plus rien" % statut)
    if statut == 403 and code == "AUTH_FORBIDDEN_ROLE":
        return "ok", "403 AUTH_FORBIDDEN_ROLE"
    return ("echec",
            "HTTP %s %s — refusé, mais pas pour le rôle : indiscernable d'un "
            "refus accidentel" % (statut, code or ""))


def verdict_effet(observe, attendu, quoi):
    """Ce qui compte est l'effet, pas le code de sortie (règle 28).

    ⚠️ **`None` veut dire « illisible » et rien d'autre.** Un appelant qui
    passerait une valeur métier légitimement nulle obtiendrait « non concluant »
    sur un produit correct — c'est arrivé au premier passage, sur
    `promoActiveCap`. Ramener la comparaison à un booléen chez l'appelant, pas
    élargir ce verdict.
    """
    if observe is None:
        return "non_concluant", "%s : état illisible" % quoi
    if observe != attendu:
        return ("echec",
                "%s : %r au lieu de %r — la route a répondu, elle n'a rien fait"
                % (quoi, observe, attendu))
    return "ok", "%s = %r" % (quoi, attendu)


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
    """POST multipart vers /storage/upload — écrit à la main."""
    frontiere = "----banc%s" % uuid.uuid4().hex
    corps = b"".join([
        ('--%s\r\nContent-Disposition: form-data; name="purpose"\r\n\r\n%s\r\n'
         % (frontiere, purpose)).encode(),
        ('--%s\r\nContent-Disposition: form-data; name="file"; '
         'filename="registre.jpg"\r\nContent-Type: image/jpeg\r\n\r\n'
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


def self_test():
    # ── Doivent PASSER ───────────────────────────────────────────────────────
    _v("acceptation 200", verdict_acceptation(200, None)[0], "ok")
    _v("acceptation 201", verdict_acceptation(201, None)[0], "ok")
    _v("refus de rôle", verdict_refus_role(403, "AUTH_FORBIDDEN_ROLE")[0], "ok")
    _v("effet constaté", verdict_effet(True, True, "suspended")[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ La garde retirée qui serait encore là — l'objet même du banc.
    #
    # Le code cité était `COMMERCANT_NOT_IN_AGENT_COMMUNES` à l'écriture du
    # banc ; il a été retiré de l'enum le 2026-08-13 avec le découpage, donc
    # **le serveur ne peut plus le rendre**. Le remplacer par un code vivant
    # n'affaiblit rien : ce qui est éprouvé ici est que **tout** 403 sur une
    # route libérée est un échec, quel qu'en soit le motif. Une garde
    # résiduelle ne se présenterait de toute façon pas sous l'ancien nom.
    _v("403 sur une route libérée",
       verdict_acceptation(403, "AUTH_FORBIDDEN_ROLE")[0], "echec")
    # ⚠️ La portée résiduelle déguisée en absence.
    _v("404 sur un commerçant qui existe",
       verdict_acceptation(404, "COMMERCANT_NOT_FOUND")[0], "echec")
    # ⚠️ Le piège hérité d'`appartenance.py`, retourné : une requête morte à la
    # validation n'a RIEN dit de l'autorisation, dans un sens comme dans l'autre.
    _v("validation → non concluant",
       verdict_acceptation(400, "VALIDATION_ERROR")[0], "non_concluant")
    _v("validation côté témoin → non concluant",
       verdict_refus_role(400, "VALIDATION_ERROR")[0], "non_concluant")
    _v("429 → non concluant", verdict_acceptation(429, None)[0], "non_concluant")
    _v("pas de réponse → non concluant",
       verdict_acceptation(None, "RESEAU")[0], "non_concluant")
    # ⚠️ Le témoin qui cesse de témoigner : l'agent admis chez l'admin.
    _v("agent admis sur une route admin",
       verdict_refus_role(200, None)[0], "echec")
    # ⚠️ Refusé, mais pas pour le rôle — un 404 n'est pas une preuve de garde.
    _v("refusé pour autre chose que le rôle",
       verdict_refus_role(404, "COMMERCANT_NOT_FOUND")[0], "echec")
    # ⚠️ La route qui répond 200 sans rien faire : le faux vert que ce banc
    # coûte le plus cher à éviter.
    _v("effet absent malgré un 200",
       verdict_effet(False, True, "suspended")[0], "echec")
    _v("état illisible → non concluant",
       verdict_effet(None, True, "suspended")[0], "non_concluant")

    refus = 10
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

    print("═" * 64)
    print("  Portée de l'agent — il agit sur tout le parc, et pas au-delà")
    print("═" * 64)
    print("  ⚠️ ce banc ÉCRIT et SUPPRIME — sur un commerçant qu'il crée")
    print("  ⚠️ ~20 écritures sur un seau de 20/min : compter deux minutes")

    st, d = appeler("POST", "/agent/login",
                    corps={"email": agent_email, "password": agent_password})
    jg = d.get("accessToken")
    if not jg:
        print("❌ connexion agent impossible (HTTP %s, %s)" % (st, d.get("code")))
        sys.exit(2)
    time.sleep(PACE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-44s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    def fiche(cid):
        """La fiche telle que l'AGENT la voit — la lecture est globale aussi."""
        st, d = appeler("GET", "/admin/commercant?limit=100", jg)
        if st != 200:
            return None
        return next((c for c in d.get("items", []) if c.get("id") == cid), None)

    def visible(pid):
        st, d = appeler("GET", "/promo?limit=100")
        if st != 200:
            return None
        return pid in {p.get("id") for p in d.get("items", [])}

    # ── 0. Le témoin négatif — AVANT toute écriture ─────────────────────────
    #
    # ⚠️ Il passe en premier exprès. Un banc incapable de refuser doit être
    # démasqué avant d'annoncer quatorze acceptations, pas après.
    print("\n── 0. témoin : trois routes restent réservées à l'admin ──")
    st, d = appeler("GET", "/admin/agent", jg)
    noter("GET /admin/agent refusé à l'agent",
          *verdict_refus_role(st, d.get("code")))
    time.sleep(PACE)

    st, d = appeler("GET", "/admin/audit-log?limit=1", jg)
    noter("GET /admin/audit-log refusé à l'agent",
          *verdict_refus_role(st, d.get("code")))
    time.sleep(PACE)

    # ── 1. Le sujet : un commerçant que l'agent n'a pas créé ────────────────
    #
    # ⚠️ Auto-inscription, sans jeton d'agent : `createdByAgentId` est `null`
    # PAR CONSTRUCTION. L'API n'expose pas ce champ — le savoir vaut mieux que
    # le lire.
    print("\n── 1. un commerçant auto-inscrit, étranger à l'agent ──")
    tel = "+213564%s" % time.strftime("%H%M%S")
    st, d = appeler("POST", "/commercant/register", corps={
        "telephone": tel, "nom": "Commerce Portée", "pin": PIN,
        "adresse": "Rue de la portée", "categorie": "alimentation",
        "acceptedTerms": True,
        "latitude": DECOR_LAT, "longitude": DECOR_LNG})
    jc = d.get("accessToken")
    if not jc:
        print("❌ inscription refusée (HTTP %s, %s) — plafond de 5/min ?"
              % (st, d.get("code")))
        return 2
    time.sleep(PACE)

    st, d = appeler("GET", "/commercant/me", jc)
    cid = d.get("id")
    if not cid:
        print("❌ fiche du commerçant illisible (HTTP %s)" % st)
        return 2
    noter("commerçant inscrit, sans agent créateur", "ok", tel)
    time.sleep(PACE)

    # La prémisse de tout le reste : l'agent VOIT cette fiche qu'il n'a pas
    # créée. Si elle n'est pas là, aucune sonde d'écriture ne prouverait rien.
    if fiche(cid) is None:
        noter("l'agent voit la fiche dans sa liste", "non_concluant",
              "absente — la portée de LECTURE est en cause, et la suite ne "
              "prouverait rien")
        return 1
    noter("l'agent voit la fiche dans sa liste", "ok", cid[:8])
    time.sleep(PACE)

    # ── 2. Le dossier de registre, déposé par le commerçant ─────────────────
    #
    # `resolveRegistreVerification` refuse un dossier vide
    # (COMMERCANT_NO_PENDING_REGISTRE_VERIFICATION) : sans ce dépôt, les deux
    # sondes suivantes mesureraient ce refus métier au lieu de la portée.
    print("\n── 2. décor : le commerçant dépose son registre ──")
    st, d = televerser(jc, "registre")
    cle = d.get("key")
    if not cle:
        noter("dépôt du registre", "non_concluant",
              "téléversement HTTP %s %s — les sondes registre ne concluraient "
              "pas" % (st, d.get("code")))
        return 1
    time.sleep(PACE)
    st, d = appeler("POST", "/commercant/me/registre", jc, {"registreKey": cle})
    if st not in (200, 201):
        noter("dépôt du registre", "non_concluant",
              "HTTP %s %s" % (st, d.get("code")))
        return 1
    noter("dépôt du registre", "ok", "en_attente")
    time.sleep(PACE)

    # ── 3. Les écritures sur le commerçant ──────────────────────────────────
    print("\n── 3. l'agent tranche le registre d'un commerçant étranger ──")
    st, d = appeler("POST", "/admin/commercant/%s/registre/rejeter" % cid, jg,
                    {"reason": "sonde du banc de portée"})
    noter("registre/rejeter accepté", *verdict_acceptation(st, d.get("code")))
    time.sleep(PACE)
    f = fiche(cid)
    noter("… et le registre est rejeté",
          *verdict_effet(f and f.get("registreStatus"), "rejete",
                         "registreStatus"))
    time.sleep(PACE)

    st, d = appeler("POST", "/admin/commercant/%s/registre/valider" % cid, jg)
    noter("registre/valider accepté", *verdict_acceptation(st, d.get("code")))
    time.sleep(PACE)
    f = fiche(cid)
    noter("… et le registre est validé",
          *verdict_effet(f and f.get("registreStatus"), "valide",
                         "registreStatus"))
    time.sleep(PACE)

    # ⚠️ `profile/valider` sur un profil qui n'attend rien répondrait 200 sans
    # rien changer — un effet inobservable n'est pas un effet. On allume donc
    # le drapeau d'abord, par le geste qui l'allume en vrai.
    print("\n── 4. l'agent lève une relecture de profil qu'il n'a pas ouverte ──")
    st, d = appeler("PATCH", "/commercant/me", jc, {"nom": "Commerce Portée II"})
    if st not in (200, 201):
        noter("profil mis en relecture", "non_concluant",
              "HTTP %s %s — sans drapeau levé, valider ne prouverait rien"
              % (st, d.get("code")))
        return 1
    time.sleep(PACE)
    f = fiche(cid)
    if not (f and f.get("profilePendingReview")):
        noter("profil mis en relecture", "non_concluant",
              "le drapeau n'est pas levé — la sonde suivante mesurerait un "
              "geste sans objet (règle 38)")
        return 1
    noter("profil mis en relecture", "ok", "profilePendingReview")
    time.sleep(PACE)

    st, d = appeler("POST", "/admin/commercant/%s/profile/valider" % cid, jg)
    noter("profile/valider accepté", *verdict_acceptation(st, d.get("code")))
    time.sleep(PACE)
    f = fiche(cid)
    noter("… et la relecture est levée",
          *verdict_effet(f and f.get("profilePendingReview"), False,
                         "profilePendingReview"))
    time.sleep(PACE)

    # ── 5. Le PIN — l'effet se constate en se connectant ────────────────────
    print("\n── 5. l'agent réinitialise le PIN d'un commerçant étranger ──")
    # ⚠️ `newPin`, pas `pin` — et le banc s'est fait prendre au premier
    # passage. Le corps `{"pin": …}` traversait `whitelist: true`, qui RETIRE
    # un champ inconnu sans rien dire, puis mourait sur `newPin` manquant :
    # `VALIDATION_ERROR`. La sonde a rendu « non concluant » et pas « échec »,
    # ce qui est exactement le point — un corps invalide n'a rien dit de
    # l'autorisation. Sans cette distinction, le banc aurait accusé une garde
    # d'appartenance résiduelle sur un produit correct (règle 38).
    st, d = appeler("POST", "/admin/commercant/%s/reset-pin" % cid, jg,
                    {"newPin": PIN_NEUF})
    noter("reset-pin accepté", *verdict_acceptation(st, d.get("code")))
    time.sleep(PACE)
    st, d = appeler("POST", "/commercant/login",
                    corps={"telephone": tel, "pin": PIN_NEUF})
    jc = d.get("accessToken") or jc
    noter("… et le nouveau PIN ouvre la session",
          *verdict_effet(d.get("accessToken") is not None, True, "connexion"))
    time.sleep(PACE)

    # ── 6. La promo — l'IDOR fondateur de la règle #1 ───────────────────────
    #
    # ⚠️ `POST /promo/agent/:cid` est nommément la route que CLAUDE.md cite
    # comme l'IDOR d'origine. Elle est rouverte par décision produit ; c'est
    # ici, et nulle part ailleurs, que ça se constate.
    print("\n── 6. l'agent crée et pilote la promo d'un commerçant étranger ──")
    st, d = appeler("POST", "/promo/agent/%s" % cid, jg, {
        "description": "Sonde du banc de portée", "prixAvant": 1000,
        "prixApres": 700, "categorie": "alimentation",
        "photoKeys": ["promo-photos/%s/portee.jpg" % cid]})
    pid = d.get("id")
    noter("POST /promo/agent/:cid accepté", *verdict_acceptation(st, d.get("code")))
    if not pid:
        noter("la suite des sondes promo", "non_concluant",
              "pas de promo — les six sondes suivantes sont sautées, et un "
              "contrôle absent doit se nommer")
        return 1
    time.sleep(PACE)
    noter("… et le client la voit", *verdict_effet(visible(pid), True, "visible"))
    time.sleep(PACE)

    st, d = appeler("PATCH", "/promo/%s" % pid, jg,
                    {"description": "Sonde modifiée par l'agent"})
    noter("PATCH /promo/:id accepté", *verdict_acceptation(st, d.get("code")))
    time.sleep(PACE)
    st, d = appeler("GET", "/promo/%s" % pid)
    noter("… et la description a changé",
          *verdict_effet(d.get("description"), "Sonde modifiée par l'agent",
                         "description"))
    time.sleep(PACE)

    st, d = appeler("POST", "/promo/%s/stop" % pid, jg)
    noter("POST /promo/:id/stop accepté", *verdict_acceptation(st, d.get("code")))
    time.sleep(PACE)
    noter("… et la promo quitte l'affichage",
          *verdict_effet(visible(pid), False, "visible"))
    time.sleep(PACE)

    st, d = appeler("POST", "/promo/%s/publish" % pid, jg)
    noter("POST /promo/:id/publish accepté",
          *verdict_acceptation(st, d.get("code")))
    time.sleep(PACE)
    noter("… et elle y revient", *verdict_effet(visible(pid), True, "visible"))
    time.sleep(PACE)

    # ── 7. La modération, par un agent ──────────────────────────────────────
    #
    # ⚠️ `admin_moderation.py` joue ces trois décisions en ADMIN. C'est le seul
    # endroit où elles sont exercées par un agent — l'un des trois lots de
    # routes que le chantier lui a ouverts.
    print("\n── 7. l'agent modère — trois décisions qui lui sont ouvertes ──")
    # ⚠️ `expectedModerationStatus` est obligatoire depuis le 2026-08-13 (garde
    # de course, voir `ResolveModerationDto`). L'omettre rendrait
    # `VALIDATION_ERROR`, donc « non concluant » — le banc ne dirait plus rien
    # sur la portée, ce qu'il est le seul à mesurer. La séquence est
    # déterministe : la promo vient d'être créée (`normale`), puis `masquee`,
    # puis `verifiee_ok`.
    st, d = appeler("POST", "/admin/moderation/%s/masquer" % pid, jg,
                    {"expectedModerationStatus": "normale"})
    noter("moderation/masquer accepté", *verdict_acceptation(st, d.get("code")))
    time.sleep(PACE)
    noter("… et la promo disparaît", *verdict_effet(visible(pid), False, "visible"))
    time.sleep(PACE)

    st, d = appeler("POST", "/admin/moderation/%s/verifier-ok" % pid, jg,
                    {"expectedModerationStatus": "masquee"})
    noter("moderation/verifier-ok accepté",
          *verdict_acceptation(st, d.get("code")))
    time.sleep(PACE)
    noter("… et le masque est levé", *verdict_effet(visible(pid), True, "visible"))
    time.sleep(PACE)

    st, d = appeler("POST", "/admin/moderation/%s/avertir" % pid, jg,
                    {"expectedModerationStatus": "verifiee_ok"})
    noter("moderation/avertir accepté", *verdict_acceptation(st, d.get("code")))
    time.sleep(PACE)
    # ⚠️ `avertir` renvoie la promo en BROUILLON : elle sort de l'affichage.
    # L'assertion d'absence n'est lisible que parce qu'on vient d'établir
    # qu'elle était bien là (le `verifier-ok` ci-dessus).
    noter("… et elle repasse en brouillon",
          *verdict_effet(visible(pid), False, "visible"))
    time.sleep(PACE)

    # ── 8. Suspendre, réactiver ─────────────────────────────────────────────
    print("\n── 8. l'agent suspend puis réactive un commerçant étranger ──")
    st, d = appeler("POST", "/admin/commercant/%s/suspend" % cid, jg,
                    {"reason": "sonde du banc de portée"})
    noter("suspend accepté", *verdict_acceptation(st, d.get("code")))
    time.sleep(PACE)
    f = fiche(cid)
    noter("… et le compte est suspendu",
          *verdict_effet(f and f.get("suspended"), True, "suspended"))
    time.sleep(PACE)

    st, d = appeler("POST", "/admin/commercant/%s/reactivate" % cid, jg)
    noter("reactivate accepté", *verdict_acceptation(st, d.get("code")))
    time.sleep(PACE)
    f = fiche(cid)
    noter("… et le compte est rétabli",
          *verdict_effet(f and f.get("suspended"), False, "suspended"))
    time.sleep(PACE)

    # ── 9. Le témoin négatif qui ÉCRIT ──────────────────────────────────────
    #
    # ⚠️ Placé ici plutôt qu'au § 0 : c'est le seul témoin dont le refus est
    # mesurable sur un effet. Le corps est VALIDE — un `VALIDATION_ERROR`
    # rendrait la sonde muette sur le rôle.
    print("\n── 9. témoin : une écriture réservée à l'admin reste fermée ──")
    st, d = appeler("PATCH", "/admin/commercant/%s/plafond-promos" % cid, jg,
                    {"promoActiveCap": 8})
    noter("plafond-promos refusé à l'agent",
          *verdict_refus_role(st, d.get("code")))
    time.sleep(PACE)
    f = fiche(cid)
    # ⚠️ **`None` ne peut pas être à la fois la valeur attendue et le drapeau
    # d'illisibilité**, et la première version de cette sonde faisait les deux :
    # elle passait `f.get("promoActiveCap")` — légitimement `None`, « suit le
    # réglage global » — à un verdict qui lit `None` comme « état illisible ».
    # Elle rendait donc « non concluant » sur un produit correct. C'est la
    # règle 29 en miniature, dans le banc censé la faire respecter : une valeur
    # de repli avait détruit l'information d'absence. La comparaison est donc
    # ramenée à un booléen, et `None` ne signifie plus qu'une seule chose.
    noter("… et le plafond n'a pas bougé",
          *verdict_effet(None if f is None else (f.get("promoActiveCap") is None),
                         True, "plafond resté au réglage global"))
    time.sleep(PACE)

    # ── 10. Supprimer — en dernier, et c'est structurel ─────────────────────
    #
    # ⚠️ `POST /admin/commercant/:id/delete` est `@Roles('admin','agent')` : un
    # agent peut effacer n'importe quel commerçant du pays. C'est la
    # conséquence la plus lourde du chantier, et elle n'était éprouvée nulle
    # part. L'effet se constate par l'ABSENCE de la fiche — `findAllForAdmin`
    # filtre `deletedAt IS NULL` depuis le 2026-08-13.
    print("\n── 10. l'agent supprime un commerçant étranger ──")
    st, d = appeler("POST", "/admin/commercant/%s/delete" % cid, jg,
                    {"reason": "sonde du banc de portée"})
    noter("delete accepté", *verdict_acceptation(st, d.get("code")))
    time.sleep(PACE)
    noter("… et la fiche quitte la liste",
          *verdict_effet(fiche(cid) is None, True, "absente de la liste"))

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
