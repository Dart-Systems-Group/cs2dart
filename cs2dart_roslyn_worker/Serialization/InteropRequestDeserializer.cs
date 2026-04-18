using System.Text.Json;
using System.Text.Json.Serialization;
using Cs2DartRoslynWorker.Models;

namespace Cs2DartRoslynWorker.Serialization;

/// <summary>
/// Deserializes a JSON payload into an <see cref="InteropRequest"/>.
/// Uses System.Text.Json with camelCase property naming to match the Dart serializer output.
/// </summary>
public static class InteropRequestDeserializer
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    /// <summary>
    /// Deserializes the UTF-8 JSON string into an <see cref="InteropRequest"/>.
    /// </summary>
    /// <param name="json">The UTF-8 JSON string received from the Dart side.</param>
    /// <returns>The deserialized <see cref="InteropRequest"/>.</returns>
    /// <exception cref="JsonException">Thrown when the JSON is malformed or missing required fields.</exception>
    public static InteropRequest Deserialize(string json)
    {
        var result = JsonSerializer.Deserialize<InteropRequest>(json, Options);
        if (result is null)
            throw new JsonException("Deserialized InteropRequest was null.");
        return result;
    }
}
