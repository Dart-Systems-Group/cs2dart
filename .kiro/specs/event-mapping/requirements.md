# C# → Dart Event Mapping — Requirements

## Introduction

This document specifies the requirements for the **event mapping** subsystem of the C# → Dart transpiler. The subsystem is responsible for translating C# `event` declarations, `EventHandler`/`EventHandler<TEventArgs>` delegates, custom delegate-typed events, event subscriptions (`+=`, `-=`), and event invocations into idiomatic Dart using `Stream`-based patterns, consuming the IR `Event` declaration node produced by the IR_Builder.

---

## Glossary

- **Event_Transpiler**: The transpiler subsystem responsible for converting C# event declarations and usages into Dart.
- **IR_Event**: The `Event` IR declaration node (defined in IR Requirement 1.3) that carries the event name, delegate IR_Type, accessibility, `IsStatic` flag, and source location.
- **IR_EventSubscription**: An `AssignmentExpression` IR node with operator `+=` or `-=` where the left-hand side resolves to an `IR_Event` symbol.
- **IR_EventInvocation**: An `InvocationExpression` IR node whose target resolves to an `IR_Event` symbol (i.e., raising the event).
- **Dart_Stream_Event**: A Dart event implemented via a `StreamController` and exposed as a `Stream<T>` property.
- **EventArgs**: A C# class derived from `System.EventArgs` that carries event payload data.
- **Multicast_Delegate**: A C# delegate that holds an invocation list of multiple handlers; all C# events are multicast by default.
- **BCL_Event**: A well-known event pattern from the .NET Base Class Library (e.g., `INotifyPropertyChanged.PropertyChanged`, `INotifyCollectionChanged.CollectionChanged`).
- **Config_Service**: The `IConfigService` instance provided to the `Event_Transpiler` at construction time; the sole source of all event mapping configuration values. The `Event_Transpiler` SHALL NOT read `transpiler.yaml` directly.

---

## Requirements

### Requirement 1: IR Event Node Consumption

**User Story:** As a Dart code generator author, I want the Event_Transpiler to consume `IR_Event` nodes from the IR without any knowledge of Roslyn or C# syntax, so that the event mapping stage is cleanly decoupled from the frontend.

#### Acceptance Criteria

1. THE Event_Transpiler SHALL accept `IR_Event` nodes as its sole input for event declaration translation; it SHALL NOT inspect Roslyn `SyntaxNode` or `SemanticModel` objects directly.
2. THE Event_Transpiler SHALL read the following fields from each `IR_Event` node: `Name`, `DelegateType` (an `IR_Type`), `Accessibility`, `IsStatic`, `IsAbstract`, `IsVirtual`, `IsOverride`, `ExplicitInterface` (nullable), and `SourceLocation`.
3. WHEN an `IR_Event` node carries an `ExplicitInterface` field, THE Event_Transpiler SHALL treat the event as an explicit interface implementation and apply the naming rules defined in Requirement 7.
4. THE Event_Transpiler SHALL process `IR_EventSubscription` nodes (IR `AssignmentExpression` with `+=` / `-=` on an event symbol) to emit Dart subscription and unsubscription calls.
5. THE Event_Transpiler SHALL process `IR_EventInvocation` nodes to emit Dart event-raise calls using the stream-based strategy.

---

### Requirement 2: Event Strategy — Stream-Based

**User Story:** As a developer migrating a C# codebase, I want C# events to be translated to Dart `Stream`-based events, so that the generated Dart code follows idiomatic Dart patterns for reactive programming.

#### Acceptance Criteria

