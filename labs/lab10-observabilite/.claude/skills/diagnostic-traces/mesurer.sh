#!/usr/bin/env bash
# mesurer.sh [répétitions] : mesure le temps de création d'une commande via la passerelle.
#
# Pour 1, 3 et 5 lignes, envoie <répétitions> commandes (5 par défaut) à
# POST /ordering/api/orders, après une commande d'échauffement non comptée, et affiche
# min, médiane et max en millisecondes. Les heures de début et de fin (UTC) servent à
# retrouver les traces de la mesure.
#
# À lancer depuis la racine de la copie, l'application démarrée (AppHost).
# Codes de retour : 0 toutes les commandes créées (201), 1 au moins un autre code,
# 2 mesure impossible (outil manquant, passerelle injoignable, argument invalide).
set -uo pipefail

PASSERELLE="${PASSERELLE:-http://localhost:5067}"
repetitions="${1:-5}"

[[ "$repetitions" =~ ^[1-9][0-9]*$ ]] || { echo "Usage : $0 [répétitions, entier >= 1]" >&2; exit 2; }
for outil in curl awk; do
  command -v "$outil" >/dev/null 2>&1 || { echo "Outil manquant : $outil" >&2; exit 2; }
done

code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$PASSERELLE/catalog/api/products" 2>/dev/null)"
if [[ "$code" != 200 ]]; then
  echo "La passerelle ne répond pas ($PASSERELLE/catalog/api/products : code ${code:-aucun})." >&2
  echo "Démarrez l'application : dotnet run --project src/ECommerce.AppHost" >&2
  exit 2
fi

# Corps d'une commande de n lignes, produits 1 à 4 en boucle.
corps() {
  local n="$1" i lignes=""
  for ((i = 0; i < n; i++)); do
    lignes+="${lignes:+,}{\"productId\":$((i % 4 + 1)),\"quantity\":1}"
  done
  printf '{"customer":"Mesure","items":[%s]}' "$lignes"
}

# Envoie une commande ; affiche « code durée_ms ».
commander() {
  curl -s -o /dev/null --max-time 60 -w '%{http_code} %{time_total}' \
    -X POST "$PASSERELLE/ordering/api/orders" -H 'Content-Type: application/json' -d "$(corps "$1")" \
    | awk '{ printf "%s %d\n", $1, $2 * 1000 + 0.5 }'
}

echecs=0
commander 1 >/dev/null # échauffement : connexions, compilation à la volée

echo "Début : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%-7s %-10s %9s %13s %9s\n' "Lignes" "Commandes" "Min (ms)" "Médiane (ms)" "Max (ms)"
for lignes in 1 3 5; do
  durees=()
  for ((r = 0; r < repetitions; r++)); do
    read -r code ms < <(commander "$lignes")
    if [[ "$code" != 201 ]]; then
      echecs=$((echecs + 1))
      echo "  commande de $lignes ligne(s) : code HTTP $code" >&2
      continue
    fi
    durees+=("$ms")
  done
  if ((${#durees[@]} == 0)); then
    printf '%-7s %-10s %9s %13s %9s\n' "$lignes" 0 - - -
    continue
  fi
  printf '%s\n' "${durees[@]}" | sort -n | awk -v l="$lignes" '
    { v[NR] = $1 }
    END { printf "%-7s %-10s %9d %13d %9d\n", l, NR, v[1], v[int((NR + 1) / 2)], v[NR] }'
done
echo "Fin : $(date -u +%Y-%m-%dT%H:%M:%SZ)"

if ((echecs > 0)); then
  echo "MESURE INCOMPLÈTE : $echecs commande(s) sans code 201." >&2
  exit 1
fi
