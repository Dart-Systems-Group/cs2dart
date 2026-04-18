import '../roslyn_frontend/models/resolved_symbol.dart'
    as frontend
    show ResolvedSymbol, SymbolKind;
import 'diagnostic_collector.dart';
import 'models/ir_nodes.dart';

export 'models/ir_nodes.dart' show IrSymbol, UnresolvedSymbol;

/// Maps [frontend.ResolvedSymbol] records (from the Roslyn_Frontend) to
/// [IrSymbol] nodes used by the IR stage.
///
/// The SymbolResolver has no dependency on Roslyn. All symbol information is
/// read from the plain-data [frontend.ResolvedSymbol] records produced by the
/// Roslyn_Frontend and stored in the [SymbolTable].
///
/// ### Mapping rules
///
/// | ResolvedSymbol.kind          | Result                                        |
/// |------------------------------|-----------------------------------------------|
/// | `type`                       | `IrSymbol` with `kind = SymbolKind.type`      |
/// | `method`                     | `IrSymbol` with `kind = SymbolKind.method`    |
/// | `field`                      | `IrSymbol` with `kind = SymbolKind.field`     |
/// | `property`                   | `IrSymbol` with `kind = SymbolKind.property`  |
/// | `event`                      | `IrSymbol` with `kind = SymbolKind.event`     |
/// | `local`                      | `IrSymbol` with `kind = SymbolKind.local`     |
/// | `parameter`                  | `IrSymbol` with `kind = SymbolKind.parameter` |
/// | `unresolved`                 | `UnresolvedSymbol` + IR0020 Warning           |
///
/// For internal symbols (those defined within the compilation unit), the
/// [IrSymbol.declarationNode] field is set in a second pass by the
/// IR_Builder after all declarations have been emitted. It is `null` on
/// first resolution.
///
/// For external symbols (those from an external assembly), the assembly name
/// and fully-qualified name are copied from the [frontend.ResolvedSymbol]
/// record.
///
/// The specific overload recorded in the [SymbolTable] is used for every
/// method reference, so the IR contains no ambiguous method references
/// (Requirement 2.6).
final class SymbolResolver {
  final DiagnosticCollector _diagnostics;

  /// Creates a [SymbolResolver] that emits diagnostics into [diagnostics].
  SymbolResolver({required DiagnosticCollector diagnostics})
      : _diagnostics = diagnostics;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Resolves a [frontend.ResolvedSymbol] to an [IrSymbol].
  ///
  /// When [resolvedSymbol.kind] is [frontend.SymbolKind.unresolved], emits an
  /// `IR0020` Warning diagnostic and returns `null` — the caller should emit
  /// an [UnresolvedSymbol] placeholder expression node instead.
  ///
  /// [originalText] is the source text of the identifier being resolved; it is
  /// used in the IR0020 diagnostic message.
  ///
  /// [sourceLocation] and [sourceFile] are attached to any emitted diagnostic.
  IrSymbol? resolve(
    frontend.ResolvedSymbol resolvedSymbol, {
    String originalText = '',
    SourceLocation? sourceLocation,
    String? sourceFile,
  }) {
    if (resolvedSymbol.kind == frontend.SymbolKind.unresolved) {
      _diagnostics.warn(
        'IR0020',
        'Symbol could not be resolved: '
            '"${originalText.isNotEmpty ? originalText : resolvedSymbol.fullyQualifiedName}". '
            'An UnresolvedSymbol placeholder will be emitted.',
        source: sourceFile,
        location: sourceLocation,
      );
      return null;
    }

    return IrSymbol(
      fullyQualifiedName: resolvedSymbol.fullyQualifiedName,
      assemblyName: resolvedSymbol.assemblyName,
      kind: _mapKind(resolvedSymbol.kind),
      sourceLocation: resolvedSymbol.sourceLocation,
      sourcePackageId: resolvedSymbol.sourcePackageId,
      // declarationNode is set in a second pass by the IR_Builder for internal
      // symbols; it remains null here for both internal and external symbols.
      declarationNode: null,
    );
  }

  /// Resolves a [frontend.ResolvedSymbol] to an [UnresolvedSymbol] expression
  /// node.
  ///
  /// This is a convenience method for the case where the caller already knows
  /// the symbol is unresolved (e.g., after [resolve] returned `null`).
  ///
  /// Emits an `IR0020` Warning diagnostic if one has not already been emitted
  /// for the same location and code (deduplication is handled by
  /// [DiagnosticCollector]).
  ///
  /// [originalText] is the source text of the unresolved identifier.
  /// [sourceSpan] is the source location of the identifier in the source file.
  UnresolvedSymbol buildUnresolvedSymbol({
    required String originalText,
    required SourceLocation sourceSpan,
    String? sourceFile,
  }) {
    _diagnostics.warn(
      'IR0020',
      'Symbol could not be resolved: "$originalText". '
          'An UnresolvedSymbol placeholder will be emitted.',
      source: sourceFile,
      location: sourceSpan,
    );
    return UnresolvedSymbol(
      originalText: originalText,
      sourceSpan: sourceSpan,
      sourceLocation: sourceSpan,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Maps a [frontend.SymbolKind] to the IR [SymbolKind].
  ///
  /// The two enums have identical members (by design — the IR enum mirrors the
  /// frontend enum). The mapping is explicit to avoid a hard coupling between
  /// the two packages.
  SymbolKind _mapKind(frontend.SymbolKind kind) {
    return switch (kind) {
      frontend.SymbolKind.type => SymbolKind.type,
      frontend.SymbolKind.method => SymbolKind.method,
      frontend.SymbolKind.field => SymbolKind.field,
      frontend.SymbolKind.property => SymbolKind.property,
      frontend.SymbolKind.event => SymbolKind.event,
      frontend.SymbolKind.local => SymbolKind.local,
      frontend.SymbolKind.parameter => SymbolKind.parameter,
      // unresolved is handled before this method is called; this branch is
      // unreachable but required for exhaustiveness.
      frontend.SymbolKind.unresolved => SymbolKind.unresolved,
    };
  }
}
