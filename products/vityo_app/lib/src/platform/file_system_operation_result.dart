import '../view_ide/environment/system_compatibility/file_system/file_system_manager.dart';

/// Structured outcome for file system operations.
sealed class FileSystemOperationResult<T> {
  const FileSystemOperationResult();

  T get valueOrThrow {
    if (this is FileSystemOperationSuccess<T>) {
      return (this as FileSystemOperationSuccess<T>).value;
    }
    throw FileSystemBoundaryException(
      (this as FileSystemOperationFailureResult<T>).failure,
    );
  }

  T? get valueOrNull =>
      this is FileSystemOperationSuccess<T>
          ? (this as FileSystemOperationSuccess<T>).value
          : null;

  FileSystemOperationFailure? get failureOrNull =>
      this is FileSystemOperationFailureResult<T>
          ? (this as FileSystemOperationFailureResult<T>).failure
          : null;

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
