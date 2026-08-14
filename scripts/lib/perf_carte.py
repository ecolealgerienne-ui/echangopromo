#!/usr/bin/env python3
"""Banc de fluidité de la carte — les temps d'image, pas les millisecondes réseau.

── Où se joue réellement la fluidité ───────────────────────────────────────

`banc_perf` mesure le serveur : 12 à 17 ms en p95. Il n'y a rien à optimiser de
ce côté aujourd'hui. Ce que le client ressent comme « ça rame » se joue donc
ailleurs — dans le nombre d'images que l'app rate pendant qu'il fait glisser la
carte.

Ce banc juge la capture produite par `integration_test/perf_carte_test.dart`,
qui panoramique et change de zoom pendant que `watchPerformance` enregistre
chaque image.

── Les deux temps, et pourquoi aucun ne remplace l'autre ───────────────────

**Construction** (côté Dart) : reconstruire l'arbre de widgets.
**Rastérisation** (côté GPU) : dessiner réellement l'image.

Une construction rapide dont la rastérisation traîne donne exactement le même
à-coup à l'écran. Ne regarder que la première — l'erreur courante, parce que
c'est celle qu'on sait optimiser — laisserait passer la moitié des causes.

⚠️ **Le budget est de 16 ms**, soit une image toutes les 16,7 ms à 60 images par
seconde. Au-delà, l'image est manquée et le geste décroche du doigt. On juge le
**p90** et non la moyenne : une moyenne à 8 ms peut cacher une image sur dix à
40 ms, et c'est précisément celle-là qui se voit.

── ⚠️ Trois réserves, toutes réelles ───────────────────────────────────────

**Un émulateur n'est pas un téléphone.** Sans accélération GPU, la
rastérisation y est exagérée dans des proportions qui n'ont aucun rapport avec
un appareil réel. Un dépassement côté rastérisation doit être **remesuré sur un
vrai appareil avant d'être cru** ; un dépassement côté construction, lui, est
du code Dart et se transpose beaucoup mieux.

**Ce banc ne peut pas vérifier qu'il mesure du `--profile`.** En `debug`, le
Dart est interprété et les temps sont deux à dix fois pires, sans rapport avec
la production — on partirait optimiser du code qui n'a rien. C'est
`test-perf-carte.sh` qui impose le mode ; lancé à la main autrement, ce banc
juge des chiffres qui ne veulent rien dire.

**Les tuiles et les photos n'y sont pas.** Leur chargement ne bloque pas le fil
d'interface et n'apparaît donc dans aucun temps d'image. Le dire évite de croire
que ce parcours couvre tout le ressenti.

── Usage ───────────────────────────────────────────────────────────────────

    python3 scripts/lib/perf_carte.py --self-test
    ./scripts/test-perf-carte.sh
"""

import json
import os
import sys

CAPTURE = os.environ.get("PERF_CAPTURE",
                         "apps/mobile/build/perf_carte.json")

# ⚠️ 16 ms : le budget d'une image à 60 Hz (16,7 ms exactement). Nommé parce
# qu'il porte une décision — un écran 120 Hz le diviserait par deux.
BUDGET_MS = float(os.environ.get("BUDGET_IMAGE_MS", "16"))

# Une image isolée au-delà de 100 ms est un à-coup **visible**, pas une
# statistique. Elle mérite son propre verdict : un p90 sain peut la masquer.
SEUIL_PIRE_MS = float(os.environ.get("SEUIL_PIRE_MS", "100"))

# En dessous, l'échantillon ne vaut rien : trois images lentes sur vingt
# feraient un p90 catastrophique sans rien dire du produit.
MIN_IMAGES = int(os.environ.get("MIN_IMAGES", "120"))


# ─────────────────────────────────────────────────────────────────────────────
# Les verdicts — la logique que l'auto-test éprouve
# ─────────────────────────────────────────────────────────────────────────────

def verdict_capture(donnees, cle):
    """⚠️ Une capture absente ou vide doit se voir, pas se sauter.

    Un profilage silencieusement vide se lit exactement comme un profilage
    réussi — c'est le défaut fondateur de la règle 28, transposé ici.
    """
    if donnees is None:
        return "non_concluant", "aucune capture : le parcours n'a pas tourné"
    if cle not in donnees:
        return ("echec",
                "la capture ne porte pas la clé « %s » : le parcours a tourné "
                "sans appeler watchPerformance, et rien n'a été mesuré" % cle)
    return "ok", "capture présente"


def verdict_echantillon(images):
    """Assez d'images pour qu'un centile veuille dire quelque chose ?"""
    if images is None:
        return "non_concluant", "nombre d'images illisible"
    if images < MIN_IMAGES:
        return ("non_concluant",
                "%d images seulement (%d attendues) : sur un échantillon aussi "
                "court, trois images lentes suffisent à faire un p90 "
                "catastrophique qui ne dit rien du produit"
                % (images, MIN_IMAGES))
    return "ok", "%d images mesurées" % images


def verdict_temps(p90_ms, budget, quoi, emulateur_sensible=False):
    """Le p90, jamais la moyenne : c'est l'image ratée qui se voit."""
    if p90_ms is None:
        return "non_concluant", "temps de %s illisible" % quoi
    if p90_ms > budget:
        reserve = (" ⚠️ sur émulateur, la rastérisation est exagérée sans "
                   "accélération GPU : à remesurer sur un vrai appareil avant "
                   "d'être cru" if emulateur_sensible else "")
        return ("echec",
                "p90 de %s = %.1f ms, budget %.0f ms — une image sur dix "
                "dépasse, et le geste décroche du doigt.%s"
                % (quoi, p90_ms, budget, reserve))
    return "ok", "p90 = %.1f ms (budget %.0f)" % (p90_ms, budget)


