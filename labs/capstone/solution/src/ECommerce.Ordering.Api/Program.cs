using ECommerce.Ordering.Api.Data;
using ECommerce.Ordering.Api.Endpoints;
using ECommerce.Ordering.Api.Services;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

// Aspire: telemetry, health checks, resilience, service discovery.
builder.AddServiceDefaults();

builder.Services.AddOpenApi();
// PostgreSQL database "orderingdb", declared in the AppHost (connection string injected by Aspire).
builder.AddNpgsqlDbContext<OrderingDbContext>("orderingdb");

// Serialize enums (e.g. OrderStatus) as strings rather than integers.
builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.Converters.Add(new System.Text.Json.Serialization.JsonStringEnumConverter()));

// Typed client to the Catalog service. "catalog" is the Aspire resource name;
// service discovery + standard resilience handlers come from AddServiceDefaults.
builder.Services.AddHttpClient<CatalogServiceClient>(client =>
    client.BaseAddress = new Uri("https+http://catalog"));

// The API key is bound from a secret store and is never written to logs.
builder.Services.Configure<ECommerce.Ordering.Api.Payment.PaymentOptions>(
    builder.Configuration.GetSection(ECommerce.Ordering.Api.Payment.PaymentOptions.SectionName));

builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddScoped<CreateOrderService>();

var app = builder.Build();

var payment = app.Services
    .GetRequiredService<Microsoft.Extensions.Options.IOptions<ECommerce.Ordering.Api.Payment.PaymentOptions>>().Value;
app.Logger.LogInformation("Payment provider {Provider} at {Endpoint}", payment.Provider, payment.Endpoint);

// Aspire default endpoints (/health, /alive).
app.MapDefaultEndpoints();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.MapOrderingEndpoints();

// Apply pending migrations on startup. EF Core takes a lock, so replicas starting together
// do not run them twice. A production pipeline can run a migration bundle instead.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<OrderingDbContext>();
    db.Database.Migrate();
}

app.Run();
