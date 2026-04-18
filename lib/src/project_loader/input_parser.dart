import 'dart:io';

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
    // Validate that the content looks like XML at all.
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw MalformedCsprojException(absolutePath, 'File is empty');
    }

    // Basic XML well-formedness check: must start with '<' and contain a root element.
    if (!trimmed.startsWith('<')) {
      throw MalformedCsprojException(
          absolutePath, 'Content does not start with an XML tag');
    }

    // Parse the XML into a simple element tree.
    final _XmlElement root;
    try {
      root = _parseXml(content);
    } on _XmlParseException catch (e) {
      throw MalformedCsprojException(absolutePath, e.message);
    }

    // Validate root element is <Project>.
    if (root.name.toLowerCase() != 'project') {
      throw MalformedCsprojException(
          absolutePath, 'Root element must be <Project>, got <${root.name}>');
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

    for (final child in root.children) {
      if (child.name.toLowerCase() == 'propertygroup') {
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
      } else if (child.name.toLowerCase() == 'itemgroup') {
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
      _XmlElement group, void Function(String name, String value) onProperty) {
    for (final child in group.children) {
      final text = child.textContent.trim();
      if (text.isNotEmpty) {
        onProperty(child.name, text);
      }
    }
  }

  /// Iterates over direct child elements of an `<ItemGroup>` and populates the
  /// provided lists with `<Compile>`, `<ProjectReference>`, and `<PackageReference>` data.
  void _parseItemGroup(
    _XmlElement group,
    String projectDir,
    List<String> compileIncludes,
    List<String> compileRemoves,
    List<String> projectReferencePaths,
    List<PackageReferenceSpec> packageReferences,
  ) {
    for (final child in group.children) {
      switch (child.name.toLowerCase()) {
        case 'compile':
          final include = child.attributes['Include'] ?? child.attributes['include'];
          if (include != null && include.isNotEmpty) {
            compileIncludes.add(include);
          }
          final remove = child.attributes['Remove'] ?? child.attributes['remove'];
          if (remove != null && remove.isNotEmpty) {
            compileRemoves.add(remove);
          }

        case 'projectreference':
          final include = child.attributes['Include'] ?? child.attributes['include'];
          if (include != null && include.isNotEmpty) {
            projectReferencePaths.add(_resolvePath(projectDir, include));
          }

        case 'packagereference':
          final name = child.attributes['Include'] ?? child.attributes['include'];
          final version = child.attributes['Version'] ??
              child.attributes['version'] ??
              _childText(child, 'Version') ??
              _childText(child, 'version') ??
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

  /// Returns the text content of the first child element with [name], or null.
  String? _childText(_XmlElement element, String name) {
    for (final child in element.children) {
      if (child.name.toLowerCase() == name.toLowerCase()) {
        final text = child.textContent.trim();
        return text.isEmpty ? null : text;
      }
    }
    return null;
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

// =============================================================================
// Minimal XML parser
// =============================================================================

/// Thrown when the XML content cannot be parsed.
final class _XmlParseException implements Exception {
  final String message;
  const _XmlParseException(this.message);
}

/// A lightweight XML element node.
final class _XmlElement {
  final String name;
  final Map<String, String> attributes;
  final List<_XmlElement> children;
  final String textContent;

  const _XmlElement({
    required this.name,
    required this.attributes,
    required this.children,
    required this.textContent,
  });
}

/// Parses [xml] into an [_XmlElement] tree.
///
/// Supports the subset of XML used by `.csproj` files:
/// - Elements with attributes
/// - Nested elements
/// - Text content
/// - XML declaration (`<?xml ... ?>`) and comments (`<!-- ... -->`) are skipped
/// - CDATA sections are not supported
///
/// Throws [_XmlParseException] on malformed input.
_XmlElement _parseXml(String xml) {
  final parser = _XmlParser(xml);
  return parser.parse();
}

final class _XmlParser {
  final String _src;
  int _pos = 0;

  _XmlParser(this._src);

  _XmlElement parse() {
    _skipWhitespace();
    // Skip XML declaration and processing instructions.
    while (_pos < _src.length && _peek(2) == '<?') {
      _skipUntil('?>');
      _pos += 2; // skip '?>'
      _skipWhitespace();
    }
    // Skip comments.
    _skipComments();
    if (_pos >= _src.length) {
      throw const _XmlParseException('Empty XML document');
    }
    final root = _parseElement();
    return root;
  }

  _XmlElement _parseElement() {
    _skipWhitespace();
    _skipComments();
    if (_pos >= _src.length || _src[_pos] != '<') {
      throw _XmlParseException(
          'Expected "<" at position $_pos, got "${_pos < _src.length ? _src[_pos] : "EOF"}"');
    }
    _pos++; // consume '<'

    // Self-closing or closing tag check handled by caller; here we parse an opening tag.
    final name = _parseName();
    if (name.isEmpty) {
      throw _XmlParseException('Empty element name at position $_pos');
    }

    final attributes = _parseAttributes();

    _skipWhitespace();
    if (_pos >= _src.length) {
      throw _XmlParseException('Unexpected end of input after <$name');
    }

    // Self-closing element: `<Foo />`
    if (_src[_pos] == '/') {
      _pos++; // consume '/'
      if (_pos >= _src.length || _src[_pos] != '>') {
        throw _XmlParseException('Expected ">" after "/" in self-closing tag <$name');
      }
      _pos++; // consume '>'
      return _XmlElement(
          name: name, attributes: attributes, children: [], textContent: '');
    }

    if (_src[_pos] != '>') {
      throw _XmlParseException(
          'Expected ">" to close opening tag <$name, got "${_src[_pos]}"');
    }
    _pos++; // consume '>'

    // Parse children and text content.
    final children = <_XmlElement>[];
    final textBuffer = StringBuffer();
    var closingTagFound = false;

    while (_pos < _src.length) {
      _skipComments();
      if (_pos >= _src.length) break;

      if (_src[_pos] == '<') {
        // Peek ahead to see if this is a closing tag.
        if (_pos + 1 < _src.length && _src[_pos + 1] == '/') {
          // Closing tag.
          _pos += 2; // consume '</'
          final closingName = _parseName();
          _skipWhitespace();
          if (_pos >= _src.length || _src[_pos] != '>') {
            throw _XmlParseException('Expected ">" to close </$closingName>');
          }
          _pos++; // consume '>'
          if (closingName.toLowerCase() != name.toLowerCase()) {
            throw _XmlParseException(
                'Mismatched tags: opened <$name>, closed </$closingName>');
          }
          closingTagFound = true;
          break;
        } else {
          // Child element.
          final child = _parseElement();
          children.add(child);
        }
      } else {
        // Text content.
        textBuffer.write(_src[_pos]);
        _pos++;
      }
    }

    if (!closingTagFound) {
      throw _XmlParseException('Missing closing tag for <$name>');
    }

    return _XmlElement(
      name: name,
      attributes: attributes,
      children: children,
      textContent: _decodeEntities(textBuffer.toString()),
    );
  }

  Map<String, String> _parseAttributes() {
    final attrs = <String, String>{};
    while (true) {
      _skipWhitespace();
      if (_pos >= _src.length) break;
      final ch = _src[_pos];
      if (ch == '>' || ch == '/') break;

      final attrName = _parseName();
      if (attrName.isEmpty) break;

      _skipWhitespace();
      if (_pos >= _src.length || _src[_pos] != '=') {
        // Attribute without value (boolean attribute) — not standard XML but be lenient.
        attrs[attrName] = '';
        continue;
      }
      _pos++; // consume '='
      _skipWhitespace();

      if (_pos >= _src.length) {
        throw _XmlParseException('Unexpected end of input reading attribute "$attrName"');
      }

      final quote = _src[_pos];
      if (quote != '"' && quote != "'") {
        throw _XmlParseException(
            'Expected quote for attribute "$attrName", got "${_src[_pos]}"');
      }
      _pos++; // consume opening quote
      final valueBuffer = StringBuffer();
      while (_pos < _src.length && _src[_pos] != quote) {
        valueBuffer.write(_src[_pos]);
        _pos++;
      }
      if (_pos >= _src.length) {
        throw _XmlParseException('Unterminated attribute value for "$attrName"');
      }
      _pos++; // consume closing quote
      attrs[attrName] = _decodeEntities(valueBuffer.toString());
    }
    return attrs;
  }

  String _parseName() {
    final start = _pos;
    while (_pos < _src.length) {
      final ch = _src[_pos];
      if (_isNameChar(ch)) {
        _pos++;
      } else {
        break;
      }
    }
    return _src.substring(start, _pos);
  }

  bool _isNameChar(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 65 && c <= 90) || // A-Z
        (c >= 97 && c <= 122) || // a-z
        (c >= 48 && c <= 57) || // 0-9
        c == 45 || // -
        c == 46 || // .
        c == 58 || // :
        c == 95; // _
  }

  void _skipWhitespace() {
    while (_pos < _src.length && _src[_pos].trim().isEmpty) {
      _pos++;
    }
  }

  void _skipComments() {
    while (_pos + 3 < _src.length && _peek(4) == '<!--') {
      _skipUntil('-->');
      _pos += 3; // skip '-->'
      _skipWhitespace();
    }
  }

  void _skipUntil(String marker) {
    while (_pos < _src.length) {
      if (_pos + marker.length <= _src.length &&
          _src.substring(_pos, _pos + marker.length) == marker) {
        return;
      }
      _pos++;
    }
  }

  String _peek(int length) {
    if (_pos + length > _src.length) return '';
    return _src.substring(_pos, _pos + length);
  }

  String _decodeEntities(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }
}
