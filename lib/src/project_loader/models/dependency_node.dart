/// A node in the [DependencyGraph] representing one C# project.
final class DependencyNode {
  /// Absolute path to the `.csproj` file.
  final String projectPath;

  /// The assembly name of this project.
  final String projectName;

  /// Absolute paths of projects this project directly depends on.
  final List<String> dependsOn;

  const DependencyNode({
    required this.projectPath,
    required this.projectName,
    required this.dependsOn,
  });
}
