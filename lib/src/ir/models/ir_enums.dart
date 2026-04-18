/// Accessibility levels for C# declarations.
enum Accessibility {
  public,
  internal,
  protected,
  private,
  protectedInternal,
  privateProtected,
}

/// The kind of a named symbol.
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

/// The syntactic target to which a C# attribute is applied.
enum AttributeTarget {
  classTarget,
  structTarget,
  interfaceTarget,
  enumTarget,
  enumMember,
  method,
  constructor,
  property,
  field,
  parameter,
  returnValue,
  assembly,
  module,
}

/// Operator kinds for operator overloads.
enum OperatorKind {
  // Arithmetic
  add,
  subtract,
  multiply,
  divide,
  modulo,
  // Bitwise
  bitwiseAnd,
  bitwiseOr,
  bitwiseXor,
  leftShift,
  rightShift,
  unsignedRightShift,
  // Unary
  unaryPlus,
  unaryMinus,
  logicalNot,
  bitwiseNot,
  increment,
  decrement,
  // Comparison
  equality,
  inequality,
  lessThan,
  greaterThan,
  lessThanOrEqual,
  greaterThanOrEqual,
  // Logical
  logicalAnd,
  logicalOr,
  // True/False
  trueOp,
  falseOp,
}

/// Variance for generic type parameters.
enum TypeParameterVariance {
  none,
  covariant,
  contravariant,
}
