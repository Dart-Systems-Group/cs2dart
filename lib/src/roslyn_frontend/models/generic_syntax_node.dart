import 'syntax_node.dart';

/// A concrete [SyntaxNode] implementation used during deserialization.
///
/// The .NET worker sends syntax nodes as JSON objects with `nodeId`, `kind`,
/// `children`, and `annotations` fields. Since [SyntaxNode] is abstract,
/// this class provides a concrete representation that holds all the data
/// received from the worker without depending on any Roslyn types.
final class GenericSyntaxNode extends SyntaxNode {
  /// The kind name of this node, e.g. "CompilationUnit", "MethodDeclaration".
  final String kind;

  /// The child nodes of this node, in source order.
  final List<SyntaxNode> children;

  /// The structured annotation objects attached to this node.
  ///
  /// Each element is one of the annotation types defined in `annotations.dart`
  /// (e.g. [AsyncAnnotation], [ForeachAnnotation], [DeclarationModifiers]),
  /// or any other plain-data annotation object.
  final List<Object> annotations;

  const GenericSyntaxNode({
    required super.nodeId,
    required this.kind,
    required this.children,
    required this.annotations,
  });
}
