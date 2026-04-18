using System.Text.Json;
using System.Text.Json.Serialization;
using Cs2DartRoslynWorker.Models;

namespace Cs2DartRoslynWorker.Serialization;

/// <summary>
/// Serializes a <see cref="FrontendResult"/> to a UTF-8 JSON string.
/// Uses System.Text.Json with camelCase property naming to match the Dart deserializer expectations.
/// </summary>
public static class FrontendResultSerializer
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    /// <summary>
    /// Serializes the <see cref="FrontendResult"/> to a UTF-8 JSON string.
    /// </summary>
    /// <param name="result">The result to serialize.</param>
    /// <returns>A UTF-8 JSON string representation of the result.</returns>
    public static string Serialize(FrontendResult result)
    {
        return JsonSerializer.Serialize(result, Options);
    }
}
