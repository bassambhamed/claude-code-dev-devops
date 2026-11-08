#!/usr/bin/env bash
# Hook PreToolUse, matcher "Bash|Write|Edit" : empêche un secret d'entrer dans le dépôt.
#   - Write, Edit : analyse le texte que Claude s'apprête à écrire.
#   - Bash « git commit » : analyse les lignes ajoutées par rapport à HEAD, et le contenu
#     des fichiers non suivis si la commande fait aussi un « git add ».
# Code 2 : l'outil n'est pas exécuté ; Claude reçoit le message, sans la valeur du secret.
# Seules les lignes ajoutées comptent : retirer un secret n'est jamais bloqué.
set -uo pipefail

# Clé de paiement de la formation, clé AWS, clé privée, jeton GitHub, clé Anthropic,
# mot de passe en clair dans une chaîne de connexion, et clé ou secret JSON avec une
# valeur littérale longue.
MOTIFS='ecpk_(live|test)_[0-9a-f]{32}'
MOTIFS+='|AKIA[0-9A-Z]{16}'
MOTIFS+='|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----'
MOTIFS+='|gh[pousr]_[A-Za-z0-9]{36}'
MOTIFS+='|sk-ant-[A-Za-z0-9_-]{20,}'
MOTIFS+='|(Password|Pwd)=[^;"'"'"'$<{ ]{4,}'
MOTIFS+='|"(ApiKey|ApiSecret|ClientSecret|Secret|Token)" *: *"[A-Za-z0-9_+/=-]{20,}"'

entree="$(cat)"
outil="$(jq -r '.tool_name // empty' <<<"$entree")"

bloquer() { # bloquer <où> <texte analysé>
  local regles
  regles="$(grep -E -o "$MOTIFS" <<<"$2" | sed -E 's/^(.{12}).*/\1…/' | sort -u | paste -sd ',' -)"
  {
    echo "Bloqué : un secret apparaît dans $1 (début : $regles)."
    echo "Ne l'écris pas dans le dépôt. Lis-le depuis la configuration à l'exécution :"
    echo "dotnet user-secrets en local, variables d'environnement ou coffre-fort ailleurs."
    echo "Si ce secret a déjà été commité ou poussé, il est compromis : il faut le révoquer."
  } >&2
  exit 2
}

case "$outil" in
  Write | Edit | MultiEdit)
    fichier="$(jq -r '.tool_input.file_path // "le fichier"' <<<"$entree")"
    texte="$(jq -r '[.tool_input.content, .tool_input.new_string, (.tool_input.edits[]?.new_string)]
                    | map(select(. != null)) | join("\n")' <<<"$entree")"
    if grep -E -q "$MOTIFS" <<<"$texte"; then bloquer "$fichier" "$texte"; fi
    ;;
  Bash)
    commande="$(jq -r '.tool_input.command // empty' <<<"$entree")"
    grep -E -q 'git( +-[cC] +[^ ]+)* +commit' <<<"$commande" || exit 0
    cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
    ajouts="$(git diff HEAD 2>/dev/null | grep -E '^\+' | grep -v -E '^\+\+\+ ')"
    if grep -E -q 'git( +-[cC] +[^ ]+)* +add' <<<"$commande"; then
      ajouts+=$'\n'"$(git ls-files --others --exclude-standard -z 2>/dev/null | xargs -0 cat 2>/dev/null)"
    fi
    if grep -E -q "$MOTIFS" <<<"$ajouts"; then bloquer "les changements à committer" "$ajouts"; fi
    ;;
esac
exit 0
