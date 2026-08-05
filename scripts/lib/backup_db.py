#!/usr/bin/env python3
"""Sauvegarde de la base — et la seule qui compte : celle qu'on a restaurée.

── Pourquoi ce script existe ────────────────────────────────────────────────

Aucun mécanisme de sauvegarde depuis le début du projet. La dette a été
identifiée le 2026-07-12, **après un incident de corruption**, et elle est
restée ouverte : c'est le seul point du registre dont l'échec serait
**irréversible**. Tout le reste se rattrape.

── Ce qui distingue ce script d'un `pg_dump` dans un cron ───────────────────

**Un fichier de sauvegarde qu'on n'a jamais restauré n'est pas une
sauvegarde** — c'est un fichier dont on espère qu'il en est une. Le mode de
défaillance classique n'est pas « le dump n'a pas tourné » : c'est « le dump
tourne tous les jours, exite 0, et produit un fichier tronqué » — découvert le
jour où on en a besoin, c'est-à-dire trop tard.

Ce script **restaure chaque sauvegarde qu'il produit**, dans une base jetable,
et compare le nombre de lignes **table par table** avec la source. Une
sauvegarde qui ne se restaure pas est signalée comme un échec, pas comme un
avertissement.

C'est la règle 28 appliquée à l'exploitation : un contrôle qu'on n'a jamais vu
refuser n'a rien montré. Ici, `--self-test` porte autant de cas qui doivent
échouer que de cas qui passent, et la vérification de restauration est le
contrôle lui-même.

── Deux choix qui méritent d'être écrits ────────────────────────────────────

1. **`pg_dump` est pris DANS le conteneur**, pas sur la machine hôte. Un client
   plus ancien que le serveur refuse de dumper (`server version mismatch`), et
   l'hôte n'a de toute façon aucun client Postgres installé. Prendre celui du
   conteneur garantit l'accord des versions par construction.

2. **Format `custom` (`-Fc`), pas du SQL brut.** Il est compressé, et surtout
   `pg_restore` peut le restaurer sélectivement — ce qui compte le jour où l'on
   veut récupérer une seule table sans écraser le reste.

── Usage ────────────────────────────────────────────────────────────────────

    python3 scripts/lib/backup_db.py --self-test
    ./scripts/backup-db.sh                    # sauvegarde + vérification + envoi
    GARDER=14 ./scripts/backup-db.sh          # rétention personnalisée

── Et depuis le 2026-08-05, l'étape 4 : l'envoi hors site ───────────────────

Les trois premières étapes ne couvrent que la corruption **logique**. Une
sauvegarde posée à côté de la base disparaît avec le disque qui la porte.
`backup_upload.py` chiffre, dépose sur S3 en ACL privée, puis **redemande
l'objet en anonyme** et exige un refus. Voir sa documentation pour le détail —
notamment pourquoi le dépôt de destination n'est pas celui de l'application.
"""

import os
import re
import subprocess
import sys
import time

CONTENEUR = os.environ.get("PG_CONTAINER", "echangopromo-postgres-1")
DESTINATION = os.environ.get("BACKUP_DIR", os.path.expanduser("~/backups/echangopromo"))
GARDER = int(os.environ.get("GARDER", "7"))
# ⚠️ Une sauvegarde plus petite que ça n'est pas une base, c'est un en-tête.
# Le seuil ne prétend pas valider le contenu — c'est la restauration qui le
# fait ; il n'attrape que le cas grossier du fichier vide.
TAILLE_MINIMALE = 1024


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_dump(code_sortie, taille, erreur):
    if code_sortie != 0:
        return "echec", "pg_dump a échoué (code %s) : %s" % (code_sortie,
                                                             (erreur or "")[:120])
    if taille is None:
        return "echec", "aucun fichier produit"
    if taille < TAILLE_MINIMALE:
        return ("echec",
                "fichier de %d octets — trop petit pour être une base, "
                "un dump tronqué exite 0 tout comme un bon" % taille)
    return "ok", "%.1f Mo" % (taille / 1024 / 1024)


