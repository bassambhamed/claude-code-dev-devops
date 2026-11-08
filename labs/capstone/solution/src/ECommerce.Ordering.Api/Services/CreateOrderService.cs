using System.Diagnostics;
using ECommerce.Ordering.Api.Data;
using ECommerce.Ordering.Api.Endpoints;
using ECommerce.Ordering.Api.Models;
using ECommerce.Ordering.Api.Telemetry;

namespace ECommerce.Ordering.Api.Services;

public sealed class CreateOrderService(OrderingDbContext db, CatalogServiceClient catalog, TimeProvider clock)
{
    public async Task<IResult> CreateAsync(CreateOrderRequest request, CancellationToken ct)
    {
        var now = clock.GetUtcNow();
        if (OrderValidation.Validate(request, DateOnly.FromDateTime(now.UtcDateTime)) is { } error)
        {
            return Results.BadRequest(error);
        }
        using var activity = OrderingTelemetry.Activities.StartActivity("CreateOrder");
        activity?.SetTag("ecommerce.order.lines", request.Items.Count);
        var started = Stopwatch.GetTimestamp();
        var order = new Order
        {
            Customer = request.Customer,
            CreatedAt = now,
            RequestedDeliveryDate = request.RequestedDeliveryDate
        };
        foreach (var line in request.Items)
        {
            var product = await catalog.GetProductAsync(line.ProductId, ct);
            if (product is null)
            {
                return Results.BadRequest($"Product {line.ProductId} does not exist.");
            }
            order.Items.Add(new OrderItem
            {
                ProductId = product.Id,
                ProductName = product.Name,
                UnitPrice = product.Price,
                Quantity = line.Quantity
            });
        }
        order.Status = OrderStatus.Confirmed;
        db.Orders.Add(order);
        await db.SaveChangesAsync(ct);
        Activity.Current?.SetTag("ecommerce.order.delivery_requested", order.RequestedDeliveryDate.HasValue);
        RecordCreated(order.Total, Stopwatch.GetElapsedTime(started), order.RequestedDeliveryDate.HasValue);
        return Results.CreatedAtRoute("GetOrderById", new { id = order.Id }, order);
    }

    private static void RecordCreated(decimal total, TimeSpan elapsed, bool hasDeliveryDate)
    {
        OrderingTelemetry.RecordCreated(total, elapsed.TotalSeconds);
        DeliveryTelemetry.Created.Add(1, new KeyValuePair<string, object?>("delivery_requested", hasDeliveryDate));
    }
}
