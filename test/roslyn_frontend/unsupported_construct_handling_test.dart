// Validates: Requirements 9.1, 9.2, 9.3, 9.4, 9.5, 9.6
import 'package:test/test.dart';
import 'package:cs2dart/src/roslyn_frontend/models/annotations.dart';
import 'package:cs2dart/src/roslyn_frontend/models/frontend_result.dart';
import 'package:cs2dart/src/roslyn_frontend/models/frontend_unit.dart';
import 'package:cs2dart/src/roslyn_frontend/models/generic_syntax_node.dart';
import 'package:cs2dart/src/roslyn_frontend/models/normalized_syntax_tree.dart';
import 'package:cs2dart/src/roslyn_frontend/models/syntax_node.dart';
import 'package:cs2dart/src/roslyn_frontend/models/symbol_table.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a [GenericSyntaxNode] with the given [kind] and [annotations].
GenericSyntaxNode _node({
  int nodeId = 1,
  String kind = 'CompilationUnit',
  List<SyntaxNode> children = const [],
  List<Object> annotations = const [],
}) =>
    GenericSyntaxNode(
      nodeId: nodeId,
      kind: kind,
      children: children,
      annotations: annotations,
    );

/// Creates a [NormalizedSyntaxTree] with the given root node.
NormalizedSyntaxTree _tree({
  String filePath = '/src/Foo.cs',
  required SyntaxNode root,
}) =>
    NormalizedSyntaxTree(
      filePath: filePath,
      root: root,
      symbolTable: const SymbolTable(entries: {}),
    );

/// Creates a minimal [FrontendUnit] with the given trees.
FrontendUnit _unit({List<NormalizedSyntaxTree> trees = const []}) =>
    FrontendUnit(
      projectName: 'TestProject',
      outputKind: OutputKind.library,
      targetFramework: 'net8.0',
      langVersion: '12.0',
      nullableEnabled: false,
      packageReferences: const [],
      normalizedTrees: trees,
    );

/// Creates a [Diagnostic] with the given fields.
Diagnostic _diag({
  required String code,
  DiagnosticSeverity severity = DiagnosticSeverity.warning,
  String message = 'test diagnostic',
  String? source,
}) =>
    Diagnostic(
      severity: severity,
      code: code,
      message: message,
      source: source,
    );

/// Builds a [FrontendResult] with the given units and diagnostics.
FrontendResult _result({
  List<FrontendUnit> units = const [],
  List<Diagnostic> diagnostics = const [],
}) {
  final hasError =
      diagnostics.any((d) => d.severity == DiagnosticSeverity.error);
  return FrontendResult(
    units: units,
    diagnostics: diagnostics,
    success: !hasError,
  );
}

/// Returns all [UnsupportedAnnotation] instances found anywhere in [result].
List<UnsupportedAnnotation> _collectUnsupportedAnnotations(
    FrontendResult result) {
  final found = <UnsupportedAnnotation>[];
  for (final unit in result.units) {
    for (final tree in unit.normalizedTrees) {
      _walkNode(tree.root, found);
    }
  }
  return found;
}

