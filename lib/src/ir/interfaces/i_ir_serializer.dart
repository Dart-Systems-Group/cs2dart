import '../models/ir_build_result.dart';

export '../models/ir_build_result.dart';

/// Exception thrown by [IIrSerializer.parse] when the JSON is malformed or
/// missing required fields.
final class IrParseException implements Exception {
  final String message;
  final String? source;

  const IrParseException(this.message, {this.source});

  @override
  String toString() {
    final src = source != null ? ' (source: $source)' : '';
    return 'IrParseException: $message$src';
  }
}

/// The public interface for the IR_Serializer.
///
/// Serializes [IrCompilationUnit] trees to a deterministic, pretty-printed
/// JSON representation and parses them back.
abstract interface class IIrSerializer {
  /// Serializes [unit] to a deterministic, pretty-printed JSON string.
  ///
  /// - Field names use camelCase.
  /// - Null fields are omitted.
  /// - Array order is preserved.
  /// - Every IR_Node type name, field name, and IR_Type is explicitly named.
  String serialize(IrCompilationUnit unit);

  /// Parses [json] and reconstructs an equivalent [IrCompilationUnit].
  ///
  /// Throws [IrParseException] if the JSON is malformed or missing required
  /// fields.
  IrCompilationUnit parse(String json);
}
