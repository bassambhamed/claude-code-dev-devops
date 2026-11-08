#!/usr/bin/env bash
# Create the runtime-only database secret. Never enable shell tracing here.
set -euo pipefail
namespace="${1:-ecommerce}"
hote="${2:-postgres}"
[[ "$namespace" == ecommerce || "$namespace" == ecommerce-helm ]] || { echo "Namespace de formation requis." >&2; exit 1; }
[[ "$(kubectl config current-context)" == k3d-formation ]] || { echo "Contexte k3d-formation requis." >&2; exit 1; }
: "${POSTGRES_PASSWORD:?Définissez POSTGRES_PASSWORD dans votre terminal.}"
# A restricted alphabet avoids connection-string delimiter and env-file injection.
[[ "$POSTGRES_PASSWORD" =~ ^[a-zA-Z0-9_-]{16,}$ ]] || { echo "Utilisez au moins 16 caractères alphanumériques, _ ou -." >&2; exit 1; }
[[ "$hote" =~ ^[a-zA-Z0-9.-]+$ ]] || { echo "Hôte PostgreSQL invalide." >&2; exit 1; }
umask 077
dossier="$(mktemp -d)"
trap 'rm -f "$dossier/donnees"; rmdir "$dossier"' EXIT
{
  printf 'POSTGRES_PASSWORD=%s\n' "$POSTGRES_PASSWORD"
  printf 'ConnectionStrings__catalogdb=Host=%s;Port=5432;Database=catalogdb;Username=postgres;Password=%s\n' "$hote" "$POSTGRES_PASSWORD"
  printf 'ConnectionStrings__orderingdb=Host=%s;Port=5432;Database=orderingdb;Username=postgres;Password=%s\n' "$hote" "$POSTGRES_PASSWORD"
} > "$dossier/donnees"
# The dry-run output is piped directly, never saved in the repository or displayed.
kubectl create secret generic ecommerce-db -n "$namespace" --from-env-file="$dossier/donnees" --dry-run=client -o yaml \
  | kubectl apply -f - >/dev/null
echo "Secret ecommerce-db installé dans $namespace (valeurs non affichées)."
