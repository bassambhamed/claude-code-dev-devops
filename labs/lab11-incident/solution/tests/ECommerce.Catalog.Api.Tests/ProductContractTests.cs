global using System.Net.Http.Json;
using System.Text.Json;
using ECommerce.Ordering.Api.Services;
using ECommerce.Web.Services;

namespace ECommerce.Catalog.Api.Tests;

/// <summary>Exercise the real API JSON with the actual DTO source files used by consumers.</summary>
public sealed class ProductContractTests : IClassFixture<PostgresFixture>, IDisposable
{
    private readonly CatalogApiFactory _factory;
    private readonly HttpClient _client;

    public ProductContractTests(PostgresFixture postgres)
    {
        _factory = new CatalogApiFactory(postgres.NewDatabase());
        _client = _factory.CreateClient();
    }

    public void Dispose()
    {
        _client.Dispose();
        _factory.Dispose();
    }

    [Fact]
    public async Task SingleProduct_DeserializesWithTheActualOrderingContract()
    {
        var consumer = new CatalogServiceClient(_client);
        var product = await consumer.GetProductAsync(1);

        Assert.NotNull(product);
        Assert.Equal(1, product.Id);
        Assert.Equal("Mechanical Keyboard", product.Name);
        Assert.Equal(119.99m, product.Price);
        Assert.True(product.AvailableStock > 0);
    }

    [Fact]
    public async Task ProductList_DeserializesWithTheActualWebContract()
    {
        // Web calls this same JSON through Gateway's /catalog prefix transformation.
        var json = await _client.GetStringAsync("/api/products");
        var products = JsonSerializer.Deserialize<List<ProductDto>>(json, JsonSerializerOptions.Web);

        Assert.NotNull(products);
        Assert.Equal(4, products.Count);
        var keyboard = Assert.Single(products, product => product.Id == 1);
        Assert.Equal(119.99m, keyboard.Price);
        Assert.Equal("Mechanical Keyboard", keyboard.Name);
    }
}