def verdict_restauration(source, restaure):
    """Table par table. Un total identique peut cacher deux écarts qui
    s'annulent — c'est le genre de coïncidence qu'on ne veut pas parier."""
    if not source:
        return "non_concluant", "aucune table dans la source — rien à comparer"
    if not restaure:
        return ("echec",
                "la restauration n'a produit AUCUNE table — le fichier n'est "
                "pas restaurable")
    manquantes = sorted(set(source) - set(restaure))
    if manquantes:
        return ("echec",
                "%d table(s) absentes après restauration : %s"
                % (len(manquantes), ", ".join(manquantes[:4])))
    ecarts = [(t, source[t], restaure[t]) for t in sorted(source)
              if source[t] != restaure[t]]
    if ecarts:
        detail = ", ".join("%s %d→%d" % e for e in ecarts[:4])
        return ("echec",
                "%d table(s) au compte différent après restauration : %s"
                % (len(ecarts), detail))
    return "ok", "%d tables, %d lignes, à l'identique" % (
        len(source), sum(source.values()))


def a_supprimer(fichiers, garder):
    """Les plus anciennes au-delà de [garder]. Rend une liste, ne supprime rien.

    ⚠️ Séparé de la suppression pour être testable : une rétention qui efface
    la mauvaise sauvegarde est pire que pas de rétention du tout.
    """
    if garder < 1:
        raise ValueError("garder doit valoir au moins 1")
    ordonnes = sorted(fichiers, reverse=True)  # noms horodatés → tri = récence
    return sorted(ordonnes[garder:])


# ─────────────────────────────────────────────────────────────────────────────

def psql(base, requete):
    """Exécute une requête dans le conteneur et rend les lignes brutes."""
    r = subprocess.run(
        ["docker", "exec", CONTENEUR, "psql", "-U", UTILISATEUR, "-d", base,
         "-tA", "-F", "|", "-c", requete],
        capture_output=True, text=True)
    if r.returncode != 0:
        return None, r.stderr.strip()
    return [l for l in r.stdout.splitlines() if l.strip()], None


def comptes(base):
    """{table: nombre de lignes} — comptes EXACTS, pas les estimations de
    `pg_stat_user_tables`, qui dérivent entre deux VACUUM."""
    lignes, err = psql(base, """
        SELECT tablename FROM pg_tables
        WHERE schemaname = 'public' ORDER BY tablename
    """)
    if lignes is None:
        return None, err
    resultat = {}
    for table in lignes:
        # Le nom vient de `pg_tables`, pas d'une entrée utilisateur — mais il
        # est tout de même mis entre guillemets, jamais interpolé nu.
        n, err = psql(base, 'SELECT count(*) FROM "%s"' % table.replace('"', ''))
        if n is None:
            return None, err
        resultat[table] = int(n[0])
    return resultat, None


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
    src = {"promo": 40, "commercant": 20}

    # ── Doivent PASSER ───────────────────────────────────────────────────────
    _v("dump valide", verdict_dump(0, 5_000_000, None)[0], "ok")
    _v("restauration fidèle", verdict_restauration(src, dict(src))[0], "ok")
    _v("rétention : rien à supprimer",
       a_supprimer(["b-1", "b-2"], 7), [])
    _v("rétention : les plus anciennes",
       a_supprimer(["b-1", "b-2", "b-3", "b-4"], 2), ["b-1", "b-2"])

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    _v("pg_dump en erreur", verdict_dump(1, 5_000_000, "boom")[0], "echec")
    # ⚠️ LE mode de défaillance visé : le dump exite 0 et le fichier est vide.
    _v("dump tronqué", verdict_dump(0, 12, None)[0], "echec")
    _v("aucun fichier", verdict_dump(0, None, None)[0], "echec")
    _v("restauration vide", verdict_restauration(src, {})[0], "echec")
    _v("table manquante",
       verdict_restauration(src, {"promo": 40})[0], "echec")
    # ⚠️ Une table restaurée à moitié : le fichier s'ouvre, les données
    # manquent. C'est ce qu'une simple vérification « pg_restore exite 0 »
    # laisserait passer.
    _v("lignes manquantes",
       verdict_restauration(src, {"promo": 39, "commercant": 20})[0], "echec")
    _v("source vide → non concluant",
       verdict_restauration({}, {})[0], "non_concluant")

    # ⚠️ Une rétention à 0 effacerait TOUT, y compris la sauvegarde qu'on vient
    # de faire. Refusée à la source plutôt que corrigée en silence.
    try:
        a_supprimer(["b-1"], 0)
        _echecs.append("rétention à 0 acceptée — elle effacerait tout")
    except ValueError:
        _ok += 1

    refus = 8
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


