import 'native_v2_models.dart';

/// Base class for every failure surfaced by the coordinator client.
///
/// Exceptions deliberately never retain credentials or raw authorization
/// headers.
sealed class CoordinatorException implements Exception {
  const CoordinatorException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

final class CoordinatorEndpointException extends CoordinatorException {
  const CoordinatorEndpointException(super.message);
}

final class CoordinatorAuthenticationException extends CoordinatorException {
  const CoordinatorAuthenticationException(super.message);
}

final class CoordinatorTimeoutException extends CoordinatorException {
  const CoordinatorTimeoutException(super.message, {required this.timeout});

  final Duration timeout;
}

/// A mutation may have reached the coordinator, but no conclusive response
/// was received.
///
/// Callers must reconcile authoritative state before offering a retry. The
/// exception deliberately retains only routing/deadline metadata, never the
/// request body, credential, or underlying error.
final class CoordinatorMutationOutcomeUnknownException
    extends CoordinatorException {
  const CoordinatorMutationOutcomeUnknownException({
    required this.method,
    required this.path,
    required this.timeout,
  }) : super(
         'Coordinator mutation may have reached the server; '
         'its outcome is unknown.',
       );

  final String method;
  final String path;
  final Duration timeout;
}

final class CoordinatorTransportException extends CoordinatorException {
  const CoordinatorTransportException(super.message);
}

final class CoordinatorCapabilityException extends CoordinatorException {
  const CoordinatorCapabilityException(super.message);
}

final class CoordinatorProtocolException extends CoordinatorException {
  const CoordinatorProtocolException(super.message, {this.path});

  final String? path;
}

final class CoordinatorBodyTooLargeException extends CoordinatorException {
  const CoordinatorBodyTooLargeException(
    super.message, {
    required this.limitBytes,
  });

  final int limitBytes;
}

final class CoordinatorHttpException extends CoordinatorException {
  const CoordinatorHttpException(
    super.message, {
    required this.statusCode,
    this.response,
  });

  final int statusCode;
  final Map<String, Object?>? response;
}

/// A typed RFC 9457 failure returned by the native gateway.
///
/// The transport redacts credential-shaped fields and the active bearer before
/// constructing this exception. The exception message intentionally uses only
/// the problem title.
final class NativeGatewayProblemException extends CoordinatorException {
  NativeGatewayProblemException({
    required this.httpStatus,
    required this.problem,
  }) : super(problem.title);

  final int httpStatus;
  final NativeGatewayProblem problem;
}

final class CoordinatorSemanticException extends CoordinatorException {
  const CoordinatorSemanticException(super.message, {required this.response});

  final Map<String, Object?> response;
}
