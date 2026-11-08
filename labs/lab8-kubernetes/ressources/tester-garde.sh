#!/usr/bin/env bash
# Exercise the hook without reading or modifying a real cluster configuration.
set -euo pipefail
copie="${1:?Usage : tester-garde.sh <copie>}"
hook="$copie/.claude/hooks/garde-kubectl.sh"
[[ -f "$hook" ]] || { echo "Hook absent : $hook" >&2; exit 1; }
dossier="$(mktemp -d)"
trap 'rm -f "$dossier/kubectl"; rmdir "$dossier"' EXIT
cat > "$dossier/kubectl" <<'FAUX'
#!/usr/bin/env bash
printf '%s\n' "${CONTEXTE_TEST:-k3d-formation}"
FAUX
chmod +x "$dossier/kubectl"
cas() {
  local contexte="$1" commande="$2" attendu="$3" code=0
  jq -n --arg c "$commande" '{tool_input:{command:$c}}' \
    | PATH="$dossier:$PATH" CONTEXTE_TEST="$contexte" bash "$hook" >/dev/null 2>&1 || code=$?
  [[ "$code" == "$attendu" ]] || { echo "ÉCHEC : $commande => $code (attendu $attendu)" >&2; exit 1; }
}
cas k3d-formation 'kubectl get pods -n ecommerce' 0
cas k3d-formation 'helm lint charts/ecommerce -f values-prod.yaml' 0
cas autre-cluster 'kubectl get pods -n ecommerce' 2
cas k3d-formation 'kubectl --context autre get pods -n ecommerce' 2
cas k3d-formation 'kubectl get pods -n kube-system' 2
cas k3d-formation 'kubectl get secret/ecommerce-db -n ecommerce' 2
cas k3d-formation 'kubectl get pods -n ecommerce; kubectl delete namespace ecommerce' 2
cas k3d-formation 'kubectl delete namespace ecommerce -n ecommerce' 2
cas k3d-formation 'kubectl get pods' 2
cas k3d-formation 'git status --short' 0
echo 'GARDE OK'
