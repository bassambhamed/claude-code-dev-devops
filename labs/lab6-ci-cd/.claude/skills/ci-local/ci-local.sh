#!/usr/bin/env bash
# ci-local.sh [--base <réf>] [étape...] : rejoue sur le poste la chaîne de la CI, puis la gate.
#
# Les étapes, avec les mêmes commandes que les workflows :
#   build    dotnet build ECommerce.slnx                      ci.yml, job « Build et tests »
#   tests    dotnet test ECommerce.slnx --no-build            ci.yml, job « Build et tests »
#   format   dotnet format --verify-no-changes, fichiers C# modifiés seulement
#                                                             ci.yml, job « Format »
#   audit    dotnet list package --vulnerable : échec sur une gravité haute ou critique
#                                                             securite.yml, job « Dépendances »
#   secrets  gitleaks git --config .gitleaks.toml (tout l'historique)
#                                                             securite.yml, job « Secrets »
# Sans étape en argument : toutes. Si vous changez une commande ici, changez-la dans le
# workflow, et inversement : une chaîne locale qui diverge de la CI ne prouve plus rien.
#
# Le format ne porte que sur les fichiers C# modifiés depuis la base (par défaut, le point de
# départ de la branche sur origin/main, ou sur main), plus les fichiers non commités : le code
# contient 7 écarts historiques dans src/ECommerce.ServiceDefaults/Extensions.cs.
#
# Code de retour : 0 gate ouverte ; 1 gate fermée (une étape a échoué) ;
# 3 gate incomplète (aucun échec, mais une étape n'a pas pu s'exécuter) ; 2 usage.
set -uo pipefail
export DOTNET_CLI_UI_LANGUAGE=en DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1

TOUTES="build tests format audit secrets"

usage() {
  echo "Usage : ci-local.sh [--base <réf>] [build] [tests] [format] [audit] [secrets]" >&2
  exit 2
}

base_demandee=""
etapes=""
while (($# > 0)); do
  case "$1" in
    --base) [[ $# -ge 2 ]] || usage; base_demandee="$2"; shift 2 ;;
    build | tests | format | audit | secrets) etapes="$etapes $1"; shift ;;
    *) usage ;;
  esac
done
etapes="${etapes:-$TOUTES}"

racine="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Pas dans un dépôt Git." >&2; exit 2; }
cd "$racine" || exit 2
[[ -f ECommerce.slnx ]] || { echo "ECommerce.slnx introuvable à la racine du dépôt." >&2; exit 2; }

temporaire="${TMPDIR:-/tmp}"
journaux="$(mktemp -d "${temporaire%/}/ci-local.XXXXXX")"

