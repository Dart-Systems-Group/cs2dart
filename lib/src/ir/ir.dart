// IR stage public API
//
// Import this file to access all IR node types, interfaces, and result types.

// Interfaces
export 'interfaces/i_ir_builder.dart';
export 'interfaces/i_ir_serializer.dart';
export 'interfaces/i_ir_validator.dart';

// Models — build result (also re-exports ir_nodes.dart)
export 'models/ir_build_result.dart';

// Models — enums (also re-exported via ir_nodes.dart)
export 'models/ir_enums.dart';

// Models — type hierarchy
export 'models/ir_type.dart';

// IR_Builder sub-components
export 'diagnostic_collector.dart';
export 'symbol_resolver.dart';
export 'type_resolver.dart';
