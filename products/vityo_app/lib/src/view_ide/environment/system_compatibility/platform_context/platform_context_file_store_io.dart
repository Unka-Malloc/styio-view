import 'dart:convert';
import 'dart:io';

import 'platform_context_model.dart';
import 'platform_context_store.dart';

class PlatformContextFileStore implements PlatformContextStore {
  const PlatformContextFileStore(this.path);

  final String path;

  @override
  Future<PlatformContextSnapshot?> load() async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is Map<String, Object?>) {
      return PlatformContextSnapshot.fromJson(decoded);
    }
    if (decoded is Map) {
      return PlatformContextSnapshot.fromJson(
        decoded.map(
          (key, value) => MapEntry<String, Object?>(key.toString(), value),
        ),
      );
    }
    throw const FormatException('Invalid platform context file shape.');
  }

  @override
  Future<void> save(PlatformContextSnapshot snapshot) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
    );
  }
}