1. THE Event_Transpiler SHALL emit a private `StreamController<T>` field and a public `Stream<T>` getter for each `IR_Event` node, where `T` is the Dart type mapped from the event's payload type (see Requirement 4).
2. THE Event_Transpiler SHALL name the `StreamController` field `_<eventName>Controller` (camelCase, `_` prefix) and the public `Stream` getter `on<EventName>` (PascalCase prefix `on`).
3. WHEN the enclosing class is disposed (implements `IDisposable` or has a `Dispose` method in the IR), THE Event_Transpiler SHALL emit a `_<eventName>Controller.close()` call inside the generated `dispose()` method.
4. WHEN an `IR_EventSubscription` with `+=` is encountered in stream mode, THE Event_Transpiler SHALL emit a `stream.listen(handler)` call and store the returned `StreamSubscription` in a local variable or field for later cancellation.
5. WHEN an `IR_EventSubscription` with `-=` is encountered in stream mode, THE Event_Transpiler SHALL emit a `subscription.cancel()` call on the previously stored `StreamSubscription`.
6. WHEN an `IR_EventInvocation` is encountered in stream mode, THE Event_Transpiler SHALL emit `_<eventName>Controller.add(eventArgs)` to raise the event.
7. WHEN an `IR_Event` is declared `static`, THE Event_Transpiler SHALL emit a static `StreamController` and a static `Stream` getter on the generated Dart class.

---

### Requirement 4: EventArgs and Payload Type Mapping

**User Story:** As a developer, I want C# `EventArgs`-derived classes and custom delegate payload types to be correctly mapped to Dart types, so that event subscribers receive strongly-typed data.

#### Acceptance Criteria

1. WHEN an `IR_Event` uses `EventHandler` (no type argument), THE Event_Transpiler SHALL use `void` as the stream payload type and emit `Stream<void>`.
2. WHEN an `IR_Event` uses `EventHandler<TEventArgs>`, THE Event_Transpiler SHALL extract `TEventArgs` from the `IR_Type` generic argument and use the Dart-mapped equivalent of `TEventArgs` as the payload type `T`.
3. WHEN `TEventArgs` is `System.EventArgs` itself, THE Event_Transpiler SHALL use `void` as the payload type (no data carried).
4. WHEN an `IR_Event` uses a custom delegate type (not `EventHandler` or `EventHandler<T>`), THE Event_Transpiler SHALL inspect the delegate's `IR_Type` (a `FunctionType` node) and derive the payload type from its parameter list: if the delegate has a single non-sender parameter, use that parameter's type; if it has multiple parameters, emit a generated Dart record type `(Type1 param1, Type2 param2, ...)` as the payload.
5. WHEN an `IR_Event` uses a delegate with a `sender` parameter (first parameter of type `object`), THE Event_Transpiler SHALL omit the sender from the Dart payload type and emit a diagnostic info noting the omission.
6. WHEN `TEventArgs` is a C# class derived from `System.EventArgs`, THE Event_Transpiler SHALL translate the `EventArgs` subclass to a Dart class following the standard class mapping rules, and use that Dart class as the payload type.
7. WHEN the delegate return type is non-void, THE Event_Transpiler SHALL emit a diagnostic warning noting that non-void event delegates are not idiomatic in C# or Dart, the return value will be dropped, and the stream strategy will be applied.

---

### Requirement 5: Custom Event Accessors

**User Story:** As a developer, I want C# events with explicit `add` and `remove` accessors to be faithfully translated, so that custom subscription logic is preserved in the generated Dart code.

#### Acceptance Criteria

1. WHEN an `IR_Event` node carries explicit `add` and `remove` accessor `Method` IR nodes, THE Event_Transpiler SHALL emit the accessor bodies as custom `listen`/`cancel` wrappers around the `StreamController`.
2. WHEN the `add` accessor body contains thread-synchronization constructs (e.g., `lock`), THE Event_Transpiler SHALL omit the lock, emit the accessor body without it, and emit diagnostic `CS2DART_EVENT_010` (warning) noting that Dart is single-threaded and the lock is dropped.
3. WHEN the `remove` accessor body contains a null-check guard (e.g., `if (value != null)`), THE Event_Transpiler SHALL preserve the null-check semantics using Dart null-safety operators.
4. WHEN an `IR_Event` has no explicit accessors (field-like event), THE Event_Transpiler SHALL generate the default stream-based implementation using a `broadcast()` `StreamController`.
5. WHEN the `add` accessor body inspects handler identity to implement deduplication (e.g., checking an invocation list or a handler collection for the presence of `value`), THE Event_Transpiler SHALL emit an approximation using a `LinkedHashSet<StreamSubscription>` to track subscriptions, and SHALL emit diagnostic `CS2DART_EVENT_011` (warning) noting that deduplication semantics are approximated.
6. WHEN the `add` or `remove` accessor body uses `WeakReference` or any weak-reference pattern to hold handler references, THE Event_Transpiler SHALL emit a standard strong-reference stream subscription, drop the weak-reference logic, and emit diagnostic `CS2DART_EVENT_012` (warning) noting that Dart does not support weak references to closures and the semantics are not preserved.
7. WHEN the `add` or `remove` accessor body contains conditional logic that inspects the handler delegate itself (e.g., comparing `value` to a specific delegate, filtering by target object), THE Event_Transpiler SHALL emit the body as a best-effort translation and emit diagnostic `CS2DART_EVENT_013` (info) noting that handler-identity logic may not be semantically equivalent in Dart.

