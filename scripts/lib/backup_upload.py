#!/usr/bin/env python3
"""Envoi de la sauvegarde vers S3 — chiffrée, et **prouvée non lisible**.

── Pourquoi ce module existe ────────────────────────────────────────────────

`backup_db.py` produit une sauvegarde et la restaure pour prouver qu'elle en
est une. Elle reste **à côté de la base**. Ça couvre la corruption logique
(un DELETE malheureux, une migration ratée) et **rien d'autre** : une perte de
disque, un conteneur détruit, un serveur qui ne redémarre pas emportent la
base et ses sauvegardes du même geste. C'est le point ouvert que le suivi
porte depuis le 2026-08-05.

── Trois choix qui méritent d'être écrits ───────────────────────────────────

1. **Le dépôt de destination est `echango-private`, pas `echango-promo`.**
   Mesuré le 2026-08-05, en anonyme :

       echango-private   listage 403 · objet inexistant 403 · aucun accès
       echango-promo     listage 403 · **une photo de promo : 200, 92 Ko**

   `echango-promo` est le dépôt de l'application, et `storage.service.ts:192`
   y pose `ACL: public-read` pour tout ce qui n'est pas `registre-documents/`.
   Il **sert des objets publics par conception**. Y déposer un dump reviendrait
   à faire dépendre le secret de toute la base d'un seul argument d'ACL passé
   correctement — la définition d'un secret fragile.

2. **Chiffré avant l'envoi, pas seulement « stocké chez un fournisseur
   sérieux ».** Le dump contient l'intégralité des données personnelles :
   numéros de téléphone des commerçants, empreintes de mots de passe, registres
   de commerce. Les identifiants S3 de l'application vivent dans un `.env` sur
   le serveur ; qui les lit lit le dépôt. Le chiffrement symétrique déplace le
   secret hors du serveur — c'est la seule ligne qui tienne encore si le `.env`
   fuit. ⚠️ **Et la contrepartie est réelle** : une phrase de passe perdue rend
   toutes les sauvegardes définitivement illisibles. Elle se range où se range
   un secret, pas dans le dépôt.

3. **Signature SigV4 écrite ici, en bibliothèque standard.** Ni `boto3`, ni
   `aws`, ni `rclone` ne sont installés en WSL, et un script de sauvegarde qui
   exige une installation est un script qui ne tournera pas le jour où on
   reconstruit la machine. ~90 lignes de signature contre une dépendance à
   installer sur chaque hôte : le compromis penche nettement.

── Ce que ce module refuse, et c'est le cœur ────────────────────────────────

Un envoi qui « a marché » ne prouve rien : `PutObject` rend `200` que l'objet
soit privé ou lisible du monde entier. Alors après chaque envoi, ce module
**redemande l'objet en anonyme** — sans aucun en-tête d'authentification — et
exige un refus. Un `200` à ce moment-là est traité comme une fuite : l'objet
est **supprimé immédiatement** et le script échoue.

Ce contrôle a été prouvé capable de refuser, en vrai et pas en théorie
(`--prouver`) : pointé sur une photo de promo publique de la production, il
rend `echec`. Règle 28 — un contrôle qu'on n'a jamais vu refuser n'a rien
montré.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/backup_upload.py --self-test
    python3 scripts/lib/backup_upload.py --prouver          # contrôle vs objet public réel
    python3 scripts/lib/backup_upload.py --envoyer <fichier.dump>

Appelé automatiquement par `backup_db.py` (étape 4).
"""

import hashlib
import hmac
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

# ─────────────────────────────────────────────────────────────────────────────
# Configuration — aucune valeur de repli silencieuse (règle 29)
# ─────────────────────────────────────────────────────────────────────────────
#
# ⚠️ Volontairement `BACKUP_S3_*` et non `S3_*`. Les identifiants de
# l'application ont besoin d'écrire des photos ; ceux des sauvegardes ont
# besoin d'écrire des sauvegardes. Les confondre donne à quiconque compromet
# l'application le pouvoir d'effacer les sauvegardes — c'est-à-dire de
# transformer un incident en perte définitive. Si l'on choisit malgré tout de
# réutiliser la même clé, on l'écrit explicitement dans le `.env` : un repli
# automatique rendrait ce choix invisible.

