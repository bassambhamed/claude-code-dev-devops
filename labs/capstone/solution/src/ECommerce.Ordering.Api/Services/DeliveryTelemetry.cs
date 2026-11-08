using System.Diagnostics.Metrics;

namespace ECommerce.Ordering.Api.Services;

public static class DeliveryTelemetry
{
    // Exported alongside the lab 10 instruments through the existing meter registration.
    private static readonly Meter Meter = new("ECommerce.Ordering");
    public static readonly Counter<long> Created = Meter.CreateCounter<long>("ecommerce.orders.delivery", "{order}");
}
