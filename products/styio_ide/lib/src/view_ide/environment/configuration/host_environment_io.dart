import 'dart:io' as io;

Map<String, String> readHostEnvironment() {
  return Map<String, String>.unmodifiable(io.Platform.environment);
}
