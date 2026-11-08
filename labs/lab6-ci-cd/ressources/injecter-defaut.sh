#!/usr/bin/env bash
# injecter-defaut.sh <copie> [--invisible] : rejoue la PR d'un collègue pressé.
#
# Sans option : crée la branche perf/total-commande à partir de la branche courante et y
# commite une « simplification » de Order.Total qui oublie la quantité. Les tests
# d'intégration du lab 2 doivent la bloquer.
#
# --invisible : crée la branche perf/catalogue-direct, où Ordering appelle Catalog à une
# adresse écrite en dur. Les tests ne la voient pas (leur faux Catalog répond à toute
# adresse) : seule une relecture peut la signaler.
#
# Le script ne pousse rien. Relancé, il ne fait rien si la branche existe déjà.
set -euo pipefail

usage() { echo "Usage : injecter-defaut.sh <copie de l'application> [--invisible]" >&2; exit 2; }

copie="${1:-}"
[[ -n "$copie" ]] || usage
mode="${2:-}"
[[ -z "$mode" || "$mode" == "--invisible" ]] || usage

[[ -f "$copie/ECommerce.slnx" ]] || { echo "Introuvable : $copie/ECommerce.slnx" >&2; exit 2; }
git -C "$copie" rev-parse --git-dir >/dev/null 2>&1 || { echo "$copie n'est pas un dépôt Git." >&2; exit 2; }

if [[ "$mode" == "--invisible" ]]; then
  branche="perf/catalogue-direct"
  fichier="src/ECommerce.Ordering.Api/Program.cs"
  avant='client.BaseAddress = new Uri("https+http://catalog"));'
  # L'idée du collègue : appeler Catalog sans passer par la résolution de nom.
  remplacement='s{client\.BaseAddress = new Uri\("https\+http://catalog"\)\);}{client.BaseAddress = new Uri("http://localhost:5147")); // direct call: no name resolution per order line}'
  apres='client.BaseAddress = new Uri("http://localhost:5147"));'
  message="perf: call Catalog directly from Ordering"
else
  branche="perf/total-commande"
  fichier="src/ECommerce.Ordering.Api/Models/Order.cs"
  avant='Items.Sum(i => i.UnitPrice * i.Quantity)'
  remplacement='s{public decimal Total => Items\.Sum\(i => i\.UnitPrice \* i\.Quantity\);}{public decimal Total => Items.Sum(i => i.UnitPrice);}'
  apres='Items.Sum(i => i.UnitPrice);'
  message="refactor: simplify Order.Total"
fi

if git -C "$copie" rev-parse --verify -q "refs/heads/$branche" >/dev/null; then
  echo "La branche $branche existe déjà : rien à faire."
  echo "Pour recommencer : git -C $copie branch -D $branche"
  exit 0
fi
git -C "$copie" diff --quiet HEAD -- || { echo "Commitez d'abord vos modifications en cours." >&2; exit 2; }
grep -q -F "$avant" "$copie/$fichier" || { echo "$fichier n'a pas la forme attendue : injection impossible." >&2; exit 1; }

depart="$(git -C "$copie" branch --show-current)"
git -C "$copie" switch -q -c "$branche"
perl -0pi -e "$remplacement" "$copie/$fichier"
if ! grep -q -F "$apres" "$copie/$fichier"; then
  git -C "$copie" restore "$fichier"
  git -C "$copie" switch -q "$depart"
  git -C "$copie" branch -q -D "$branche"
  echo "Le remplacement a échoué : $fichier n'a pas changé." >&2
  exit 1
fi

git -C "$copie" add "$fichier"
git -C "$copie" -c user.name="Collègue pressé" -c user.email="collegue@ecommerce.example" \
  commit -q -m "$message"

echo "Branche $branche créée à partir de ${depart:-HEAD}."
echo "Commit du collègue : $(git -C "$copie" log -1 --format='%h %s (%an)')"
git -C "$copie" diff --stat HEAD~1 HEAD
