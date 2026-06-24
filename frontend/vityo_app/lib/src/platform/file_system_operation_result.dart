import '../view_ide/environment/system_compatibility/file_system/file_system_manager.dart';

/// Structured outcome for file system operations.
sealed class FileSystemOperationResult<T> {
  T get valueOrThrow {
    return switch (this) {
      FileSystemOperationSuccess<T>(:final value) => value,
      FileSystemOperationFailureResult<T>(:final failure) =>
        throw FileSystemBoundaryException(failure),
    };
  }

  T? get valueOrNull => switch (this) {
    FileSystemOperationSuccess<T>(:final value) => value,
    FileSystemOperationFailureResult<T>(_) => null,
  };

  FileSystemOperationFailure? get failureOrNull => switch (this) {
    FileSystemOperationSuccess<T>(_) => null,
    FileSystemOperationFailureResult<T>(:final failure) => failure,
  };

  bool get isSuccess => this is FileSystemOperationSuccess<T>;
  bool get isFailure => this is FileSystemOperationFailureResult<T>;

  R map<R>({
    required R Function(FileSystemOperationSuccess<T> success) onSuccess,
    required R Function(FileSystemOperationFailureResult<T> failure) onFailure,
  }) =>
      switch (this) {
        FileSystemOperationSuccess<T> s => onSuccess(s),
        FileSystemOperationFailureResult<T> f => onFailure(f),
      };
}

class FileSystemOperationSuccess<T> extends FileSystemOperationResult<T> {
  const FileSystemOperationSuccess(this.value);

  final T value;
}

class FileSystemOperationFailureResult<T>
    extends FileSystemOperationResult<T> {
  const FileSystemOperationFailureResult(this.failure);

  final FileSystemOperationFailure failure;
}
