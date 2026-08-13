#!/usr/bin/env sh
# C3 — Avis de sécurité sur les dépendances VERROUILLÉES (base publique OSV).
#
# ⚠️ « À jour » et « sans vulnérabilité connue » sont deux questions différentes,
# et c'est la confusion que ce script existe pour lever. `npm outdated` /
# `pub outdated` répondent à la première : ils comptent les versions de retard,
# dont l'immense majorité n'a aucune portée de sécurité. Ici on pose la seconde,
# à osv.dev : *cette version PRÉCISE est-elle visée par un avis ?*
#
# ⚠️ La source de vérité est le fichier de VERROUILLAGE, pas le fichier de
# contraintes : c'est la version réellement embarquée qui est vulnérable ou non,
# pas la contrainte qui l'a choisie. Si les fichiers de verrouillage ne sont pas
# versionnés, c'est le préalable à traiter AVANT d'auditer quoi que ce soit.
#
# Usage :
#   sh scripts/audit-dependances.sh              # audite tous les lockfiles trouvés
#   sh scripts/audit-dependances.sh --self-test  # vérifie que ce script sait REFUSER
#
# Nécessite un accès réseau (api.osv.dev). Volontairement HORS du lanceur de
# bancs : ceux-ci doivent rester jouables hors ligne.

cd "$(dirname "$0")/.." || exit 2
. scripts/lib/audit.sh

OSV_URL="https://api.osv.dev/v1/querybatch"

# Plancher de paquets. En dessous, c'est que la lecture des lockfiles a échoué,
# et « aucun avis » ne veut plus rien dire (un défaut n'a pas de valeur par
# défaut — surtout pas « rien à signaler »).
PLANCHER="${AUDIT_DEP_PLANCHER:-5}"

_REQ="${TMPDIR:-/tmp}/audit-osv-req.$$.json"
_NOMS="${TMPDIR:-/tmp}/audit-osv-noms.$$"
_REP="${TMPDIR:-/tmp}/audit-osv-rep.$$.json"
trap 'rm -f "$_REQ" "$_NOMS" "$_REP"' EXIT

