#!/usr/bin/env bash
# rejouer-incident.sh <copie> : rejoue l'historique de l'incident « des totaux à 0 € ».
#
# - Étiquette l'état actuel de la copie « incident-bon » : la dernière version saine.
# - Crée la branche « incident » et y ajoute 20 commits de quatre collègues, datés des
#   trois derniers jours. L'un d'eux rompt le contrat Catalog → Ordering, un autre écrit
#   la clé de paiement dans les logs. Chaque commit compile.
# - Écrit l'extrait de log de production transmis par un collègue dans
#   incident/journal-ordering.log, exclu de Git (.git/info/exclude).
#
# Lancez-le depuis le dossier de formation, sur votre copie commitée (fin du lab 10) :
#   bash labs/lab11-incident/ressources/rejouer-incident.sh ~/lab-ecommerce
# Ne touche qu'au code de Catalog, d'Ordering et de ServiceDefaults, aux tests et à la
# documentation. Pour recommencer : git switch main && git branch -D incident && git tag -d incident-bon
#
# Codes de retour : 0 historique rejoué, 1 refus ou échec (copie remise en l'état), 2 usage.
set -Eeuo pipefail

copie="${1:-}"
if [[ -z "$copie" ]]; then
  echo "Usage : $0 <copie de l'application>" >&2
  exit 2
fi
copie="$(cd "$copie" 2>/dev/null && pwd -P)" || { echo "Dossier introuvable : $1" >&2; exit 2; }
cd "$copie"

[[ -f ECommerce.slnx ]] || { echo "ECommerce.slnx introuvable dans $copie." >&2; exit 1; }
git rev-parse --verify -q HEAD >/dev/null || { echo "$copie n'est pas un dépôt Git avec au moins un commit." >&2; exit 1; }
if git rev-parse -q --verify refs/tags/incident-bon >/dev/null; then
  echo "L'incident a déjà été rejoué (l'étiquette incident-bon existe)." >&2
  echo "Pour recommencer : git switch main && git branch -D incident && git tag -d incident-bon" >&2
  exit 1
fi
if git rev-parse -q --verify refs/heads/incident >/dev/null; then
  echo "Une branche « incident » existe déjà : renommez-la ou supprimez-la." >&2
  exit 1
fi
if ! git diff --quiet HEAD || [[ -n "$(git status --porcelain --untracked-files=all -- src tests docs)" ]]; then
  echo "La copie contient des modifications non commitées (ou des fichiers non suivis dans src, tests, docs) :" >&2
  echo "commitez-les ou mettez-les de côté (git stash -u)." >&2
  exit 1
fi

CAT=src/ECommerce.Catalog.Api
ORD=src/ECommerce.Ordering.Api
DEF=src/ECommerce.ServiceDefaults
TCAT=tests/ECommerce.Catalog.Api.Tests
TORD=tests/ECommerce.Ordering.Api.Tests
for f in "$CAT/Models/Product.cs" "$CAT/README.md" "$ORD/Program.cs" "$ORD/README.md" "$DEF/README.md"; do
  [[ -f "$f" ]] || { echo "Fichier attendu introuvable : $f" >&2; exit 1; }
done
grep -q '^    public decimal Price { get; set; }' "$CAT/Models/Product.cs" \
  || { echo "$CAT/Models/Product.cs n'a pas la propriété Price attendue." >&2; exit 1; }
grep -q '^var app = builder.Build();' "$ORD/Program.cs" \
  || { echo "$ORD/Program.cs ne contient pas « var app = builder.Build(); »." >&2; exit 1; }

depart="$(git rev-parse HEAD)"
branche_depart="$(git branch --show-current)"
annuler() {
  echo "Échec : la copie est remise dans son état de départ." >&2
  git reset -q --hard "$depart"
  git clean -q -fd -- src tests docs 2>/dev/null || true
  git switch -q "${branche_depart:-main}" 2>/dev/null || git checkout -q "$depart"
  git branch -q -D incident 2>/dev/null || true
  git tag -d incident-bon >/dev/null 2>&1 || true
}
trap 'annuler' ERR