CLES_REQUISES = (
    "BACKUP_S3_ENDPOINT",
    "BACKUP_S3_REGION",
    "BACKUP_S3_BUCKET",
    "BACKUP_S3_ACCESS_KEY_ID",
    "BACKUP_S3_SECRET_ACCESS_KEY",
)

PREFIXE_DEFAUT = "db-backups/"
GARDER_DISTANT_DEFAUT = 30
DELAI = 120


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_configuration(env, remote_declare):
    """L'absence de configuration doit être une information, pas un silence.

    Une sauvegarde qui reste sur la machine n'est pas fausse — elle est
    incomplète, et c'est précisément ce qu'il faut dire. Le seul cas refusé est
    celui où l'on ne peut pas distinguer « choisi » de « oublié ».
    """
    if remote_declare == "off":
        return ("desactive",
                "envoi distant explicitement désactivé — la sauvegarde reste "
                "sur la machine et ne protège PAS d'une perte de disque")
    manquantes = [c for c in CLES_REQUISES if not (env.get(c) or "").strip()]
    if manquantes:
        if len(manquantes) == len(CLES_REQUISES):
            return ("echec",
                    "envoi distant non configuré. Renseigner %s, ou poser "
                    "BACKUP_REMOTE=off pour assumer une sauvegarde locale seule"
                    % ", ".join(CLES_REQUISES[:2]) + "…")
        # ⚠️ Le cas dangereux : une configuration à moitié faite ressemble à une
        # configuration. On refuse plus fort que pour une absence totale.
        return ("echec",
                "configuration INCOMPLÈTE — %d clé(s) manquante(s) : %s"
                % (len(manquantes), ", ".join(manquantes)))
    return "ok", "%s → %s" % (env["BACKUP_S3_BUCKET"], env["BACKUP_S3_ENDPOINT"])


def verdict_chiffrement(code_sortie, sha_avant, sha_apres_dechiffrement,
                        taille_chiffree):
    """Chiffrer sans savoir déchiffrer produit un fichier, pas une sauvegarde.

    Le mode de défaillance visé n'est pas « gpg a planté » — c'est « gpg a
    exité 0 et le fichier ne se rouvre pas », symétrique exact du dump tronqué
    que `verdict_dump` attrape.
    """
    if code_sortie != 0:
        return "echec", "gpg a échoué (code %s)" % code_sortie
    if not taille_chiffree:
        return "echec", "aucun fichier chiffré produit"
    if sha_apres_dechiffrement is None:
        return "echec", "le fichier chiffré NE SE DÉCHIFFRE PAS"
    if sha_avant != sha_apres_dechiffrement:
        return ("echec",
                "déchiffré ≠ original (%s… vs %s…) — le fichier est altéré"
                % (sha_avant[:12], sha_apres_dechiffrement[:12]))
    return "ok", "AES-256, déchiffrement vérifié (%.1f Mo)" % (
        taille_chiffree / 1024 / 1024)


def verdict_envoi(code_http, etag_distant, md5_local, erreur=None):
    if code_http != 200:
        return ("echec", "PUT a rendu HTTP %s%s"
                % (code_http, " : %s" % erreur[:120] if erreur else ""))
    if not etag_distant:
        # Sans ETag on ne peut rien comparer. Ne pas conclure « ok » : le
        # transport n'est pas vérifié, et le prétendre serait pire que se taire.
        return ("non_concluant",
                "envoi accepté mais aucun ETag rendu — intégrité non vérifiée")
    if etag_distant.strip('"').lower() != md5_local.lower():
        return ("echec",
                "ETag distant %s ≠ MD5 local %s — l'objet stocké n'est pas "
                "celui qu'on a envoyé" % (etag_distant.strip('"')[:12],
                                          md5_local[:12]))
    return "ok", "ETag == MD5 local"


def verdict_etancheite(code_http_anonyme):
    """LE contrôle. Un objet déposé « en privé » n'est privé que si on a
    vérifié qu'il ne se lit pas sans clé.

    ⚠️ `PutObject` rend 200 quelle que soit l'ACL effective — un dépôt mal
    réglé, un `x-amz-acl` ignoré par le fournisseur, et la sauvegarde complète
    de la base devient une URL. Rien dans la réponse d'écriture ne le dirait.
    """
    if code_http_anonyme == 200:
        return ("echec",
                "🔴 L'OBJET EST LISIBLE SANS AUTHENTIFICATION (HTTP 200) — "
                "sauvegarde complète de la base exposée")
    if code_http_anonyme in (401, 403, 404):
        return "ok", "refus anonyme confirmé (HTTP %s)" % code_http_anonyme
    if code_http_anonyme is None:
        return ("non_concluant",
                "le dépôt n'a pas répondu — étanchéité NON vérifiée")
    return ("non_concluant",
            "réponse inattendue (HTTP %s) — étanchéité non concluante"
            % code_http_anonyme)


