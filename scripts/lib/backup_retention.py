#!/usr/bin/env python3
"""La politique de rétention — une seule, appliquée des deux côtés.

── Ce qu'elle dit ───────────────────────────────────────────────────────────

    7 quotidiennes  +  8 hebdomadaires

Une quinzaine de fichiers pour deux mois d'histoire, là où « garder les 30
plus récentes » n'en couvrait qu'un.

── Pourquoi l'étiquette est posée à la CRÉATION, pas au tri ─────────────────

On aurait pu classer au moment de purger, en relisant la date dans chaque nom.
L'étiquette dans le nom est meilleure pour une raison qui n'a rien d'esthétique :
**la décision n'existe alors qu'à un seul endroit**. Le dépôt distant reprend
le nom du fichier local ; classer à la purge aurait demandé de regrouper deux
fois — une fois sur le disque, une fois sur S3 — donc deux implémentations
qu'il aurait fallu tenir d'accord (règle 30). Avec l'étiquette, les deux
rétentions redeviennent « trier, garder les N premiers », appliqué à deux lots.

Bénéfice de terrain : `--lister` affiche des noms qui **disent ce qu'ils
sont**, à 3 h du matin, quand on cherche quoi restaurer.

── Pourquoi la semaine ISO, et pas « le vendredi » ──────────────────────────

L'idée première était d'étiqueter la sauvegarde du vendredi. Le critère est
faux, et son mode de défaillance est exactement celui que ce projet traque :
**si le serveur est éteint ce vendredi-là** — reboot, maintenance, incident —
il n'y a pas d'hebdo cette semaine. Jeudi et samedi existent, sans étiquette,
et seront purgés au bout de 7 jours. La semaine disparaît entièrement de
l'histoire, sans que rien ne le signale, puisque tout le reste s'est bien
passé.

Le bon critère n'est pas « on est vendredi » mais **« cette semaine a-t-elle
déjà son exemplaire ? »**. L'étiquette porte donc la semaine ISO
(`hebdo-2026W32`), et le test est une comparaison de chaîne — pas du calcul de
dates. Si vendredi manque, c'est samedi qui devient l'exemplaire de la semaine.

── Deux refus qui ne se négocient pas ───────────────────────────────────────

1. **Un nom illisible n'est jamais supprimé.** Un fichier dont on ne sait pas
   extraire l'horodatage est *inconnu*, pas *vieux*. Le purger « au cas où »
   serait le contraire exact du métier de ce script.

2. **Un palier à zéro est refusé à la source.** `jours=0` viderait tout le lot
   quotidien, y compris la sauvegarde qu'on vient de faire. Ça ne se corrige
   pas en silence, ça se refuse.

Usage : python3 scripts/lib/backup_retention.py --self-test
"""

import datetime
import re
import sys

MARQUE_HEBDO = "-hebdo-"

# ⚠️ Les valeurs par défaut vivent ICI et nulle part ailleurs. Le disque local
# et le dépôt distant appliquent la MÊME politique : si l'un passe à 10
# semaines et pas l'autre, une hebdo purgée localement ne le serait pas à
# distance, et l'histoire des deux côtés cesserait de se correspondre.
JOURS_DEFAUT = 7
SEMAINES_DEFAUT = 8

# ⚠️ L'horodatage, PAS le nom entier : l'étiquette hebdo s'insère après lui, et
# le préfixe S3 avant. Trier sur le nom brut marcherait aujourd'hui par
# coïncidence de format — on trie sur ce qui porte réellement le temps.
MOTIF_HORODATAGE = re.compile(r"(\d{8})-(\d{6})")


def etiquette_semaine(jour):
    """`hebdo-2026W32` pour une date donnée (datetime.date).

    Calculée par `isocalendar()` et non par `strftime('%G%V')` : les
    directives ISO ne sont pas portables d'une plateforme à l'autre, et une
    étiquette qui change de forme selon la machine casserait le tri.
    """
    an, semaine, _ = jour.isocalendar()
    return "hebdo-%dW%02d" % (an, semaine)


