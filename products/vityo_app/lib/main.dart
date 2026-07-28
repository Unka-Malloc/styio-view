import 'package:flutter/widgets.dart';

import 'src/ide/platform/desktop_delivery_smoke.dart';
import 'src/view_render/view_render.dart';

Future<void> main(List<String> arguments) async {
  if (await tryRunDesktopDeliverySmoke(arguments)) {
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrap = await AppBootstrap.load();
  runApp(VityoApp(bootstrap: bootstrap));
}
