#!/usr/bin/env bash
# Render and inspect both profiles offline. No Kubernetes access is needed.
set -euo pipefail
mkdir -p preuves/lab9
for profil in dev prod; do
  helm lint charts/ecommerce -f "values-$profil.yaml" --strict
  helm template formation charts/ecommerce -n ecommerce-helm -f "values-$profil.yaml" > "preuves/lab9/rendu-$profil.yaml"
  # No Secret payload belongs in a chart. Only references to existing Secrets.
  if grep -Eq '^kind: Secret$|^[[:space:]]+(password|POSTGRES_PASSWORD):[[:space:]]+[^$]' "preuves/lab9/rendu-$profil.yaml"; then
    echo "Secret embarqué dans le rendu $profil." >&2; exit 1
  fi
  [[ "$(grep -c '^kind: Deployment$' "preuves/lab9/rendu-$profil.yaml")" == 4 ]]
  [[ "$(grep -c 'runAsNonRoot: true' "preuves/lab9/rendu-$profil.yaml")" == 4 ]]
  if [[ "$profil" == prod ]] && grep -Eq 'path: /(health|alive)' "preuves/lab9/rendu-$profil.yaml"; then
    echo "Sonde HTTP de développement présente en production." >&2; exit 1
  fi
done
diff -u preuves/lab9/rendu-dev.yaml preuves/lab9/rendu-prod.yaml > preuves/lab9/ecarts.diff || [[ $? == 1 ]]
echo "CHART OK : lint et rendus dev/prod ; relire les YAML avant installation."
