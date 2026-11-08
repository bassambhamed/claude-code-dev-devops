using ECommerce.Ordering.Api.Data;
using ECommerce.Ordering.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace ECommerce.Ordering.Api.Endpoints;

public static class OrderingEndpoints
{
    public static RouteGroupBuilder MapOrderingEndpoints(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/orders").WithTags("Ordering");
        group.MapGet("/", GetOrdersAsync).WithName("GetOrders");
        group.MapGet("/{id:int}", async (int id, OrderingDbContext db) =>
            await db.Orders.AsNoTracking().Include(o => o.Items).FirstOrDefaultAsync(o => o.Id == id) is { } order
                ? Results.Ok(order) : Results.NotFound()).WithName("GetOrderById");
        group.MapPost("/", (CreateOrderRequest request, CreateOrderService service, CancellationToken ct) =>
            service.CreateAsync(request, ct)).WithName("CreateOrder");
        return group;
    }

    private static async Task<IResult> GetOrdersAsync(OrderingDbContext db, DateOnly? deliveryDate, CancellationToken ct)
    {
        var query = db.Orders.AsNoTracking().Include(o => o.Items).AsQueryable();
        if (deliveryDate is { } date)
        {
            query = query.Where(o => o.RequestedDeliveryDate == date);
        }
        return Results.Ok(await query.OrderByDescending(o => o.Id).ToListAsync(ct));
    }
}

public record CreateOrderRequest(string Customer, List<OrderLine> Items, DateOnly? RequestedDeliveryDate = null);
public record OrderLine(int ProductId, int Quantity);
