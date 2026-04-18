import 'ir_type.dart';
import 'resolved_symbol.dart';

/// Attached to method/local-function nodes that carry the async modifier,
/// or to iterator methods containing yield statements.
final class AsyncAnnotation {
  /// True when the method has the `async` modifier.
  final bool isAsync;

  /// True when the method body contains `yield` statements.
  final bool isIterator;

  /// True when the return type is `void` (fire-and-forget async void).
  final bool isFireAndForget;

  /// Resolved symbol for the return type (Task, Task<T>, ValueTask, etc.);
  /// null for non-async methods or when resolution fails.
  final ResolvedSymbol? returnTypeSymbol;

  const AsyncAnnotation({
    required this.isAsync,
    this.isIterator = false,
    this.isFireAndForget = false,
    this.returnTypeSymbol,
  });
}

/// Attached to await expressions that had ConfigureAwait(false).
final class ConfigureAwaitAnnotation {
  /// Always false when this annotation is present (ConfigureAwait(false)).
  final bool configureAwait;

  const ConfigureAwaitAnnotation({required this.configureAwait});
}

/// Attached to arithmetic operations inside checked/unchecked blocks.
final class OverflowCheckAnnotation {
  /// True when inside a `checked` block; false when inside `unchecked`.
  final bool checked;

  const OverflowCheckAnnotation({required this.checked});
}

/// Attached to foreach loop nodes with the resolved element type.
final class ForeachAnnotation {
  /// The resolved element type of the collection being iterated.
  final IrType elementType;

  const ForeachAnnotation({required this.elementType});
}

/// Attached to indexer get/set method declarations.
final class IndexerAnnotation {
  /// Always true when this annotation is present.
  final bool isIndexer;

  const IndexerAnnotation({required this.isIndexer});
}

/// Attached to extension method declarations.
final class ExtensionAnnotation {
  /// Always true when this annotation is present.
  final bool isExtension;

  /// The resolved symbol for the type being extended.
  final ResolvedSymbol extendedType;

  const ExtensionAnnotation({
    required this.isExtension,
    required this.extendedType,
  });
}

/// Attached to explicit interface implementation method declarations.
final class ExplicitInterfaceAnnotation {
  /// The resolved symbol for the interface being explicitly implemented.
  final ResolvedSymbol implementedInterface;

  const ExplicitInterfaceAnnotation({required this.implementedInterface});
}

/// Attached to nodes that cannot be normalized or lowered.
final class UnsupportedAnnotation {
  /// Human-readable description of why the construct is unsupported.
  final String description;

  /// The original source text span for diagnostic reporting.
  final String originalSourceSpan;

  const UnsupportedAnnotation({
    required this.description,
    required this.originalSourceSpan,
  });
}

/// Accessibility levels for C# declarations.
enum Accessibility {
  public,
  internal,
  protected,
  protectedInternal,
  privateProtected,
  private,
}

/// Attached to declaration nodes with resolved modifier flags.
final class DeclarationModifiers {
  /// The accessibility level of the declaration.
  final Accessibility accessibility;

  final bool isStatic;
  final bool isAbstract;
  final bool isVirtual;
  final bool isOverride;
  final bool isSealed;
  final bool isReadonly;
  final bool isConst;
  final bool isExtern;
  final bool isNew;
  final bool isOperator;
  final bool isConversion;
  final bool isImplicit;
  final bool isExplicit;
  final bool isExtension;
  final bool isIndexer;

  const DeclarationModifiers({
    required this.accessibility,
    this.isStatic = false,
    this.isAbstract = false,
    this.isVirtual = false,
    this.isOverride = false,
    this.isSealed = false,
    this.isReadonly = false,
    this.isConst = false,
    this.isExtern = false,
    this.isNew = false,
    this.isOperator = false,
    this.isConversion = false,
    this.isImplicit = false,
    this.isExplicit = false,
    this.isExtension = false,
    this.isIndexer = false,
  });
}
