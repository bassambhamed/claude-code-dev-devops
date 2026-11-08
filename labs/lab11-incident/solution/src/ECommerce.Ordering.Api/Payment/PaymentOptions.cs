namespace ECommerce.Ordering.Api.Payment;

/// <summary>Payment settings. ApiKey comes from a secret store and must never be logged.</summary>
public sealed class PaymentOptions
{
    public const string SectionName = "Payment";
    public string Provider { get; set; } = string.Empty;
    public string Endpoint { get; set; } = string.Empty;
    public string ApiKey { get; set; } = string.Empty;
}
