
// IR node hierarchy — all sealed base classes and their concrete subclasses
// must live in the same Dart library to satisfy the sealed class constraint.
//
// This file defines:
//   - IrNode (sealed base)
//   - IrDeclarationNode (sealed) + all declaration subtypes
//   - IrStatementNode (sealed) + all statement subtypes
//   - IrExpressionNode (sealed) + all expression subtypes
//   - PatternNode (sealed) + all pattern subtypes
//   - IrSymbol, NamedArgument, ParameterInfo, and helper types
//   - UnsupportedNode, UnresolvedSymbol placeholder nodes

import '../../config/models/source_location.dart';
import '../../project_loader/models/diagnostic.dart';
import 'ir_enums.dart';
import 'ir_type.dart';

export '../../config/models/source_location.dart';
export '../../project_loader/models/diagnostic.dart';
export 'ir_enums.dart';
export 'ir_type.dart';

// =============================================================================
// IrSymbol
// =============================================================================

/// A stable, fully-qualified identifier for a named entity in the IR.
final class IrSymbol {
  final String fullyQualifiedName;
  final String assemblyName;
  final SymbolKind kind;
  final SourceLocation? sourceLocation;
  final String? sourcePackageId;

  /// Non-null when the symbol refers to a type within the compilation unit.
  final IrDeclarationNode? declarationNode;

