using System.Net;
using System.Net.Http.Json;
using ECommerce.Catalog.Api.Data;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace ECommerce.Catalog.Api.Tests;

/// <summary>
/// Hosts Catalog.Api in memory with a database private to this factory,
/// seeded with products 1 to 4 by EnsureCreated in Program.cs.
/// </summary>
public sealed class CatalogApiFactory : WebApplicationFactory<Program>
{
    private readonly string _databaseName = $"catalog-tests-{Guid.NewGuid()}";

    protected override void ConfigureWebHost(IWebHostBuilder builder) =>
        builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<DbContextOptions<CatalogDbContext>>();
            services.RemoveAll<IDbContextOptionsConfiguration<CatalogDbContext>>();
            services.AddDbContext<CatalogDbContext>(options => options.UseInMemoryDatabase(_databaseName));
        });
}

public sealed class ProductEndpointsTests : IDisposable
{
    private readonly CatalogApiFactory _factory = new();
    private readonly HttpClient _client;

    public ProductEndpointsTests() => _client = _factory.CreateClient();

    public void Dispose()
    {
        _client.Dispose();
        _factory.Dispose();
    }

    [Fact]
    public async Task GetProducts_ReturnsTheFourSeededProducts()
    {
        var products = await _client.GetFromJsonAsync<List<ProductResponse>>("/api/products");

        Assert.NotNull(products);
        Assert.Equal(4, products.Count);
    }

    [Fact]
    public async Task GetProductById_ReturnsTheProduct()
    {
        var product = await _client.GetFromJsonAsync<ProductResponse>("/api/products/1");

        Assert.NotNull(product);
        Assert.Equal("Mechanical Keyboard", product.Name);
        Assert.Equal(119.99m, product.Price);
    }

    [Fact]
    public async Task GetProductById_UnknownId_Returns404()
    {
        var response = await _client.GetAsync("/api/products/999");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    private sealed record ProductResponse(int Id, string Name, decimal Price, int AvailableStock);
}
