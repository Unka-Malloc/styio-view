import 'package:flutter/foundation.dart';

abstract class EditorOwnedController extends ChangeNotifier {
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;

  @protected
  void ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('$runtimeType has been disposed.');
    }
  }

  @protected
  void notifyControllerListeners() {
    ensureNotDisposed();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    super.dispose();
  }
}