def est_hebdo(nom):
    return MARQUE_HEBDO in nom


def horodatage(nom):
    """Rend '20260805-155651', ou None si le nom n'en porte pas."""
    m = MOTIF_HORODATAGE.search(nom)
    return "%s-%s" % (m.group(1), m.group(2)) if m else None


def doit_etiqueter(noms_existants, jour):
    """Cette semaine a-t-elle déjà son exemplaire ?"""
    etq = etiquette_semaine(jour)
    return not any(etq in n for n in noms_existants)


def repartir(noms, jours, semaines):
    """Rend {'garder', 'supprimer', 'illisibles'} — ne supprime RIEN.

    Séparé de la suppression pour être éprouvable : une rétention qui efface
    la mauvaise sauvegarde est pire que pas de rétention du tout.
    """
    if jours < 1:
        raise ValueError("jours doit valoir au moins 1 — 0 viderait le lot "
                         "quotidien, y compris la sauvegarde du jour")
    if semaines < 1:
        raise ValueError("semaines doit valoir au moins 1 — 0 viderait tout "
                         "l'historique hebdomadaire")

    illisibles = sorted(n for n in noms if horodatage(n) is None)
    lisibles = [n for n in noms if horodatage(n) is not None]

    def recents(lot, combien):
        # Tri sur l'horodatage extrait, décroissant ; le nom départage pour
        # rester déterministe si deux sauvegardes partagent la seconde.
        ordonnes = sorted(lot, key=lambda n: (horodatage(n), n), reverse=True)
        return ordonnes[:combien], ordonnes[combien:]

    g_jour, s_jour = recents([n for n in lisibles if not est_hebdo(n)], jours)
    g_sem, s_sem = recents([n for n in lisibles if est_hebdo(n)], semaines)

    return {
        "garder": sorted(g_jour + g_sem),
        "supprimer": sorted(s_jour + s_sem),
        # ⚠️ Jamais dans « supprimer ». Remontés pour être DITS : un fichier
        # qu'on ne sait pas classer doit se voir, pas s'accumuler en silence.
        "illisibles": illisibles,
    }


def verdict_hebdo_manquant(nb_hebdo, nb_quotidiennes, plus_ancienne, aujourdhui):
    """Une étiquette qui cesserait d'être posée serait INDOLORE pendant 7 jours,
    puis on n'aurait plus que 7 jours d'histoire — avec un script au vert tous
    les matins. Un compte à zéro n'est pas un compte, c'est une absence.
    """
    if nb_hebdo > 0 or nb_quotidiennes == 0 or plus_ancienne is None:
        return "ok", ""
    if (aujourdhui - plus_ancienne).days < 8:
        return "ok", ""
    return ("non_concluant",
            "AUCUNE sauvegarde hebdomadaire alors que les quotidiennes "
            "remontent à %d jours — l'étiquetage ne se pose plus, et "
            "l'historique se limitera à %d jours"
            % ((aujourdhui - plus_ancienne).days, nb_quotidiennes))


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


def _q(jour):
    return "echango_promo-202608%02d-030000.dump" % jour


def _h(jour, semaine):
    return "echango_promo-202608%02d-030000-hebdo-2026W%02d.dump" % (jour, semaine)


