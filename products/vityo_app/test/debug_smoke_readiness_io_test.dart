import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_smoke_readiness_io.dart';

void main() {
  test(
    'C++ DAP smoke readiness uses explicit adapter and compiler overrides',
    () async {
      final probe = CppDapSmokeReadinessProbe(
        lookupExecutable: (name) async => null,
      );

      final readiness = await probe.detect(
        environment: const <String, String>{
          'VITYO_DAP_ADAPTER': '/opt/debug/lldb-dap',
          'CXX': '/opt/llvm/bin/clang++',
        },
      );

      expect(readiness.ready, isTrue);
      expect(readiness.adapterPath, '/opt/debug/lldb-dap');
      expect(readiness.compilerPath, '/opt/llvm/bin/clang++');
    },
  );

  test(
    'C++ DAP smoke readiness discovers adapter and compiler candidates',
    () async {
      final probe = CppDapSmokeReadinessProbe(
        lookupExecutable: (name) async {
          return switch (name) {
            'lldb-dap' => '/usr/bin/lldb-dap',
            'clang++' => '/usr/bin/clang++',
            _ => null,
          };
        },
      );

      final readiness = await probe.detect();

      expect(readiness.ready, isTrue);
      expect(readiness.adapterPath, '/usr/bin/lldb-dap');
      expect(readiness.compilerPath, '/usr/bin/clang++');
    },
  );

  test('C++ DAP smoke readiness blocks when no adapter is available', () async {
    final probe = CppDapSmokeReadinessProbe(
      lookupExecutable: (name) async {
        return name == 'clang++' ? '/usr/bin/clang++' : null;
      },
    );

    final readiness = await probe.detect();

    expect(readiness.ready, isFalse);
    expect(readiness.adapterPath, isNull);
    expect(readiness.reason, contains('no lldb-dap'));
  });

  test(
    'C++ DAP smoke readiness blocks when no compiler is available',
    () async {
      final probe = CppDapSmokeReadinessProbe(
        lookupExecutable: (name) async {
          return name == 'lldb-dap' ? '/usr/bin/lldb-dap' : null;
        },
      );

      final readiness = await probe.detect();

      expect(readiness.ready, isFalse);
      expect(readiness.compilerPath, isNull);
      expect(readiness.reason, contains('no C++ compiler'));
    },
  );
}
