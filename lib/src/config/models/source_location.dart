/// A source location within a configuration file.
final class SourceLocation {
  final String filePath;
  final int line;
  final int column;

  const SourceLocation({
    required this.filePath,
    required this.line,
    required this.column,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceLocation &&
          filePath == other.filePath &&
          line == other.line &&
          column == other.column;

  @override
  int get hashCode => Object.hash(filePath, line, column);

  @override
  String toString() => '$filePath:$line:$column';
}
