import 'dart:io';

import 'package:cs2dart/cs2dart.dart';
import 'package:cs2dart/src/orchestrator/cli_runner.dart';

Future<void> main(List<String> args) async {
  final orchestrator = OrchestratorFactory.create();
  final runner = CliRunner(orchestrator);
  final exitCode = await runner.run(args);
  exit(exitCode);
}