---

### Requirement 6: Abstract and Interface Events

**User Story:** As a developer, I want events declared on C# interfaces and abstract classes to generate the correct Dart abstract members, so that implementing classes are required to provide event implementations.

#### Acceptance Criteria

1. WHEN an `IR_Event` is declared on an IR `Interface` node, THE Event_Transpiler SHALL emit an abstract `Stream<T> get on<EventName>` getter on the generated Dart abstract class.
2. WHEN an `IR_Event` is declared with `IsAbstract = true` on an IR `Class` node, THE Event_Transpiler SHALL emit the same abstract members as in criterion 1.
3. WHEN a concrete class implements an interface that declares events, THE Event_Transpiler SHALL emit the full stream implementation on the concrete Dart class and annotate it with `@override`.
4. WHEN an `IR_Event` is declared with `IsVirtual = true`, THE Event_Transpiler SHALL emit a non-abstract implementation that subclasses can override, using the `@mustCallSuper` annotation if the base implementation contains non-trivial logic.
5. WHEN an `IR_Event` is declared with `IsOverride = true`, THE Event_Transpiler SHALL emit `@override` on the generated Dart member.

---

### Requirement 7: Explicit Interface Implementation

**User Story:** As a developer, I want C# explicit interface event implementations to be correctly scoped in Dart, so that name collisions between events from different interfaces are resolved.

#### Acceptance Criteria

1. WHEN an `IR_Event` carries a non-null `ExplicitInterface` field, THE Event_Transpiler SHALL emit the Dart member with a name prefixed by the interface name in camelCase (e.g., `INotifyPropertyChanged.PropertyChanged` → `iNotifyPropertyChangedOnPropertyChanged`).
2. THE Event_Transpiler SHALL emit a `// explicit interface: <InterfaceName>` comment above the generated member to preserve traceability.
3. WHEN two explicit interface events from different interfaces would produce the same prefixed name, THE Event_Transpiler SHALL append a numeric suffix (`_2`, `_3`, …) and emit a diagnostic warning.

---

### Requirement 8: BCL Event Mappings

**User Story:** As a developer, I want well-known .NET BCL event patterns to map to idiomatic Dart equivalents, so that common patterns like `INotifyPropertyChanged` work correctly without manual intervention.

#### Acceptance Criteria

1. THE Event_Transpiler SHALL map `INotifyPropertyChanged.PropertyChanged` to a `Stream<String> get onPropertyChanged` that emits the property name string, and SHALL emit a `_notifyPropertyChanged(String propertyName)` helper method that adds to the controller.
2. THE Event_Transpiler SHALL map `INotifyCollectionChanged.CollectionChanged` to a `Stream<CollectionChangedEventArgs> get onCollectionChanged`, where `CollectionChangedEventArgs` is a generated Dart class carrying `action`, `newItems`, and `oldItems` fields.
3. THE Event_Transpiler SHALL map `System.ComponentModel.INotifyDataErrorInfo.ErrorsChanged` to a `Stream<String> get onErrorsChanged` that emits the property name.
4. WHEN a BCL event has no direct idiomatic Dart equivalent, THE Event_Transpiler SHALL apply the default Event_Strategy and emit a `// TODO: review BCL event mapping for <EventName>` comment.
5. THE Event_Transpiler SHALL allow BCL event mappings to be overridden via `IConfigService.eventMappings`.

---

### Requirement 9: Static Events

