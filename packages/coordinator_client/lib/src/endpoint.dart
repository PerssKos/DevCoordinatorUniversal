import 'errors.dart';

enum CoordinatorConnectionKind { legacyLoopbackV1, nativeGatewayV2 }

/// A validated coordinator origin.
///
/// Legacy v1 is intentionally limited to literal IPv4 loopback or
/// `localhost`. Native v2 is HTTPS-only and has no implicit downgrade path.
final class CoordinatorEndpoint {
  CoordinatorEndpoint._(this.uri, this.kind);

  factory CoordinatorEndpoint.legacyV1(Uri uri) {
    _validateCommon(uri);
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const CoordinatorEndpointException(
        'Legacy v1 requires an HTTP or HTTPS URL.',
      );
    }
    if (!_isAllowedLegacyHost(uri.host)) {
      throw const CoordinatorEndpointException(
        'Legacy v1 is allowed only on localhost or 127.0.0.0/8.',
      );
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      throw const CoordinatorEndpointException(
        'Legacy v1 endpoint must not contain a path prefix.',
      );
    }
    return CoordinatorEndpoint._(
      uri.replace(path: '', query: null, fragment: null),
      CoordinatorConnectionKind.legacyLoopbackV1,
    );
  }

  factory CoordinatorEndpoint.nativeV2(Uri uri) {
    _validateCommon(uri);
    if (uri.scheme != 'https') {
      throw const CoordinatorEndpointException(
        'Native gateway v2 requires HTTPS.',
      );
    }
    final normalizedPath = uri.path == '/'
        ? ''
        : uri.path.replaceFirst(RegExp(r'/+$'), '');
    return CoordinatorEndpoint._(
      uri.replace(path: normalizedPath, query: null, fragment: null),
      CoordinatorConnectionKind.nativeGatewayV2,
    );
  }

  final Uri uri;
  final CoordinatorConnectionKind kind;

  Uri resolve(String absolutePath, [Map<String, String>? queryParameters]) {
    if (!absolutePath.startsWith('/')) {
      throw const CoordinatorEndpointException(
        'Coordinator request paths must be absolute.',
      );
    }
    final prefix = uri.path;
    return uri.replace(
      path: '$prefix$absolutePath',
      queryParameters: (queryParameters?.isEmpty ?? true)
          ? null
          : queryParameters,
    );
  }

  static void _validateCommon(Uri uri) {
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw const CoordinatorEndpointException(
        'Coordinator endpoint must be an absolute URL with a host.',
      );
    }
    if (uri.userInfo.isNotEmpty) {
      throw const CoordinatorEndpointException(
        'Coordinator endpoint must not contain credentials.',
      );
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw const CoordinatorEndpointException(
        'Coordinator endpoint must not contain a query or fragment.',
      );
    }
  }

  static bool _isAllowedLegacyHost(String host) {
    final normalized = host.toLowerCase();
    if (normalized == 'localhost') {
      return true;
    }
    final parts = normalized.split('.');
    if (parts.length != 4) {
      return false;
    }
    final octets = parts.map(int.tryParse).toList(growable: false);
    return octets.every(
          (value) => value != null && value >= 0 && value <= 255,
        ) &&
        octets.first == 127;
  }
}
