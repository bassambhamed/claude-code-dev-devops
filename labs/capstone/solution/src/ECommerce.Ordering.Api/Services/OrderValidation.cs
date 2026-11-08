using ECommerce.Ordering.Api.Endpoints;

namespace ECommerce.Ordering.Api.Services;

public static class OrderValidation
{
    public static string? Validate(CreateOrderRequest request, DateOnly today)
    {
        if (string.IsNullOrWhiteSpace(request.Customer))
        {
            return "Customer is required.";
        }
        if (request.Customer.Length > 200)
        {
            return "Customer must not exceed 200 characters.";
        }
        if (request.Items is null || request.Items.Count == 0)
        {
            return "An order must contain at least one item.";
        }
        if (request.Items.Any(item => item is null || item.Quantity < 1))
        {
            return "Quantity must be at least 1.";
        }
        if (request.RequestedDeliveryDate is { } date && (date <= today || date > today.AddDays(90)))
        {
            return "Requested delivery date must be between tomorrow and 90 days from today (UTC).";
        }
        return null;
    }
}
