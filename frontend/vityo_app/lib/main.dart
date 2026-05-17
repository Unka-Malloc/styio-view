import 'package:flutter/widgets.dart';

import 'src/view_render/view_render.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrap = await AppBootstrap.load();
  runApp(VityoApp(bootstrap: bootstrap));
}
