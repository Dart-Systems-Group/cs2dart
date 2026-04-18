import '../models/project_file_data.dart';

/// Parses `.csproj` and `.sln` files into structured data.
abstract interface class IInputParser {
  /// Parses a `.csproj` file and returns a [ProjectFileData] containing
  /// source file globs, package references, project references, and metadata.
  ///
  /// Emits a `PL0003` Error diagnostic on malformed XML.
  Future<ProjectFileData> parseCsproj(String absolutePath);

  /// Parses a `.sln` file and returns the list of `.csproj` paths it references.
  ///
  /// Paths are resolved relative to the `.sln` directory.
  /// Emits a `PL0004` Error diagnostic on malformed `.sln` content.
  Future<List<String>> parseSln(String absolutePath);
}
