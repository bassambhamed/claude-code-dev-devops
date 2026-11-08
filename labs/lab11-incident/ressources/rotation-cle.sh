#!/usr/bin/env bash
# rotation-cle.sh <copie> : rotation « de formation » de la clé de paiement exposée.
#
# Joue le rôle du portail du fournisseur EasyCheckout :
#   1. retrouve la clé exposée dans incident/journal-ordering.log et la marque révoquée ;
#   2. émet une nouvelle clé et la range dans les user-secrets d'Ordering (le coffre local,
#      comme au lab 3), sans jamais l'afficher ;
#   3. consigne l'opération, clés masquées, dans incident/rotation.log (hors Git).
#
# À lancer par vous, dans un terminal, jamais par Claude : la nouvelle clé ne doit pas
# passer par la session.
#   bash labs/lab11-incident/ressources/rotation-cle.sh ~/lab-ecommerce
# Codes de retour : 0 rotation faite, 1 échec, 2 usage.
set -euo pipefail

copie="${1:-}"
if [[ -z "$copie" ]]; then
  echo "Usage : $0 <copie de l'application>" >&2
  exit 2
fi
copie="$(cd "$copie" 2>/dev/null && pwd -P)" || { echo "Dossier introuvable : $1" >&2; exit 2; }
cd "$copie"

journal=incident/journal-ordering.log
projet=src/ECommerce.Ordering.Api
[[ -f "$journal" ]] || { echo "$journal introuvable : avez-vous lancé rejouer-incident.sh ?" >&2; exit 1; }
grep -q '<UserSecretsId>' "$projet/ECommerce.Ordering.Api.csproj" \
  || { echo "Ordering n'a pas de UserSecretsId : lancez « dotnet user-secrets init --project $projet » (lab 3)." >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "Outil manquant : openssl" >&2; exit 1; }

masquer() { printf '%s…' "${1:0:14}"; }                 # ecpk_live_9b1f…
empreinte() { printf '%s' "$1" | openssl dgst -sha256 | awk '{ print substr($NF, 1, 12) }'; }

exposee="$(grep -o -E 'ecpk_(live|test)_[0-9a-f]{32}' "$journal" | head -n 1 || true)"
[[ -n "$exposee" ]] || { echo "Aucune clé ecpk_ dans $journal : rien à révoquer." >&2; exit 1; }

nouvelle="ecpk_live_$(openssl rand -hex 16)"
if ! DOTNET_CLI_UI_LANGUAGE=en dotnet user-secrets set "Payment:ApiKey" "$nouvelle" --project "$projet" >/dev/null; then
  echo "Échec de dotnet user-secrets set : la nouvelle clé n'a pas été rangée." >&2
  exit 1
fi

heure="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  echo "$heure révoquée $(masquer "$exposee") empreinte $(empreinte "$exposee")"
  echo "$heure émise    $(masquer "$nouvelle") empreinte $(empreinte "$nouvelle") rangée dans user-secrets (Payment:ApiKey, Ordering)"
} | tee -a incident/rotation.log

echo "Rotation consignée dans $copie/incident/rotation.log (hors Git)."
echo "En production, la nouvelle clé irait dans le coffre-fort de l'environnement (variable Payment__ApiKey)."
