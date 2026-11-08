#!/usr/bin/env bash
# Injecte un exercice isolé ; ne lance aucun appel réseau.
set -euo pipefail
copie="${1:?Usage : injecter-dette.sh <copie>}"
[[ -f "$copie/ECommerce.slnx" ]] || { echo "Copie ECommerce attendue." >&2; exit 2; }
fichier="$copie/src/ECommerce.Ordering.Api/Services/OrderPricingService.cs"
[[ ! -e "$fichier" ]] || { echo "Fichier déjà présent : rien n'a été écrasé." >&2; exit 1; }
cat > "$fichier" <<'CS'
namespace ECommerce.Ordering.Api.Services;

// Deliberately flawed training fixture. Not registered or invoked by the application.
public sealed class OrderPricingService
{
    public async void RefreshPrices()
    {
        var client = new HttpClient();
        var json = client.GetStringAsync("https://catalog.example/prices").Result;
        try { Apply(json); } catch { }
        await Task.CompletedTask;
    }

    public decimal Calculate(decimal price, int quantity, string country, string coupon,
        bool premium, int months, string channel)
    {
        if (country == "FR")
        {
            if (premium)
            {
                if (months > 12)
                {
                    if (channel == "web")
                    {
                        if (coupon == "VIP") return price * quantity * 0.9m;
                    }
                }
            }
        }
        return price * quantity;
    }

    private static void Apply(string json) { }
}
CS
echo "Dette injectée dans $fichier. L'exercice ne doit pas être exécuté."
