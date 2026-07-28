import 'desktop_delivery_smoke_stub.dart'
    if (dart.library.io) 'desktop_delivery_smoke_io.dart'
    as implementation;

Future<bool> tryRunDesktopDeliverySmoke(List<String> arguments) =>
    implementation.tryRunDesktopDeliverySmoke(arguments);
