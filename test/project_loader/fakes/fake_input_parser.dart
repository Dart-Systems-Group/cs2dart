import 'package:cs2dart/src/project_loader/interfaces/i_input_parser.dart';
import 'package:cs2dart/src/project_loader/input_parser.dart';
import 'package:cs2dart/src/project_loader/models/project_file_data.dart';

/// A test double for [IInputParser] that returns data from in-memory fixtures.
///
/// No file I/O is performed. Throws [MalformedCsprojException] or
/// [MalformedSlnException] when the requested path is not in the fixture maps.
final class FakeInputParser implements IInputParser {
  /// Fixture responses for [parseCsproj]. Keys are absolute `.csproj` paths.
  final Map<String, ProjectFileData> csprojFixtures;

  /// Fixture responses for [parseSln]. Keys are absolute `.sln` paths.
  final Map<String, List<String>> slnFixtures;

  FakeInputParser({
    Map<String, ProjectFileData>? csprojFixtures,
    Map<String, List<String>>? slnFixtures,
  })  : csprojFixtures = csprojFixtures ?? {},
        slnFixtures = slnFixtures ?? {};

  @override
  Future<ProjectFileData> parseCsproj(String absolutePath) async {
    final result = csprojFixtures[absolutePath];
    if (result == null) {
      throw MalformedCsprojException(absolutePath, 'No fixture registered for path');
    }
    return result;
  }

  @override
  Future<List<String>> parseSln(String absolutePath) async {
    final result = slnFixtures[absolutePath];
    if (result == null) {
      throw MalformedSlnException(absolutePath, 'No fixture registered for path');
    }
    return result;
  }
}
