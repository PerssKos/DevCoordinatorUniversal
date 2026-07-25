import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

import 'release_models.dart';
import 'release_source.dart';

/// Reads the latest non-draft, non-prerelease GitHub Release.
///
/// The injected [http.Client] remains owned by the caller and is never closed
/// by this source. Public repositories require no credential; callers should
/// never embed repository-maintainer tokens in distributed applications.
final class GitHubReleaseSource implements ReleaseSource {
  GitHubReleaseSource._({
    required http.Client client,
    required String owner,
    required String repository,
    required Uri apiBaseUri,
    required String userAgent,
    required Duration timeout,
  }) : _client = client,
       _timeout = timeout,
       _userAgent = userAgent,
       _latestUri = _buildLatestUri(apiBaseUri, owner, repository),
       sourceId = 'github:${_buildLatestUri(apiBaseUri, owner, repository)}';

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
  }) {
    _validateRepositoryPart(owner, 'owner');
    _validateRepositoryPart(repository, 'repository');
    _validateHeaderValue(userAgent, 'userAgent');
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
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
    );
  }

  static const _githubApiVersion = '2022-11-28';
  static const _maxErrorBodyLength = 2048;

  final http.Client _client;
  final Duration _timeout;
  final String _userAgent;
  final Uri _latestUri;

  @override
  final String sourceId;

  /// GitHub REST endpoint used by this source.
  Uri get endpoint => _latestUri;

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

    final http.Response response;
    try {
      response = await _client
          .get(_latestUri, headers: headers)
          .timeout(_timeout);
    } on TimeoutException catch (error) {
      throw ReleaseTransportException(
        'GitHub release request timed out after $_timeout.',
        uri: _latestUri,
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw ReleaseTransportException(
        'GitHub release request failed.',
        uri: _latestUri,
        cause: error,
      );
    }

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

  ReleaseInfo _parseRelease(List<int> bodyBytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bodyBytes));
    } on Object catch (error) {
      throw ReleasePayloadException(
        'GitHub release response is not valid UTF-8 JSON.',
        uri: _latestUri,
        cause: error,
      );
    }

    if (decoded is! Map<Object?, Object?>) {
      throw ReleasePayloadException(
        'GitHub release response must be a JSON object.',
        uri: _latestUri,
      );
    }

    final json = <String, Object?>{};
    for (final entry in decoded.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ReleasePayloadException(
          'GitHub release response contains a non-string key.',
          uri: _latestUri,
        );
      }
      json[key] = entry.value;
    }

    final id = _requiredInt(json, 'id');
    final tagName = _requiredString(json, 'tag_name');
    final htmlUrl = _requiredString(json, 'html_url');
    final publishedAtText = _requiredString(json, 'published_at');
    final draft = _requiredBool(json, 'draft');
    final prerelease = _requiredBool(json, 'prerelease');
    final name = _nullableString(json, 'name');
    final notes = _nullableString(json, 'body') ?? '';

    if (draft || prerelease) {
      throw ReleasePayloadException(
        'The latest stable endpoint returned a draft or prerelease.',
        uri: _latestUri,
      );
    }

    final version = _parseTagVersion(tagName);
    final pageUri = Uri.tryParse(htmlUrl);
    if (pageUri == null ||
        !pageUri.isAbsolute ||
        pageUri.scheme != 'https' ||
        pageUri.host.isEmpty ||
        pageUri.userInfo.isNotEmpty) {
      throw ReleasePayloadException(
        'GitHub field "html_url" must be an absolute HTTPS URL without '
        'embedded credentials.',
        uri: _latestUri,
      );
    }

    final publishedAt = DateTime.tryParse(publishedAtText);
    if (publishedAt == null) {
      throw ReleasePayloadException(
        'GitHub field "published_at" is not a valid timestamp.',
        uri: _latestUri,
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
      );
    } on ArgumentError catch (error) {
      throw ReleasePayloadException(
        'GitHub release metadata is invalid.',
        uri: _latestUri,
        cause: error,
      );
    }
  }

  Version _parseTagVersion(String tagName) {
    final normalized = tagName.startsWith('v') || tagName.startsWith('V')
        ? tagName.substring(1)
        : tagName;
    try {
      return Version.parse(normalized);
    } on FormatException catch (error) {
      throw ReleasePayloadException(
        'GitHub tag "$tagName" is not a semantic version.',
        uri: _latestUri,
        cause: error,
      );
    }
  }

  int _requiredInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw ReleasePayloadException(
        'GitHub field "$key" must be an integer.',
        uri: _latestUri,
      );
    }
    return value;
  }

  String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty || value.trim() != value) {
      throw ReleasePayloadException(
        'GitHub field "$key" must be a non-empty string.',
        uri: _latestUri,
      );
    }
    return value;
  }

  bool _requiredBool(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! bool) {
      throw ReleasePayloadException(
        'GitHub field "$key" must be a boolean.',
        uri: _latestUri,
      );
    }
    return value;
  }

  String? _nullableString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw ReleasePayloadException(
        'GitHub field "$key" must be a string or null.',
        uri: _latestUri,
      );
    }
    return value;
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
