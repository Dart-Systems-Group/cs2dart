import 'dart:io';

import 'package:xml/xml.dart';

import 'interfaces/i_input_parser.dart';
import 'models/package_reference_spec.dart';
import 'models/project_file_data.dart';

/// Exception thrown by [InputParser] when a `.csproj` file contains malformed XML.
///
/// The [ProjectLoader] coordinator catches this and emits a `PL0003` diagnostic.
final class MalformedCsprojException implements Exception {
  final String path;
  final String details;

  const MalformedCsprojException(this.path, this.details);

  @override
  String toString() => 'MalformedCsprojException: $path — $details';
}

/// Exception thrown by [InputParser] when a `.sln` file is malformed.
///
/// The [ProjectLoader] coordinator catches this and emits a `PL0004` diagnostic.
final class MalformedSlnException implements Exception {
  final String path;
  final String details;

  const MalformedSlnException(this.path, this.details);

  @override
  String toString() => 'MalformedSlnException: $path — $details';
}

/// Concrete implementation of [IInputParser] that parses `.csproj` and `.sln` files.
final class InputParser implements IInputParser {
  const InputParser();

  @override
  Future<ProjectFileData> parseCsproj(String absolutePath) async {
    final file = File(absolutePath);
    final String content;
    try {
      content = await file.readAsString();
    } catch (e) {
      throw MalformedCsprojException(absolutePath, 'Cannot read file: $e');
    }

    try {
      return _parseCsprojContent(absolutePath, content);
    } on MalformedCsprojException {
      rethrow;
    } catch (e) {
      throw MalformedCsprojException(absolutePath, 'Unexpected parse error: $e');
    }
  }

  @override
  Future<List<String>> parseSln(String absolutePath) async {
    final file = File(absolutePath);
    final String content;
    try {
      content = await file.readAsString();
    } catch (e) {
      throw MalformedSlnException(absolutePath, 'Cannot read file: $e');
    }

    // A valid .sln must have some content. Completely empty files are malformed.
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw MalformedSlnException(absolutePath, 'File is empty');
    }

    // A .sln file should contain at least some recognisable structure.
    // We consider it malformed if it contains no typical .sln markers at all
    // (e.g. it's a random text file with no Project(...) lines and no
    // "Microsoft Visual Studio Solution File" header).
    final hasSlnHeader = trimmed.contains('Microsoft Visual Studio Solution File') ||
        trimmed.contains('Project(');
    if (!hasSlnHeader) {
      throw MalformedSlnException(
          absolutePath, 'Content does not appear to be a valid .sln file');
    }

    // Extract .csproj paths from Project(...) lines.
    // Format: Project("{GUID}") = "Name", "relative\path\to\Project.csproj", "{GUID}"
    final projectLineRegex = RegExp(
      r'Project\("[^"]*"\)\s*=\s*"[^"]*"\s*,\s*"([^"]*\.csproj)"',
      caseSensitive: false,
    );

    final slnDir = file.parent.path;
    final csprojPaths = <String>[];

    for (final match in projectLineRegex.allMatches(content)) {
      final relativePath = match.group(1)!;
      // Normalise Windows-style backslashes to forward slashes.
      final normalised = relativePath.replaceAll('\\', '/');
      final resolved = '$slnDir/$normalised';
      csprojPaths.add(resolved);
    }