# --- Lecture des fichiers de verrouillage -------------------------------------
# Les lockfiles sont DÉCOUVERTS, jamais listés en dur : sinon l'audit reste vert
# sur le périmètre d'hier après l'ajout d'un sous-projet.
#
# ⚠️ Les formats NON SUPPORTÉS sont NOMMÉS, pas ignorés en silence. Un lockfile
# trouvé mais non lu est un angle mort ; le taire reviendrait à présenter une
# couverture partielle comme complète.
lit_locks() {
  "$PY" - "$@" <<'PYEOF'
import io, json, os, re, sys

paquets = {}   # (ecosysteme, nom) -> version
lus, non_lus = [], []

def ajoute(eco, nom, version):
    if nom and version:
        paquets[(eco, nom.strip())] = version.strip()

def texte(chemin):
    return io.open(chemin, encoding="utf-8", errors="replace").read()

for chemin in sys.argv[1:]:
    base = os.path.basename(chemin)
    avant = len(paquets)
    try:
        if base == "pubspec.lock":
            for m in re.finditer(r"\n  ([A-Za-z0-9_]+):\n(?:.*\n)*?    version: \"([^\"]+)\"", texte(chemin)):
                ajoute("Pub", m.group(1), m.group(2))

        elif base == "package-lock.json":
            d = json.loads(texte(chemin))
            for cle, info in (d.get("packages") or {}).items():
                if not cle or not isinstance(info, dict) or info.get("link"):
                    continue
                nom = info.get("name") or cle.split("node_modules/")[-1]
                ajoute("npm", nom, info.get("version"))
            for nom, info in (d.get("dependencies") or {}).items():   # lockfile v1
                if isinstance(info, dict):
                    ajoute("npm", nom, info.get("version"))

        elif base == "yarn.lock":
            # yarn v1 : « nom@contrainte:\n  version "x.y.z" »
            for bloc in re.split(r"\n(?=\S)", texte(chemin)):
                t = re.match(r'^"?(@?[^@\s"]+)@', bloc)
                v = re.search(r'\n\s+version:?\s+"?([^"\s]+)"?', bloc)
                if t and v:
                    ajoute("npm", t.group(1), v.group(1))

        elif base == "poetry.lock":
            for bloc in texte(chemin).split("[[package]]")[1:]:
                n = re.search(r'\nname\s*=\s*"([^"]+)"', bloc)
                v = re.search(r'\nversion\s*=\s*"([^"]+)"', bloc)
                if n and v:
                    ajoute("PyPI", n.group(1), v.group(1))

        elif base == "Pipfile.lock":
            d = json.loads(texte(chemin))
            for section in ("default", "develop"):
                for nom, info in (d.get(section) or {}).items():
                    v = (info or {}).get("version", "")
                    if v.startswith("=="):
                        ajoute("PyPI", nom, v[2:])

        elif base == "requirements.txt":
            # Seules les versions ÉPINGLÉES sont exploitables. Une contrainte
            # (`>=`, `~=`) ne dit pas ce qui est installé : la compter serait
            # inventer une mesure.
            for ligne in texte(chemin).splitlines():
                m = re.match(r"^\s*([A-Za-z0-9._-]+)\s*==\s*([A-Za-z0-9._+!-]+)", ligne)
                if m:
                    ajoute("PyPI", m.group(1), m.group(2))

        elif base == "Cargo.lock":
            for bloc in texte(chemin).split("[[package]]")[1:]:
                n = re.search(r'\nname\s*=\s*"([^"]+)"', bloc)
                v = re.search(r'\nversion\s*=\s*"([^"]+)"', bloc)
                if n and v:
                    ajoute("crates.io", n.group(1), v.group(1))

        elif base in ("go.sum", "go.mod"):
            for m in re.finditer(r"^(\S+)\s+(v\S+?)(?:/go\.mod)?\s", texte(chemin), re.M):
                ajoute("Go", m.group(1), m.group(2))

        elif base == "composer.lock":
            d = json.loads(texte(chemin))
            for section in ("packages", "packages-dev"):
                for p in (d.get(section) or []):
                    ajoute("Packagist", p.get("name"), p.get("version"))

        elif base == "Gemfile.lock":
            for m in re.finditer(r"^\s{4}([A-Za-z0-9_.-]+) \(([^)=<>~ ]+)\)$", texte(chemin), re.M):
                ajoute("RubyGems", m.group(1), m.group(2))

        else:
            non_lus.append(chemin)
            continue
    except Exception as exc:
        non_lus.append("%s (%s)" % (chemin, exc.__class__.__name__))
        continue

    lus.append("%s:%d" % (chemin, len(paquets) - avant))

sys.stderr.write("LUS %s\n" % " ".join(lus))
if non_lus:
    sys.stderr.write("NON_LUS %s\n" % " ".join(non_lus))

print(json.dumps({"queries": [
    {"package": {"name": nom, "ecosystem": eco}, "version": version}
    for (eco, nom), version in sorted(paquets.items())
]}))
PYEOF
}

# Rend « nom version écosystème » par paquet, dans le MÊME ordre que la requête —
# l'API OSV répond par un tableau positionnel, sans rappeler ce qu'elle a reçu.
noms_depuis_requete() {
  "$PY" -c '
import io, json, sys
for q in json.load(io.open(sys.argv[1], encoding="utf-8"))["queries"]:
    print(q["package"]["name"], q["version"], q["package"]["ecosystem"])
' "$1"
}

# Croise la réponse OSV avec la liste des paquets. Sort en ERREUR si la réponse
# est inexploitable : un audit qui ne sait pas s'il a interrogé quoi que ce soit
# doit se taire, pas rassurer.
croise() {
  "$PY" - "$1" "$2" <<'PYEOF'
import io, json, sys
reponse = json.load(io.open(sys.argv[1], encoding="utf-8"))
paquets = [l.split() for l in io.open(sys.argv[2], encoding="utf-8").read().splitlines() if l.strip()]
resultats = reponse.get("results")
if resultats is None or len(resultats) != len(paquets):
    sys.stderr.write("reponse OSV inexploitable (%s resultats pour %s paquets)\n"
                     % (len(resultats or []), len(paquets)))
    sys.exit(2)
for infos, entree in zip(paquets, resultats):
    avis = [v["id"] for v in entree.get("vulns", [])]
    if avis:
        print("%s %s %s %s" % (infos[0], infos[1], infos[2], ",".join(avis)))
PYEOF
}

