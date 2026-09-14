import 'error/failure.dart';

/// A tiny `Result` type.
///
/// Repositories return `Result<T>` instead of throwing, so the UI layer is
/// forced by the type system to handle the failure branch. Dart 3 sealed
/// classes make the `switch` exhaustive at compile time.
sealed class Result<T> {
  const Result();

  /// Convenience: run [body], converting any [Failure] into [Err].
  static Future<Result<T>> guard<T>(Future<T> Function() body) async {
    try {
      return Ok<T>(await body());
    } on Failure catch (f) {
      return Err<T>(f);
    }
  }

  bool get isOk => this is Ok<T>;

  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  Failure? get failureOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final failure) => failure,
  };

  R fold<R>(R Function(T value) onOk, R Function(Failure failure) onErr) {
    return switch (this) {
      Ok<T>(:final value) => onOk(value),
      Err<T>(:final failure) => onErr(failure),
    };
  }

  Result<R> map<R>(R Function(T value) transform) {
    return switch (this) {
      Ok<T>(:final value) => Ok<R>(transform(value)),
      Err<T>(:final failure) => Err<R>(failure),
    };
  }
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}
