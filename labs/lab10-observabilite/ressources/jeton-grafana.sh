#!/usr/bin/env bash
# jeton-grafana.sh : crée un jeton Grafana en LECTURE SEULE pour le serveur MCP Grafana.
#
# Le compte de service « claude-lecture » (rôle Viewer) est créé s'il n'existe pas, puis
# un jeton valable 24 h lui est ajouté. Seul le jeton est écrit sur la sortie standard,
# pour être capturé sans s'afficher :
#
#   export GRAFANA_JETON_LECTURE="$(bash labs/lab10-observabilite/ressources/jeton-grafana.sh)"
#
# Variables : GRAFANA (http://localhost:3000), GRAFANA_ADMIN (admin:admin, le compte
# par défaut de grafana/otel-lgtm).
# Codes de retour : 0 jeton créé, 1 échec de l'API Grafana, 2 Grafana injoignable ou outil manquant.
set -uo pipefail

GRAFANA="${GRAFANA:-http://localhost:3000}"
GRAFANA_ADMIN="${GRAFANA_ADMIN:-admin:admin}"
COMPTE="claude-lecture"

for outil in curl jq; do
  command -v "$outil" >/dev/null 2>&1 || { echo "Outil manquant : $outil" >&2; exit 2; }
done

api() { # api <méthode> <chemin> [corps JSON] : écrit la réponse, échoue si le code n'est pas 2xx
  curl -s -f --max-time 10 -u "$GRAFANA_ADMIN" -X "$1" -H 'Content-Type: application/json' \
    ${3:+-d "$3"} "$GRAFANA$2"
}

if ! curl -s -f --max-time 5 "$GRAFANA/api/health" >/dev/null; then
  echo "Grafana ne répond pas sur $GRAFANA : l'AppHost tourne-t-il, avec la ressource lgtm ?" >&2
  exit 2
fi

id="$(api GET "/api/serviceaccounts/search?query=$COMPTE" | jq -r --arg n "$COMPTE" '.serviceAccounts[] | select(.name == $n) | .id' | head -n 1)"
if [[ -z "$id" ]]; then
  id="$(api POST /api/serviceaccounts "{\"name\":\"$COMPTE\",\"role\":\"Viewer\"}" | jq -r '.id // empty')"
  [[ -n "$id" ]] || { echo "Création du compte de service $COMPTE impossible : vérifiez les identifiants dans votre terminal." >&2; exit 1; }
  echo "Compte de service $COMPTE créé (rôle Viewer)." >&2
fi

nom="$COMPTE-$(date +%Y%m%d-%H%M%S)"
jeton="$(api POST "/api/serviceaccounts/$id/tokens" "{\"name\":\"$nom\",\"secondsToLive\":86400}" | jq -r '.key // empty')"
[[ -n "$jeton" ]] || { echo "Création du jeton impossible pour le compte $COMPTE." >&2; exit 1; }

echo "Jeton $nom créé pour $COMPTE (Viewer, 24 h)." >&2
printf '%s\n' "$jeton"
