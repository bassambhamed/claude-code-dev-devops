using System.Globalization;
using System.Net;
using System.Net.Http.Json;
using ECommerce.Ordering.Api.Endpoints;
using ECommerce.Ordering.Api.Services;

namespace ECommerce.Ordering.Api.Tests;

public sealed class DeliveryDateTests : IClassFixture<PostgresFixture>
{
    private static readonly DateOnly Today = new(2026, 11, 8);
    private static readonly TimeProvider Clock = new FixedClock();
    private readonly PostgresFixture _postgres;

    public DeliveryDateTests(PostgresFixture postgres) => _postgres = postgres;

    [Theory]
    [InlineData(null, true)]
    [InlineData(-1, false)]
    [InlineData(0, false)]
    [InlineData(1, true)]
    [InlineData(90, true)]
    [InlineData(91, false)]
    public void Validation_UsesTheUtcDateWindow(int? days, bool valid)
    {
        var request = new CreateOrderRequest("Ada", [new(1, 1)], days.HasValue ? Today.AddDays(days.Value) : null);
        Assert.Equal(valid, OrderValidation.Validate(request, Today) is null);
    }

    [Fact]
    public async Task Date_IsStoredReturnedAndFiltered_ExistingOrdersRemainValid()
    {
        var database = _postgres.NewDatabase();
        using var firstFactory = new OrderingApiFactory(database, Clock);
        using var first = firstFactory.CreateClient();
        var date = Today.AddDays(7);
        var legacy = await first.PostAsJsonAsync("/api/orders", new { customer = "Legacy", items = new[] { new { productId = 1, quantity = 1 } } });
        Assert.Equal(HttpStatusCode.Created, legacy.StatusCode);
        var response = await first.PostAsJsonAsync("/api/orders", new CreateOrderRequest("Ada", [new(1, 2)], date));
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var created = await response.Content.ReadFromJsonAsync<DeliveryOrder>();
        Assert.NotNull(created);
        Assert.Equal(date, created.RequestedDeliveryDate);
        Assert.Equal(239.98m, created.Total);

        // A new host/factory reads the persisted data, rather than an EF tracked object.
        using var secondFactory = new OrderingApiFactory(database, Clock);
        using var second = secondFactory.CreateClient();
        var filtered = await second.GetFromJsonAsync<List<DeliveryOrder>>($"/api/orders?deliveryDate={date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)}");
        Assert.NotNull(filtered);
        Assert.Single(filtered);
        Assert.Equal(created.Id, filtered[0].Id);
        var all = await second.GetFromJsonAsync<List<DeliveryOrder>>("/api/orders");
        Assert.NotNull(all);
        Assert.Contains(all, order => order.Customer == "Legacy" && order.RequestedDeliveryDate is null);
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(0)]
    [InlineData(91)]
    public async Task InvalidDate_Returns400WithoutCreatingAnOrder(int days)
    {
        using var factory = new OrderingApiFactory(_postgres.NewDatabase(), Clock);
        using var client = factory.CreateClient();
        var date = Today.AddDays(days);
        var response = await client.PostAsJsonAsync("/api/orders", new CreateOrderRequest("Ada", [new(1, 1)], date));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var orders = await client.GetFromJsonAsync<List<DeliveryOrder>>("/api/orders");
        Assert.NotNull(orders);
        Assert.Empty(orders);
    }

    [Theory]
    [InlineData(1)]
    [InlineData(90)]
    public async Task ValidBoundary_IsAcceptedUsingTheInjectedClock(int days)
    {
        using var factory = new OrderingApiFactory(_postgres.NewDatabase(), Clock);
        using var client = factory.CreateClient();
        var response = await client.PostAsJsonAsync("/api/orders", new CreateOrderRequest("Ada", [new(1, 1)], Today.AddDays(days)));
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    [Fact]
    public async Task MalformedDates_Return400ForBodyAndQuery()
    {
        using var factory = new OrderingApiFactory(_postgres.NewDatabase(), Clock);
        using var client = factory.CreateClient();
        using var json = new StringContent("""{"customer":"Ada","items":[{"productId":1,"quantity":1}],"requestedDeliveryDate":"not-a-date"}""", System.Text.Encoding.UTF8, "application/json");
        var body = await client.PostAsync("/api/orders", json);
        var query = await client.GetAsync("/api/orders?deliveryDate=not-a-date");
        Assert.Equal(HttpStatusCode.BadRequest, body.StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, query.StatusCode);
        var orders = await client.GetFromJsonAsync<List<DeliveryOrder>>("/api/orders");
        Assert.NotNull(orders);
        Assert.Empty(orders);
    }

    // Boundary behavior must not depend on the wall clock or the host timezone.
    private sealed class FixedClock : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => new(2026, 11, 8, 23, 59, 59, TimeSpan.Zero);
    }

    private sealed record DeliveryOrder(int Id, string Customer, decimal Total, DateOnly? RequestedDeliveryDate);
}