def verdict_pire_image(pire_ms, seuil):
    """⚠️ Un p90 sain peut masquer un à-coup unique et parfaitement visible."""
    if pire_ms is None:
        return "non_concluant", "pire image illisible"
    if pire_ms > seuil:
        return ("echec",
                "une image a pris %.0f ms (seuil %.0f) : c'est un à-coup vu à "
                "l'œil nu, qu'un p90 sain ne rattrape pas" % (pire_ms, seuil))
    return "ok", "pire image %.0f ms (seuil %.0f)" % (pire_ms, seuil)


def verdict_ratees(ratees, total):
    """La part d'images hors budget — la mesure la plus proche du ressenti."""
    if ratees is None or not total:
        return "non_concluant", "décompte illisible"
    part = 100.0 * ratees / total
    if part > 10.0:
        return ("echec",
                "%d images sur %d hors budget (%.0f %%) : au-delà de 10 %%, "
                "le décrochage est continu, pas ponctuel"
                % (ratees, total, part))
    return "ok", "%d/%d hors budget (%.1f %%)" % (ratees, total, part)


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
    _v("capture présente", verdict_capture({"carte": {}}, "carte")[0], "ok")
    _v("échantillon suffisant", verdict_echantillon(600)[0], "ok")
    _v("construction dans le budget",
       verdict_temps(9.2, 16, "construction")[0], "ok")
    _v("aucun à-coup", verdict_pire_image(48, 100)[0], "ok")
    _v("peu d'images ratées", verdict_ratees(30, 600)[0], "ok")

    # ── Doivent REFUSER ──────────────────────────────────────────────────────
    # ⚠️ Le pire résultat possible : un profilage vide qui se lit comme réussi.
    _v("watchPerformance jamais appelé",
       verdict_capture({"autre": {}}, "carte")[0], "echec")
    _v("construction hors budget",
       verdict_temps(24.0, 16, "construction")[0], "echec")
    # ⚠️ L'à-coup unique, que le p90 ne rattrape pas.
    _v("à-coup visible", verdict_pire_image(180, 100)[0], "echec")
    _v("décrochage continu", verdict_ratees(120, 600)[0], "echec")

    # ── Doivent rester NON CONCLUANTS ────────────────────────────────────────
    # ⚠️ Trois images lentes sur vingt feraient un p90 sans valeur.
    _v("échantillon trop court", verdict_echantillon(20)[0], "non_concluant")
    _v("aucune capture", verdict_capture(None, "carte")[0], "non_concluant")
    _v("images illisibles", verdict_echantillon(None)[0], "non_concluant")
    _v("temps illisible",
       verdict_temps(None, 16, "construction")[0], "non_concluant")
    _v("pire image illisible", verdict_pire_image(None, 100)[0],
       "non_concluant")
    _v("décompte illisible", verdict_ratees(None, 600)[0], "non_concluant")
    _v("total nul", verdict_ratees(0, 0)[0], "non_concluant")

    refus = 11
    total = _ok + len(_echecs)
    print("auto-test : %d cas, dont %d refus" % (total, refus))
    for e in _echecs:
        print("  ❌ %s" % e)
    print("  %d/%d" % (_ok, total))
    return not _echecs


# ─────────────────────────────────────────────────────────────────────────────

def main():
    print("═" * 74)
    print("  Fluidité de la carte — les temps d'image")
    print("═" * 74)

    donnees = None
    if os.path.exists(CAPTURE):
        try:
            with open(CAPTURE, encoding="utf-8") as f:
                donnees = json.load(f)
        except Exception as e:
            print("  capture illisible : %s" % e)
    else:
        print("  capture introuvable : %s" % CAPTURE)

    resultats = []

    def noter(libelle, verdict, explication):
        marque = {"ok": "✅", "echec": "❌", "non_concluant": "⚠️ "}[verdict]
        print("  %s %-30s %s" % (marque, libelle, explication))
        resultats.append(verdict)

    print("\n── la capture existe et porte des images ──")
    noter("fichier de capture", *verdict_capture(donnees, "carte"))
    resume = (donnees or {}).get("carte")
    if not isinstance(resume, dict):
        print("\n" + "═" * 74)
        print("1 contrôle, aucune mesure — lancer ./scripts/test-perf-carte.sh")
        return 1

    images = resume.get("frame_count")
    noter("échantillon", *verdict_echantillon(images))

    print("\n── construction (Dart) : reconstruire l'arbre de widgets ──")
    noter("p90", *verdict_temps(
        resume.get("90th_percentile_frame_build_time_millis"),
        BUDGET_MS, "construction"))
    noter("pire image", *verdict_pire_image(
        resume.get("worst_frame_build_time_millis"), SEUIL_PIRE_MS))
    noter("images hors budget", *verdict_ratees(
        resume.get("missed_frame_build_budget_count"), images))

    print("\n── rastérisation (GPU) : dessiner l'image ──")
    noter("p90", *verdict_temps(
        resume.get("90th_percentile_frame_rasterizer_time_millis"),
        BUDGET_MS, "rastérisation", emulateur_sensible=True))
    noter("pire image", *verdict_pire_image(
        resume.get("worst_frame_rasterizer_time_millis"), SEUIL_PIRE_MS))
    noter("images hors budget", *verdict_ratees(
        resume.get("missed_frame_rasterizer_budget_count"), images))

    print("\n   moyennes : construction %.1f ms · rastérisation %.1f ms"
          % (resume.get("average_frame_build_time_millis") or 0,
             resume.get("average_frame_rasterizer_time_millis") or 0))

    print("\n" + "═" * 74)
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
