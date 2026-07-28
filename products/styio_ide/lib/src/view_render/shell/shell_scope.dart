import 'package:flutter/widgets.dart';

import 'shell_model.dart';

class ShellScope extends InheritedNotifier<ShellModel> {
  const ShellScope({super.key, required ShellModel model, required super.child})
    : super(notifier: model);

  static ShellModel of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'ShellScope is missing in the widget tree.');
    return scope!.notifier!;
  }
}
