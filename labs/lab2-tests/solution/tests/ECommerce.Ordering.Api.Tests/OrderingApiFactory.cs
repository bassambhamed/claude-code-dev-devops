using System.Net;
using System.Net.Http.Json;
using ECommerce.Ordering.Api.Data;
using ECommerce.Ordering.Api.Services;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace ECommerce.Ordering.Api.Tests;

/// <summary>
/// Hosts Ordering.Api in memory with its own database and a fake Catalog.
/// Create one factory per test so that no test sees another test's orders.
/// </summary>
public sealed class OrderingApiFactory : WebApplicationFactory<Program>
{
    private readonly string _databaseName = $"ordering-tests-{Guid.NewGuid()}";

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        // Aspire normally injects this setting. The address is never called:
        // the fake handler below answers instead of the network.
        builder.UseSetting("services:catalog:http:0", "http://catalog.test");

        builder.ConfigureTestServices(services =>
        {
            // Program.cs uses a database named "ordering", shared by every host in the
            // test process. Replace it with a database private to this factory.
            services.RemoveAll<DbContextOptions<OrderingDbContext>>();
            services.RemoveAll<IDbContextOptionsConfiguration<OrderingDbContext>>();
            services.AddDbContext<OrderingDbContext>(options => options.UseInMemoryDatabase(_databaseName));

            services.AddHttpClient<CatalogServiceClient>()
                .ConfigurePrimaryHttpMessageHandler(() => new FakeCatalogHandler());
        });
    }
}

/// <summary>
/// Stands in for Catalog.Api: answers GET /api/products/{id} for the known
/// products, and 404 for anything else, like the real service.
/// </summary>
public sealed class FakeCatalogHandler : HttpMessageHandler
{
    private const string ProductsPath = "/api/products/";

    private static readonly Dictionary<int, CatalogProduct> Products = new()
    {
        [1] = new CatalogProduct(1, "Mechanical Keyboard", "Hot-swappable RGB keyboard", 119.99m, 50),
        [2] = new CatalogProduct(2, "Wireless Mouse", "Ergonomic 8k DPI mouse", 49.50m, 120),
    };

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var path = request.RequestUri?.AbsolutePath ?? string.Empty;

        if (request.Method == HttpMethod.Get
            && path.StartsWith(ProductsPath, StringComparison.Ordinal)
            && int.TryParse(path[ProductsPath.Length..], out var id)
            && Products.TryGetValue(id, out var product))
        {
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = JsonContent.Create(product)
            });
        }

        return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
    }
}