# --- Auto-test : ce script sait-il REFUSER ? ----------------------------------
# Un audit qui rend « rien à signaler » sur N paquets est indiscernable d'un
# audit qui n'a rien interrogé du tout : même sortie, même code retour. On lui
# soumet donc une version dont on SAIT qu'elle est visée par un avis, et une
# version SAINE DU MÊME PAQUET — le second témoin prouve que le filtrage se fait
# sur la VERSION et pas sur le nom.
if [ "$1" = "--self-test" ]; then
  titre "Auto-test — l'audit sait-il signaler une version vulnérable ?"
  autotest_socle || exit "$RC_ECHEC"

  # `minimist` 1.2.5 : pollution de prototype (GHSA-xvch-5gv4-984h), corrigée en
  # 1.2.6. Le témoin sain est 1.2.8. Choisi parce qu'il ne dépend pas de
  # l'écosystème du projet audité : ce scénario prouve la CHAÎNE (réseau,
  # requête, croisement positionnel), pas le contenu du dépôt.
  #
  # ⚠️ UN TÉMOIN DE CE TYPE VIEILLIT. Le premier essayé ici était `lodash`
  # 4.17.15 / 4.17.21 — et 4.17.21 porte aujourd'hui trois avis parus depuis. Le
  # scénario SC-DEP.2 échouait donc sur un script correct.
  #
  # Si SC-DEP.2 échoue, DEUX causes possibles, à trancher avant de toucher au
  # code : (a) le filtrage ne se fait plus sur la version — vrai défaut ; (b) un
  # avis est paru sur la version « saine » — le témoin a vieilli, il faut le
  # remplacer. Vérifier d'abord :
  #     curl -s -X POST -d '{"queries":[{"package":{"name":"minimist","ecosystem":"npm"},"version":"1.2.8"}]}' \
  #       https://api.osv.dev/v1/querybatch
  printf '{"queries":[{"package":{"name":"minimist","ecosystem":"npm"},"version":"1.2.5"},{"package":{"name":"minimist","ecosystem":"npm"},"version":"1.2.8"}]}' > "$_REQ"
  printf 'minimist 1.2.5 npm\nminimist 1.2.8 npm\n' > "$_NOMS"
  if ! curl -s -X POST -d @"$_REQ" "$OSV_URL" -o "$_REP" --max-time 60; then
    skip "SC-DEP.0" "OSV joignable — api.osv.dev inatteignable — l'audit ne prouve rien"
    bilan; exit $?
  fi
  if ! _touches=$(croise "$_REP" "$_NOMS"); then
    skip "SC-DEP.0" "réponse OSV exploitable — croisement impossible"
    bilan; exit $?
  fi
  attend_egal "SC-DEP.1" "la version vulnérable est signalée" "1" \
    "$(printf '%s\n' "$_touches" | grep -c '^minimist 1.2.5 ')"
  attend_egal "SC-DEP.2" "la version saine du MÊME paquet ne l'est pas" "0" \
    "$(printf '%s\n' "$_touches" | grep -c '^minimist 1.2.8 ')"
  bilan; exit $?
fi

# --- Audit réel ---------------------------------------------------------------
titre "Dépendances verrouillées — avis de sécurité (OSV)"

# Découverte. `-prune` sur les dossiers d'artefacts : un lockfile de dépendance
# installée n'est pas une dépendance du projet.
LOCKS=$(find . \
  \( -name node_modules -o -name .git -o -name build -o -name dist \
     -o -name vendor -o -name .dart_tool -o -name target -o -name Pods \) -prune -o \
  \( -name 'pubspec.lock' -o -name 'package-lock.json' -o -name 'yarn.lock' \
     -o -name 'poetry.lock' -o -name 'Pipfile.lock' -o -name 'requirements.txt' \
     -o -name 'Cargo.lock' -o -name 'go.sum' -o -name 'composer.lock' \
     -o -name 'Gemfile.lock' \) -print 2>/dev/null | sed 's|^\./||' | sans_cr)

