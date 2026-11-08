#!/usr/bin/env bash
# Le hook aide la session ; seule la CI décide de la livraison.
set -uo pipefail
entree="$(cat)"
# Une seule relance automatique ; un blocage persistant doit être expliqué à l'humain.
[[ "$(jq -r '.stop_hook_active // false' <<<"$entree")" == true ]] && exit 0
projet="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // empty' <<<"$entree")}"
cd "$projet" 2>/dev/null || exit 0
[[ -f ECommerce.slnx ]] || exit 0
journal="$(mktemp)"
trap 'rm -f "$journal"' EXIT
if DOTNET_CLI_UI_LANGUAGE=en dotnet build ECommerce.slnx >"$journal" 2>&1 \
  && DOTNET_CLI_UI_LANGUAGE=en dotnet test ECommerce.slnx --no-build >>"$journal" 2>&1 \
  && dotnet run .claude/skills/code-health/codehealth.cs -- src --gate --base "${CODE_HEALTH_BASE:-main}" >>"$journal" 2>&1; then
  exit 0
fi
echo "Porte qualité fermée. Corrige la cause ou explique le blocage ; ne masque aucun test." >&2
tail -n 35 "$journal" >&2
exit 2