# ─────────────────────────────────────────────────────────────────────────────

def lire_env():
    """`DATABASE_URL` du .env — la seule source de vérité sur la base servie."""
    chemin = os.path.expanduser(
        os.environ.get("ENV_FILE", "~/projects/echangopromo/apps/backend/.env"))
    if not os.path.exists(chemin):
        print("❌ .env introuvable : %s" % chemin)
        sys.exit(2)
    for ligne in open(chemin, encoding="utf-8"):
        if ligne.startswith("DATABASE_URL="):
            url = ligne.split("=", 1)[1].strip()
            m = re.match(r"postgres(?:ql)?://([^:]+):([^@]+)@[^/]+/(\S+)", url)
            if not m:
                print("❌ DATABASE_URL illisible : %s" % url)
                sys.exit(2)
            return m.group(1), m.group(3)
    print("❌ DATABASE_URL absente de %s" % chemin)
    sys.exit(2)


UTILISATEUR, BASE = ("", "")


def main():
    global UTILISATEUR, BASE
    UTILISATEUR, BASE = lire_env()
    stamp = time.strftime("%Y%m%d-%H%M%S")
    os.makedirs(DESTINATION, exist_ok=True)
    fichier = os.path.join(DESTINATION, "%s-%s.dump" % (BASE, stamp))
    base_verif = "verif_restauration_%s" % stamp

    print("═" * 64)
    print("  Sauvegarde de %s — et vérification par restauration" % BASE)
    print("═" * 64)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-38s %s" % (marque, libelle, explication))
        # Le LIBELLÉ est conservé, pas seulement le verdict : depuis que
        # l'étape 4 existe, deux familles d'échec cohabitent, et le message
        # final doit dire LAQUELLE. Voir plus bas.
        resultats.append((libelle, verdict))

    # ── 1. Le dump ──────────────────────────────────────────────────────────
    print("\n── 1. sauvegarde ──")
    with open(fichier, "wb") as sortie:
        r = subprocess.run(
            ["docker", "exec", CONTENEUR, "pg_dump", "-Fc", "-U", UTILISATEUR,
             "-d", BASE],
            stdout=sortie, stderr=subprocess.PIPE)
    taille = os.path.getsize(fichier) if os.path.exists(fichier) else None
    v, expl = verdict_dump(r.returncode, taille, r.stderr.decode("utf-8", "replace"))
    noter(os.path.basename(fichier), v, expl)
    if v != "ok":
        return 1

    # ── 2. La restauration, qui est le vrai contrôle ────────────────────────
    print("\n── 2. vérification : on la restaure pour de bon ──")
    source, err = comptes(BASE)
    if source is None:
        noter("lecture de la source", "non_concluant", err or "illisible")
        return 1

    subprocess.run(["docker", "exec", CONTENEUR, "createdb", "-U", UTILISATEUR,
                    base_verif], capture_output=True)
    try:
        # `pg_restore` passe par stdin : le fichier vit sur l'hôte, pas dans le
        # conteneur.
        with open(fichier, "rb") as entree:
            rr = subprocess.run(
                ["docker", "exec", "-i", CONTENEUR, "pg_restore", "-U",
                 "%s" % UTILISATEUR, "-d", base_verif, "--no-owner"],
                stdin=entree, capture_output=True)
        restaure, err = comptes(base_verif)
        if restaure is None:
            noter("restauration", "echec", err or "base de vérification illisible")
            return 1
        v, expl = verdict_restauration(source, restaure)
        noter("comptes source ↔ restauré", v, expl)
        if v != "ok" and rr.stderr:
            print("     pg_restore : %s"
                  % rr.stderr.decode("utf-8", "replace").strip()[:200])
    finally:
        # ⚠️ Toujours, même en cas d'échec : une base de vérification laissée
        # derrière s'accumulerait à chaque passage.
        subprocess.run(["docker", "exec", CONTENEUR, "dropdb", "-U", UTILISATEUR,
                        "--if-exists", base_verif], capture_output=True)

    # ── 3. La rétention ─────────────────────────────────────────────────────
    print("\n── 3. rétention (%d sauvegardes gardées) ──" % GARDER)
    toutes = [f for f in os.listdir(DESTINATION) if f.endswith(".dump")]
    vieilles = a_supprimer(toutes, GARDER)
    for f in vieilles:
        os.remove(os.path.join(DESTINATION, f))
    noter("purge", "ok", "%d gardée(s), %d supprimée(s)"
          % (min(len(toutes), GARDER), len(vieilles)))

    # ── 4. L'envoi hors site ────────────────────────────────────────────────
    # ⚠️ Sans cette étape, tout ce qui précède ne couvre que la corruption
    # LOGIQUE. Une sauvegarde posée à côté de la base disparaît avec elle : le
    # disque, le conteneur, la machine. C'est le seul mode de défaillance que
    # les trois premières étapes ne voient pas du tout.
    print("\n── 4. envoi hors site ──")
    # La frontière entre « la sauvegarde elle-même » et « sa copie distante ».
    # Repérée par un INDICE et non par les libellés : ceux de l'étape 4
    # viennent d'un autre module et changeront sans prévenir.
    avant_envoi = len(resultats)
    try:
        import backup_upload
    except ImportError as e:
        noter("module d'envoi", "non_concluant", "backup_upload introuvable : %s" % e)
    else:
        backup_upload.envoyer(fichier, backup_upload.lire_config(), noter)

    print("\n" + "═" * 64)
    echecs = [l for l, v in resultats if v == "echec"]
    non_concluants = [l for l, v in resultats if v == "non_concluant"]
    print("%d contrôles, %d échec(s), %d non concluant(s)"
          % (len(resultats), len(echecs), len(non_concluants)))

    # ⚠️ Le message final DOIT distinguer les deux familles d'échec. Avant que
    # l'étape 4 existe, un seul échec était possible et le message pouvait le
    # nommer sans réfléchir. Depuis, un envoi non configuré affichait « la
    # sauvegarde NE SE RESTAURE PAS » alors qu'elle venait d'être restaurée
    # avec succès : un opérateur réveillé à 3 h aurait jeté un fichier sain.
    # Un message qui fait conclure faux est pire qu'un message absent.
    locaux = [l for l, v in resultats[:avant_envoi] if v == "echec"]
    distants = [l for l, v in resultats[avant_envoi:] if v == "echec"]
    if locaux:
        print("⚠️  la sauvegarde a été produite mais NE SE RESTAURE PAS — "
              "la traiter comme inexistante.")
    elif distants:
        print("⚠️  la sauvegarde est saine et restaurable, mais elle N'A PAS "
              "QUITTÉ LA MACHINE — elle ne protège que de la corruption "
              "logique, pas d'une perte de disque.")
    return 1 if (echecs or non_concluants) else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)
    sys.exit(main())