maintenant="$(date +%s)"
fuseau="$(date +%z)"
horodater() { # horodater <epoch> : date ISO 8601 UTC, sous macOS comme sous Linux
  date -u -r "$1" +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%S
}

# commiter <auteur> <heures avant maintenant> <message> : committe tout ce qui a changé.
commiter() {
  local quand=$((maintenant - $2 * 3600))
  local email
  email="$(printf '%s' "${1%% *}" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C tr -cd 'a-z')@ecommerce.example"
  for chemin in src tests docs; do
    if [[ -d "$chemin" ]]; then git add -A -- "$chemin"; fi
  done
  GIT_AUTHOR_DATE="$quand $fuseau" GIT_COMMITTER_DATE="$quand $fuseau" \
    git -c user.name="$1" -c user.email="$email" commit -q -m "$3"
}

# remplacer <fichier> <expression perl> : la substitution doit s'appliquer une fois au moins.
remplacer() {
  perl -0 -i -pe 'BEGIN { $n = 0 } $n += ('"$2"'); END { exit($n > 0 ? 0 : 3) }' "$1" \
    || { echo "Modification impossible dans $1." >&2; return 1; }
}

git tag incident-bon
git switch -q -c incident

# --- 1 -----------------------------------------------------------------------------------
cat >>"$CAT/README.md" <<'MD'

## Contract

`GET /api/products` and `GET /api/products/{id}` return the `Product` entity in camelCase:
`id`, `name`, `description`, `price`, `availableStock`, `category`. Ordering (`CatalogProduct`)
and the Web UI (`ProductDto`) keep their own copies of this contract.
MD
commiter "Inès Rousseau" 74 "docs(catalog): describe the product contract"

# --- 2 -----------------------------------------------------------------------------------
mkdir -p "$CAT/Pricing"
cat >"$CAT/Pricing/Vat.cs" <<'CS'
namespace ECommerce.Catalog.Api.Pricing;

/// <summary>
/// VAT helpers for the prices sent to partners. Catalog prices exclude VAT.
/// </summary>
public static class Vat
{
    public const decimal StandardRate = 0.20m;

    public static decimal IncludeVat(decimal priceExcludingVat, decimal rate = StandardRate) =>
        Math.Round(priceExcludingVat * (1 + rate), 2, MidpointRounding.ToEven);
}
CS
commiter "Camille Martin" 71 "feat(catalog): VAT helper for partner prices"

# --- 3 -----------------------------------------------------------------------------------
if [[ -d "$TCAT" ]]; then
  cat >"$TCAT/VatTests.cs" <<'CS'
using ECommerce.Catalog.Api.Pricing;

namespace ECommerce.Catalog.Api.Tests;

public class VatTests
{
    [Fact]
    public void IncludeVat_AddsTheStandardRate() =>
        Assert.Equal(143.99m, Vat.IncludeVat(119.99m));

    [Fact]
    public void IncludeVat_UsesTheGivenRate() =>
        Assert.Equal(52.22m, Vat.IncludeVat(49.50m, 0.055m));
}
CS
else
  echo "- VAT helper: catalog prices exclude VAT." >>"$CAT/README.md"
fi
commiter "Camille Martin" 70 "test(catalog): cover the VAT helper"

# --- 4 -----------------------------------------------------------------------------------
mkdir -p "$ORD/Payment"
cat >"$ORD/Payment/PaymentOptions.cs" <<'CS'
namespace ECommerce.Ordering.Api.Payment;

/// <summary>
/// Settings of the payment provider ("Payment" section). The API key is a secret: it comes
/// from user-secrets in Development and from the environment (Payment__ApiKey) elsewhere.
/// </summary>
public sealed class PaymentOptions
{
    public const string SectionName = "Payment";

