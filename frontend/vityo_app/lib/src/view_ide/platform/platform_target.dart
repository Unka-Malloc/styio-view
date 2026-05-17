import 'package:flutter/foundation.dart';

enum PlatformTarget {
  web,
  windows,
  linux,
  android,
  macos,
  ios,
  unknown,
}

extension PlatformTargetX on PlatformTarget {
  String get wireValue {
    switch (this) {
      case PlatformTarget.web:
        return 'web';
      case PlatformTarget.windows:
        return 'windows';
      case PlatformTarget.linux:
        return 'linux';
      case PlatformTarget.android:
        return 'android';
      case PlatformTarget.macos:
        return 'macos';
      case PlatformTarget.ios:
        return 'ios';
      case PlatformTarget.unknown:
        return 'unknown';
    }
  }

  String get label {
    switch (this) {
      case PlatformTarget.web:
        return 'Web';
      case PlatformTarget.windows:
        return 'Windows';
      case PlatformTarget.linux:
        return 'Linux';
      case PlatformTarget.android:
        return 'Android';
      case PlatformTarget.macos:
        return 'macOS';
      case PlatformTarget.ios:
        return 'iOS';
      case PlatformTarget.unknown:
        return 'Unknown';
    }
  }
}

PlatformTarget platformTargetFromWireValue(String value) {
  for (final target in PlatformTarget.values) {
    if (target.wireValue == value) {
      return target;
    }
  }
  return PlatformTarget.unknown;
}

PlatformTarget detectPlatformTarget() {
  if (kIsWeb) {
    return PlatformTarget.web;
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
      return PlatformTarget.windows;
    case TargetPlatform.linux:
      return PlatformTarget.linux;
    case TargetPlatform.android:
      return PlatformTarget.android;
    case TargetPlatform.macOS:
      return PlatformTarget.macos;
    case TargetPlatform.iOS:
      return PlatformTarget.ios;
    case TargetPlatform.fuchsia:
      return PlatformTarget.unknown;
  }
}
