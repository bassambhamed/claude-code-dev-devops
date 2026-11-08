var builder = DistributedApplication.CreateBuilder(args);

// PostgreSQL server, one logical database per service. The data volume keeps the data
// across restarts; the fixed host port lets tools outside Aspire (psql, MCP) connect.
var postgres = builder.AddPostgres("postgres", port: 5433)
    .WithDataVolume();
var catalogDb = postgres.AddDatabase("catalogdb");
var orderingDb = postgres.AddDatabase("orderingdb");

// Local development telemetry backend. Ports are restricted to loopback by Aspire's proxy.
var lgtm = builder.AddContainer("lgtm", "grafana/otel-lgtm", "0.40.0")
    .WithHttpEndpoint(port: 3000, targetPort: 3000, name: "grafana")
    .WithEndpoint(port: 4317, targetPort: 4317, name: "otlp", scheme: "http");

// Catalog microservice.
var catalog = builder.AddProject<Projects.ECommerce_Catalog_Api>("catalog")
    .WithEnvironment("Grafana__OtlpEndpoint", lgtm.GetEndpoint("otlp"))
    .WithReference(catalogDb)
    .WaitFor(catalogDb);

// Ordering microservice — depends on Catalog (resolved via service discovery).
var ordering = builder.AddProject<Projects.ECommerce_Ordering_Api>("ordering")
    .WithEnvironment("Grafana__OtlpEndpoint", lgtm.GetEndpoint("otlp"))
    .WithReference(orderingDb)
    .WaitFor(orderingDb)
    .WithReference(catalog)
    .WaitFor(catalog);

// API Gateway (YARP) — the single entry point for the services.
var gateway = builder.AddProject<Projects.ECommerce_Gateway>("gateway")
    .WithEnvironment("Grafana__OtlpEndpoint", lgtm.GetEndpoint("otlp"))
    .WithReference(catalog)
    .WithReference(ordering)
    .WaitFor(catalog)
    .WaitFor(ordering);

// Blazor web frontend — talks to the services through the gateway.
builder.AddProject<Projects.ECommerce_Web>("web")
    .WithEnvironment("Grafana__OtlpEndpoint", lgtm.GetEndpoint("otlp"))
    .WithReference(gateway)
    .WaitFor(gateway)
    .WithExternalHttpEndpoints();

builder.Build().Run();