    public string Provider { get; set; } = string.Empty;
    public string Endpoint { get; set; } = string.Empty;
    public string ApiKey { get; set; } = string.Empty;
}
CS
remplacer "$ORD/Program.cs" 's/^(var app = builder\.Build\(\);\n)/\/\/ Payment provider settings ("Payment" section; the API key comes from secrets).\nbuilder.Services.Configure<ECommerce.Ordering.Api.Payment.PaymentOptions>(\n    builder.Configuration.GetSection(ECommerce.Ordering.Api.Payment.PaymentOptions.SectionName));\n\n$1/m'
commiter "Yanis Belkacem" 68 "chore(ordering): bind the payment settings"

# --- 5 -----------------------------------------------------------------------------------
cat >>"$ORD/README.md" <<'MD'

## Payment settings

`Payment:Provider` and `Payment:Endpoint` live in `appsettings.json`. `Payment:ApiKey` is a
secret: `dotnet user-secrets` in Development, the `Payment__ApiKey` environment variable
elsewhere. They are bound to `PaymentOptions` (`Payment/PaymentOptions.cs`).
MD
commiter "Yanis Belkacem" 67 "docs(ordering): document the payment settings"

# --- 6 -----------------------------------------------------------------------------------
remplacer "$ORD/Program.cs" 's/^(var app = builder\.Build\(\);\n)/$1\n\/\/ Go-live check: show which payment provider this instance talks to.\nvar payment = app.Services\n    .GetRequiredService<Microsoft.Extensions.Options.IOptions<ECommerce.Ordering.Api.Payment.PaymentOptions>>().Value;\napp.Logger.LogInformation("Payment provider {Provider} at {Endpoint}, key {ApiKey}",\n    payment.Provider, payment.Endpoint, payment.ApiKey);\n/m'
commiter "Yanis Belkacem" 66 "chore(ordering): log the payment provider at startup"

# --- 7 -----------------------------------------------------------------------------------
remplacer "$CAT/Pricing/Vat.cs" 's/(    public const decimal StandardRate = 0\.20m;\n)/$1    public const decimal ReducedRate = 0.055m;\n/'
commiter "Camille Martin" 52 "feat(catalog): reduced VAT rate"

# --- 8 -----------------------------------------------------------------------------------
mkdir -p docs
cat >docs/release-notes.md <<'MD'
# Release notes

## Partner API (in progress)

- Catalog: VAT helpers for the prices sent to partners (standard and reduced rates).
- Ordering: payment provider settings bound to `PaymentOptions`.
MD
commiter "Hugo Lefèvre" 51 "docs: start the release notes of the partner API"

# --- 9 -----------------------------------------------------------------------------------
cat >"$CAT/Pricing/PriceFormatter.cs" <<'CS'
using System.Globalization;

namespace ECommerce.Catalog.Api.Pricing;

/// <summary>
/// Formats prices for the partner exports, whatever the server culture: "119.99 EUR".
/// </summary>
public static class PriceFormatter
{
    public static string Format(decimal amount, string currency = "EUR") =>
        string.Create(CultureInfo.InvariantCulture, $"{amount:0.00} {currency}");
}
CS
commiter "Camille Martin" 50 "feat(catalog): format partner prices"

# --- 10 ----------------------------------------------------------------------------------
if [[ -d "$TCAT" ]]; then
  cat >"$TCAT/PriceFormatterTests.cs" <<'CS'
using ECommerce.Catalog.Api.Pricing;

namespace ECommerce.Catalog.Api.Tests;

public class PriceFormatterTests
{
    [Fact]
    public void Format_UsesTwoDecimalsAndEuroByDefault() =>
        Assert.Equal("119.99 EUR", PriceFormatter.Format(119.99m));

    [Fact]
    public void Format_UsesTheGivenCurrency() =>
        Assert.Equal("5.00 USD", PriceFormatter.Format(5m, "USD"));
}
CS
else
  echo "- Price formatter: \"119.99 EUR\", invariant culture." >>"$CAT/README.md"
