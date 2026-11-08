namespace ECommerce.Catalog.Api.Services;

/// <summary>
/// Warehouse simulation kept for the latency exercise. Product reads use the stored
/// snapshot again; a live warehouse request does not belong in this read path.
/// </summary>
public class WarehouseClient(IConfiguration configuration)
{
    public async Task<int> GetLiveStockAsync(int productId, int storedStock, CancellationToken cancellationToken = default)
    {
        await Task.Delay(configuration.GetValue("Warehouse:LatencyMs", 800), cancellationToken);
        return storedStock;
    }
}
