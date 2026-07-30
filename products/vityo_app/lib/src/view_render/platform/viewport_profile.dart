import '../../view_ide/platform/platform_target.dart';

enum ViewportFamily { desktop, mobile }

class ViewportProfile {
  const ViewportProfile({
    required this.family,
    required this.width,
    required this.height,
    this.platformTarget = PlatformTarget.unknown,
  });

  final ViewportFamily family;
  final double width;
  final double height;
  final PlatformTarget platformTarget;

  bool get isDesktop => family == ViewportFamily.desktop;
  bool get isMobile => family == ViewportFamily.mobile;

  String get label {
    switch (family) {
      case ViewportFamily.desktop:
        return 'Desktop';
      case ViewportFamily.mobile:
        return 'Mobile';
    }
  }
}

ViewportProfile resolveViewportProfile({
  required PlatformTarget platformTarget,
  required double width,
  required double height,
}) {
  switch (platformTarget) {
    case PlatformTarget.windows:
    case PlatformTarget.linux:
    case PlatformTarget.macos:
      return ViewportProfile(
        family: ViewportFamily.desktop,
        width: width,
        height: height,
        platformTarget: platformTarget,
      );
    case PlatformTarget.android:
    case PlatformTarget.ios:
      return ViewportProfile(
        family: ViewportFamily.mobile,
        width: width,
        height: height,
        platformTarget: platformTarget,
      );
    case PlatformTarget.web:
    case PlatformTarget.unknown:
      return ViewportProfile(
        family: width >= 960 ? ViewportFamily.desktop : ViewportFamily.mobile,
        width: width,
        height: height,
        platformTarget: platformTarget,
      );
  }
}