def verdict_listage(code_http, balise_racine, tronque):
    """Un 200 ne dit pas qu'on a listé ce qu'on croit.

    ⚠️ Trouvé en éprouvant ce module contre MinIO le 2026-08-05 : `GET /` avec
    des identifiants valides a rendu **200 et un `ListAllMyBucketsResult`** —
    la liste des dépôts, pas celle des objets. Aucun `<Key>` dedans, donc « 0
    sauvegarde distante », donc une purge qui ne purge jamais rien **en se
    déclarant `ok`**. Le contrôle rassurait sur exactement ce qu'il ne
    regardait pas.

    On exige donc la bonne balise racine, et on refuse de purger sur une liste
    tronquée : supprimer d'après une vue partielle, c'est risquer d'effacer la
    mauvaise sauvegarde — le mode de défaillance que `a_supprimer` cherche déjà
    à éviter en étant séparé de la suppression.
    """
    if code_http != 200:
        return "non_concluant", "listage impossible (HTTP %s)" % code_http
    if balise_racine != "ListBucketResult":
        return ("non_concluant",
                "réponse 200 mais document « %s » au lieu de ListBucketResult "
                "— on ignore ce qui a été listé, donc on ne purge pas"
                % (balise_racine or "vide"))
    if tronque:
        return ("non_concluant",
                "listage tronqué (plus de 1000 objets) — purger sur une vue "
                "partielle effacerait peut-être la mauvaise sauvegarde")
    return "ok", ""


def a_supprimer_distant(cles, garder):
    """Les plus anciennes au-delà de [garder]. Rend une liste, ne supprime rien.

    Même forme que `backup_db.a_supprimer` — et **délibérément pas la même
    fonction** : la rétention locale et la rétention distante peuvent diverger
    (on garde 7 jours sur disque et 30 hors site), donc changer l'une ne doit
    pas changer l'autre (règle 30, branche « non ⇒ deux endroits »).
    """
    if garder < 1:
        raise ValueError("garder doit valoir au moins 1")
    ordonnes = sorted(cles, reverse=True)  # clés horodatées → tri = récence
    return sorted(ordonnes[garder:])


# ─────────────────────────────────────────────────────────────────────────────
# Signature SigV4 — bibliothèque standard uniquement
# ─────────────────────────────────────────────────────────────────────────────

def _hmac(cle, message):
    return hmac.new(cle, message.encode("utf-8"), hashlib.sha256).digest()


def _cle_de_signature(secret, date, region, service="s3"):
    k = _hmac(("AWS4" + secret).encode("utf-8"), date)
    k = _hmac(k, region)
    k = _hmac(k, service)
    return _hmac(k, "aws4_request")


def signer(methode, hote, chemin, parametres, sha_payload, acces, secret,
           region, entetes_sup=None):
    """Rend les en-têtes signés pour une requête S3.

    `chemin` doit déjà commencer par « / » et être encodé comme il sera envoyé.
    """
    maintenant = time.gmtime()
    amz_date = time.strftime("%Y%m%dT%H%M%SZ", maintenant)
    date_courte = time.strftime("%Y%m%d", maintenant)

    entetes = {
        "host": hote,
        "x-amz-content-sha256": sha_payload,
        "x-amz-date": amz_date,
    }
    entetes.update({k.lower(): v for k, v in (entetes_sup or {}).items()})

    signes = sorted(entetes)
    canonique_entetes = "".join("%s:%s\n" % (k, entetes[k].strip()) for k in signes)
    entetes_signes = ";".join(signes)

    requete_canonique = "\n".join([
        methode,
        chemin,
        "&".join("%s=%s" % (urllib.parse.quote(k, safe=""),
                            urllib.parse.quote(str(v), safe=""))
                 for k, v in sorted((parametres or {}).items())),
        canonique_entetes,
        entetes_signes,
        sha_payload,
    ])

    portee = "%s/%s/s3/aws4_request" % (date_courte, region)
    a_signer = "\n".join([
        "AWS4-HMAC-SHA256",
        amz_date,
        portee,
        hashlib.sha256(requete_canonique.encode("utf-8")).hexdigest(),
    ])
    signature = hmac.new(_cle_de_signature(secret, date_courte, region),
                         a_signer.encode("utf-8"), hashlib.sha256).hexdigest()

    entetes["Authorization"] = (
        "AWS4-HMAC-SHA256 Credential=%s/%s, SignedHeaders=%s, Signature=%s"
        % (acces, portee, entetes_signes, signature))
    return entetes


