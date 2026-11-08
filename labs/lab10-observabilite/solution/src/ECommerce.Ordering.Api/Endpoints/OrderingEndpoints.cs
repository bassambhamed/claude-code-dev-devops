using ECommerce.Ordering.Api.Data;
using ECommerce.Ordering.Api.Models;
using ECommerce.Ordering.Api.Services;
using ECommerce.Ordering.Api.Telemetry;
using System.Diagnostics;
using Microsoft.EntityFrameworkCore;

namespace ECommerce.Ordering.Api.Endpoints;

public static class OrderingEndpoints
{
    private const int MaxCustomerLength = 200;

    public static RouteGroupBuilder MapOrderingEndpoints(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/orders").WithTags("Ordering");

        group.MapGet("/", async (OrderingDbContext db) =>
            await db.Orders.AsNoTracking().Include(o => o.Items).ToListAsync())
            .WithName("GetOrders");

        group.MapGet("/{id:int}", async (int id, OrderingDbContext db) =>
            await db.Orders.AsNoTracking().Include(o => o.Items).FirstOrDefaultAsync(o => o.Id == id) is { } order
                ? Results.Ok(order)
                : Results.NotFound())
            .WithName("GetOrderById");

        group.MapPost("/", async (
            CreateOrderRequest request,
            OrderingDbContext db,
            CatalogServiceClient catalog,
            CancellationToken ct) =>
        {
            var started = Stopwatch.GetTimestamp();
            using var activity = OrderingTelemetry.Activities.StartActivity("CreateOrder");

            // Errors stay plain strings: the Web UI shows them as they are.
            if (Validate(request) is { } error)
            {
                return Results.BadRequest(error);
            }

            var order = new Order
            {
                Customer = request.Customer,
                CreatedAt = DateTimeOffset.UtcNow,
                Status = OrderStatus.Pending
            };

            // Validate each product against the Catalog service (sync HTTP call).
            foreach (var item in request.Items)
            {
                var product = await catalog.GetProductAsync(item.ProductId, ct);
                if (product is null)
                {
                    return Results.BadRequest($"Product {item.ProductId} does not exist.");
                }

                order.Items.Add(new OrderItem
                {
                    ProductId = product.Id,
                    ProductName = product.Name,
                    UnitPrice = product.Price,
                    Quantity = item.Quantity
                });
            }

            order.Status = OrderStatus.Confirmed;
            db.Orders.Add(order);
            await db.SaveChangesAsync(ct);

            // Count only committed orders. Rejected requests do not increase the counter.
            OrderingTelemetry.RecordCreated(order.Total, Stopwatch.GetElapsedTime(started).TotalSeconds);
            activity?.SetTag("ecommerce.order.lines", order.Items.Count);

            return Results.CreatedAtRoute("GetOrderById", new { id = order.Id }, order);
        })
        .WithName("CreateOrder");

        return group;
    }

    // Returns the first validation error, or null when the request is valid.
    private static string? Validate(CreateOrderRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Customer))
        {
            return "Customer is required.";
        }

        if (request.Customer.Length > MaxCustomerLength)
        {
            return $"Customer must not exceed {MaxCustomerLength} characters.";
        }

        // System.Text.Json leaves Items null when the property is missing from the body.
        if (request.Items is null || request.Items.Count == 0)
        {
            return "An order must contain at least one item.";
        }

        if (request.Items.Any(item => item.Quantity < 1))
        {
            return "Quantity must be at least 1.";
        }

        return null;
    }
}

public record CreateOrderRequest(string Customer, List<OrderLine> Items);
public record OrderLine(int ProductId, int Quantity);
