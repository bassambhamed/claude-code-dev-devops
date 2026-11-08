#!/usr/bin/env bash
# livrer-version-lente.sh <copie> : rejoue « la dernière livraison » de l'équipe Catalog.
#
# Le commit ajouté fait interroger le système d'entrepôt (simulé) à chaque lecture d'un
# produit, pour afficher un stock « en temps réel ». Il compile, les tests passent… et
# chaque ligne de commande coûte désormais un appel lent.
#
# Lancez-le depuis le dossier de formation, sur votre copie commitée :
#   bash labs/lab10-observabilite/ressources/livrer-version-lente.sh ~/lab-ecommerce
# Relancé, il ne fait rien. Pour l'annuler : git -C <copie> revert <commit>.
#
# Codes de retour : 0 livré (ou déjà livré), 1 refus ou échec, 2 usage.
set -euo pipefail

copie="${1:-}"
if [[ -z "$copie" ]]; then
  echo "Usage : $0 <copie de l'application>" >&2
  exit 2
fi
copie="$(cd "$copie" 2>/dev/null && pwd -P)" || { echo "Dossier introuvable : $1" >&2; exit 2; }

[[ -f "$copie/ECommerce.slnx" ]] || { echo "ECommerce.slnx introuvable dans $copie." >&2; exit 1; }
git -C "$copie" rev-parse --verify -q HEAD >/dev/null || { echo "$copie n'est pas un dépôt Git avec au moins un commit." >&2; exit 1; }

catalog="$copie/src/ECommerce.Catalog.Api"
client="$catalog/Services/WarehouseClient.cs"
endpoints="$catalog/Endpoints/CatalogEndpoints.cs"
programme="$catalog/Program.cs"

if [[ -f "$client" ]]; then
  echo "La livraison est déjà en place ($client existe) : rien à faire."
  exit 0
fi

if ! git -C "$copie" diff --quiet HEAD; then
  echo "La copie contient des modifications non commitées : commitez-les ou mettez-les de côté (git stash)." >&2
  exit 1
fi

for f in "$endpoints" "$programme"; do
  [[ -f "$f" ]] || { echo "Fichier attendu introuvable : $f" >&2; exit 1; }
done

annuler() {
  git -C "$copie" checkout -q -- "$endpoints" "$programme" 2>/dev/null || true
  rm -f "$client"
  rmdir "$catalog/Services" 2>/dev/null || true
}

# 1. Le client du système d'entrepôt.
mkdir -p "$catalog/Services"
cat >"$client" <<'CS'
namespace ECommerce.Catalog.Api.Services;

/// <summary>
/// Client for the warehouse system, which knows the live stock of each product.
/// The warehouse is simulated here: each call waits Warehouse:LatencyMs milliseconds
/// (800 by default, the response time measured on the real system).
/// </summary>
public class WarehouseClient(IConfiguration configuration)
{
    public async Task<int> GetLiveStockAsync(int productId, int storedStock, CancellationToken cancellationToken = default)
    {
        var latency = configuration.GetValue("Warehouse:LatencyMs", 800);
        await Task.Delay(latency, cancellationToken);

        // The simulated warehouse agrees with the stored stock.
        return storedStock;
    }
}
CS

# 2. La lecture d'un produit interroge l'entrepôt.
ancre='group\.MapGet\("/\{id:int\}", async \(int id, CatalogDbContext db\) =>\s*await db\.Products\.FindAsync\(id\) is \{ \} product\s*\? Results\.Ok\(product\)\s*: Results\.NotFound\(\)\)\s*\.WithName\("GetProductById"\);'
remplacement='group.MapGet("/{id:int}", async (int id, CatalogDbContext db, WarehouseClient warehouse, CancellationToken ct) =>
        {
            if (await db.Products.FindAsync([id], ct) is not { } product)
            {
                return Results.NotFound();
            }

            // The stored stock can be hours old: ask the warehouse for the live value.
            product.AvailableStock = await warehouse.GetLiveStockAsync(product.Id, product.AvailableStock, ct);
            return Results.Ok(product);
        })
        .WithName("GetProductById");'
if ! ANCRE="$ancre" REMPL="$remplacement" perl -0 -i -pe '
    BEGIN { $n = 0 }
    $n += s/$ENV{ANCRE}/$ENV{REMPL}/g;
    END { exit($n == 1 ? 0 : 3) }' "$endpoints"; then
  annuler
  echo "Le point de terminaison GET /api/products/{id} n'a pas la forme attendue (fin du lab 4) dans $endpoints." >&2
  exit 1
fi
perl -0 -i -pe 's/^(using ECommerce\.Catalog\.Api\.Models;\n)/$1using ECommerce.Catalog.Api.Services;\n/m' "$endpoints"

# 3. Enregistrement du client.
if ! perl -0 -i -pe '
    BEGIN { $n = 0 }
    $n += s/^(builder\.AddNpgsqlDbContext<CatalogDbContext>\("catalogdb"\);\n)/$1\n\/\/ Live stock from the warehouse system.\nbuilder.Services.AddSingleton<WarehouseClient>();\n/m;
    END { exit($n == 1 ? 0 : 3) }' "$programme"; then
  annuler
  echo "Ligne AddNpgsqlDbContext<CatalogDbContext>(\"catalogdb\") introuvable dans $programme." >&2
  exit 1
fi
perl -0 -i -pe 's/^(using ECommerce\.Catalog\.Api\.Endpoints;\n)/$1using ECommerce.Catalog.Api.Services;\n/m' "$programme"

# 4. La livraison doit compiler, comme une vraie.
if ! (cd "$copie" && DOTNET_CLI_UI_LANGUAGE=en dotnet build src/ECommerce.Catalog.Api -nologo -v q >/dev/null 2>&1); then
  annuler
  echo "La version modifiée de Catalog ne compile pas : livraison annulée." >&2
  echo "Vérifiez : dotnet build src/ECommerce.Catalog.Api" >&2
  exit 1
fi

git -C "$copie" add -- "$client" "$endpoints" "$programme"
git -C "$copie" -c user.name="Équipe Catalog" -c user.email="catalog@ecommerce.example" \
  commit -q -m "feat(catalog): live stock from the warehouse on product reads" \
  -m "The stored stock can be hours old. GET /api/products/{id} now asks the warehouse system for the live value."

echo "Livraison rejouée : $(git -C "$copie" log -1 --format='%h %s')"
echo "Redémarrez l'AppHost pour la « déployer », puis mesurez le temps de création d'une commande."