    return csprojPaths;
  }

  // ---------------------------------------------------------------------------
  // Internal parsing helpers
  // ---------------------------------------------------------------------------

  ProjectFileData _parseCsprojContent(String absolutePath, String content) {
    // Guard: empty file.
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw MalformedCsprojException(absolutePath, 'File is empty');
    }

    // Parse XML using package:xml; XmlException is thrown on malformed input.
    final XmlDocument document;
    try {
      document = XmlDocument.parse(content);
    } on XmlException catch (e) {
      throw MalformedCsprojException(absolutePath, e.message);
    }

    // Validate root element is <Project> (case-insensitive).
    final root = document.rootElement;
    if (root.name.local.toLowerCase() != 'project') {
      throw MalformedCsprojException(
          absolutePath, 'Root element must be <Project>');
    }

    final projectDir = File(absolutePath).parent.path;

    // Collect all PropertyGroup and ItemGroup children.
    String? assemblyName;
    String? targetFramework;
    String? outputType;
    String? langVersion;
    bool nullableEnabled = false;

    final compileIncludes = <String>[];
    final compileRemoves = <String>[];
    final projectReferencePaths = <String>[];
    final packageReferences = <PackageReferenceSpec>[];

    for (final child in root.childElements) {
      final childName = child.name.local.toLowerCase();
      if (childName == 'propertygroup') {
        _parsePropertyGroup(child, (name, value) {
          switch (name.toLowerCase()) {
            case 'assemblyname':
              assemblyName = value;
            case 'targetframework':
              targetFramework = value.trim();
            case 'targetframeworks':
              // Select the first non-empty framework when multiple are listed.
              final parts = value.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty);
              if (parts.isNotEmpty) targetFramework = parts.first;
            case 'outputtype':
              outputType = value.trim();
            case 'langversion':
              langVersion = value.trim();
            case 'nullable':
              nullableEnabled = value.trim().toLowerCase() == 'enable';
          }
        });
      } else if (childName == 'itemgroup') {
        _parseItemGroup(
          child,
          projectDir,
          compileIncludes,
          compileRemoves,
          projectReferencePaths,
          packageReferences,
        );
      }
    }

    // Determine source globs / resolved paths.
    final List<String> sourceGlobs;
    if (compileIncludes.isEmpty) {
      // Implicit SDK-style glob: expand **/*.cs relative to project directory.
      sourceGlobs = _expandImplicitGlob(projectDir);
    } else {
      // Explicit <Compile Include="..."> entries — resolve relative paths.
      final resolved = compileIncludes
          .map((p) => _resolvePath(projectDir, p))
          .where((p) => !compileRemoves.map((r) => _resolvePath(projectDir, r)).contains(p))
          .toList();
      resolved.sort();
      sourceGlobs = resolved;
    }

    return ProjectFileData(
      absolutePath: absolutePath,
      assemblyName: assemblyName,
      targetFramework: targetFramework,
      outputType: outputType,
      langVersion: langVersion,
      nullableEnabled: nullableEnabled,
      sourceGlobs: sourceGlobs,
      projectReferencePaths: projectReferencePaths,
      packageReferences: packageReferences,
    );
  }

  /// Iterates over direct child elements of a `<PropertyGroup>` and calls [onProperty]
  /// for each one with its element name and text content.
  void _parsePropertyGroup(
      XmlElement group, void Function(String name, String value) onProperty) {
    for (final child in group.childElements) {
      final text = child.innerText.trim();
      if (text.isNotEmpty) {
        onProperty(child.name.local, text);
      }
    }
  }

  /// Iterates over direct child elements of an `<ItemGroup>` and populates the
  /// provided lists with `<Compile>`, `<ProjectReference>`, and `<PackageReference>` data.
  void _parseItemGroup(
    XmlElement group,
    String projectDir,
    List<String> compileIncludes,
    List<String> compileRemoves,
    List<String> projectReferencePaths,
    List<PackageReferenceSpec> packageReferences,
  ) {
    for (final child in group.childElements) {
      switch (child.name.local.toLowerCase()) {
        case 'compile':
          final include = child.getAttribute('Include') ?? child.getAttribute('include');
          if (include != null && include.isNotEmpty) {
            compileIncludes.add(include);
          }
          final remove = child.getAttribute('Remove') ?? child.getAttribute('remove');
          if (remove != null && remove.isNotEmpty) {
            compileRemoves.add(remove);
          }

        case 'projectreference':
          final include = child.getAttribute('Include') ?? child.getAttribute('include');
          if (include != null && include.isNotEmpty) {
            projectReferencePaths.add(_resolvePath(projectDir, include));
          }

        case 'packagereference':
          final name = child.getAttribute('Include') ?? child.getAttribute('include');
          final version = child.getAttribute('Version') ??
              child.getAttribute('version') ??
              child.getElement('Version')?.innerText ??
              child.getElement('version')?.innerText ??
              '';
          if (name != null && name.isNotEmpty) {
            packageReferences.add(PackageReferenceSpec(
              packageName: name,
              version: version,
            ));
          }
      }
    }
  }

  /// Resolves [path] relative to [base] if it is not already absolute.
  ///
  /// Also normalises `..` and `.` segments so that paths like
  /// `App/../Services/Services.csproj` are collapsed to
  /// `Services/Services.csproj` before comparison.
  String _resolvePath(String base, String path) {
    // Normalise Windows-style separators.
    final normalised = path.replaceAll('\\', '/');
    final combined = File(normalised).isAbsolute
        ? normalised
        : '${base.replaceAll('\\', '/')}/$normalised';
    // Use Uri to collapse `..` and `.` segments.
    return Uri.file(combined).toFilePath();
  }

  /// Expands the implicit `**/*.cs` glob by recursively listing all `.cs` files
  /// under [projectDir], then sorting them alphabetically by absolute path.
  List<String> _expandImplicitGlob(String projectDir) {
    final dir = Directory(projectDir);
    if (!dir.existsSync()) return [];

    final csFiles = dir
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((f) => f.path.endsWith('.cs'))
        .map((f) => f.absolute.path)
        .toList();

    csFiles.sort();
    return csFiles;
  }
}
