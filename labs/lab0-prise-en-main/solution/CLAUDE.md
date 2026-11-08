# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A .NET 10 e-commerce app built as microservices and orchestrated by .NET Aspire 13.4. A Blazor UI (interactive server) calls a YARP gateway, which routes requests to the Catalog and Ordering minimal APIs. Storage is EF Core in-memory. There are no tests, no real database, no Dockerfile and no CI yet.

## Commands

Run everything from the repository root (the folder with `ECommerce.slnx`).

```bash
dotnet build ECommerce.slnx                        # build all 6 projects
dotnet run --project src/ECommerce.AppHost         # run every service and the Aspire dashboard
dotnet format ECommerce.slnx --verify-no-changes   # format check (SDK defaults, no .editorconfig)
dotnet dev-certs https --trust                     # one-time; otherwise the dashboard logs UntrustedRoot errors
```

- **Baseline:** the build has 0 errors but reports NU1902/NU1903 vulnerability warnings for the transitive packages `MessagePack` (AppHost) and `Microsoft.OpenApi` (Catalog, Ordering). The format check already fails on 7 WHITESPACE findings in `src/ECommerce.ServiceDefaults/Extensions.cs`.
- **Tests:** there are no test projects, so `dotnet test` runs nothing. Verify changes with the build plus `/smoke-test`.
- **URLs:** the console prints `Login URL: https://localhost:17089/login?t=<token>` (new token on every run). Gateway `http://localhost:5067`, Web `https://localhost:7218`, Catalog `:5147`, Ordering `:5086`. The APIs have no `/` route, so a 404 there is expected.
- **Smoke test:** `/smoke-test`, or by hand:
  ```bash
  curl http://localhost:5067/catalog/api/products
  curl -X POST http://localhost:5067/ordering/api/orders -H 'Content-Type: application/json' \
       -d '{"customer":"Ada","items":[{"productId":1,"quantity":2}]}'   # 201; unknown productId or empty items: 400
  ```
- **Logs:** service logs never reach the AppHost console. Read them in the dashboard (console logs, structured logs, traces), or run the service on its own.
- **Running one service:** Catalog has no dependencies (`dotnet run --project src/ECommerce.Catalog.Api`). Ordering needs the setting the AppHost injects: `services__catalog__http__0=http://localhost:5147 dotnet run --project src/ECommerce.Ordering.Api`.
- **Restarting:** the AppHost starts services with `dotnet run --no-build`, so after editing code, restart the AppHost (it rebuilds everything). Restarting a resource from the dashboard does not rebuild it. A background AppHost ignores SIGINT: stop it with SIGTERM, then wait about 15 s until `pgrep -f ECommerce` prints nothing, or port 5067 is still in use.

## Architecture

```
Web (Blazor) ─▶ Gateway (YARP) ─┬─ /catalog/*  ─▶ Catalog.Api
                                └─ /ordering/* ─▶ Ordering.Api ─▶ Catalog.Api  (direct call)
```

- **Service discovery** (`src/ECommerce.AppHost/AppHost.cs`): resource names (`catalog`, `ordering`, `gateway`, `web`) are hostnames. Callers use `https+http://<name>`. A service resolves a name only if its resource has `.WithReference(<target>)`. Never hard-code hosts or ports.
- **Gateway routing lives in configuration** (`src/ECommerce.Gateway/appsettings.json`), with `PathRemovePrefix`: `GET /catalog/api/products` becomes `GET /api/products` on Catalog.
- **ServiceDefaults** (`src/ECommerce.ServiceDefaults/Extensions.cs`): OpenTelemetry, service discovery, the standard resilience handler on every `HttpClient`, health checks. `/health`, `/alive` and `/openapi/v1.json` exist **only in Development**. A custom `Meter` is exported only after `.AddMeter(...)`. The resilience handler also retries non-idempotent calls such as `POST /ordering/api/orders`.
- **Data:** each API has an EF Core in-memory database created by `EnsureCreated()`; every restart resets it. Catalog seeds products 1–4 with `HasData`. The schema uses the Fluent API in `OnModelCreating`.
- **Contracts are copied, not shared.** The APIs serialize their EF entities, so changing `Product`, `Order` or `OrderItem` changes the wire format. Update the copies by hand: `CatalogProduct` (Ordering, `Services/CatalogServiceClient.cs`), `ProductDto` (Web, `Services/CatalogApiClient.cs`), and `OrderDto`, `OrderItemDto`, `CreateOrderDto`, `OrderLineDto` (Web, `Services/OrderingApiClient.cs`).
- **JSON** is camelCase. `OrderStatus` is serialized as a string. Errors are `Results.BadRequest("…")`: a plain JSON string that the Web UI shows to the user unchanged.
- **Order creation** (`src/ECommerce.Ordering.Api/Endpoints/OrderingEndpoints.cs`): one Catalog call per line; name and price are copied into the `OrderItem`. The server does not validate the customer name or the quantity, and never checks the stock.
- **Web UI:** no global render mode. Each interactive page must declare `@rendermode InteractiveServer`, or its `@onclick` handlers do nothing. The cart is a dictionary inside `Products.razor`.

## Conventions

- Minimal APIs: one static `XxxEndpoints` class per service with `MapXxxEndpoints`, over `MapGroup("/api/...")`. Every endpoint has `.WithName(...)` (`CreatedAtRoute` relies on it). Request records sit at the bottom of the endpoints file.
- Folders: `Models/` entities, `Data/` DbContext, `Endpoints/` routes, `Services/` typed `HttpClient`s.
- C#: primary constructors, file-scoped namespaces, nullable reference types. NuGet versions are pinned in each `.csproj`.
- Code, comments and UI strings are in English.
