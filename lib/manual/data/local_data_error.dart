/// Base type for failures in the local manual-entry data layer.
sealed class LocalDataError implements Exception {
  const LocalDataError(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// The supplied local data does not satisfy its schema or domain rules.
final class LocalDataValidationError extends LocalDataError {
  const LocalDataValidationError(super.message);
}

/// A local read or write operation failed.
final class LocalDataStorageError extends LocalDataError {
  const LocalDataStorageError(super.message, {super.cause});
}

/// Stored data uses a version the current implementation cannot read.
final class LocalDataVersionIncompatibleError extends LocalDataError {
  const LocalDataVersionIncompatibleError({
    required this.storedVersion,
    required this.supportedVersion,
  }) : super(
          'Stored data version $storedVersion is incompatible with supported '
          'version $supportedVersion.',
        );

  final int storedVersion;
  final int supportedVersion;
}
