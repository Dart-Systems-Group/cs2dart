using System.Text;
using Cs2DartRoslynWorker;
using Cs2DartRoslynWorker.Serialization;

// Configure stdout/stdin for binary I/O.
// Disable auto-flush on stdout; we flush manually after each response.
var stdin = Console.OpenStandardInput();
var stdout = Console.OpenStandardOutput();

try
{
    // Allocate a reusable 4-byte buffer for the length prefix.
    var lengthBuffer = new byte[4];

    while (true) 
    {
        // 1. Read 4-byte little-endian length prefix from stdin.
        int bytesRead = ReadExact(stdin, lengthBuffer, 0, 4);
        if (bytesRead == 0)
        {
            // EOF — Dart side closed stdin; exit cleanly.
            break;
        }

        int length = BitConverter.ToInt32(lengthBuffer, 0);
        if (length < 0)
        {
            Console.Error.WriteLine($"[cs2dart_roslyn_worker] Invalid message length: {length}");
            Environment.Exit(2);
        }

        // 2. Read exactly `length` bytes of UTF-8 JSON.
        var jsonBytes = new byte[length];
        ReadExact(stdin, jsonBytes, 0, length);
        string json = Encoding.UTF8.GetString(jsonBytes);

        // 3. Deserialize to InteropRequest.
        var request = InteropRequestDeserializer.Deserialize(json);

        // 4. Process.
        var result = WorkerRequestHandler.Handle(request);

        // 5. Serialize FrontendResult to JSON.
        string responseJson = FrontendResultSerializer.Serialize(result);
        byte[] responseBytes = Encoding.UTF8.GetBytes(responseJson);

        // 6. Write 4-byte LE length prefix + JSON bytes to stdout, then flush.
        byte[] responseLengthBytes = BitConverter.GetBytes(responseBytes.Length);
        stdout.Write(responseLengthBytes, 0, 4);
        stdout.Write(responseBytes, 0, responseBytes.Length);
        stdout.Flush();
    }
}
catch (Exception ex)
{
    // Catch all top-level exceptions, write to stderr, exit with non-zero code.
    Console.Error.WriteLine($"[cs2dart_roslyn_worker] Fatal error: {ex}");
    Environment.Exit(1);
}

/// <summary>
/// Reads exactly <paramref name="count"/> bytes from <paramref name="stream"/> into
/// <paramref name="buffer"/> starting at <paramref name="offset"/>.
/// Returns 0 on immediate EOF (no bytes available), or <paramref name="count"/> on success.
/// Throws <see cref="EndOfStreamException"/> on partial EOF.
/// </summary>
static int ReadExact(Stream stream, byte[] buffer, int offset, int count)
{
    int totalRead = 0;
    while (totalRead < count)
    {
        int read = stream.Read(buffer, offset + totalRead, count - totalRead);
        if (read == 0)
        {
            if (totalRead == 0)
                return 0; // Clean EOF before any bytes were read.
            throw new EndOfStreamException(
                $"Unexpected EOF after reading {totalRead} of {count} bytes.");
        }
        totalRead += read;
    }
    return totalRead;
}
