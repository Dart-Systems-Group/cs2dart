import 'dart:io';
import 'package:test/test.dart';
import 'package:cs2dart/src/project_loader/input_parser.dart';

void main() {
  late InputParser parser;

  setUp(() {
    parser = const InputParser();
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String fixturePath(String relative) {
    // Resolve relative to the workspace root (where `dart test` is run from).
    return '${Directory.current.path}/test/fixtures/$relative';
  }

  // ---------------------------------------------------------------------------
  // Basic metadata extraction
  // ---------------------------------------------------------------------------

  group('parseCsproj — basic metadata', () {
    test('extracts AssemblyName, TargetFramework, OutputType, LangVersion, Nullable', () async {
      final path = fixturePath('simple_console/SimpleConsole.csproj');
      final data = await parser.parseCsproj(path);

      expect(data.absolutePath, equals(path));
      expect(data.assemblyName, equals('SimpleConsole'));
      expect(data.targetFramework, equals('net8.0'));
      expect(data.outputType, equals('Exe'));
      expect(data.langVersion, equals('12.0'));
      expect(data.nullableEnabled, isTrue);
    });

    test('nullableEnabled is false when <Nullable> is absent', () async {
      final path = fixturePath('with_references/WithReferences.csproj');
      final data = await parser.parseCsproj(path);
      expect(data.nullableEnabled, isFalse);
    });

    test('nullableEnabled is false when <Nullable> is not "enable"', () async {
      final tmpDir = await Directory.systemTemp.createTemp('csproj_test_');
      final file = File('${tmpDir.path}/Test.csproj');
      await file.writeAsString('''
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>disable</Nullable>
  </PropertyGroup>
</Project>
''');
      addTearDown(() => tmpDir.delete(recursive: true));

      final data = await parser.parseCsproj(file.path);
      expect(data.nullableEnabled, isFalse);
    });

    test('assemblyName is null when <AssemblyName> is absent', () async {
      final path = fixturePath('with_references/WithReferences.csproj');
      final data = await parser.parseCsproj(path);
      expect(data.assemblyName, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // TargetFrameworks (plural)
  // ---------------------------------------------------------------------------

  group('parseCsproj — TargetFrameworks', () {
    test('selects first framework from semicolon-separated list', () async {
      final path = fixturePath('multi_frameworks/MultiFrameworks.csproj');
      final data = await parser.parseCsproj(path);
      expect(data.targetFramework, equals('net8.0'));
    });

    test('handles single framework in TargetFrameworks', () async {
      final tmpDir = await Directory.systemTemp.createTemp('csproj_test_');
      final file = File('${tmpDir.path}/Test.csproj');
      await file.writeAsString('''
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>net8.0</TargetFrameworks>
  </PropertyGroup>
</Project>
''');
      addTearDown(() => tmpDir.delete(recursive: true));

      final data = await parser.parseCsproj(file.path);
      expect(data.targetFramework, equals('net8.0'));
    });
  });

  // ---------------------------------------------------------------------------
  // Source file enumeration
  // ---------------------------------------------------------------------------

  group('parseCsproj — source file enumeration', () {
    test('implicit glob expands to .cs files sorted alphabetically', () async {
      final path = fixturePath('simple_console/SimpleConsole.csproj');
      final data = await parser.parseCsproj(path);

      // The fixture directory contains Program.cs.
      expect(data.sourceGlobs, isNotEmpty);
      expect(data.sourceGlobs.every((p) => p.endsWith('.cs')), isTrue);
      // Sorted alphabetically.
      final sorted = [...data.sourceGlobs]..sort();
      expect(data.sourceGlobs, equals(sorted));
    });

    test('explicit <Compile Include> entries are used when present', () async {
      final path = fixturePath('explicit_compile/ExplicitCompile.csproj');
      final data = await parser.parseCsproj(path);

      // Foo.cs and Bar.cs are included; Excluded.cs is removed.
      final names = data.sourceGlobs.map((p) => p.split('/').last).toList();
      expect(names, containsAll(['Foo.cs', 'Bar.cs']));
      expect(names, isNot(contains('Excluded.cs')));
    });

    test('explicit <Compile Remove> entries are excluded', () async {
      final path = fixturePath('explicit_compile/ExplicitCompile.csproj');
      final data = await parser.parseCsproj(path);

      final names = data.sourceGlobs.map((p) => p.split('/').last).toList();
      expect(names, isNot(contains('Excluded.cs')));
    });

    test('source paths are absolute', () async {
      final path = fixturePath('simple_console/SimpleConsole.csproj');
      final data = await parser.parseCsproj(path);

      for (final src in data.sourceGlobs) {
        expect(File(src).isAbsolute, isTrue, reason: '$src should be absolute');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // ProjectReference and PackageReference
  // ---------------------------------------------------------------------------

  group('parseCsproj — references', () {
    test('extracts ProjectReference paths as absolute paths', () async {
      final path = fixturePath('with_references/WithReferences.csproj');
      final data = await parser.parseCsproj(path);

      expect(data.projectReferencePaths, hasLength(1));
      expect(data.projectReferencePaths.first, endsWith('SimpleConsole.csproj'));
    });

    test('extracts PackageReference entries with name and version', () async {
      final path = fixturePath('with_references/WithReferences.csproj');
      final data = await parser.parseCsproj(path);

      expect(data.packageReferences, hasLength(2));

      final newtonsoftJson =
          data.packageReferences.firstWhere((p) => p.packageName == 'Newtonsoft.Json');
      expect(newtonsoftJson.version, equals('13.0.3'));

      final serilog =
          data.packageReferences.firstWhere((p) => p.packageName == 'Serilog');
      expect(serilog.version, equals('3.1.1'));
    });

    test('returns empty lists when no references are present', () async {
      final path = fixturePath('simple_console/SimpleConsole.csproj');
      final data = await parser.parseCsproj(path);

      expect(data.projectReferencePaths, isEmpty);
      expect(data.packageReferences, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Malformed XML — PL0003
  // ---------------------------------------------------------------------------

  group('parseCsproj — malformed XML', () {
    test('throws MalformedCsprojException on empty file', () async {
      final tmpDir = await Directory.systemTemp.createTemp('csproj_test_');
      final file = File('${tmpDir.path}/Empty.csproj');
      await file.writeAsString('');
      addTearDown(() => tmpDir.delete(recursive: true));

      expect(
        () => parser.parseCsproj(file.path),
        throwsA(isA<MalformedCsprojException>()),
      );
    });

    test('throws MalformedCsprojException on non-XML content', () async {
      final tmpDir = await Directory.systemTemp.createTemp('csproj_test_');
      final file = File('${tmpDir.path}/Bad.csproj');
      await file.writeAsString('this is not xml at all');
      addTearDown(() => tmpDir.delete(recursive: true));

      expect(
        () => parser.parseCsproj(file.path),
        throwsA(isA<MalformedCsprojException>()),
      );
    });

    test('throws MalformedCsprojException on mismatched tags', () async {
      final tmpDir = await Directory.systemTemp.createTemp('csproj_test_');
      final file = File('${tmpDir.path}/Mismatched.csproj');
      await file.writeAsString('<Project><PropertyGroup></WrongClose></Project>');
      addTearDown(() => tmpDir.delete(recursive: true));

      expect(
        () => parser.parseCsproj(file.path),
        throwsA(isA<MalformedCsprojException>()),
      );
    });

    test('throws MalformedCsprojException on unclosed tag', () async {
      final tmpDir = await Directory.systemTemp.createTemp('csproj_test_');
      final file = File('${tmpDir.path}/Unclosed.csproj');
      await file.writeAsString('<Project><PropertyGroup>');
      addTearDown(() => tmpDir.delete(recursive: true));

      expect(
        () => parser.parseCsproj(file.path),
        throwsA(isA<MalformedCsprojException>()),
      );
    });

    test('throws MalformedCsprojException when root element is not <Project>', () async {
      final tmpDir = await Directory.systemTemp.createTemp('csproj_test_');
      final file = File('${tmpDir.path}/WrongRoot.csproj');
      await file.writeAsString('<NotAProject></NotAProject>');
      addTearDown(() => tmpDir.delete(recursive: true));

      expect(
        () => parser.parseCsproj(file.path),
        throwsA(isA<MalformedCsprojException>()),
      );
    });

    test('throws MalformedCsprojException when file does not exist', () async {
      expect(
        () => parser.parseCsproj('/nonexistent/path/Missing.csproj'),
        throwsA(isA<MalformedCsprojException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // parseSln
  // ---------------------------------------------------------------------------

  group('parseSln', () {
    test('returns csproj paths from a valid .sln file', () async {
      final tmpDir = await Directory.systemTemp.createTemp('sln_test_');
      addTearDown(() => tmpDir.delete(recursive: true));

      // Create a dummy .csproj so the path is resolvable (not required by parseSln itself).
      final slnContent = '''
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Alpha", "Alpha\\Alpha.csproj", "{AAA}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Beta", "Beta\\Beta.csproj", "{BBB}"
EndProject
''';
      final slnFile = File('${tmpDir.path}/MySolution.sln');
      await slnFile.writeAsString(slnContent);

      final paths = await parser.parseSln(slnFile.path);

      expect(paths, hasLength(2));
      expect(paths[0], endsWith('Alpha/Alpha.csproj'));
      expect(paths[1], endsWith('Beta/Beta.csproj'));
    });

    test('resolves paths relative to the .sln directory', () async {
      final tmpDir = await Directory.systemTemp.createTemp('sln_test_');
      addTearDown(() => tmpDir.delete(recursive: true));

      final slnContent = '''
Microsoft Visual Studio Solution File, Format Version 12.00
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Lib", "src\\Lib\\Lib.csproj", "{CCC}"
EndProject
''';
      final slnFile = File('${tmpDir.path}/Solution.sln');
      await slnFile.writeAsString(slnContent);

      final paths = await parser.parseSln(slnFile.path);

      expect(paths, hasLength(1));
      expect(paths.first, equals('${tmpDir.path}/src/Lib/Lib.csproj'));
    });

    test('normalises backslashes to forward slashes', () async {
      final tmpDir = await Directory.systemTemp.createTemp('sln_test_');
      addTearDown(() => tmpDir.delete(recursive: true));

      final slnContent = '''
Microsoft Visual Studio Solution File, Format Version 12.00
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "App", "sub\\dir\\App.csproj", "{DDD}"
EndProject
''';
      final slnFile = File('${tmpDir.path}/Solution.sln');
      await slnFile.writeAsString(slnContent);

      final paths = await parser.parseSln(slnFile.path);

      expect(paths.first, isNot(contains('\\')));
      expect(paths.first, contains('/'));
    });

    test('returns empty list for a valid .sln with no projects', () async {
      final tmpDir = await Directory.systemTemp.createTemp('sln_test_');
      addTearDown(() => tmpDir.delete(recursive: true));

      final slnContent = '''
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
Global
  GlobalSection(SolutionProperties) = preSolution
    HideSolutionNode = FALSE
  EndGlobalSection
EndGlobal
''';
      final slnFile = File('${tmpDir.path}/Empty.sln');
      await slnFile.writeAsString(slnContent);

      final paths = await parser.parseSln(slnFile.path);
      expect(paths, isEmpty);
    });

    test('throws MalformedSlnException when file does not exist', () async {
      expect(
        () => parser.parseSln('/nonexistent/path/Missing.sln'),
        throwsA(isA<MalformedSlnException>()),
      );
    });

    test('throws MalformedSlnException on empty file', () async {
      final tmpDir = await Directory.systemTemp.createTemp('sln_test_');
      addTearDown(() => tmpDir.delete(recursive: true));

      final slnFile = File('${tmpDir.path}/Empty.sln');
      await slnFile.writeAsString('');

      expect(
        () => parser.parseSln(slnFile.path),
        throwsA(isA<MalformedSlnException>()),
      );
    });

    test('throws MalformedSlnException on clearly non-.sln content', () async {
      final tmpDir = await Directory.systemTemp.createTemp('sln_test_');
      addTearDown(() => tmpDir.delete(recursive: true));

      final slnFile = File('${tmpDir.path}/NotASln.sln');
      await slnFile.writeAsString('this is just some random text with no sln markers');

      expect(
        () => parser.parseSln(slnFile.path),
        throwsA(isA<MalformedSlnException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // XML features
  // ---------------------------------------------------------------------------

  group('parseCsproj — XML features', () {
    test('handles XML declaration', () async {
      final tmpDir = await Directory.systemTemp.createTemp('csproj_test_');
      final file = File('${tmpDir.path}/WithDecl.csproj');
      await file.writeAsString('''<?xml version="1.0" encoding="utf-8"?>
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
''');
      addTearDown(() => tmpDir.delete(recursive: true));

      final data = await parser.parseCsproj(file.path);
      expect(data.targetFramework, equals('net8.0'));
    });

    test('handles XML comments', () async {
      final tmpDir = await Directory.systemTemp.createTemp('csproj_test_');
      final file = File('${tmpDir.path}/WithComments.csproj');
      await file.writeAsString('''
<Project Sdk="Microsoft.NET.Sdk">
  <!-- This is a comment -->
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <!-- Another comment -->
    <AssemblyName>MyApp</AssemblyName>
  </PropertyGroup>
</Project>
''');
      addTearDown(() => tmpDir.delete(recursive: true));

      final data = await parser.parseCsproj(file.path);
      expect(data.targetFramework, equals('net8.0'));
      expect(data.assemblyName, equals('MyApp'));
    });

    test('handles self-closing elements', () async {
      final tmpDir = await Directory.systemTemp.createTemp('csproj_test_');
      final file = File('${tmpDir.path}/SelfClose.csproj');
      await file.writeAsString('''
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Serilog" Version="3.1.1" />
  </ItemGroup>
</Project>
''');
      addTearDown(() => tmpDir.delete(recursive: true));

      final data = await parser.parseCsproj(file.path);
      expect(data.packageReferences, hasLength(1));
      expect(data.packageReferences.first.packageName, equals('Serilog'));
      expect(data.packageReferences.first.version, equals('3.1.1'));
    });
  });
}
