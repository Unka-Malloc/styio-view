import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final class WindowsNamedPipeUnavailable implements Exception {
  const WindowsNamedPipeUnavailable();
}

final class WindowsNamedPipeConnection {
  WindowsNamedPipeConnection._(this._handle);

  final int _handle;
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast(sync: true);
  ReceivePort? _receivePort;
  Isolate? _reader;
  Future<void> _writeTail = Future<void>.value();
  var _closed = false;

  Stream<Uint8List> get incoming => _incoming.stream;

  static Future<WindowsNamedPipeConnection> connect(String endpoint) async {
    final handle = _openPipe(endpoint);
    final connection = WindowsNamedPipeConnection._(handle);
    await connection._startReader();
    return connection;
  }

  Future<void> _startReader() async {
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    receivePort.listen((message) {
      if (message is Uint8List) {
        if (!_incoming.isClosed) _incoming.add(message);
      } else if (message is List<int>) {
        if (!_incoming.isClosed) _incoming.add(Uint8List.fromList(message));
      } else if (message == null && !_incoming.isClosed) {
        unawaited(_incoming.close());
      }
    });
    _reader = await Isolate.spawn<List<Object>>(_readPipe, <Object>[
      _handle,
      receivePort.sendPort,
    ], errorsAreFatal: true);
  }

  Future<void> write(Uint8List bytes) {
    if (_closed) throw StateError('named pipe is closed');
    final payload = Uint8List.fromList(bytes);
    final operation = _writeTail.then(
      (_) => Isolate.run(() => _writePipeBytes(_handle, payload)),
    );
    _writeTail = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _writeTail;
    _closeHandle(_handle);
    _reader?.kill(priority: Isolate.immediate);
    _reader = null;
    _receivePort?.close();
    _receivePort = null;
    if (!_incoming.isClosed) await _incoming.close();
  }
}

const _genericRead = 0x80000000;
const _genericWrite = 0x40000000;
const _openExisting = 3;
const _errorPipeBusy = 231;
const _invalidHandle = -1;

final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

typedef _CreateFileWNative =
    IntPtr Function(
      Pointer<Utf16>,
      Uint32,
      Uint32,
      Pointer<Void>,
      Uint32,
      Uint32,
      IntPtr,
    );
typedef _CreateFileWDart =
    int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int);
typedef _WaitNamedPipeWNative = Int32 Function(Pointer<Utf16>, Uint32);
typedef _WaitNamedPipeWDart = int Function(Pointer<Utf16>, int);
typedef _ReadFileNative =
    Int32 Function(
      IntPtr,
      Pointer<Uint8>,
      Uint32,
      Pointer<Uint32>,
      Pointer<Void>,
    );
typedef _ReadFileDart =
    int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>);
typedef _WriteFileNative =
    Int32 Function(
      IntPtr,
      Pointer<Uint8>,
      Uint32,
      Pointer<Uint32>,
      Pointer<Void>,
    );
typedef _WriteFileDart =
    int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>);
typedef _CloseHandleNative = Int32 Function(IntPtr);
typedef _CloseHandleDart = int Function(int);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

final _CreateFileWDart _createFile = _kernel32
    .lookupFunction<_CreateFileWNative, _CreateFileWDart>('CreateFileW');
final _WaitNamedPipeWDart _waitNamedPipe = _kernel32
    .lookupFunction<_WaitNamedPipeWNative, _WaitNamedPipeWDart>(
      'WaitNamedPipeW',
    );
final _ReadFileDart _readFile = _kernel32
    .lookupFunction<_ReadFileNative, _ReadFileDart>('ReadFile');
final _WriteFileDart _writeFile = _kernel32
    .lookupFunction<_WriteFileNative, _WriteFileDart>('WriteFile');
final _CloseHandleDart _closeHandleFunction = _kernel32
    .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
final _GetLastErrorDart _getLastError = _kernel32
    .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');

int _openPipe(String endpoint) {
  final name = endpoint.toNativeUtf16();
  try {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      final handle = _createFile(
        name,
        _genericRead | _genericWrite,
        0,
        nullptr,
        _openExisting,
        0,
        0,
      );
      if (handle != _invalidHandle) return handle;
      if (_getLastError() != _errorPipeBusy ||
          DateTime.now().isAfter(deadline)) {
        throw const WindowsNamedPipeUnavailable();
      }
      _waitNamedPipe(name, 100);
    }
  } finally {
    malloc.free(name);
  }
}

void _readPipe(List<Object> arguments) {
  final handle = arguments[0] as int;
  final sendPort = arguments[1] as SendPort;
  final buffer = malloc<Uint8>(64 * 1024);
  final read = malloc<Uint32>();
  try {
    while (true) {
      read.value = 0;
      final succeeded = _readFile(handle, buffer, 64 * 1024, read, nullptr);
      if (succeeded == 0 || read.value == 0) break;
      sendPort.send(Uint8List.fromList(buffer.asTypedList(read.value)));
    }
  } finally {
    malloc.free(read);
    malloc.free(buffer);
    sendPort.send(null);
  }
}

void _writePipeBytes(int handle, Uint8List bytes) {
  final buffer = malloc<Uint8>(bytes.length);
  final written = malloc<Uint32>();
  try {
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    var offset = 0;
    while (offset < bytes.length) {
      written.value = 0;
      final succeeded = _writeFile(
        handle,
        buffer + offset,
        bytes.length - offset,
        written,
        nullptr,
      );
      if (succeeded == 0 || written.value == 0) {
        throw StateError('vityod named pipe write failed');
      }
      offset += written.value;
    }
  } finally {
    malloc.free(written);
    malloc.free(buffer);
  }
}

void _closeHandle(int handle) {
  _closeHandleFunction(handle);
}
