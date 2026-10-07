enum ParseErrorCode {
  invalidInput,
  invalidSource,
  incompatibleSource,
  integrityFailure,
  scriptError,
  permissionDenied,
  unknownPlatform,
  unsupportedContent,
  authenticationRequired,
  notFound,
  network,
  timeout,
  cancelled,
  dependencyMissing,
  parseFailed,
}

/// Messages are safe for UI/logging; cookies and signed URLs are not included.
class ParseException implements Exception {
  const ParseException(this.code, this.message);
  final ParseErrorCode code;
  final String message;
  @override
  String toString() => 'ParseException(${code.name}): $message';
}