fi
commiter "Camille Martin" 49 "test(catalog): cover the price formatter"

# --- 11 ----------------------------------------------------------------------------------
cat >"$ORD/Models/OrderReference.cs" <<'CS'
namespace ECommerce.Ordering.Api.Models;

/// <summary>
/// Human-readable order references for the support team: ORD-000042.
/// </summary>
public static class OrderReference
{
    public static string For(int orderId) => $"ORD-{orderId:D6}";
}
CS
commiter "Yanis Belkacem" 48 "feat(ordering): human-readable order references"

# --- 12 ----------------------------------------------------------------------------------
remplacer "$CAT/Models/Product.cs" 's/^(namespace ECommerce\.Catalog\.Api\.Models;)/using System.Text.Json.Serialization;\n\n$1/m'
remplacer "$CAT/Models/Product.cs" 's/^(    public decimal Price \{ get; set; \}\n)/    \/\/ Partner API naming: the price is published as "unitPrice".\n    [JsonPropertyName("unitPrice")]\n$1/m'
remplacer "$CAT/README.md" 's/`price`, `availableStock`/`unitPrice`, `availableStock`/'
if [[ -d "$TCAT" ]]; then
  # Les tests de Catalog lisent désormais unitPrice : ils restent verts.
  find "$TCAT" -name '*.cs' -not -path '*/obj/*' -not -path '*/bin/*' -print0 \
    | xargs -0 perl -i -pe 's/\bdecimal Price\b/decimal UnitPrice/g; s/\.Price\b/.UnitPrice/g; s/"price"/"unitPrice"/g'
fi
commiter "Camille Martin" 47 "feat(catalog): align the product JSON with the partner API naming"

# --- 13 ----------------------------------------------------------------------------------
if [[ -d "$TORD" ]]; then
  cat >"$TORD/OrderReferenceTests.cs" <<'CS'
using ECommerce.Ordering.Api.Models;

namespace ECommerce.Ordering.Api.Tests;

public class OrderReferenceTests
{
    [Fact]
    public void For_PadsTheIdToSixDigits() =>
        Assert.Equal("ORD-000042", OrderReference.For(42));
}
CS
else
  echo "- Order references: ORD-000042." >>"$ORD/README.md"
fi
commiter "Yanis Belkacem" 46 "test(ordering): cover the order references"

# --- 14 ----------------------------------------------------------------------------------
cat >"$DEF/TelemetryTags.cs" <<'CS'
namespace ECommerce.ServiceDefaults;

/// <summary>
/// Attribute names shared by the traces and metrics of every service.
/// </summary>
public static class TelemetryTags
{
    public const string ProductId = "ecommerce.product.id";
    public const string OrderId = "ecommerce.order.id";
}
CS
commiter "Hugo Lefèvre" 30 "chore(telemetry): shared attribute names"

# --- 15 ----------------------------------------------------------------------------------
cat >>"$DEF/README.md" <<'MD'

## Shared attribute names

`TelemetryTags.cs` holds the attribute names that every service uses on its spans and
metrics (`ecommerce.product.id`, `ecommerce.order.id`), so that dashboards can join them.
MD
commiter "Hugo Lefèvre" 29 "docs(servicedefaults): document the shared attribute names"

# --- 16 ----------------------------------------------------------------------------------
cat >>docs/release-notes.md <<'MD'
- Catalog: the product JSON follows the partner API naming (`unitPrice`).
MD
commiter "Inès Rousseau" 28 "docs: partner API naming in the release notes"

# --- 17 ----------------------------------------------------------------------------------
remplacer "$CAT/Pricing/Vat.cs" 's/MidpointRounding\.ToEven/MidpointRounding.AwayFromZero/'
commiter "Camille Martin" 27 "fix(catalog): round partner prices half away from zero"

