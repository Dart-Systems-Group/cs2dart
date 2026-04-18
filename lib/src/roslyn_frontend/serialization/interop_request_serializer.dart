import '../../project_loader/models/roslyn_interop.dart';
import '../models/interop_request.dart';

/// Serializes and deserializes [InteropRequest] to/from JSON-compatible maps.
///
/// All keys use camelCase matching the Dart field names.
final class InteropRequestSerializer {
  const InteropRequestSerializer();

  // -------------------------------------------------------------------------
  // toJson
  // -------------------------------------------------------------------------

  /// Converts an [InteropRequest] to a JSON-compatible [Map<String, dynamic>].
  Map<String, dynamic> toJson(InteropRequest request) {
    return {
      'projects': request.projects.map(_projectEntryToJson).toList(),
      'config': _frontendConfigToJson(request.config),
    };
  }

  Map<String, dynamic> _projectEntryToJson(ProjectEntryRequest entry) {
    return {
      'projectName': entry.projectName,
      'projectFilePath': entry.projectFilePath,
      'outputKind': _outputKindToJson(entry.outputKind),
      'targetFramework': entry.targetFramework,
      'langVersion': entry.langVersion,
      'nullableEnabled': entry.nullableEnabled,
      'packageReferences':
          entry.packageReferences.map(_packageReferenceToJson).toList(),
      'sourceFilePaths': List<String>.from(entry.sourceFilePaths),
    };
  }

  Map<String, dynamic> _frontendConfigToJson(FrontendConfig config) {
    return {
      'linqStrategy': config.linqStrategy,
      'nullabilityEnabled': config.nullabilityEnabled,
      'experimentalFeatures': Map<String, bool>.from(config.experimentalFeatures),
    };
  }

  Map<String, dynamic> _packageReferenceToJson(PackageReferenceEntry entry) {
    return {
      'packageName': entry.packageName,
      'version': entry.version,
      'tier': entry.tier,
      if (entry.dartMapping != null)
        'dartMapping': _dartMappingToJson(entry.dartMapping!),
    };
  }

  Map<String, dynamic> _dartMappingToJson(DartMapping mapping) {
    return {
      'dartPackageName': mapping.dartPackageName,
      'dartImportPath': mapping.dartImportPath,
    };
  }

  String _outputKindToJson(OutputKind kind) {
    return switch (kind) {
      OutputKind.exe => 'exe',
      OutputKind.library => 'library',
      OutputKind.winExe => 'winExe',
    };
  }

  // -------------------------------------------------------------------------
  // fromJson
  // -------------------------------------------------------------------------

  /// Reconstructs an [InteropRequest] from a JSON-compatible map.
  ///
  /// Intended for round-trip testing; the resulting object is value-equal to
  /// the original when serialized with [toJson].
  InteropRequest fromJson(Map<String, dynamic> json) {
    final projectsList = (json['projects'] as List<dynamic>)
        .map((e) => _projectEntryFromJson(e as Map<String, dynamic>))
        .toList();

    final config =
        _frontendConfigFromJson(json['config'] as Map<String, dynamic>);

    return InteropRequest(projects: projectsList, config: config);
  }

  ProjectEntryRequest _projectEntryFromJson(Map<String, dynamic> json) {
    final packageRefs = (json['packageReferences'] as List<dynamic>)
        .map((e) => _packageReferenceFromJson(e as Map<String, dynamic>))
        .toList();

    final sourceFilePaths =
        (json['sourceFilePaths'] as List<dynamic>).cast<String>();

    return ProjectEntryRequest(
      projectName: json['projectName'] as String,
      projectFilePath: json['projectFilePath'] as String,
      outputKind: _outputKindFromJson(json['outputKind'] as String),
      targetFramework: json['targetFramework'] as String,
      langVersion: json['langVersion'] as String,
      nullableEnabled: json['nullableEnabled'] as bool,
      packageReferences: packageRefs,
      sourceFilePaths: sourceFilePaths,
    );
  }

  FrontendConfig _frontendConfigFromJson(Map<String, dynamic> json) {
    final features = (json['experimentalFeatures'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as bool));

    return FrontendConfig(
      linqStrategy: json['linqStrategy'] as String,
      nullabilityEnabled: json['nullabilityEnabled'] as bool,
      experimentalFeatures: features,
    );
  }

  PackageReferenceEntry _packageReferenceFromJson(Map<String, dynamic> json) {
    final dartMappingJson = json['dartMapping'] as Map<String, dynamic>?;
    final dartMapping =
        dartMappingJson != null ? _dartMappingFromJson(dartMappingJson) : null;

    return PackageReferenceEntry(
      packageName: json['packageName'] as String,
      version: json['version'] as String,
      tier: json['tier'] as int,
      dartMapping: dartMapping,
    );
  }

  DartMapping _dartMappingFromJson(Map<String, dynamic> json) {
    return DartMapping(
      dartPackageName: json['dartPackageName'] as String,
      dartImportPath: json['dartImportPath'] as String,
    );
  }

  OutputKind _outputKindFromJson(String value) {
    return switch (value) {
      'exe' => OutputKind.exe,
      'library' => OutputKind.library,
      'winExe' => OutputKind.winExe,
      _ => throw ArgumentError.value(value, 'outputKind', 'Unknown OutputKind'),
    };
  }
}
