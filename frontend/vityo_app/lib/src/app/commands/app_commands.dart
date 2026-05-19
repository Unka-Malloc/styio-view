import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

export '../../view_ide/commands/app_commands.dart';

import '../../view_ide/commands/app_commands.dart';

class AppCommandIntent extends Intent {
  const AppCommandIntent(this.commandId);

  final AppCommandId commandId;
}

class AppCommandShortcutRegistry {
  static Map<ShortcutActivator, Intent> get shortcutIntents {
    final bindings = <ShortcutActivator, Intent>{};
    for (final command in StyioCommandRegistry.commands) {
      for (final shortcut in command.shortcuts) {
        bindings[_activatorFor(shortcut)] = AppCommandIntent(command.id);
      }
    }
    return bindings;
  }

  static ShortcutActivator _activatorFor(AppCommandShortcutSpec shortcut) {
    return SingleActivator(
      _logicalKeyFor(shortcut.key),
      control: shortcut.control,
      meta: shortcut.meta,
      shift: shortcut.shift,
    );
  }

  static LogicalKeyboardKey _logicalKeyFor(String key) {
    switch (key) {
      case 'comma':
        return LogicalKeyboardKey.comma;
      case 'digit1':
        return LogicalKeyboardKey.digit1;
      case 'digit2':
        return LogicalKeyboardKey.digit2;
      case 'digit3':
        return LogicalKeyboardKey.digit3;
      case 'enter':
        return LogicalKeyboardKey.enter;
      case 'f5':
        return LogicalKeyboardKey.f5;
      case 'f8':
        return LogicalKeyboardKey.f8;
      case 'f9':
        return LogicalKeyboardKey.f9;
      case 'f10':
        return LogicalKeyboardKey.f10;
      case 'f12':
        return LogicalKeyboardKey.f12;
      case 'keyF':
        return LogicalKeyboardKey.keyF;
      case 'keyR':
        return LogicalKeyboardKey.keyR;
      case 'keyS':
        return LogicalKeyboardKey.keyS;
      case 'keyV':
        return LogicalKeyboardKey.keyV;
      case 'period':
        return LogicalKeyboardKey.period;
    }
    throw ArgumentError.value(key, 'key', 'Unsupported command shortcut key');
  }
}
