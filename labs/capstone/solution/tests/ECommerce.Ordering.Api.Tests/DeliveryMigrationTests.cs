using ECommerce.Ordering.Api.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace ECommerce.Ordering.Api.Tests;

public sealed class DeliveryMigrationTests(PostgresFixture postgres) : IClassFixture<PostgresFixture>
{
    [Fact]
    public async Task Upgrade_PreservesAnOrderCreatedBeforeTheNewColumn()
    {
        var options = new DbContextOptionsBuilder<OrderingDbContext>().UseNpgsql(postgres.NewDatabase()).Options;
        await using var db = new OrderingDbContext(options);
        await db.GetService<IMigrator>().MigrateAsync("20261108181354_InitialCreate");
        await db.Database.ExecuteSqlRawAsync("""
            INSERT INTO "Orders" ("Customer", "CreatedAt", "Status")
            VALUES ('Legacy', CURRENT_TIMESTAMP, 1)
            """);
        await db.Database.MigrateAsync();
        var order = await db.Orders.SingleAsync();
        Assert.Equal("Legacy", order.Customer);
        Assert.Null(order.RequestedDeliveryDate);
        Assert.False(db.Database.HasPendingModelChanges());
    }
}
