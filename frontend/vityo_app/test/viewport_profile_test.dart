import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/platform/viewport_profile.dart';

void main() {
  test('desktop platforms always resolve to desktop viewport family', () {
    final profile = resolveViewportProfile(
      platformTarget: PlatformTarget.macos,
      width: 640,
      height: 480,
    );

    expect(profile.isDesktop, isTrue);
    expect(profile.label, 'Desktop');
    expect(profile.platformTarget, PlatformTarget.macos);
  });

  test('mobile platforms always resolve to mobile viewport family', () {
    final profile = resolveViewportProfile(
      platformTarget: PlatformTarget.ios,
      width: 1440,
      height: 900,
    );

    expect(profile.isMobile, isTrue);
    expect(profile.label, 'Mobile');
  });

  test('web resolves by viewport width', () {
    final desktopWeb = resolveViewportProfile(
      platformTarget: PlatformTarget.web,
      width: 1280,
      height: 800,
    );
    final mobileWeb = resolveViewportProfile(
      platformTarget: PlatformTarget.web,
      width: 430,
      height: 932,
    );

    expect(desktopWeb.isDesktop, isTrue);
    expect(mobileWeb.isMobile, isTrue);
    expect(desktopWeb.platformTarget, PlatformTarget.web);
  });
}