if [ -z "$LOCKS" ]; then
  skip "SC-DEP.3" "fichiers de verrouillage trouvés — aucun. Rien n'est prouvé sur les dépendances"
  printf '  Si le projet a des dépendances, leurs lockfiles ne sont pas versionnés :\n'
  printf '  c'\''est le préalable à traiter avant d'\''auditer cette couche.\n'
  bilan; exit $?
fi

printf '  %sfichiers de verrouillage : %s%s\n' "$C_DIM" "$(printf '%s' "$LOCKS" | tr '\n' ' ')" "$C_OFF"

# shellcheck disable=SC2086
lit_locks $LOCKS > "$_REQ" 2>"${_REP}.log" || {
  skip "SC-DEP.3" "lecture des fichiers de verrouillage — échec"
  cat "${_REP}.log" >&2; bilan; exit $?
}
# Le détail de ce qui a été lu ET de ce qui ne l'a pas été.
sed -n 's/^LUS /  lus      : /p;s/^NON_LUS /  NON LUS  : /p' "${_REP}.log"
if grep -q '^NON_LUS' "${_REP}.log"; then
  skip "SC-DEP.5" "tous les formats de verrouillage sont lus — certains ne le sont pas (voir ci-dessus)"
fi
rm -f "${_REP}.log"

noms_depuis_requete "$_REQ" > "$_NOMS"
_NB=$(grep -c . < "$_NOMS" | tr -d ' ')

if [ "${_NB:-0}" -lt "$PLANCHER" ]; then
  skip "SC-DEP.3" "paquets extraits — seulement $_NB (plancher $PLANCHER) — la lecture a échoué"
  bilan; exit $?
fi
printf '  %s%d versions verrouillées, interrogées à osv.dev%s\n' "$C_DIM" "$_NB" "$C_OFF"

if ! curl -s -X POST -d @"$_REQ" "$OSV_URL" -o "$_REP" --max-time 120; then
  skip "SC-DEP.4" "OSV joignable — inatteignable. Rien n'est prouvé, SURTOUT PAS l'absence d'avis"
  bilan; exit $?
fi

if ! _TOUCHES=$(croise "$_REP" "$_NOMS"); then
  skip "SC-DEP.4" "réponse OSV exploitable — croisement impossible"
  bilan; exit $?
fi

if [ -n "$_TOUCHES" ]; then
  printf '%s\n' "$_TOUCHES" | while read -r _nom _ver _eco _ids; do
    ko "SC-DEP.4" "$_eco/$_nom $_ver — avis $_ids" "aucun avis" "$_ids"
  done
  # `while` tourne dans un sous-shell : ses compteurs sont perdus. L'échec est
  # donc rendu explicitement plutôt que confié à `bilan`.
  printf '\n  %sDes dépendances embarquées sont visées par un avis de sécurité.%s\n' "$C_KO" "$C_OFF"
  printf '  Voir https://osv.dev/vulnerability/<ID> pour la portée exacte —\n'
  printf '  un avis n'\''est pas une exploitation : vérifier que le chemin est ATTEINT.\n'
  exit "$RC_ECHEC"
fi

ok "SC-DEP.4" "aucun avis sur les $_NB versions embarquées"

printf '\n  %sCe vert ne couvre que ce qui est DÉCLARÉ et VERROUILLÉ.%s\n' "$C_DIM" "$C_OFF"
printf '  %sHors périmètre : les binaires embarqués, les dépendances système%s\n' "$C_DIM" "$C_OFF"
printf '  %s(couche C4) et les paquets abandonnés — absence de correctif À VENIR,%s\n' "$C_DIM" "$C_OFF"
printf '  %spas vulnérabilité. À noter séparément, avec la décision.%s\n' "$C_DIM" "$C_OFF"

bilan
exit $?
