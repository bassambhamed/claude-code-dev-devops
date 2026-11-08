# Catalog API image. Build from the repository root:
#   docker build -f src/ECommerce.Catalog.Api/Dockerfile -t ecommerce/catalog:1.0 .

# Build stage: the SDK never reaches the final image.
FROM mcr.microsoft.com/dotnet/sdk:10.0.403-noble@sha256:212fe4cb74627d5adf9817a4088906ae3edff1bd853bb27565d4b46731efe61e AS build
WORKDIR /src

# Restore first: this layer stays cached until a project file changes.
COPY src/ECommerce.ServiceDefaults/ECommerce.ServiceDefaults.csproj src/ECommerce.ServiceDefaults/
COPY src/ECommerce.Catalog.Api/ECommerce.Catalog.Api.csproj src/ECommerce.Catalog.Api/
RUN dotnet restore src/ECommerce.Catalog.Api/ECommerce.Catalog.Api.csproj

# Then the source code, and publish without restoring again.
COPY src/ECommerce.ServiceDefaults/ src/ECommerce.ServiceDefaults/
COPY src/ECommerce.Catalog.Api/ src/ECommerce.Catalog.Api/
RUN dotnet publish src/ECommerce.Catalog.Api/ECommerce.Catalog.Api.csproj \
      -c Release -o /app --no-restore -p:UseAppHost=false

# Runtime stage: chiseled Ubuntu, no shell, no package manager.
FROM mcr.microsoft.com/dotnet/aspnet:10.0.14-noble-chiseled@sha256:f2557fb81b1cfcfdfcde9d3bf247ed60b2cd38f00a88153f61e34737fab8ade7
WORKDIR /app
COPY --from=build /app .
# Numeric non-root user provided by the image (Kubernetes can then check runAsNonRoot).
USER $APP_UID
EXPOSE 8080
ENTRYPOINT ["dotnet", "ECommerce.Catalog.Api.dll"]