  const IrSymbol({
    required this.fullyQualifiedName,
    required this.assemblyName,
    required this.kind,
    this.sourceLocation,
    this.sourcePackageId,
    this.declarationNode,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IrSymbol &&
          fullyQualifiedName == other.fullyQualifiedName &&
          assemblyName == other.assemblyName &&
          kind == other.kind &&
          sourceLocation == other.sourceLocation &&
          sourcePackageId == other.sourcePackageId;

  @override
  int get hashCode => Object.hash(
        fullyQualifiedName,
        assemblyName,
        kind,
        sourceLocation,
        sourcePackageId,
      );

  @override
  String toString() => 'IrSymbol($fullyQualifiedName, $kind)';
}

// =============================================================================
// Base node classes (sealed)
// =============================================================================

/// The common base for every IR node in the tree.
sealed class IrNode {
  final SourceLocation? sourceLocation;
  const IrNode({this.sourceLocation});
}

/// Base class for all declaration IR nodes.
sealed class IrDeclarationNode extends IrNode {
  const IrDeclarationNode({super.sourceLocation});
}

/// Base class for all statement IR nodes.
sealed class IrStatementNode extends IrNode {
  const IrStatementNode({super.sourceLocation});
}

/// Base class for all expression IR nodes.
///
/// Every expression carries a resolved [IrType]. Non-null after IR_Builder.
sealed class IrExpressionNode extends IrNode {
  final IrType type;
  const IrExpressionNode({required this.type, super.sourceLocation});
}

// =============================================================================
// Helper types
// =============================================================================

/// A named argument in an attribute application, e.g. `Name = "value"`.
final class NamedArgument {
  final String name;
  final IrExpressionNode value;
  const NamedArgument({required this.name, required this.value});
}

/// A parameter in a lambda expression.
final class ParameterInfo {
  final String name;
  final IrType? type;
  const ParameterInfo({required this.name, this.type});
}

/// A single element in a tuple expression.
final class TupleElementExpression {
  final String? name;
  final IrExpressionNode value;
  const TupleElementExpression({this.name, required this.value});
}

/// A member of an anonymous object creation.
final class AnonymousObjectMember {
  final String name;
  final IrExpressionNode value;
  const AnonymousObjectMember({required this.name, required this.value});
}

/// A single arm in a switch expression.
final class SwitchExpressionArm {
  final PatternNode pattern;
  final IrExpressionNode? whenExpression;
  final IrExpressionNode result;
  const SwitchExpressionArm({
    required this.pattern,
    this.whenExpression,
    required this.result,
  });
}

/// A part of an interpolated string.
sealed class InterpolatedStringPart {
  const InterpolatedStringPart();
}

final class InterpolatedStringText extends InterpolatedStringPart {
  final String text;
  const InterpolatedStringText({required this.text});
}

final class InterpolatedStringExpression extends InterpolatedStringPart {
  final IrExpressionNode expression;
  final String? format;
  const InterpolatedStringExpression({required this.expression, this.format});
}

// =============================================================================
// Type parameter constraints
// =============================================================================

sealed class TypeParameterConstraint {
  const TypeParameterConstraint();
}

final class ReferenceTypeConstraint extends TypeParameterConstraint {
  const ReferenceTypeConstraint();
}

final class ValueTypeConstraint extends TypeParameterConstraint {
  const ValueTypeConstraint();
}

final class DefaultConstructorConstraint extends TypeParameterConstraint {
  const DefaultConstructorConstraint();
}

final class BaseTypeConstraint extends TypeParameterConstraint {
  final IrType baseType;
  const BaseTypeConstraint({required this.baseType});
}

final class NotNullConstraint extends TypeParameterConstraint {
  const NotNullConstraint();
}

// =============================================================================
// Pattern nodes (sealed)
// =============================================================================

sealed class PatternNode {
  const PatternNode();
}

final class TypePatternNode extends PatternNode {
  final IrType type;
  final String? variableName;
  const TypePatternNode({required this.type, this.variableName});
}

final class ConstantPatternNode extends PatternNode {
  final IrExpressionNode value;
  const ConstantPatternNode({required this.value});
}

final class PropertySubPattern {
  final String propertyName;
  final PatternNode pattern;
  const PropertySubPattern({required this.propertyName, required this.pattern});
}

final class PropertyPatternNode extends PatternNode {
  final IrType? type;
  final List<PropertySubPattern> subPatterns;
  final String? variableName;
  const PropertyPatternNode({
    this.type,
    required this.subPatterns,
    this.variableName,
  });
}

final class PositionalPatternNode extends PatternNode {
  final IrType? type;
  final List<PatternNode> subPatterns;
  final String? variableName;
  const PositionalPatternNode({
    this.type,
    required this.subPatterns,
    this.variableName,
  });
}

final class DiscardPatternNode extends PatternNode {
  const DiscardPatternNode();
}

final class VarPatternNode extends PatternNode {
  final String variableName;
  const VarPatternNode({required this.variableName});
}

final class RelationalPatternNode extends PatternNode {
  final String operator;
  final IrExpressionNode value;
  const RelationalPatternNode({required this.operator, required this.value});
}

final class LogicalPatternNode extends PatternNode {
  final String operator; // "and", "or", "not"
  final List<PatternNode> operands;
  const LogicalPatternNode({required this.operator, required this.operands});
}

// =============================================================================
// Declaration nodes
// =============================================================================

final class CompilationUnitNode extends IrDeclarationNode {
  final List<AttributeNode> assemblyAttributes;
  final List<AttributeNode> moduleAttributes;
  final List<IrDeclarationNode> members;
  const CompilationUnitNode({
    required this.assemblyAttributes,
    required this.moduleAttributes,
    required this.members,
    super.sourceLocation,
  });
}

final class NamespaceNode extends IrDeclarationNode {
  final String name;
  final List<IrDeclarationNode> members;
  const NamespaceNode({
    required this.name,
    required this.members,
    super.sourceLocation,
  });
}

final class ClassNode extends IrDeclarationNode {
  final String name;
  final Accessibility accessibility;
  final bool isStatic;
  final bool isAbstract;
  final bool isSealed;
  final bool isPartial;
  final IrType? baseClass;
  final List<IrType> implementedInterfaces;
  final List<TypeParameterNode> typeParameters;
  final List<AttributeNode> attributes;
  final List<IrDeclarationNode> members;
  const ClassNode({
    required this.name,
    required this.accessibility,
    this.isStatic = false,
    this.isAbstract = false,
    this.isSealed = false,
    this.isPartial = false,
    this.baseClass,
    this.implementedInterfaces = const [],
    this.typeParameters = const [],
    this.attributes = const [],
    required this.members,
    super.sourceLocation,
  });
}

final class StructNode extends IrDeclarationNode {
  final String name;
  final Accessibility accessibility;
  final bool isReadonly;
  final bool isPartial;
  final List<IrType> implementedInterfaces;
  final List<TypeParameterNode> typeParameters;
  final List<AttributeNode> attributes;
  final List<IrDeclarationNode> members;
  const StructNode({
    required this.name,
    required this.accessibility,
    this.isReadonly = false,
    this.isPartial = false,
    this.implementedInterfaces = const [],
    this.typeParameters = const [],
    this.attributes = const [],
    required this.members,
    super.sourceLocation,
  });
}

final class InterfaceNode extends IrDeclarationNode {
  final String name;
  final Accessibility accessibility;
  final bool isPartial;
  final List<IrType> implementedInterfaces;
  final List<TypeParameterNode> typeParameters;
  final List<AttributeNode> attributes;
  final List<IrDeclarationNode> members;
  const InterfaceNode({
    required this.name,
    required this.accessibility,
    this.isPartial = false,
    this.implementedInterfaces = const [],
    this.typeParameters = const [],
    this.attributes = const [],
    required this.members,
    super.sourceLocation,
  });
}

final class EnumNode extends IrDeclarationNode {
  final String name;
  final Accessibility accessibility;
  final IrType? underlyingType;
  final List<AttributeNode> attributes;
  final List<EnumMemberNode> members;
  const EnumNode({
    required this.name,
    required this.accessibility,
    this.underlyingType,
    this.attributes = const [],
    required this.members,
    super.sourceLocation,
  });
}

final class EnumMemberNode extends IrDeclarationNode {
  final String name;
  final Object? constantValue;
  final List<AttributeNode> attributes;
  const EnumMemberNode({
    required this.name,
    this.constantValue,
    this.attributes = const [],
    super.sourceLocation,
  });
}

final class MethodNode extends IrDeclarationNode {
  final String name;
  final Accessibility accessibility;
  final IrType returnType;
  final List<TypeParameterNode> typeParameters;
  final List<ParameterNode> parameters;
  final List<AttributeNode> attributes;
  final IrStatementNode? body;
  final bool isStatic;
  final bool isAbstract;
  final bool isVirtual;
  final bool isOverride;
  final bool isSealed;
  final bool isExtern;
  final bool isAsync;
  final bool isIterator;
  final bool isOperator;
  final bool isConversion;
  final bool isImplicit;
  final bool isExplicit;
  final bool isExtension;
  final bool isIndexer;
  final bool isNew;
  final OperatorKind? operatorKind;
  final IrType? extendedType;
  final IrSymbol? explicitInterface;
  const MethodNode({
    required this.name,
    required this.accessibility,
    required this.returnType,
    this.typeParameters = const [],
    this.parameters = const [],
    this.attributes = const [],
    this.body,
    this.isStatic = false,
    this.isAbstract = false,
    this.isVirtual = false,
    this.isOverride = false,
    this.isSealed = false,
    this.isExtern = false,
    this.isAsync = false,
    this.isIterator = false,
    this.isOperator = false,
    this.isConversion = false,
    this.isImplicit = false,
    this.isExplicit = false,
    this.isExtension = false,
    this.isIndexer = false,
    this.isNew = false,
    this.operatorKind,
    this.extendedType,
    this.explicitInterface,
    super.sourceLocation,
  });
}

final class ConstructorNode extends IrDeclarationNode {
  final String name;
  final Accessibility accessibility;
  final List<ParameterNode> parameters;
  final List<AttributeNode> attributes;
  final IrStatementNode? body;
  final bool isStatic;
  final bool isExtern;
  const ConstructorNode({
    required this.name,
    required this.accessibility,
    this.parameters = const [],
    this.attributes = const [],
    this.body,
    this.isStatic = false,
    this.isExtern = false,
    super.sourceLocation,
  });
}

final class DestructorNode extends IrDeclarationNode {
  final String name;
  final List<AttributeNode> attributes;
  final IrStatementNode? body;
  const DestructorNode({
    required this.name,
    this.attributes = const [],
    this.body,
    super.sourceLocation,
  });
}

final class PropertyNode extends IrDeclarationNode {
  final String name;
  final Accessibility accessibility;
  final IrType type;
  final List<AttributeNode> attributes;
  final MethodNode? getter;
  final MethodNode? setter;
  final FieldNode? backingField;
  final bool isStatic;
  final bool isAbstract;
  final bool isVirtual;
  final bool isOverride;
  final bool isSealed;
  const PropertyNode({
    required this.name,
    required this.accessibility,
    required this.type,
    this.attributes = const [],
    this.getter,
    this.setter,
    this.backingField,
    this.isStatic = false,
    this.isAbstract = false,
    this.isVirtual = false,
    this.isOverride = false,
    this.isSealed = false,
    super.sourceLocation,
  });
}

final class FieldNode extends IrDeclarationNode {
  final String name;
  final Accessibility accessibility;
  final IrType type;
  final List<AttributeNode> attributes;
  final IrExpressionNode? initializer;
  final bool isStatic;
  final bool isReadonly;
  final bool isConst;
  final Object? constantValue;
  const FieldNode({
    required this.name,
    required this.accessibility,
    required this.type,
    this.attributes = const [],
    this.initializer,
    this.isStatic = false,
    this.isReadonly = false,
    this.isConst = false,
    this.constantValue,
    super.sourceLocation,
  });
}

final class EventNode extends IrDeclarationNode {
  final String name;
  final Accessibility accessibility;
  final IrType type;
  final List<AttributeNode> attributes;
  final bool isStatic;
  final bool isAbstract;
  final bool isVirtual;
  final bool isOverride;
  const EventNode({
    required this.name,
    required this.accessibility,
    required this.type,
    this.attributes = const [],
    this.isStatic = false,
    this.isAbstract = false,
    this.isVirtual = false,
    this.isOverride = false,
    super.sourceLocation,
  });
}

final class DelegateNode extends IrDeclarationNode {
  final String name;
  final Accessibility accessibility;
  final IrType returnType;
  final List<TypeParameterNode> typeParameters;
  final List<ParameterNode> parameters;
  final List<AttributeNode> attributes;
  const DelegateNode({
    required this.name,
    required this.accessibility,
    required this.returnType,
    this.typeParameters = const [],
    this.parameters = const [],
    this.attributes = const [],
    super.sourceLocation,
  });
}

final class TypeParameterNode extends IrDeclarationNode {
  final String name;
  final TypeParameterVariance variance;
  final List<TypeParameterConstraint> constraints;
  final List<AttributeNode> attributes;
  const TypeParameterNode({
    required this.name,
    this.variance = TypeParameterVariance.none,
    this.constraints = const [],
    this.attributes = const [],
    super.sourceLocation,
  });
}

final class ParameterNode extends IrDeclarationNode {
  final String name;
  final IrType type;
  final List<AttributeNode> attributes;
  final IrExpressionNode? defaultValue;
  final bool isParams;
  final bool isRef;
  final bool isOut;
  final bool isIn;
  const ParameterNode({
    required this.name,
    required this.type,
    this.attributes = const [],
    this.defaultValue,
    this.isParams = false,
    this.isRef = false,
    this.isOut = false,
    this.isIn = false,
    super.sourceLocation,
  });
}

final class LocalFunctionNode extends IrDeclarationNode {
  final String name;
  final IrType returnType;
  final List<TypeParameterNode> typeParameters;
  final List<ParameterNode> parameters;
  final IrStatementNode? body;
  final bool isStatic;
  final bool isAsync;
  final bool isIterator;
  const LocalFunctionNode({
    required this.name,
    required this.returnType,
    this.typeParameters = const [],
    this.parameters = const [],
    this.body,
    this.isStatic = false,
    this.isAsync = false,
    this.isIterator = false,
    super.sourceLocation,
  });
}

final class AttributeNode extends IrDeclarationNode {
  final String fullyQualifiedName;
  final String shortName;
  final List<IrExpressionNode> positionalArguments;
  final List<NamedArgument> namedArguments;
  final AttributeTarget target;
  const AttributeNode({
    required this.fullyQualifiedName,
    required this.shortName,
    this.positionalArguments = const [],
    this.namedArguments = const [],
    required this.target,
    super.sourceLocation,
  });
}

// =============================================================================
// Statement nodes
// =============================================================================

final class BlockNode extends IrStatementNode {
  final List<IrStatementNode> statements;
  const BlockNode({required this.statements, super.sourceLocation});
}

final class ExpressionStatementNode extends IrStatementNode {
  final IrExpressionNode expression;
  const ExpressionStatementNode({
    required this.expression,
    super.sourceLocation,
  });
}

final class ReturnStatementNode extends IrStatementNode {
  final IrExpressionNode? value;
  const ReturnStatementNode({this.value, super.sourceLocation});
}

final class IfStatementNode extends IrStatementNode {
  final IrExpressionNode condition;
  final IrStatementNode thenBranch;
  final IrStatementNode? elseBranch;
  const IfStatementNode({
    required this.condition,
    required this.thenBranch,
    this.elseBranch,
    super.sourceLocation,
  });
}

final class WhileStatementNode extends IrStatementNode {
  final IrExpressionNode condition;
  final IrStatementNode body;
  const WhileStatementNode({
    required this.condition,
    required this.body,
    super.sourceLocation,
  });
}

final class ForStatementNode extends IrStatementNode {
  final List<IrStatementNode> initializers;
  final IrExpressionNode? condition;
  final List<IrExpressionNode> incrementors;
  final IrStatementNode body;
  const ForStatementNode({
    this.initializers = const [],
    this.condition,
    this.incrementors = const [],
    required this.body,
    super.sourceLocation,
  });
}

final class ForEachStatementNode extends IrStatementNode {
  final String variableName;
  final IrType elementType;
  final IrExpressionNode collection;
  final IrStatementNode body;
  const ForEachStatementNode({
    required this.variableName,
    required this.elementType,
    required this.collection,
    required this.body,
    super.sourceLocation,
  });
}

final class SwitchStatementNode extends IrStatementNode {
  final IrExpressionNode expression;
  final List<SwitchCaseNode> cases;
  const SwitchStatementNode({
    required this.expression,
    required this.cases,
    super.sourceLocation,
  });
}

final class SwitchCaseNode extends IrStatementNode {
  final IrExpressionNode? label;
  final PatternNode? pattern;
  final List<IrStatementNode> body;
  const SwitchCaseNode({
    this.label,
    this.pattern,
    required this.body,
    super.sourceLocation,
  });
}

final class BreakStatementNode extends IrStatementNode {
  const BreakStatementNode({super.sourceLocation});
}

final class ContinueStatementNode extends IrStatementNode {
  const ContinueStatementNode({super.sourceLocation});
}

final class ThrowStatementNode extends IrStatementNode {
  final IrExpressionNode? thrownExpression;
  final bool isRethrow;
  const ThrowStatementNode({
    this.thrownExpression,
    this.isRethrow = false,
    super.sourceLocation,
  });
}

final class TryCatchStatementNode extends IrStatementNode {
  final IrStatementNode body;
  final List<CatchClauseNode> catchClauses;
  final FinallyClauseNode? finallyClause;
  const TryCatchStatementNode({
    required this.body,
    this.catchClauses = const [],
    this.finallyClause,
    super.sourceLocation,
  });
}

final class CatchClauseNode extends IrStatementNode {
  final IrType? exceptionType;
  final IrSymbol? exceptionVariable;
  final String? exceptionVariableName;
  final IrExpressionNode? whenExpression;
  final IrStatementNode body;
  const CatchClauseNode({
    this.exceptionType,
    this.exceptionVariable,
    this.exceptionVariableName,
    this.whenExpression,
    required this.body,
    super.sourceLocation,
  });
}

final class FinallyClauseNode extends IrStatementNode {
  final IrStatementNode body;
  const FinallyClauseNode({required this.body, super.sourceLocation});
}

final class LocalDeclarationNode extends IrStatementNode {
  final String variableName;
  final IrType type;
  final IrExpressionNode? initializer;
  final bool isConst;
  final bool isVar;
  const LocalDeclarationNode({
    required this.variableName,
    required this.type,
    this.initializer,
    this.isConst = false,
    this.isVar = false,
    super.sourceLocation,
  });
}

final class YieldReturnStatementNode extends IrStatementNode {
  final IrExpressionNode value;
  const YieldReturnStatementNode({required this.value, super.sourceLocation});
}

final class YieldBreakStatementNode extends IrStatementNode {
  const YieldBreakStatementNode({super.sourceLocation});
}

// =============================================================================
// Expression nodes
// =============================================================================

final class LiteralNode extends IrExpressionNode {
  final Object? value;
  const LiteralNode({required super.type, this.value, super.sourceLocation});
}

final class IdentifierNode extends IrExpressionNode {
  final String name;
  final IrSymbol? irSymbol;
  const IdentifierNode({
    required super.type,
    required this.name,
    this.irSymbol,
    super.sourceLocation,
  });
}

final class BinaryExpressionNode extends IrExpressionNode {
  final IrExpressionNode left;
  final String operator;
  final IrExpressionNode right;
  final bool overflowCheck;
  const BinaryExpressionNode({
    required super.type,
    required this.left,
    required this.operator,
    required this.right,
    this.overflowCheck = false,
    super.sourceLocation,
  });
}

final class UnaryExpressionNode extends IrExpressionNode {
  final String operator;
  final IrExpressionNode operand;
  final bool isPrefix;
  const UnaryExpressionNode({
    required super.type,
    required this.operator,
    required this.operand,
    this.isPrefix = true,
    super.sourceLocation,
  });
}

final class AssignmentExpressionNode extends IrExpressionNode {
  final IrExpressionNode target;
  final String operator;
  final IrExpressionNode value;
  const AssignmentExpressionNode({
    required super.type,
    required this.target,
    required this.operator,
    required this.value,
    super.sourceLocation,
  });
}

final class ConditionalExpressionNode extends IrExpressionNode {
  final IrExpressionNode condition;
  final IrExpressionNode thenExpression;
  final IrExpressionNode elseExpression;
  const ConditionalExpressionNode({
    required super.type,
    required this.condition,
    required this.thenExpression,
    required this.elseExpression,
    super.sourceLocation,
  });
}

final class InvocationExpressionNode extends IrExpressionNode {
  final IrExpressionNode target;
  final List<IrExpressionNode> arguments;
  final IrSymbol? irSymbol;
  final bool isFireAndForget;
  const InvocationExpressionNode({
    required super.type,
    required this.target,
    this.arguments = const [],
    this.irSymbol,
    this.isFireAndForget = false,
    super.sourceLocation,
  });
}

final class MemberAccessExpressionNode extends IrExpressionNode {
  final IrExpressionNode target;
  final String memberName;
  final IrSymbol? irSymbol;
  const MemberAccessExpressionNode({
    required super.type,
    required this.target,
    required this.memberName,
    this.irSymbol,
    super.sourceLocation,
  });
}

final class ElementAccessExpressionNode extends IrExpressionNode {
  final IrExpressionNode target;
  final List<IrExpressionNode> arguments;
  const ElementAccessExpressionNode({
    required super.type,
    required this.target,
    required this.arguments,
    super.sourceLocation,
  });
}

final class ObjectCreationExpressionNode extends IrExpressionNode {
  final IrType createdType;
  final List<IrExpressionNode> arguments;
  final IrSymbol? irSymbol;
  final List<AssignmentExpressionNode> initializers;
  const ObjectCreationExpressionNode({
    required super.type,
    required this.createdType,
    this.arguments = const [],
    this.irSymbol,
    this.initializers = const [],
    super.sourceLocation,
  });
}

final class ArrayCreationExpressionNode extends IrExpressionNode {
  final IrType elementType;
  final List<IrExpressionNode> sizes;
  final List<IrExpressionNode> initializers;
  const ArrayCreationExpressionNode({
    required super.type,
    required this.elementType,
    this.sizes = const [],
    this.initializers = const [],
    super.sourceLocation,
  });
}

final class CastExpressionNode extends IrExpressionNode {
  final IrType targetType;
  final IrExpressionNode operand;
  const CastExpressionNode({
    required super.type,
    required this.targetType,
    required this.operand,
    super.sourceLocation,
  });
}

final class IsExpressionNode extends IrExpressionNode {
  final IrExpressionNode operand;
  final IrType checkedType;
  final PatternNode? pattern;
  const IsExpressionNode({
    required super.type,
    required this.operand,
    required this.checkedType,
    this.pattern,
    super.sourceLocation,
  });
}

final class AsExpressionNode extends IrExpressionNode {
  final IrExpressionNode operand;
  final IrType targetType;
  const AsExpressionNode({
    required super.type,
    required this.operand,
    required this.targetType,
    super.sourceLocation,
  });
}

final class LambdaExpressionNode extends IrExpressionNode {
  final List<ParameterInfo> parameters;
  final IrNode body;
  final bool isAsync;
  const LambdaExpressionNode({
    required super.type,
    required this.parameters,
    required this.body,
    this.isAsync = false,
    super.sourceLocation,
  });
}

final class AnonymousObjectCreationNode extends IrExpressionNode {
  final List<AnonymousObjectMember> members;
  const AnonymousObjectCreationNode({
    required super.type,
    required this.members,
    super.sourceLocation,
  });
}

final class TupleExpressionNode extends IrExpressionNode {
  final List<TupleElementExpression> elements;
  const TupleExpressionNode({
    required super.type,
    required this.elements,
    super.sourceLocation,
  });
}

final class SwitchExpressionNode extends IrExpressionNode {
  final IrExpressionNode expression;
  final List<SwitchExpressionArm> arms;
  const SwitchExpressionNode({
    required super.type,
    required this.expression,
    required this.arms,
    super.sourceLocation,
  });
}

final class ThrowExpressionNode extends IrExpressionNode {
  final IrExpressionNode thrownExpression;
  const ThrowExpressionNode({
    required super.type,
    required this.thrownExpression,
    super.sourceLocation,
  });
}

final class AwaitExpressionNode extends IrExpressionNode {
  final IrExpressionNode operand;
  final bool configureAwait;
  const AwaitExpressionNode({
    required super.type,
    required this.operand,
    this.configureAwait = true,
    super.sourceLocation,
  });
}

final class InterpolatedStringNode extends IrExpressionNode {
  final List<InterpolatedStringPart> parts;
  const InterpolatedStringNode({
    required super.type,
    required this.parts,
    super.sourceLocation,
  });
}

final class NullCoalescingExpressionNode extends IrExpressionNode {
  final IrExpressionNode left;
  final IrExpressionNode right;
  const NullCoalescingExpressionNode({
    required super.type,
    required this.left,
    required this.right,
    super.sourceLocation,
  });
}

final class NullConditionalExpressionNode extends IrExpressionNode {
  final IrExpressionNode operand;
  final IrExpressionNode access;
  const NullConditionalExpressionNode({
    required super.type,
    required this.operand,
    required this.access,
    super.sourceLocation,
  });
}

// =============================================================================
// Placeholder nodes
// =============================================================================

/// A placeholder node for C# constructs that have no corresponding IR node
/// subtype, or that are explicitly unsupported (e.g., `goto`, `unsafe`).
///
/// Emits an IR-prefixed Error diagnostic and continues processing.
final class UnsupportedNode extends IrNode {
  final String description;
  final SourceLocation sourceSpan;
  final Diagnostic diagnostic;
  const UnsupportedNode({
    required this.description,
    required this.sourceSpan,
    required this.diagnostic,
    super.sourceLocation,
  });
}

/// A placeholder expression node for identifiers that could not be resolved
/// by the Roslyn_Frontend (i.e., `SymbolKind.unresolved`).
///
/// Emits an IR0020 Warning diagnostic and continues processing.
final class UnresolvedSymbol extends IrExpressionNode {
  final String originalText;
  final SourceLocation sourceSpan;
  const UnresolvedSymbol({
    required this.originalText,
    required this.sourceSpan,
    super.sourceLocation,
  }) : super(type: const UnresolvedType());
}
