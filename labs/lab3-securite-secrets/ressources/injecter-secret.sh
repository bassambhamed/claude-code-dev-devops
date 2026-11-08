#!/usr/bin/env bash
# injecter-secret.sh <copie> : rejoue l'erreur d'un collègue pressé. Une clé de paiement
# « de production » est ajoutée à la configuration d'Ordering, puis commitée.
#
# La clé est FACTICE : elle ne donne accès à rien. Traitez-la pourtant comme une vraie.
set -euo pipefail

copie="${1:?Usage : injecter-secret.sh <copie de l application>}"
fichier="$copie/src/ECommerce.Ordering.Api/appsettings.json"

[[ -f "$fichier" ]] || { echo "Introuvable : $fichier" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq est requis." >&2; exit 2; }
if grep -q '"Payment"' "$fichier"; then
  echo "La configuration de paiement est déjà présente : rien à faire."
  exit 0
fi
git -C "$copie" diff --quiet HEAD -- || { echo "Commitez d'abord vos modifications en cours." >&2; exit 2; }

# Ajoute un bloc "Payment" après "AllowedHosts".
perl -0pi -e 's/("AllowedHosts": "\*")(\r?\n)\}/$1,$2  "Payment": {$2    "Provider": "EasyCheckout",$2    "Endpoint": "https:\/\/api.easycheckout.example\/v2",$2    "ApiKey": "ecpk_live_7f3a9c1e5b2d4f6a8c0e1b3d5f7a9c2e"$2  }$2}/' "$fichier"
grep -q '"Payment"' "$fichier" || { echo "Le fichier n'a pas la forme attendue : injection impossible." >&2; exit 1; }
jq empty "$fichier"

git -C "$copie" add "$fichier"
git -C "$copie" -c user.name="Collègue pressé" -c user.email="collegue@ecommerce.example" \
  commit -q -m "chore: configure payment provider for go-live"
echo "Commit du collègue : $(git -C "$copie" log -1 --format='%h %s (%an)')"