# --- 18 ----------------------------------------------------------------------------------
if [[ -f "$TCAT/VatTests.cs" ]]; then
  remplacer "$TCAT/VatTests.cs" 's/(        Assert\.Equal\(52\.22m, Vat\.IncludeVat\(49\.50m, 0\.055m\)\);\n)/$1\n    [Fact]\n    public void IncludeVat_RoundsHalfAwayFromZero() =>\n        Assert.Equal(0.13m, Vat.IncludeVat(0.125m, 0m));\n/'
else
  echo "- Partner prices are rounded half away from zero." >>"$CAT/README.md"
fi
commiter "Inès Rousseau" 26 "test(catalog): rounding of partner prices"

# --- 19 ----------------------------------------------------------------------------------
remplacer "$ORD/Payment/PaymentOptions.cs" 's/(    public string ApiKey \{ get; set; \} = string\.Empty;)/    \/\/\/ <summary>Key issued by the provider for this environment.<\/summary>\n$1/'
commiter "Yanis Belkacem" 25 "chore(ordering): document the payment options"

# --- 20 ----------------------------------------------------------------------------------
cat >>docs/release-notes.md <<'MD'

## Delivery of Friday

Deployed to production with the 20 commits above. No database migration.
MD
commiter "Hugo Lefèvre" 24 "docs: release notes for the Friday delivery"

trap - ERR

# --- Contrôle : chaque commit compile ; on vérifie au moins le dernier ---------------------
if ! DOTNET_CLI_UI_LANGUAGE=en dotnet build ECommerce.slnx -nologo -v q >/dev/null 2>&1; then
  annuler
  echo "La solution ne compile pas après le rejeu : vérifiez dotnet build ECommerce.slnx sur la fin du lab 10." >&2
  exit 1
fi

# --- L'extrait de log transmis par un collègue (hors Git) ---------------------------------
mkdir -p incident
grep -qx 'incident/' .git/info/exclude 2>/dev/null || echo 'incident/' >>.git/info/exclude
prefixe="ecpk_live_"
cle="${prefixe}9b1f4c7e2a6d8053b9e1f7a4c2d6e8b0"
deploiement=$((maintenant - 22 * 3600))
journal=incident/journal-ordering.log
{
  t=$deploiement
  echo "$(horodater $t).118Z info ECommerce.Ordering.Api[0] Payment provider EasyCheckout at https://api.easycheckout.example/v2, key $cle"
  echo "$(horodater $t).164Z info Microsoft.Hosting.Lifetime[14] Now listening on: http://[::]:8080"
  echo "$(horodater $t).165Z info Microsoft.Hosting.Lifetime[0] Application started. Press Ctrl+C to shut down."
  echo "$(horodater $t).165Z info Microsoft.Hosting.Lifetime[0] Hosting environment: Production"
  for h in 15 14 3 2 1; do
    t=$((maintenant - h * 3600 + 17 * h))
    echo "$(horodater $t).402Z info Microsoft.EntityFrameworkCore.Database.Command[20101] Executed DbCommand (3ms) [Parameters=[@p0='?', @p1='?', @p2='?'], CommandType='Text', CommandTimeout='30'] INSERT INTO \"Orders\" (\"CreatedAt\", \"Customer\", \"Status\") VALUES (@p0, @p1, @p2) RETURNING \"Id\";"
    echo "$(horodater $t).409Z info Microsoft.EntityFrameworkCore.Database.Command[20101] Executed DbCommand (2ms) [Parameters=[@p3='?', @p4='?', @p5='?', @p6='?', @p7='?'], CommandType='Text', CommandTimeout='30'] INSERT INTO \"OrderItems\" (\"OrderId\", \"ProductId\", \"ProductName\", \"Quantity\", \"UnitPrice\") VALUES (@p3, @p4, @p5, @p6, @p7) RETURNING \"Id\";"
  done
} >"$journal"

echo "Incident rejoué sur la branche « incident » : $(git rev-list --count incident-bon..HEAD) commits depuis l'étiquette incident-bon."
git log --oneline -3
echo "Extrait de log de production transmis par un collègue : $copie/$journal (exclu de Git)."
