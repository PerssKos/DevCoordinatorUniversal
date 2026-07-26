import 'release_models.dart';

/// Retrieves the current stable release from a remote provider.
abstract interface class ReleaseSource {
  /// Stable key used to prevent validators being reused across repositories.
  String get sourceId;

  /// Fetches the current stable release.
  ///
  /// [ifNoneMatch] is an opaque validator from an earlier response. A source
  /// returns [ReleaseNotModified] when that validator is still current.
  Future<ReleaseFetchResult> fetchLatest({String? ifNoneMatch});
}

/// Retrieves a bounded catalog of stable releases from a remote provider.
///
/// Catalog consumers can apply platform and distribution-channel eligibility
/// without making provider adapters aware of application-specific file names.
abstract interface class StableReleaseCatalogSource {
  /// Stable key used to prevent validators being reused across catalogs.
  String get catalogSourceId;

  /// Maximum number of provider releases inspected by one request.
  int get maximumCatalogSize;

  /// Fetches a bounded catalog of non-draft, non-prerelease releases.
  Future<ReleaseCatalogFetchResult> fetchStableReleases({String? ifNoneMatch});
}

/// Result of a conditional release fetch.
sealed class ReleaseFetchResult {
  const ReleaseFetchResult({required this.etag});

  /// Response validator, if supplied by the provider.
  final String? etag;
}

/// A provider returned fresh release metadata.
final class ReleaseFetched extends ReleaseFetchResult {
  /// Creates a successful fetch result.
  const ReleaseFetched({required this.release, required super.etag});

  /// Parsed stable release.
  final ReleaseInfo release;
}

/// A provider confirmed that a cached release is still current.
final class ReleaseNotModified extends ReleaseFetchResult {
  /// Creates a not-modified result.
  const ReleaseNotModified({required super.etag});
}

/// Result of a conditional stable-release catalog fetch.
sealed class ReleaseCatalogFetchResult {
  const ReleaseCatalogFetchResult({required this.etag});

  /// Response validator, if supplied by the provider.
  final String? etag;
}

/// A provider returned fresh stable-release metadata.
final class ReleaseCatalogFetched extends ReleaseCatalogFetchResult {
  /// Creates a successful catalog fetch result.
  const ReleaseCatalogFetched({required this.releases, required super.etag});

  /// Stable releases within the source's documented bound.
  final List<ReleaseInfo> releases;
}

/// A provider confirmed that a cached stable catalog is still current.
final class ReleaseCatalogNotModified extends ReleaseCatalogFetchResult {
  /// Creates a not-modified catalog result.
  const ReleaseCatalogNotModified({required super.etag});
}

/// Base class for expected update-service failures.
sealed class ReleaseUpdateException implements Exception {
  /// Creates an expected failure with a user-safe diagnostic [message].
  const ReleaseUpdateException(this.message);

  /// User-safe diagnostic message.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The remote provider could not be reached or did not answer in time.
final class ReleaseTransportException extends ReleaseUpdateException {
  /// Creates a transport failure.
  const ReleaseTransportException(
    super.message, {
    required this.uri,
    required this.cause,
  });

  /// Requested endpoint.
  final Uri uri;

  /// Original client or timeout error.
  final Object cause;
}

/// The provider returned a non-success HTTP response.
final class ReleaseHttpException extends ReleaseUpdateException {
  /// Creates an HTTP failure.
  const ReleaseHttpException(
    super.message, {
    required this.uri,
    required this.statusCode,
    required this.responseBody,
    this.requestId,
    this.retryAfter,
    this.rateLimitRemaining,
    this.rateLimitReset,
  });

  /// Requested endpoint.
  final Uri uri;

  /// HTTP response status.
  final int statusCode;

  /// Bounded, decoded response body useful for diagnostics.
  final String responseBody;

  /// GitHub request identifier, when returned.
  final String? requestId;

  /// Provider retry hint, when returned.
  final String? retryAfter;

  /// Remaining GitHub rate limit, when returned.
  final String? rateLimitRemaining;

  /// GitHub rate-limit reset epoch, when returned.
  final String? rateLimitReset;

  /// Whether response metadata indicates rate limiting.
  bool get isRateLimited =>
      statusCode == 429 ||
      (statusCode == 403 && (rateLimitRemaining == '0' || retryAfter != null));
}

/// A success response did not satisfy the release schema.
final class ReleasePayloadException extends ReleaseUpdateException {
  /// Creates a malformed-payload failure.
  const ReleasePayloadException(super.message, {required this.uri, this.cause});

  /// Requested endpoint.
  final Uri uri;

  /// Lower-level JSON or semantic-version parse error, when available.
  final Object? cause;
}

/// A `304 Not Modified` response could not be paired with cached metadata.
final class ReleaseCacheMissException extends ReleaseUpdateException {
  /// Creates a cache protocol failure.
  const ReleaseCacheMissException(super.message);
}

/// A provider or persisted catalog exceeded its declared structural bound.
final class ReleaseCatalogBoundsException extends ReleaseUpdateException {
  /// Creates a provider-neutral catalog-bound failure.
  const ReleaseCatalogBoundsException(super.message);
}