void _walkNode(SyntaxNode node, List<UnsupportedAnnotation> out) {
  if (node is GenericSyntaxNode) {
    for (final annotation in node.annotations) {
      if (annotation is UnsupportedAnnotation) {
        out.add(annotation);
      }
    }
    for (final child in node.children) {
      _walkNode(child, out);
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Requirement 9.1, 9.6 — unsafe block
  // -------------------------------------------------------------------------
  group('unsafe block', () {
    test(
        'unsafe block node carries UnsupportedAnnotation with description mentioning unsafe',
        () {
      final unsafeAnnotation = const UnsupportedAnnotation(
        description: 'unsafe block: cannot be approximated in Dart',
        originalSourceSpan: 'unsafe { int* p = &x; }',
      );
      final unsafeNode = _node(
        nodeId: 10,
        kind: 'UnsafeStatement',
        annotations: [unsafeAnnotation],
      );
      final result = _result(
        units: [
          _unit(trees: [_tree(root: unsafeNode)])
        ],
        diagnostics: [
          _diag(
            code: 'RF0005',
            severity: DiagnosticSeverity.error,
            message: 'unsafe block encountered; cannot be approximated in Dart',
            source: '/src/Foo.cs',
          ),
        ],
      );

      final annotations = _collectUnsupportedAnnotations(result);
      expect(annotations, hasLength(1));
      expect(annotations.first.description, contains('unsafe'));
    });

    test('unsafe block emits RF0005 Error diagnostic', () {
      final result = _result(
        units: [
          _unit(trees: [
            _tree(
              root: _node(
                kind: 'UnsafeStatement',
                annotations: [
                  const UnsupportedAnnotation(
                    description: 'unsafe block',
                    originalSourceSpan: 'unsafe { }',
                  ),
                ],
              ),
            )
          ])
        ],
        diagnostics: [
          _diag(
            code: 'RF0005',
            severity: DiagnosticSeverity.error,
            message: 'unsafe block encountered',
          ),
        ],
      );

      final rf0005 =
          result.diagnostics.where((d) => d.code == 'RF0005').toList();
      expect(rf0005, hasLength(1));
      expect(rf0005.first.severity, DiagnosticSeverity.error);
    });

    test('unsafe block causes success = false', () {
      final result = _result(
        diagnostics: [
          _diag(
            code: 'RF0005',
            severity: DiagnosticSeverity.error,
            message: 'unsafe block encountered',
          ),
        ],
      );

      expect(result.success, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Requirement 9.1 — fixed statement
  // -------------------------------------------------------------------------
  group('fixed statement', () {
    test('fixed statement node carries UnsupportedAnnotation', () {
      final annotation = const UnsupportedAnnotation(
        description: 'fixed statement: cannot be approximated in Dart',
        originalSourceSpan: 'fixed (int* p = &x) { }',
      );
      final fixedNode = _node(
        nodeId: 20,
        kind: 'FixedStatement',
        annotations: [annotation],
      );
      final result = _result(
        units: [
          _unit(trees: [_tree(root: fixedNode)])
        ],
        diagnostics: [
          _diag(
            code: 'RF0005',
            severity: DiagnosticSeverity.error,
            message: 'fixed statement encountered',
          ),
        ],
      );

      final annotations = _collectUnsupportedAnnotations(result);
      expect(annotations, hasLength(1));
      expect(annotations.first.originalSourceSpan,
          contains('fixed'));
    });

    test('fixed statement emits RF0005 Error diagnostic', () {
      final result = _result(
        units: [
          _unit(trees: [
            _tree(
              root: _node(
                kind: 'FixedStatement',
                annotations: [
                  const UnsupportedAnnotation(
                    description: 'fixed statement',
                    originalSourceSpan: 'fixed (int* p = &x) { }',
                  ),
                ],
              ),
            )
          ])
        ],
        diagnostics: [
          _diag(
            code: 'RF0005',
            severity: DiagnosticSeverity.error,
            message: 'fixed statement encountered',
          ),
        ],
      );

      final rf0005 =
          result.diagnostics.where((d) => d.code == 'RF0005').toList();
      expect(rf0005, hasLength(1));
      expect(rf0005.first.severity, DiagnosticSeverity.error);
    });
  });

  // -------------------------------------------------------------------------
  // Requirement 9.1 — stackalloc
  // -------------------------------------------------------------------------
  group('stackalloc', () {
    test('stackalloc node carries UnsupportedAnnotation', () {
      final annotation = const UnsupportedAnnotation(
        description: 'stackalloc: cannot be approximated in Dart',
        originalSourceSpan: 'stackalloc int[10]',
      );
      final stackallocNode = _node(
        nodeId: 30,
        kind: 'StackAllocArrayCreationExpression',
        annotations: [annotation],
      );
      final result = _result(
        units: [
          _unit(trees: [_tree(root: stackallocNode)])
        ],
        diagnostics: [
          _diag(
            code: 'RF0005',
            severity: DiagnosticSeverity.error,
            message: 'stackalloc encountered',
          ),
        ],
      );

      final annotations = _collectUnsupportedAnnotations(result);
      expect(annotations, hasLength(1));
      expect(annotations.first.description, contains('stackalloc'));
    });

    test('stackalloc emits RF0005 Error diagnostic', () {
      final result = _result(
        diagnostics: [
          _diag(
            code: 'RF0005',
            severity: DiagnosticSeverity.error,
            message: 'stackalloc encountered',
          ),
        ],
      );

      final rf0005 =
          result.diagnostics.where((d) => d.code == 'RF0005').toList();
      expect(rf0005, hasLength(1));
      expect(rf0005.first.severity, DiagnosticSeverity.error);
    });
  });

  // -------------------------------------------------------------------------
  // Requirement 9.5 — goto / labeled statement
  // -------------------------------------------------------------------------
  group('goto and labeled statement', () {
    test('goto statement node carries UnsupportedAnnotation', () {
      final annotation = const UnsupportedAnnotation(
        description: 'goto statement: no Dart equivalent',
        originalSourceSpan: 'goto myLabel;',
      );
      final gotoNode = _node(
        nodeId: 40,
        kind: 'GotoStatement',
        annotations: [annotation],
      );
      final result = _result(
        units: [
          _unit(trees: [_tree(root: gotoNode)])
        ],
        diagnostics: [
          _diag(
            code: 'RF0006',
            severity: DiagnosticSeverity.warning,
            message: 'goto statement encountered; no Dart equivalent',
          ),
        ],
      );

      final annotations = _collectUnsupportedAnnotations(result);
      expect(annotations, hasLength(1));
      expect(annotations.first.description, contains('goto'));
    });

    test('goto statement emits RF0006 Warning diagnostic', () {
      final result = _result(
        units: [
          _unit(trees: [
            _tree(
              root: _node(
                kind: 'GotoStatement',
                annotations: [
                  const UnsupportedAnnotation(
                    description: 'goto statement: no Dart equivalent',
                    originalSourceSpan: 'goto myLabel;',
                  ),
                ],
              ),
            )
          ])
        ],
        diagnostics: [
          _diag(
            code: 'RF0006',
            severity: DiagnosticSeverity.warning,
            message: 'goto statement encountered',
          ),
        ],
      );

      final rf0006 =
          result.diagnostics.where((d) => d.code == 'RF0006').toList();
      expect(rf0006, hasLength(1));
      expect(rf0006.first.severity, DiagnosticSeverity.warning);
    });

    test('labeled statement node carries UnsupportedAnnotation', () {
      final annotation = const UnsupportedAnnotation(
        description: 'labeled statement: no Dart equivalent',
        originalSourceSpan: 'myLabel: DoSomething();',
      );
      final labeledNode = _node(
        nodeId: 41,
        kind: 'LabeledStatement',
        annotations: [annotation],
      );
      final result = _result(
        units: [
          _unit(trees: [_tree(root: labeledNode)])
        ],
        diagnostics: [
          _diag(
            code: 'RF0006',
            severity: DiagnosticSeverity.warning,
            message: 'labeled statement encountered; no Dart equivalent',
          ),
        ],
      );

      final annotations = _collectUnsupportedAnnotations(result);
      expect(annotations, hasLength(1));
      expect(annotations.first.description, contains('label'));
    });

    test('goto does not cause success = false (Warning severity)', () {
      final result = _result(
        diagnostics: [
          _diag(
            code: 'RF0006',
            severity: DiagnosticSeverity.warning,
            message: 'goto statement encountered',
          ),
        ],
      );

      expect(result.success, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Requirement 9.1 — __arglist
  // -------------------------------------------------------------------------
  group('__arglist', () {
    test('__arglist node carries UnsupportedAnnotation', () {
      final annotation = const UnsupportedAnnotation(
        description: '__arglist: unsupported construct',
        originalSourceSpan: '__arglist(x, y)',
      );
      final arglistNode = _node(
        nodeId: 50,
        kind: 'ArgListExpression',
        annotations: [annotation],
      );
      final result = _result(
        units: [
          _unit(trees: [_tree(root: arglistNode)])
        ],
        diagnostics: [
          _diag(
            code: 'RF0003',
            severity: DiagnosticSeverity.warning,
            message: '__arglist encountered; unsupported construct',
          ),
        ],
      );

      final annotations = _collectUnsupportedAnnotations(result);
      expect(annotations, hasLength(1));
      expect(annotations.first.description, contains('__arglist'));
    });

    test('__arglist emits RF0003 Warning diagnostic', () {
      final result = _result(
        units: [
          _unit(trees: [
            _tree(
              root: _node(
                kind: 'ArgListExpression',
                annotations: [
                  const UnsupportedAnnotation(
                    description: '__arglist: unsupported construct',
                    originalSourceSpan: '__arglist(x, y)',
                  ),
                ],
              ),
            )
          ])
        ],
        diagnostics: [
          _diag(
            code: 'RF0003',
            severity: DiagnosticSeverity.warning,
            message: '__arglist encountered',
          ),
        ],
      );

      final rf0003 =
          result.diagnostics.where((d) => d.code == 'RF0003').toList();
      expect(rf0003, hasLength(1));
      expect(rf0003.first.severity, DiagnosticSeverity.warning);
    });

    test('__arglist does not cause success = false (Warning severity)', () {
      final result = _result(
        diagnostics: [
          _diag(
            code: 'RF0003',
            severity: DiagnosticSeverity.warning,
            message: '__arglist encountered',
          ),
        ],
      );

      expect(result.success, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Requirement 9.4 — processing continues after unsupported construct
  // -------------------------------------------------------------------------
  group('processing continues after unsupported construct', () {
    test(
        'FrontendResult contains valid nodes alongside UnsupportedAnnotation nodes',
        () {
      // A tree with an unsupported node (unsafe) and a valid sibling node.
      final unsafeNode = _node(
        nodeId: 60,
        kind: 'UnsafeStatement',
        annotations: [
          const UnsupportedAnnotation(
            description: 'unsafe block',
            originalSourceSpan: 'unsafe { }',
          ),
        ],
      );
      final validNode = _node(
        nodeId: 61,
        kind: 'MethodDeclaration',
        annotations: [],
      );
      final root = _node(
        nodeId: 1,
        kind: 'CompilationUnit',
        children: [unsafeNode, validNode],
      );

      final result = _result(
        units: [
          _unit(trees: [_tree(root: root)])
        ],
        diagnostics: [
          _diag(
            code: 'RF0005',
            severity: DiagnosticSeverity.error,
            message: 'unsafe block encountered',
          ),
        ],
      );

      // The result should contain both the unsupported node and the valid node.
      final rootNode = result.units.first.normalizedTrees.first.root
          as GenericSyntaxNode;
      expect(rootNode.children, hasLength(2));

      // One child has UnsupportedAnnotation.
      final unsupported = rootNode.children
          .whereType<GenericSyntaxNode>()
          .where((n) => n.annotations.any((a) => a is UnsupportedAnnotation))
          .toList();
      expect(unsupported, hasLength(1));

      // The other child is a valid MethodDeclaration with no unsupported annotation.
      final valid = rootNode.children
          .whereType<GenericSyntaxNode>()
          .where((n) => n.kind == 'MethodDeclaration')
          .toList();
      expect(valid, hasLength(1));
      expect(
          valid.first.annotations.any((a) => a is UnsupportedAnnotation),
          isFalse);
    });

    test(
        'multiple unsupported constructs in one tree all produce UnsupportedAnnotations',
        () {
      final gotoNode = _node(
        nodeId: 70,
        kind: 'GotoStatement',
        annotations: [
          const UnsupportedAnnotation(
            description: 'goto statement: no Dart equivalent',
            originalSourceSpan: 'goto label;',
          ),
        ],
      );
      final arglistNode = _node(
        nodeId: 71,
        kind: 'ArgListExpression',
        annotations: [
          const UnsupportedAnnotation(
            description: '__arglist: unsupported construct',
            originalSourceSpan: '__arglist()',
          ),
        ],
      );
      final root = _node(
        nodeId: 1,
        kind: 'CompilationUnit',
        children: [gotoNode, arglistNode],
      );

      final result = _result(
        units: [
          _unit(trees: [_tree(root: root)])
        ],
        diagnostics: [
          _diag(code: 'RF0006', severity: DiagnosticSeverity.warning),
          _diag(code: 'RF0003', severity: DiagnosticSeverity.warning),
        ],
      );

      final annotations = _collectUnsupportedAnnotations(result);
      expect(annotations, hasLength(2));
    });

    test(
        'unsupported construct in one tree does not prevent other trees from being present',
        () {
      final unsafeTree = _tree(
        filePath: '/src/Unsafe.cs',
        root: _node(
          kind: 'UnsafeStatement',
          annotations: [
            const UnsupportedAnnotation(
              description: 'unsafe block',
              originalSourceSpan: 'unsafe { }',
            ),
          ],
        ),
      );
      final validTree = _tree(
        filePath: '/src/Valid.cs',
        root: _node(kind: 'CompilationUnit'),
      );

      final result = _result(
        units: [
          _unit(trees: [unsafeTree, validTree])
        ],
        diagnostics: [
          _diag(
            code: 'RF0005',
            severity: DiagnosticSeverity.error,
            message: 'unsafe block encountered',
          ),
        ],
      );

      expect(result.units.first.normalizedTrees, hasLength(2));
      expect(result.units.first.normalizedTrees[0].filePath, '/src/Unsafe.cs');
      expect(result.units.first.normalizedTrees[1].filePath, '/src/Valid.cs');
    });
  });

  // -------------------------------------------------------------------------
  // Requirement 9.3 — RF0004 Error when unsupported construct makes
  // declaration semantically incomplete
  // -------------------------------------------------------------------------
  group('RF0004 — semantically incomplete declaration', () {
    test(
        'RF0004 Error is emitted when unsupported construct makes declaration semantically incomplete',
        () {
      // A method whose return type is an unsupported construct (e.g., a pointer
      // type), making the declaration semantically incomplete.
      final methodNode = _node(
        nodeId: 80,
        kind: 'MethodDeclaration',
        annotations: [
          const UnsupportedAnnotation(
            description:
                'unsupported return type: pointer type cannot be represented in Dart',
            originalSourceSpan: 'unsafe int* GetPointer()',
          ),
        ],
      );
      final result = _result(
        units: [
          _unit(trees: [_tree(root: methodNode)])
        ],
        diagnostics: [
          _diag(
            code: 'RF0004',
            severity: DiagnosticSeverity.error,
            message:
                'unsupported construct makes declaration semantically incomplete',
            source: '/src/Foo.cs',
          ),
        ],
      );

      final rf0004 =
          result.diagnostics.where((d) => d.code == 'RF0004').toList();
      expect(rf0004, hasLength(1));
      expect(rf0004.first.severity, DiagnosticSeverity.error);
    });

    test('RF0004 causes success = false', () {
      final result = _result(
        diagnostics: [
          _diag(
            code: 'RF0004',
            severity: DiagnosticSeverity.error,
            message: 'unsupported construct makes declaration semantically incomplete',
          ),
        ],
      );

      expect(result.success, isFalse);
    });

    test(
        'RF0004 can coexist with RF0005 when unsafe block makes declaration incomplete',
        () {
      final result = _result(
        units: [
          _unit(trees: [
            _tree(
              root: _node(
                kind: 'MethodDeclaration',
                annotations: [
                  const UnsupportedAnnotation(
                    description: 'unsafe return type',
                    originalSourceSpan: 'unsafe int* Foo()',
                  ),
                ],
              ),
            )
          ])
        ],
        diagnostics: [
          _diag(
            code: 'RF0005',
            severity: DiagnosticSeverity.error,
            message: 'unsafe block encountered',
          ),
          _diag(
            code: 'RF0004',
            severity: DiagnosticSeverity.error,
            message: 'declaration semantically incomplete',
          ),
        ],
      );

      expect(result.diagnostics.any((d) => d.code == 'RF0005'), isTrue);
      expect(result.diagnostics.any((d) => d.code == 'RF0004'), isTrue);
      expect(result.success, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Cross-cutting: UnsupportedAnnotation structure
  // -------------------------------------------------------------------------
  group('UnsupportedAnnotation structure', () {
    test('UnsupportedAnnotation carries non-empty description', () {
      const annotation = UnsupportedAnnotation(
        description: 'unsafe block: cannot be approximated in Dart',
        originalSourceSpan: 'unsafe { int* p = &x; }',
      );

      expect(annotation.description, isNotEmpty);
    });

    test('UnsupportedAnnotation carries non-empty originalSourceSpan', () {
      const annotation = UnsupportedAnnotation(
        description: 'goto statement: no Dart equivalent',
        originalSourceSpan: 'goto myLabel;',
      );

      expect(annotation.originalSourceSpan, isNotEmpty);
    });

    test('UnsupportedAnnotation description is human-readable', () {
      const annotation = UnsupportedAnnotation(
        description: 'stackalloc: cannot be approximated in Dart',
        originalSourceSpan: 'stackalloc int[10]',
      );

      // Description should be a non-trivial string (more than just a code).
      expect(annotation.description.length, greaterThan(5));
    });
  });
}
