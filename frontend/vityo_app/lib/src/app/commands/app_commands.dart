import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

export '../../view_ide/commands/app_commands.dart';
export '../../view_ide/commands/command_palette.dart';
export '../../view_ide/commands/command_keybinding_profile.dart';

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
      alt: shortcut.alt,
      shift: shortcut.shift,
    );
  }

  static LogicalKeyboardKey _logicalKeyFor(String key) {
    switch (key) {
      case 'arrowLeft':
        return LogicalKeyboardKey.arrowLeft;
      case 'arrowRight':
        return LogicalKeyboardKey.arrowRight;
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
      case 'f2':
        return LogicalKeyboardKey.f2;
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
      case 'keyB':
        return LogicalKeyboardKey.keyB;
      case 'keyE':
        return LogicalKeyboardKey.keyE;
      case 'keyF':
        return LogicalKeyboardKey.keyF;
      case 'keyH':
        return LogicalKeyboardKey.keyH;
      case 'keyO':
        return LogicalKeyboardKey.keyO;
      case 'keyP':
        return LogicalKeyboardKey.keyP;
      case 'keyR':
        return LogicalKeyboardKey.keyR;
      case 'keyS':
        return LogicalKeyboardKey.keyS;
      case 'keyT':
        return LogicalKeyboardKey.keyT;
      case 'keyV':
        return LogicalKeyboardKey.keyV;
      case 'period':
        return LogicalKeyboardKey.period;
    }
    throw ArgumentError.value(key, 'key', 'Unsupported command shortcut key');
  }
}