def self_test():
    global _ok
    d = datetime.date

    # ── Doivent PASSER ───────────────────────────────────────────────────────
    _v("étiquette d'une semaine ISO",
       etiquette_semaine(d(2026, 8, 5)), "hebdo-2026W32")
    # ⚠️ Le 1er janvier 2027 tombe dans la semaine 53 de 2026 au sens ISO.
    # Vérifié ici pour que le passage d'année ne produise pas deux étiquettes
    # concurrentes sur la même semaine réelle.
    _v("passage d'année (ISO)",
       etiquette_semaine(d(2027, 1, 1)), "hebdo-2026W53")
    _v("reconnaissance d'une hebdo", est_hebdo(_h(7, 32)), True)
    _v("une quotidienne n'est pas hebdo", est_hebdo(_q(7)), False)
    _v("horodatage lu", horodatage(_q(5)), "20260805-030000")
    _v("préfixe S3 sans effet sur l'horodatage",
       horodatage("db-backups/" + _q(5) + ".gpg"), "20260805-030000")

    _v("rien à supprimer sous le plafond",
       repartir([_q(1), _q(2)], 7, 8)["supprimer"], [])
    r = repartir([_q(j) for j in range(1, 11)], 7, 8)
    _v("les 3 plus anciennes quotidiennes partent",
       r["supprimer"], sorted([_q(1), _q(2), _q(3)]))
    # ⚠️ LE cœur de la politique : une hebdo n'entre PAS dans le compte des
    # quotidiennes, sinon 8 semaines d'histoire seraient purgées en 7 jours.
    r = repartir([_q(j) for j in range(1, 11)] + [_h(3, 27)], 7, 8)
    _v("l'hebdo survit au-delà de la fenêtre quotidienne",
       _h(3, 27) in r["garder"], True)
    _v("étiqueter : semaine encore vide",
       doit_etiqueter([_q(3), _q(4)], d(2026, 8, 5)), True)

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    _v("étiqueter : la semaine a déjà son exemplaire",
       doit_etiqueter([_h(3, 32)], d(2026, 8, 5)), False)
    # ⚠️ Le vendredi manqué : samedi doit pouvoir prendre l'étiquette. Même
    # semaine ISO, exemplaire absent ⇒ oui.
    _v("vendredi manqué, samedi prend le relais",
       doit_etiqueter([_q(3), _q(4)], d(2026, 8, 8)), True)

    # ⚠️ Un nom illisible est INCONNU, pas VIEUX. Jamais supprimé.
    r = repartir([_q(j) for j in range(1, 11)] + ["notes.txt", "vieux.dump"], 7, 8)
    _v("l'illisible n'est jamais supprimé",
       [n for n in r["supprimer"] if n in ("notes.txt", "vieux.dump")], [])
    _v("l'illisible est remonté pour être dit",
       r["illisibles"], ["notes.txt", "vieux.dump"])
    # ⚠️ Le cas qui fait mal : QUE des noms illisibles. Une rétention naïve les
    # trierait et en supprimerait — ici elle ne touche à rien.
    r = repartir(["a.txt", "b.txt", "c.txt"], 1, 1)
    _v("rien de classable ⇒ rien de supprimé", r["supprimer"], [])

    _v("une seule sauvegarde ⇒ conservée",
       repartir([_q(5)], 7, 8)["supprimer"], [])

    for palier, valeur in (("jours", 0), ("semaines", 0)):
        try:
            repartir([_q(5)], 0 if palier == "jours" else 7,
                     0 if palier == "semaines" else 8)
            _echecs.append("palier %s à 0 accepté — il viderait le lot" % palier)
        except ValueError:
            _ok += 1

    # Le garde-fou de l'étiquetage disparu.
    _v("aucune hebdo mais série jeune ⇒ on ne crie pas",
       verdict_hebdo_manquant(0, 3, d(2026, 8, 3), d(2026, 8, 5))[0], "ok")
    _v("aucune hebdo sur une série de 3 semaines ⇒ alerte",
       verdict_hebdo_manquant(0, 20, d(2026, 7, 15), d(2026, 8, 5))[0],
       "non_concluant")
    _v("des hebdos existent ⇒ rien à signaler",
       verdict_hebdo_manquant(4, 20, d(2026, 7, 15), d(2026, 8, 5))[0], "ok")
    # Dépôt vide : ne pas confondre « ça ne marche plus » avec « ça n'a pas
    # encore commencé ».
    _v("dépôt vide ⇒ pas d'alarme",
       verdict_hebdo_manquant(0, 0, None, d(2026, 8, 5))[0], "ok")

    refus = 12
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(0 if self_test() else 1)
    print(__doc__)
    sys.exit(2)
