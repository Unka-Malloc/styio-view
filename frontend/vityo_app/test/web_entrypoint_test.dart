import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web entrypoint redirects the root address to the editor route', () {
    final index = _webIndexFile();
    final html = index.readAsStringSync();

    expect(html, contains('window.location.pathname === "/"'));
    expect(html, contains('window.location.replace("/editor"'));
    expect(html, contains('flutter_bootstrap.js'));
    expect(html, isNot(contains('Vityo Integration Shell')));
  });
}

File _webIndexFile() {
  final candidates = <File>[
    File('web/index.html'),
    File('frontend/vityo_app/web/index.html'),
  ];

  for (final candidate in candidates) {
    if (candidate.existsSync()) {
      return candidate;
    }
  }

  throw StateError('Unable to locate frontend/vityo_app/web/index.html.');
}
