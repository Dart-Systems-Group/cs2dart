// Re-exports the authoritative IRoslynFrontend definition from the
// roslyn_frontend module. The Orchestrator depends on this path for
// backwards compatibility; the full interface lives in:
//   lib/src/roslyn_frontend/interfaces/i_roslyn_frontend.dart
export '../../roslyn_frontend/interfaces/i_roslyn_frontend.dart';
