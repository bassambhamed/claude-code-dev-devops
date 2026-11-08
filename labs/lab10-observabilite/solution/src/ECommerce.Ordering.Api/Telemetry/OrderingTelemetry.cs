using System.Diagnostics;
using System.Diagnostics.Metrics;

namespace ECommerce.Ordering.Api.Telemetry;

/// <summary>Low-cardinality business telemetry. No customer name or order ID is exported.</summary>
public static class OrderingTelemetry
{
    public const string MeterName = "ECommerce.Ordering";
    public static readonly ActivitySource Activities = new("ECommerce.Ordering.Api");
    private static readonly Meter Meter = new(MeterName);
    private static readonly Counter<long> Created = Meter.CreateCounter<long>("ecommerce.orders.created");
    private static readonly Counter<double> Amount = Meter.CreateCounter<double>("ecommerce.orders.amount");
    private static readonly Histogram<double> Duration = Meter.CreateHistogram<double>("ecommerce.orders.duration", "s");

    public static void RecordCreated(decimal total, double elapsedSeconds)
    {
        Created.Add(1);
        Amount.Add((double)total, new KeyValuePair<string, object?>("currency", "EUR"));
        Duration.Record(elapsedSeconds);
    }
}