# Résultats, dans l'ordre d'exécution (bash 3.2 : pas de tableau associatif).
noms=() ; statuts=() ; durees=() ; details=()
noter() { # noter <étape> <OK|ÉCHEC|NON EXÉCUTÉ> <durée> <détail>
  noms+=("$1"); statuts+=("$2"); durees+=("$3"); details+=("$4")
  printf '%-8s %-12s %4s s  %s\n' "$1" "$2" "$3" "$4"
}
statut_de() { # statut_de <étape> : le statut, ou rien si l'étape n'a pas tourné
  local i
  ((${#noms[@]} > 0)) || return 0
  for i in "${!noms[@]}"; do [[ "${noms[$i]}" == "$1" ]] && { echo "${statuts[$i]}"; return; }; done
}
demandee() { [[ " $etapes " == *" $1 "* ]]; }
compter() { # compter <Total|Failed> : somme du compteur sur les lignes de résumé de dotnet test
  grep -E '^(Passed|Failed)!' "$journaux/tests.log" | sed -E "s/.*$1: +([0-9]+).*/\\1/" | awk '{s += $1} END {print s + 0}'
}

extrait() { # extrait <titre> : affiche l'entrée standard, limitée, sous un titre
  local contenu
  contenu="$(head -n 20)"
  [[ -n "$contenu" ]] || return 0
  echo "  --- $1"
  sed 's/^/  | /' <<<"$contenu"
}

# Avertissement : la CI ne voit que les commits.
non_commites="$(git status --porcelain | wc -l | tr -d ' ')"
if ((non_commites > 0)); then
  echo "Attention : $non_commites fichier(s) non commité(s). La chaîne locale les inclut ; la CI ne verra que vos commits."
fi
echo

# --- build ----------------------------------------------------------------------------
if demandee build; then
  debut=$SECONDS
  if dotnet build ECommerce.slnx >"$journaux/build.log" 2>&1; then
    noter build OK $((SECONDS - debut)) "$(grep -E '^ +[0-9]+ Warning\(s\)' "$journaux/build.log" | awk '{print $1}' | tail -n 1) avertissement(s)"
  else
    noter build "ÉCHEC" $((SECONDS - debut)) "voir l'extrait ci-dessous"
    grep -E ' error [A-Z]+[0-9]+' "$journaux/build.log" | sed -E 's/ \[[^]]*\]$//' | sort -u | extrait "Erreurs de compilation"
  fi
fi

# --- tests ----------------------------------------------------------------------------
if demandee tests; then
  debut=$SECONDS
  case "$(statut_de build)" in
    "ÉCHEC") noter tests "NON EXÉCUTÉ" 0 "le build a échoué" ;;
    *)
      options=()
      [[ "$(statut_de build)" == OK ]] && options=(--no-build)
      if dotnet test ECommerce.slnx ${options[@]+"${options[@]}"} >"$journaux/tests.log" 2>&1; then
        noter tests OK $((SECONDS - debut)) "$(compter Total) test(s) réussi(s)"
      else
        noter tests "ÉCHEC" $((SECONDS - debut)) "$(compter Failed) test(s) en échec sur $(compter Total)"
        {
          grep -E ' error [A-Z]+[0-9]+' "$journaux/tests.log" | sed -E 's/ \[[^]]*\]$//' | sort -u
          grep -E -A7 '^ +Failed [A-Za-z]' "$journaux/tests.log" | grep -v -E '^\s*(Stack Trace:|at |--- End of|--$)'
          grep -E 'Docker|docker' "$journaux/tests.log" | head -n 3
        } | extrait "Tests en échec"
      fi
      ;;
  esac
fi

# --- format ---------------------------------------------------------------------------
if demandee format; then
  debut=$SECONDS
  if [[ -n "$base_demandee" ]]; then
    reference="$base_demandee"
  elif git rev-parse --verify -q origin/main >/dev/null; then
    reference="origin/main"
  else
    reference="main"
  fi
  if ! base="$(git merge-base HEAD "$reference" 2>/dev/null)"; then
    noter format "NON EXÉCUTÉ" 0 "base introuvable : $reference (option --base)"
  else
    fichiers=()
    while IFS= read -r f; do
      [[ -n "$f" && -f "$f" ]] && fichiers+=("$f")
    done < <({
      git diff --name-only --diff-filter=ACMR "$base" -- '*.cs'
      git diff --name-only --diff-filter=ACMR HEAD -- '*.cs'
      git ls-files --others --exclude-standard -- '*.cs'
    } | sort -u)
    if ((${#fichiers[@]} == 0)); then
      noter format OK 0 "aucun fichier C# modifié depuis $reference"
    elif dotnet format ECommerce.slnx --verify-no-changes --include "${fichiers[@]}" >"$journaux/format.log" 2>&1; then
      noter format OK $((SECONDS - debut)) "${#fichiers[@]} fichier(s) C# modifié(s) depuis $reference"
    else
      noter format "ÉCHEC" $((SECONDS - debut)) "${#fichiers[@]} fichier(s) C# vérifié(s) ; corrigez avec dotnet format ECommerce.slnx --include <fichier>"
      grep -E ': (error|warning) ' "$journaux/format.log" | sed -E "s|^$racine/||; s/ \[[^]]*\]$//" | sort -u | extrait "Écarts de format"
    fi
  fi
fi

# --- audit ----------------------------------------------------------------------------
if demandee audit; then
  debut=$SECONDS
  if ! command -v jq >/dev/null; then
    noter audit "NON EXÉCUTÉ" 0 "jq est requis"
  elif ! dotnet restore ECommerce.slnx >"$journaux/audit.log" 2>&1 ||
    ! dotnet list ECommerce.slnx package --vulnerable --include-transitive --format json >"$journaux/audit.json" 2>>"$journaux/audit.log"; then
    noter audit "NON EXÉCUTÉ" $((SECONDS - debut)) "restauration ou audit impossible (réseau ?) : $journaux/audit.log"
  else
    # Même filtre que securite.yml.
    jq -r '.projects[] | (.path | split("/") | last) as $projet
           | .frameworks[]? | ((.topLevelPackages // []) + (.transitivePackages // []))[]
           | select(.vulnerabilities) | . as $p | .vulnerabilities[]
           | "\(.severity)\t\($projet)\t\($p.id) \($p.resolvedVersion)\t\(.advisoryurl)"' "$journaux/audit.json" |
      sort -u >"$journaux/vulnerabilites.txt"
    if grep -E -q '^(High|Critical)' "$journaux/vulnerabilites.txt"; then
      noter audit "ÉCHEC" $((SECONDS - debut)) "dépendance de gravité haute ou critique"
      extrait "Vulnérabilités" <"$journaux/vulnerabilites.txt"
    else
      noter audit OK $((SECONDS - debut)) "aucune vulnérabilité haute ou critique ($(wc -l <"$journaux/vulnerabilites.txt" | tr -d ' ') autre(s))"
    fi
  fi
fi

# --- secrets --------------------------------------------------------------------------
if demandee secrets; then
  debut=$SECONDS
  if ! command -v gitleaks >/dev/null; then
    noter secrets "NON EXÉCUTÉ" 0 "gitleaks introuvable : installez-le (lab 3)"
  elif [[ ! -f .gitleaks.toml ]]; then
    noter secrets "NON EXÉCUTÉ" 0 ".gitleaks.toml absent (lab 3)"
  elif gitleaks git --config .gitleaks.toml --redact --verbose --no-color . >"$journaux/secrets.log" 2>&1; then
    noter secrets OK $((SECONDS - debut)) "aucun secret dans l'historique (gitleaks $(gitleaks version 2>/dev/null))"
  else
    noter secrets "ÉCHEC" $((SECONDS - debut)) "secret détecté dans l'historique (gitleaks $(gitleaks version 2>/dev/null))"
    grep -E '^(RuleID|File|Line|Commit|Fingerprint):' "$journaux/secrets.log" | extrait "Constats gitleaks (valeurs masquées)"
  fi
fi

# --- gate -----------------------------------------------------------------------------
echo
fermee="" ; incomplete=""
for i in "${!noms[@]}"; do
  case "${statuts[$i]}" in
    "ÉCHEC") fermee="$fermee ${noms[$i]}" ;;
    "NON EXÉCUTÉ") incomplete="$incomplete ${noms[$i]}" ;;
  esac
done
echo "Journaux complets : $journaux"
if [[ -n "$fermee" ]]; then
  echo "GATE FERMÉE : échec de${fermee}${incomplete:+ ; non exécuté :$incomplete}"
  exit 1
elif [[ -n "$incomplete" ]]; then
  echo "GATE INCOMPLÈTE : aucun échec, mais non exécuté :$incomplete"
  exit 3
fi
echo "GATE OUVERTE : $(echo $etapes | wc -w | tr -d ' ') étape(s) réussie(s)"
exit 0