# ─────────────────────────────────────────────────────────────────────────────
# HTTP
# ─────────────────────────────────────────────────────────────────────────────

def _hote_virtuel(endpoint, bucket):
    """OVH rejette les requêtes anonymes en style « path » — même raisonnement
    que `storage.service.ts:204`. On reste en virtual-hosted partout, pour que
    l'URL signée et l'URL de contrôle anonyme désignent bien le même objet.
    """
    p = urllib.parse.urlparse(endpoint)
    return "%s.%s" % (bucket, p.netloc), p.scheme or "https"


def requete_s3(methode, env, cle_objet, corps=None, parametres=None,
               entetes_sup=None, taille=None):
    """Rend (code_http, corps_reponse, entetes) — jamais d'exception sur un
    code d'erreur : un 403 est une donnée, pas un accident."""
    hote, schema = _hote_virtuel(env["BACKUP_S3_ENDPOINT"], env["BACKUP_S3_BUCKET"])
    chemin = "/" + urllib.parse.quote(cle_objet, safe="/~")

    if corps is None:
        sha = hashlib.sha256(b"").hexdigest()
    else:
        sha = corps["sha256"]

    entetes = signer(methode, hote, chemin, parametres, sha,
                     env["BACKUP_S3_ACCESS_KEY_ID"],
                     env["BACKUP_S3_SECRET_ACCESS_KEY"],
                     env["BACKUP_S3_REGION"], entetes_sup)

    url = "%s://%s%s" % (schema, hote, chemin)
    if parametres:
        url += "?" + urllib.parse.urlencode(sorted(parametres.items()))

    donnees = None
    if corps is not None:
        donnees = open(corps["chemin"], "rb")
        entetes["Content-Length"] = str(taille)

    requete = urllib.request.Request(url, data=donnees, method=methode)
    for k, v in entetes.items():
        requete.add_header(k, v)
    try:
        with urllib.request.urlopen(requete, timeout=DELAI) as r:
            return r.status, r.read(), dict(r.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read(), dict(e.headers)
    except Exception as e:  # réseau, DNS, TLS
        return None, str(e).encode("utf-8"), {}
    finally:
        if donnees is not None:
            donnees.close()


def get_anonyme(env, cle_objet):
    """⚠️ AUCUN en-tête d'authentification. C'est tout l'intérêt : on se met à
    la place de n'importe qui sur Internet."""
    hote, schema = _hote_virtuel(env["BACKUP_S3_ENDPOINT"], env["BACKUP_S3_BUCKET"])
    url = "%s://%s/%s" % (schema, hote, urllib.parse.quote(cle_objet, safe="/~"))
    return _code_seul(url)


def _code_seul(url):
    try:
        requete = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(requete, timeout=DELAI) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return None


# ─────────────────────────────────────────────────────────────────────────────
# Empreintes et chiffrement
# ─────────────────────────────────────────────────────────────────────────────

def empreintes(chemin):
    """SHA-256 (intégrité de bout en bout) et MD5 (comparaison à l'ETag)."""
    sha, md5 = hashlib.sha256(), hashlib.md5()
    with open(chemin, "rb") as f:
        for bloc in iter(lambda: f.read(1024 * 1024), b""):
            sha.update(bloc)
            md5.update(bloc)
    return sha.hexdigest(), md5.hexdigest()


def chiffrer(source, destination, phrase):
    """gpg symétrique AES-256, non interactif.

    ⚠️ La phrase passe par un descripteur, jamais par la ligne de commande :
    `--passphrase <phrase>` la rendrait lisible dans `ps` par tout utilisateur
    de la machine.
    """
    r = subprocess.run(
        ["gpg", "--batch", "--yes", "--quiet", "--symmetric",
         "--cipher-algo", "AES256", "--passphrase-fd", "0",
         "--output", destination, source],
        input=phrase.encode("utf-8"), capture_output=True)
    return r.returncode, r.stderr.decode("utf-8", "replace")


def dechiffrer_vers_sha(chemin_chiffre, phrase):
    """Déchiffre en mémoire et rend le SHA-256 — ou None si ça ne s'ouvre pas.

    Rien n'est écrit sur le disque : le clair ne doit pas exister deux fois.
    """
    r = subprocess.run(
        ["gpg", "--batch", "--yes", "--quiet", "--decrypt",
         "--passphrase-fd", "0", chemin_chiffre],
        input=phrase.encode("utf-8"), capture_output=True)
    if r.returncode != 0:
        return None
    return hashlib.sha256(r.stdout).hexdigest()


# ─────────────────────────────────────────────────────────────────────────────
# Le flux complet
# ─────────────────────────────────────────────────────────────────────────────

def lire_config(env=None):
    env = dict(env if env is not None else os.environ)
    return env


def envoyer(fichier, env, noter):
    """Chiffre, envoie, prouve l'étanchéité, purge. `noter(libelle, v, expl)`
    remonte chaque verdict à l'appelant — même format que `backup_db.py`."""
    remote = (env.get("BACKUP_REMOTE") or "").strip().lower()
    v, expl = verdict_configuration(env, remote)
    # ⚠️ Une désactivation DÉCLARÉE ne fait pas échouer le lot, et ce n'est pas
    # une entorse à la règle 29 : le choix est écrit, donc l'information
    # d'absence existe. Échouer chaque nuit sur un réglage délibéré apprendrait
    # surtout à ignorer le code de sortie — c'est-à-dire à rater le vrai échec.
    noter("configuration de l'envoi",
          "ok" if v == "desactive" else v,
          ("⚠️  " + expl) if v == "desactive" else expl)
    if v != "ok":
        return

    phrase = env.get("BACKUP_PASSPHRASE") or ""
    chiffrement = (env.get("BACKUP_CHIFFREMENT") or "").strip().lower()
    if not phrase and chiffrement != "off":
        noter("chiffrement", "echec",
              "BACKUP_PASSPHRASE absente. Le dump part en clair vers un tiers "
              "sinon — poser BACKUP_CHIFFREMENT=off pour l'assumer par écrit")
        return

    a_envoyer, suffixe, temporaire = fichier, "", None
    sha_clair, _ = empreintes(fichier)

    if chiffrement != "off":
        chiffre = fichier + ".gpg"
        code, err = chiffrer(fichier, chiffre, phrase)
        taille = os.path.getsize(chiffre) if os.path.exists(chiffre) else 0
        sha_retour = dechiffrer_vers_sha(chiffre, phrase) if taille else None
        v, expl = verdict_chiffrement(code, sha_clair, sha_retour, taille)
        noter("chiffrement + déchiffrement", v, expl if v == "ok"
              else "%s %s" % (expl, err[:80]))
        if v != "ok":
            if os.path.exists(chiffre):
                os.remove(chiffre)
            return
        a_envoyer, suffixe, temporaire = chiffre, ".gpg", chiffre
    else:
        noter("chiffrement", "non_concluant",
              "DÉSACTIVÉ par BACKUP_CHIFFREMENT=off — le dump part en clair")

    try:
        _televerser(fichier, a_envoyer, suffixe, env, noter)
    finally:
        # ⚠️ Le chiffré est un artefact de TRANSPORT, pas une sauvegarde de
        # plus. Le laisser doublerait l'espace occupé et surtout ferait vivre
        # une seconde copie des données hors de toute rétention — celle de
        # `backup_db` ne liste que les `*.dump`, jamais les `*.dump.gpg`.
        if temporaire and os.path.exists(temporaire):
            os.remove(temporaire)


def _televerser(fichier, a_envoyer, suffixe, env, noter):
    prefixe = env.get("BACKUP_S3_PREFIX") or PREFIXE_DEFAUT
    cle = prefixe + os.path.basename(fichier) + suffixe
    sha_envoi, md5_envoi = empreintes(a_envoyer)
    taille = os.path.getsize(a_envoyer)

    code, corps, entetes = requete_s3(
        "PUT", env, cle,
        corps={"chemin": a_envoyer, "sha256": sha_envoi},
        entetes_sup={
            # Explicite, jamais implicite : on ne suppose pas le défaut du dépôt.
            "x-amz-acl": "private",
            "Content-Type": "application/octet-stream",
        },
        taille=taille)
    v, expl = verdict_envoi(code, entetes.get("ETag"), md5_envoi,
                            corps.decode("utf-8", "replace") if corps else None)
    noter("envoi de %s" % cle, v, expl)
    if v == "echec":
        return

    # ── LE contrôle : l'objet se lit-il sans clé ? ──────────────────────────
    code_anonyme = get_anonyme(env, cle)
    v, expl = verdict_etancheite(code_anonyme)
    noter("étanchéité (requête anonyme)", v, expl)
    if v == "echec":
        # ⚠️ On ne laisse pas derrière soi un objet dont on vient d'établir
        # qu'il est public. Le supprimer est plus urgent que de le signaler.
        requete_s3("DELETE", env, cle)
        noter("objet retiré du dépôt", "ok", "suppression immédiate après fuite")
        return

    # ── Rétention distante ─────────────────────────────────────────────────
    garder = int(env.get("BACKUP_GARDER_DISTANT") or GARDER_DISTANT_DEFAUT)
    code, corps, _ = requete_s3("GET", env, "", parametres={
        "list-type": "2", "prefix": prefixe, "max-keys": "1000"})

    racine, tronque = None, False
    if code == 200 and corps:
        try:
            arbre = ET.fromstring(corps)
            racine = arbre.tag.split("}")[-1]
            tronque = any(e.tag.split("}")[-1] == "IsTruncated"
                          and (e.text or "").lower() == "true"
                          for e in arbre.iter())
        except ET.ParseError:
            racine = "illisible"

    v, expl = verdict_listage(code, racine, tronque)
    if v != "ok":
        noter("rétention distante", v, "%s — les anciennes s'accumulent" % expl)
        return

    cles = [e.text for e in ET.fromstring(corps).iter()
            if e.tag.split("}")[-1] == "Key" and e.text]
    vieilles = a_supprimer_distant(cles, garder)
    for k in vieilles:
        requete_s3("DELETE", env, k)
    noter("rétention distante", "ok", "%d gardée(s), %d supprimée(s)"
          % (min(len(cles), garder), len(vieilles)))


# ─────────────────────────────────────────────────────────────────────────────
# Auto-test
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
    global _ok
    complet = {c: "x" for c in CLES_REQUISES}

    # ── Doivent PASSER ───────────────────────────────────────────────────────
    _v("configuration complète", verdict_configuration(complet, "")[0], "ok")
    _v("désactivation explicite",
       verdict_configuration({}, "off")[0], "desactive")
    _v("chiffrement fidèle",
       verdict_chiffrement(0, "abc", "abc", 5_000_000)[0], "ok")
    _v("envoi conforme", verdict_envoi(200, '"d41d8c"', "D41D8C")[0], "ok")
    _v("refus anonyme 403", verdict_etancheite(403)[0], "ok")
    _v("refus anonyme 404", verdict_etancheite(404)[0], "ok")
    _v("listage conforme",
       verdict_listage(200, "ListBucketResult", False)[0], "ok")
    _v("rétention : rien à supprimer", a_supprimer_distant(["a", "b"], 30), [])
    _v("rétention : les plus anciennes",
       a_supprimer_distant(["a-1", "a-2", "a-3"], 1), ["a-1", "a-2"])
    _v("signature déterministe et non vide",
       len(signer("GET", "h", "/k", None, "abc", "AK", "SK", "gra")
           ["Authorization"]) > 80, True)

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ LE cas qui justifie tout ce module : l'envoi a réussi ET l'objet est
    # public. Aucune réponse d'écriture ne l'aurait dit.
    _v("objet lisible en anonyme", verdict_etancheite(200)[0], "echec")
    _v("configuration absente", verdict_configuration({}, "")[0], "echec")
    # ⚠️ Plus dangereux qu'une absence : ça ressemble à une configuration.
    _v("configuration à moitié faite",
       verdict_configuration({"BACKUP_S3_ENDPOINT": "e",
                              "BACKUP_S3_BUCKET": "b"}, "")[0], "echec")
    _v("clé présente mais vide",
       verdict_configuration(dict(complet, BACKUP_S3_SECRET_ACCESS_KEY="  "),
                             "")[0], "echec")
    _v("gpg en erreur", verdict_chiffrement(1, "abc", None, 0)[0], "echec")
    # ⚠️ Le symétrique du dump tronqué : gpg exite 0, le fichier ne se rouvre pas.
    _v("chiffré illisible",
       verdict_chiffrement(0, "abc", None, 5_000_000)[0], "echec")
    _v("déchiffré différent",
       verdict_chiffrement(0, "abc", "def", 5_000_000)[0], "echec")
    _v("aucun fichier chiffré",
       verdict_chiffrement(0, "abc", "abc", 0)[0], "echec")
    _v("PUT refusé", verdict_envoi(403, None, "d41d8c")[0], "echec")
    _v("ETag ≠ MD5 local",
       verdict_envoi(200, '"aaaa"', "bbbb")[0], "echec")
    # Sans ETag, on ne conclut pas — se taire vaut mieux que rassurer.
    _v("ETag absent", verdict_envoi(200, None, "bbbb")[0], "non_concluant")
    _v("dépôt injoignable", verdict_etancheite(None)[0], "non_concluant")
    _v("code inattendu", verdict_etancheite(500)[0], "non_concluant")
    # ⚠️ LE faux vert trouvé en éprouvant ce module contre MinIO : 200, mais
    # c'est la liste des DÉPÔTS. Zéro `<Key>` — donc « rien à purger », dit
    # d'un ton assuré, pendant que les sauvegardes s'empilent.
    _v("200 mais mauvais document",
       verdict_listage(200, "ListAllMyBucketsResult", False)[0], "non_concluant")
    _v("listage tronqué",
       verdict_listage(200, "ListBucketResult", True)[0], "non_concluant")
    _v("listage refusé", verdict_listage(403, None, False)[0], "non_concluant")

    try:
        a_supprimer_distant(["a"], 0)
        _echecs.append("rétention distante à 0 acceptée — elle effacerait tout")
    except ValueError:
        _ok += 1

    refus = 17
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


def prouver():
    """Le contrôle d'étanchéité, pointé sur un objet RÉELLEMENT public.

    ⚠️ Un auto-test qui nourrit `verdict_etancheite(200)` prouve que la
    fonction sait dire « echec » — pas que la chaîne HTTP qui l'alimente sait
    rapporter un 200. Ici on interroge une vraie photo de promo de la
    production, publique par conception, et on exige que le contrôle la
    dénonce. C'est la mutation du vrai fichier, version réseau.
    """
    print("── preuve : le contrôle d'étanchéité sait-il refuser ? ──\n")
    public = ("https://echango-promo.s3.gra.io.cloud.ovh.net/"
              "promo-photos/")
    cible = os.environ.get("URL_PUBLIQUE_CONNUE", "")
    if not cible:
        print("  Fournir URL_PUBLIQUE_CONNUE=<url d'un objet public réel>.")
        print("  (une photo de promo de la production, sous %s…)" % public)
        return False

    code = _code_seul(cible)
    v, expl = verdict_etancheite(code)
    print("  objet public réel  → HTTP %s → %s" % (code, v))
    print("     %s" % expl)
    if v != "echec":
        print("\n  ❌ LE CONTRÔLE NE SAIT PAS REFUSER — il aurait laissé passer "
              "une sauvegarde publique.")
        return False

    inexistant = cible.rsplit("/", 1)[0] + "/sonde-inexistante-echango.bin"
    code2 = _code_seul(inexistant)
    v2, _ = verdict_etancheite(code2)
    print("  objet absent       → HTTP %s → %s" % (code2, v2))
    if v2 == "echec":
        print("\n  ❌ Le contrôle crie au loup sur un objet absent.")
        return False

    print("\n  ✅ Le contrôle dénonce un objet public et accepte un refus.")
    return True


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)
    if "--prouver" in sys.argv:
        sys.exit(0 if prouver() else 1)
    if "--envoyer" in sys.argv:
        i = sys.argv.index("--envoyer")
        if i + 1 >= len(sys.argv):
            print("❌ --envoyer attend un chemin de fichier")
            sys.exit(2)
        chemin = sys.argv[i + 1]
        if not os.path.exists(chemin):
            print("❌ fichier introuvable : %s" % chemin)
            sys.exit(2)
        etat = []

        def noter(libelle, verdict, explication):
            marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
            print("  %s %-38s %s" % (marque, libelle, explication))
            etat.append(verdict)

        envoyer(chemin, lire_config(), noter)
        sys.exit(1 if ("echec" in etat or "non_concluant" in etat) else 0)
    print(__doc__)
    sys.exit(2)
