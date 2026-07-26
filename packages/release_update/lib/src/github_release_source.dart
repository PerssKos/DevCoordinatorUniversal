import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

import 'release_limits.dart';
import 'release_models.dart';
import 'release_source.dart';

/// Reads the latest non-draft, non-prerelease GitHub Release.
///
/// The injected [http.Client] remains owned by the caller and is never closed
/// by this source. Public repositories require no credential; callers should
/// never embed repository-maintainer tokens in distributed applications.
final class GitHubReleaseSource
    implements ReleaseSource, StableReleaseCatalogSource {
  GitHubReleaseSource._({
    required http.Client client,
    required String owner,
    required String repository,
    required Uri apiBaseUri,
    required String userAgent,
    required Duration timeout,
    required this.maximumCatalogSize,
    required this.maximumResponseBytes,
  }) : _client = client,
       _timeout = timeout,
       _userAgent = userAgent,
       _latestUri = _buildLatestUri(apiBaseUri, owner, repository),
       _catalogUri = _buildCatalogUri(
         apiBaseUri,
         owner,
         repository,
         maximumCatalogSize,
       ),
       sourceId = 'github:${_buildLatestUri(apiBaseUri, owner, repository)}',
       catalogSourceId =
           'github-catalog:${_buildCatalogUri(apiBaseUri, owner, repository, maximumCatalogSize)}';

  /// Creates a source for [owner]/[repository].
  ///
  /// [apiBaseUri] may point at GitHub Enterprise and may contain a path prefix
  /// such as `/api/v3/`. It must not contain credentials, a query, or fragment.
  factory GitHubReleaseSource({
    required http.Client client,
    required String owner,
    required String repository,
    String userAgent = 'release_update.dart',
    Uri? apiBaseUri,
    Duration timeout = const Duration(seconds: 10),
    int maximumCatalogSize = 20,
    int maximumResponseBytes = defaultMaximumResponseBytes,
  }) {
    _validateRepositoryPart(owner, 'owner');
    _validateRepositoryPart(repository, 'repository');
    _validateHeaderValue(userAgent, 'userAgent');
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
    if (maximumCatalogSize < 1 ||
        maximumCatalogSize > maximumReleaseCatalogEntries) {
      throw ArgumentError.value(
        maximumCatalogSize,
        'maximumCatalogSize',
        'Must be between 1 and $maximumReleaseCatalogEntries.',
      );
    }
    if (maximumResponseBytes < 1 ||
        maximumResponseBytes > absoluteMaximumResponseBytes) {
      throw ArgumentError.value(
        maximumResponseBytes,
        'maximumResponseBytes',
        'Must be between 1 and $absoluteMaximumResponseBytes.',
      );
    }

    final baseUri = apiBaseUri ?? Uri.parse('https://api.github.com/');
    _validateApiBaseUri(baseUri);
    return GitHubReleaseSource._(
      client: client,
      owner: owner,
      repository: repository,
      apiBaseUri: baseUri,
      userAgent: userAgent,
      timeout: timeout,
      maximumCatalogSize: maximumCatalogSize,
      maximumResponseBytes: maximumResponseBytes,
    );
  }

  static const _githubApiVersion = '2022-11-28';
  static const _maxErrorBodyLength = 2048;

  final http.Client _client;
  final Duration _timeout;
  final String _userAgent;
  final Uri _latestUri;
  final Uri _catalogUri;

  /// Maximum number of response-body bytes buffered before parsing.
  final int maximumResponseBytes;

  @override
  final String sourceId;

  @override
  final String catalogSourceId;

  @override
  final int maximumCatalogSize;

  /// GitHub REST endpoint used by this source.
  Uri get endpoint => _latestUri;

  /// Bounded GitHub REST endpoint used for stable-release catalog discovery.
  Uri get catalogEndpoint => _catalogUri;

  @override
  Future<ReleaseFetchResult> fetchLatest({String? ifNoneMatch}) async {
    if (ifNoneMatch != null) {
      _validateHeaderValue(ifNoneMatch, 'ifNoneMatch');
    }

    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': _githubApiVersion,
      'User-Agent': _userAgent,
      if (ifNoneMatch != null) 'If-None-Match': ifNoneMatch,
    };

    final response = await _get(
      _latestUri,
      headers: headers,
      requestLabel: 'release',
    );

    final etag = _nonEmptyHeader(response.headers['etag']);
    if (response.statusCode == 304) {
      return ReleaseNotModified(etag: etag);
    }
    if (response.statusCode != 200) {
      throw ReleaseHttpException(
        'GitHub returned HTTP ${response.statusCode}.',
        uri: _latestUri,
        statusCode: response.statusCode,
        responseBody: _boundedBody(response.bodyBytes),
        requestId: _nonEmptyHeader(response.headers['x-github-request-id']),
        retryAfter: _nonEmptyHeader(response.headers['retry-after']),
        rateLimitRemaining: _nonEmptyHeader(
          response.headers['x-ratelimit-remaining'],
        ),
        rateLimitReset: _nonEmptyHeader(response.headers['x-ratelimit-reset']),
      );
    }

    return ReleaseFetched(
      release: _parseRelease(response.bodyBytes),
      etag: etag,
    );
  }

  @override
  Future<ReleaseCatalogFetchResult> fetchStableReleases({
    String? ifNoneMatch,
  }) async {
    if (ifNoneMatch != null) {
      _validateHeaderValue(ifNoneMatch, 'ifNoneMatch');
    }
    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': _githubApiVersion,
      'User-Agent': _userAgent,
      if (ifNoneMatch != null) 'If-None-Match': ifNoneMatch,
    };

    final response = await _get(
      _catalogUri,
      headers: headers,
      requestLabel: 'release catalog',
    );

    final etag = _nonEmptyHeader(response.headers['etag']);
    if (response.statusCode == 304) {
      return ReleaseCatalogNotModified(etag: etag);
    }
    if (response.statusCode != 200) {
      throw ReleaseHttpException(
        'GitHub returned HTTP ${response.statusCode}.',
        uri: _catalogUri,
        statusCode: response.statusCode,
        responseBody: _boundedBody(response.bodyBytes),
        requestId: _nonEmptyHeader(response.headers['x-github-request-id']),
        retryAfter: _nonEmptyHeader(response.headers['retry-after']),
        rateLimitRemaining: _nonEmptyHeader(
          response.headers['x-ratelimit-remaining'],
        ),
        rateLimitReset: _nonEmptyHeader(response.headers['x-ratelimit-reset']),
      );
    }

    return ReleaseCatalogFetched(
      releases: _parseStableCatalog(response.bodyBytes),
      etag: etag,
    );
  }

  Future<_BufferedHttpResponse> _get(
    Uri uri, {
    required Map<String, String> headers,
    required String requestLabel,
  }) async {
    final request = http.Request('GET', uri)..headers.addAll(headers);
    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(_timeout);
    } on TimeoutException catch (error) {
      throw ReleaseTransportException(
        'GitHub $requestLabel request timed out after $_timeout.',
        uri: uri,
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw ReleaseTransportException(
        'GitHub $requestLabel request failed.',
        uri: uri,
        cause: error,
      );
    }

    final bodyBytes = await _readBoundedBody(
      response,
      uri: uri,
      requestLabel: requestLabel,
    );
    return _BufferedHttpResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      bodyBytes: bodyBytes,
    );
  }

  Future<List<int>> _readBoundedBody(
    http.StreamedResponse response, {
    required Uri uri,
    required String requestLabel,
  }) async {
    final contentLength = response.contentLength;
    if (contentLength != null && contentLength > maximumResponseBytes) {
      final subscription = response.stream.listen((_) {});
      await subscription.cancel();
      throw ReleasePayloadException(
        'GitHub $requestLabel response exceeded the '
        '$maximumResponseBytes-byte limit.',
        uri: uri,
      );
    }

    final bytes = BytesBuilder(copy: false);
    final completion = Completer<List<int>>();
    StreamSubscription<List<int>>? subscription;
    var cancelWhenReady = false;

    void cancelStream() {
      final activeSubscription = subscription;
      if (activeSubscription == null) {
        cancelWhenReady = true;
      } else {
        unawaited(activeSubscription.cancel());
      }
    }

    void completeError(Object error, StackTrace stackTrace) {
      if (completion.isCompleted) return;
      completion.completeError(error, stackTrace);
      cancelStream();
    }

    final timer = Timer(_timeout, () {
      completeError(
        ReleaseTransportException(
          'GitHub $requestLabel response timed out after $_timeout.',
          uri: uri,
          cause: TimeoutException(
            'Response body did not complete within $_timeout.',
            _timeout,
          ),
        ),
        StackTrace.current,
      );
    });

    subscription = response.stream.listen(
      (chunk) {
        if (completion.isCompleted) return;
        if (bytes.length + chunk.length > maximumResponseBytes) {
          completeError(
            ReleasePayloadException(
              'GitHub $requestLabel response exceeded the '
              '$maximumResponseBytes-byte limit.',
              uri: uri,
            ),
            StackTrace.current,
          );
          return;
        }
        bytes.add(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        completeError(
          ReleaseTransportException(
            'GitHub $requestLabel response failed.',
            uri: uri,
            cause: error,
          ),
          stackTrace,
        );
      },
      onDone: () {
        if (!completion.isCompleted) {
          completion.complete(bytes.takeBytes());
        }
      },
      cancelOnError: true,
    );
    if (cancelWhenReady) {
      unawaited(subscription.cancel());
    }

    try {
      return await completion.future;
    } finally {
      timer.cancel();
    }
  }

  ReleaseInfo _parseRelease(List<int> bodyBytes) {
    final decoded = _decodeJson(bodyBytes, _latestUri);
    if (decoded is! Map<Object?, Object?>) {
      throw ReleasePayloadException(
        'GitHub release response must be a JSON object.',
        uri: _latestUri,
      );
    }
    return _parseReleaseObject(decoded, uri: _latestUri, requireStable: true);
  }

  List<ReleaseInfo> _parseStableCatalog(List<int> bodyBytes) {
    final decoded = _decodeJson(bodyBytes, _catalogUri);
    if (decoded is! List<Object?>) {
      throw ReleasePayloadException(
        'GitHub release catalog response must be a JSON array.',
        uri: _catalogUri,
      );
    }
    if (decoded.length > maximumCatalogSize) {
      throw ReleasePayloadException(
        'GitHub release catalog exceeded the requested bound.',
        uri: _catalogUri,
      );
    }
    final releases = <ReleaseInfo>[];
    for (final value in decoded) {
      if (value is! Map<Object?, Object?>) {
        continue;
      }
      try {
        final json = _stringKeyedObject(value, _catalogUri);
        final draft = _requiredBool(json, 'draft', _catalogUri);
        final prerelease = _requiredBool(json, 'prerelease', _catalogUri);
        if (draft || prerelease) {
          continue;
        }
        final tagName = json['tag_name'];
        if (tagName is! String ||
            tagName.isEmpty ||
            tagName.length > maximumTagNameLength ||
            tagName.trim() != tagName) {
          continue;
        }
        final version = _tryParseTagVersion(tagName);
        if (version == null) {
          continue;
        }
        releases.add(
          _parseReleaseJson(
            json,
            uri: _catalogUri,
            requireStable: false,
            parsedVersion: version,
          ),
        );
      } on ReleasePayloadException {
        // Catalog records are independent candidates. A malformed record is
        // ineligible itself, but must not hide an older valid target.
        continue;
      }
    }
    try {
      return ReleaseCatalogCacheEntry(
        sourceId: catalogSourceId,
        releases: releases,
        validatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ).releases;
    } on ArgumentError catch (error) {
      throw ReleasePayloadException(
        'GitHub release catalog contains duplicate identities or ambiguous '
        'semantic-version precedence.',
        uri: _catalogUri,
        cause: error,
      );
    }
  }

  Object? _decodeJson(List<int> bodyBytes, Uri uri) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bodyBytes));
    } on Object catch (error) {
      throw ReleasePayloadException(
        'GitHub release response is not valid UTF-8 JSON.',
        uri: uri,
        cause: error,
      );
    }
    return decoded;
  }

  ReleaseInfo _parseReleaseObject(
    Map<Object?, Object?> value, {
    required Uri uri,
    required bool requireStable,
  }) => _parseReleaseJson(
    _stringKeyedObject(value, uri),
    uri: uri,
    requireStable: requireStable,
  );

  ReleaseInfo _parseReleaseJson(
    Map<String, Object?> json, {
    required Uri uri,
    required bool requireStable,
    Version? parsedVersion,
  }) {
    final id = _requiredInt(json, 'id', uri);
    final tagName = _requiredString(
      json,
      'tag_name',
      uri,
      maximumLength: maximumTagNameLength,
    );
    final htmlUrl = _requiredString(
      json,
      'html_url',
      uri,
      maximumLength: maximumUriLength,
    );
    final publishedAtText = _requiredString(
      json,
      'published_at',
      uri,
      maximumLength: maximumTimestampLength,
    );
    final draft = _requiredBool(json, 'draft', uri);
    final prerelease = _requiredBool(json, 'prerelease', uri);
    final name = _nullableString(
      json,
      'name',
      uri,
      maximumLength: maximumReleaseNameLength,
    );
    final notes =
        _nullableString(
          json,
          'body',
          uri,
          maximumLength: maximumReleaseNotesLength,
        ) ??
        '';
    final assets = _parseAssets(json['assets'], uri);

    if (requireStable && (draft || prerelease)) {
      throw ReleasePayloadException(
        'The latest stable endpoint returned a draft or prerelease.',
        uri: uri,
      );
    }

    final version = parsedVersion ?? _parseTagVersion(tagName, uri);
    final pageUri = Uri.tryParse(htmlUrl);
    if (pageUri == null ||
        !pageUri.isAbsolute ||
        pageUri.scheme != 'https' ||
        pageUri.host.isEmpty ||
        pageUri.userInfo.isNotEmpty) {
      throw ReleasePayloadException(
        'GitHub field "html_url" must be an absolute HTTPS URL without '
        'embedded credentials.',
        uri: uri,
      );
    }

    final publishedAt = DateTime.tryParse(publishedAtText);
    if (publishedAt == null) {
      throw ReleasePayloadException(
        'GitHub field "published_at" is not a valid timestamp.',
        uri: uri,
      );
    }

    try {
      return ReleaseInfo(
        id: id,
        version: version,
        tagName: tagName,
        name: name,
        notes: notes,
        pageUri: pageUri,
        publishedAt: publishedAt,
        assets: assets,
      );
    } on ArgumentError catch (error) {
      throw ReleasePayloadException(
        'GitHub release metadata is invalid.',
        uri: uri,
        cause: error,
      );
    }
  }

  List<ReleaseAsset> _parseAssets(Object? value, Uri uri) {
    if (value is! List<Object?>) {
      throw ReleasePayloadException(
        'GitHub field "assets" must be an array.',
        uri: uri,
      );
    }
    if (value.length > maximumReleaseAssets) {
      throw ReleasePayloadException(
        'GitHub field "assets" exceeded the supported bound.',
        uri: uri,
      );
    }

    final candidates = <ReleaseAsset>[];
    final taintedIds = <int>{};
    final taintedNames = <String>{};
    for (final item in value) {
      if (item is! Map<Object?, Object?>) {
        continue;
      }
      final rawId = item['id'];
      final rawName = item['name'];
      final potentialId = rawId is int && rawId > 0 ? rawId : null;
      final potentialName = _potentialAssetName(rawName);
      try {
        final json = _stringKeyedObject(item, uri);
        final state = _requiredString(json, 'state', uri, maximumLength: 32);
        if (state != 'uploaded') {
          if (potentialId != null) taintedIds.add(potentialId);
          if (potentialName != null) taintedNames.add(potentialName);
          continue;
        }

        final id = _requiredInt(json, 'id', uri);
        final name = _requiredString(
          json,
          'name',
          uri,
          maximumLength: maximumAssetNameLength,
        );
        final downloadUrl = _requiredString(
          json,
          'browser_download_url',
          uri,
          maximumLength: maximumUriLength,
        );
        final contentType = _requiredString(
          json,
          'content_type',
          uri,
          maximumLength: maximumContentTypeLength,
        );
        final sizeInBytes = _requiredInt(json, 'size', uri);
        final downloadUri = Uri.tryParse(downloadUrl);
        if (downloadUri == null) {
          throw ReleasePayloadException(
            'GitHub release asset "$name" has an invalid download URL.',
            uri: uri,
          );
        }
        candidates.add(
          ReleaseAsset(
            id: id,
            name: name,
            downloadUri: downloadUri,
            contentType: contentType,
            sizeInBytes: sizeInBytes,
          ),
        );
      } on ReleasePayloadException {
        if (potentialId != null) taintedIds.add(potentialId);
        if (potentialName != null) taintedNames.add(potentialName);
      } on ArgumentError {
        if (potentialId != null) taintedIds.add(potentialId);
        if (potentialName != null) taintedNames.add(potentialName);
      }
    }

    final idCounts = <int, int>{};
    final nameCounts = <String, int>{};
    for (final asset in candidates) {
      idCounts.update(asset.id, (count) => count + 1, ifAbsent: () => 1);
      nameCounts.update(asset.name, (count) => count + 1, ifAbsent: () => 1);
    }
    return List<ReleaseAsset>.unmodifiable(
      candidates.where(
        (asset) =>
            idCounts[asset.id] == 1 &&
            nameCounts[asset.name] == 1 &&
            !taintedIds.contains(asset.id) &&
            !taintedNames.contains(asset.name),
      ),
    );
  }

  Version _parseTagVersion(String tagName, Uri uri) {
    final version = _tryParseTagVersion(tagName);
    if (version != null) {
      return version;
    }
    throw ReleasePayloadException(
      'GitHub tag "$tagName" is not a semantic version.',
      uri: uri,
    );
  }

  Version? _tryParseTagVersion(String tagName) {
    final normalized = tagName.startsWith('v') || tagName.startsWith('V')
        ? tagName.substring(1)
        : tagName;
    try {
      return Version.parse(normalized);
    } on FormatException {
      return null;
    }
  }

  int _requiredInt(Map<String, Object?> json, String key, Uri uri) {
    final value = json[key];
    if (value is! int) {
      throw ReleasePayloadException(
        'GitHub field "$key" must be an integer.',
        uri: uri,
      );
    }
    return value;
  }

  String _requiredString(
    Map<String, Object?> json,
    String key,
    Uri uri, {
    required int maximumLength,
  }) {
    final value = json[key];
    if (value is! String ||
        value.isEmpty ||
        value.length > maximumLength ||
        value.trim() != value) {
      throw ReleasePayloadException(
        'GitHub field "$key" must be a non-empty string.',
        uri: uri,
      );
    }
    return value;
  }

  bool _requiredBool(Map<String, Object?> json, String key, Uri uri) {
    final value = json[key];
    if (value is! bool) {
      throw ReleasePayloadException(
        'GitHub field "$key" must be a boolean.',
        uri: uri,
      );
    }
    return value;
  }

  String? _nullableString(
    Map<String, Object?> json,
    String key,
    Uri uri, {
    required int maximumLength,
  }) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is! String || value.length > maximumLength) {
      throw ReleasePayloadException(
        'GitHub field "$key" must be a string or null.',
        uri: uri,
      );
    }
    return value;
  }

  String? _potentialAssetName(Object? value) {
    if (value is! String ||
        value.isEmpty ||
        value.length > maximumAssetNameLength ||
        value.trim() != value ||
        value.contains('/') ||
        value.contains('\\') ||
        value.codeUnits.any(
          (codeUnit) => codeUnit < 0x20 || codeUnit == 0x7f,
        )) {
      return null;
    }
    return value;
  }

  Map<String, Object?> _stringKeyedObject(
    Map<Object?, Object?> value,
    Uri uri,
  ) {
    final json = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ReleasePayloadException(
          'GitHub response contains a non-string object key.',
          uri: uri,
        );
      }
      json[key] = entry.value;
    }
    return json;
  }

  static Uri _buildLatestUri(Uri apiBaseUri, String owner, String repository) {
    final prefix = apiBaseUri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: true);
    return Uri(
      scheme: apiBaseUri.scheme,
      host: apiBaseUri.host,
      port: apiBaseUri.hasPort ? apiBaseUri.port : null,
      pathSegments: <String>[
        ...prefix,
        'repos',
        owner,
        repository,
        'releases',
        'latest',
      ],
    );
  }

  static Uri _buildCatalogUri(
    Uri apiBaseUri,
    String owner,
    String repository,
    int maximumCatalogSize,
  ) {
    final latestUri = _buildLatestUri(apiBaseUri, owner, repository);
    return latestUri.replace(
      pathSegments: <String>[
        ...latestUri.pathSegments.take(latestUri.pathSegments.length - 1),
      ],
      queryParameters: <String, String>{
        'per_page': maximumCatalogSize.toString(),
      },
    );
  }

  static void _validateRepositoryPart(String value, String name) {
    if (value.isEmpty ||
        value.trim() != value ||
        value == '.' ||
        value == '..' ||
        value.contains('/') ||
        value.contains('\\')) {
      throw ArgumentError.value(
        value,
        name,
        'Must be one non-empty repository path segment.',
      );
    }
  }

  static void _validateApiBaseUri(Uri uri) {
    if (!uri.isAbsolute ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError.value(
        uri,
        'apiBaseUri',
        'Must be an absolute HTTPS URI without credentials, query, or '
            'fragment.',
      );
    }
  }

  static void _validateHeaderValue(String value, String name) {
    if (value.isEmpty || value.codeUnits.any(_isInvalidHeaderCodeUnit)) {
      throw ArgumentError.value(
        value,
        name,
        'Must be a non-empty valid HTTP header value.',
      );
    }
  }

  static String? _nonEmptyHeader(String? value) =>
      value == null || value.isEmpty ? null : value;

  static bool _isInvalidHeaderCodeUnit(int codeUnit) =>
      (codeUnit < 0x20 && codeUnit != 0x09) ||
      codeUnit == 0x7f ||
      codeUnit > 0xff;

  static String _boundedBody(List<int> bytes) {
    final decoded = utf8.decode(bytes, allowMalformed: true);
    if (decoded.length <= _maxErrorBodyLength) {
      return decoded;
    }
    return decoded.substring(0, _maxErrorBodyLength);
  }
}

final class _BufferedHttpResponse {
  const _BufferedHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<int> bodyBytes;
}
