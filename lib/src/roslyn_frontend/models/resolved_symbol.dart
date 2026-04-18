import '../../config/models/source_location.dart';

export '../../config/models/source_location.dart';

/// The kind of a resolved symbol.
enum SymbolKind {
  type,
  method,
  field,
  property,
  event,
  local,
  parameter,

  /// Sentinel: Roslyn could not bind this reference.
  unresolved,
}

/// A plain-data record representing a fully-resolved Roslyn symbol.
///
/// No Roslyn types appear in this record. All fields are plain Dart values.
final class ResolvedSymbol {
  /// Fully-qualified name, e.g. "System.Collections.Generic.List<T>".
  final String fullyQualifiedName;

  /// The assembly that defines this symbol, e.g. "System.Collections".
  final String assemblyName;

  /// The kind of symbol.
  final SymbolKind kind;

  /// NuGet package ID when the symbol comes from an external package; null
  /// when the symbol is defined in the same compilation or the BCL.
  final String? sourcePackageId;

  /// Source location of the symbol's declaration; null for external symbols.
  final SourceLocation? sourceLocation;

  /// Compile-time constant value for const symbols; null otherwise.
  final Object? constantValue;

  const ResolvedSymbol({
    required this.fullyQualifiedName,
    required this.assemblyName,
    required this.kind,
    this.sourcePackageId,
    this.sourceLocation,
    this.constantValue,
  });
}