**User Story:** As a developer, I want static C# events to be correctly translated to static Dart members, so that class-level event patterns are preserved.

#### Acceptance Criteria

1. WHEN an `IR_Event` has `IsStatic = true`, THE Event_Transpiler SHALL emit a static `StreamController` and a static `Stream` getter on the generated Dart class.
2. THE Event_Transpiler SHALL emit a static initializer or `late static` declaration for the static `StreamController` to ensure it is initialized before first use.
3. WHEN a static event's enclosing class has a static `Dispose` or teardown method in the IR, THE Event_Transpiler SHALL emit a `_<eventName>Controller.close()` call within that method.
4. WHEN a static `IR_EventSubscription` with `+=` is encountered, THE Event_Transpiler SHALL emit `ClassName.on<EventName>.listen(handler)`.

---

### Requirement 10: Diagnostics and Round-Trip Fidelity

**User Story:** As a developer, I want the transpiler to report clear diagnostics for unsupported or approximated event features, so that I can review and fix any semantic gaps after transpilation.

#### Acceptance Criteria

1. WHEN a C# event feature cannot be faithfully represented in Dart, THE Event_Transpiler SHALL emit a named diagnostic (e.g., `CS2DART_EVENT_001`) with a severity level, description, source location, and recommended remediation.
2. THE Event_Transpiler SHALL produce deterministic output: the same `IR_Event` input SHALL always produce the same Dart output.
3. FOR ALL C# events that are fully supported, the generated Dart code SHALL pass `dart analyze` with zero errors.
4. THE Event_Transpiler SHALL track event transpilation coverage in the feature support matrix, reporting the percentage of C# event features with full, partial, or no Dart mapping.
5. THE Event_Transpiler SHALL NOT emit duplicate diagnostics for the same source location and diagnostic code.

---

### Requirement 11: Consume the Configuration Service

**User Story:** As a pipeline module author, I want the `Event_Transpiler` to receive all configuration values through `IConfigService`, so that it is decoupled from YAML parsing and file I/O.

#### Acceptance Criteria

1. THE Event_Transpiler SHALL accept an `IConfigService` instance at construction time and SHALL use it as the sole source of all configuration values.
2. THE Event_Transpiler SHALL NOT read or parse `transpiler.yaml` directly; all configuration access SHALL go through `IConfigService`.
3. WHEN `IConfigService.eventMappings` contains an entry for a given C# event name with a `dart_name` override, THE Event_Transpiler SHALL use that name instead of the derived `on<EventName>` name.
4. WHEN `IConfigService.eventMappings` contains an entry with a `dart_type` override, THE Event_Transpiler SHALL use that Dart type string as the stream payload type.
5. WHEN all `IConfigService` accessors return their Default_Values, THE Event_Transpiler SHALL apply all default rules without error.

---

### Requirement 12: Correctness Properties for Property-Based Testing

**User Story:** As a transpiler test engineer, I want well-defined correctness properties for the Event_Transpiler, so that I can write property-based tests that catch regressions across a wide range of C# event inputs.

#### Acceptance Criteria

1. FOR ALL valid `IR_Event` nodes, THE Event_Transpiler SHALL produce Dart output that passes `dart analyze` with zero errors (well-formedness property).
2. FOR ALL valid `IR_Event` nodes, running THE Event_Transpiler twice on the same input SHALL produce identical Dart output (determinism property).
3. FOR ALL `IR_Event` nodes with `IsStatic = false`, the generated Dart class SHALL contain exactly one `Stream<T>` getter per event (one-to-one mapping property).
4. FOR ALL `IR_EventSubscription` nodes with `+=`, the generated Dart code SHALL contain a corresponding `listen` call; for all `-=` nodes, a corresponding `cancel` call SHALL be emitted (subscription symmetry property).
5. FOR ALL `IR_Event` nodes where the delegate type is `EventHandler` or `EventHandler<TEventArgs>`, the generated payload type SHALL be `void` or the Dart-mapped `TEventArgs` type respectively (payload type fidelity property).
6. FOR ALL pairs of distinct `IR_Event` nodes within the same enclosing class, the generated Dart member names SHALL be distinct (name uniqueness property).
