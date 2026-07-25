import 'package:pub_semver/pub_semver.dart';

/// Metadata needed to present and evaluate a published application release.
final class ReleaseInfo {
  /// Creates immutable release metadata.
  ReleaseInfo({
    required this.id,
    required this.version,
    required this.tagName,
    required this.pageUri,
    required DateTime publishedAt,
    this.name,
    this.notes = '',
  }) : publishedAt = publishedAt.toUtc() {
    if (id <= 0) {
      throw ArgumentError.value(id, 'id', 'Must be positive.');
    }
    if (tagName.isEmpty || tagName.trim() != tagName) {
      throw ArgumentError.value(
        tagName,
        'tagName',
        'Must be non-empty and have no surrounding whitespace.',
      );
    }
    final tagVersion = _parseTagVersion(tagName);
    if (tagVersion != version) {
      throw ArgumentError.value(
        version,
        'version',
        'Must exactly match semantic tag "$tagName".',
      );
    }
    if (!pageUri.isAbsolute ||
        pageUri.scheme != 'https' ||
        pageUri.host.isEmpty ||
        pageUri.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        pageUri,
        'pageUri',
        'Must be an absolute HTTPS URI without embedded credentials.',
      );
    }
  }

  /// Provider-assigned immutable release identifier.
  final int id;

  /// Semantic version parsed from [tagName].
  final Version version;

  /// Original, unmodified provider tag.
  final String tagName;

  /// Optional human-readable release title.
  final String? name;

  /// Release notes. An absent provider body is represented as an empty string.
  final String notes;

  /// Browser page used by update prompts.
  final Uri pageUri;

  /// Provider publication time, normalized to UTC.
  final DateTime publishedAt;

  /// Encodes this value for application-owned cache persistence.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'version': version.toString(),
    'tagName': tagName,
    'name': name,
    'notes': notes,
    'pageUrl': pageUri.toString(),
    'publishedAt': publishedAt.toIso8601String(),
  };

  /// Decodes a value previously produced by [toJson].
  ///
  /// Throws [FormatException] when persisted data is absent or malformed.
  factory ReleaseInfo.fromJson(Map<String, Object?> json) {
    final id = _requiredInt(json, 'id');
    final versionText = _requiredString(json, 'version');
    final tagName = _requiredString(json, 'tagName');
    final pageUrl = _requiredString(json, 'pageUrl');
    final publishedAtText = _requiredString(json, 'publishedAt');
    final name = _optionalString(json, 'name');
    final notes = _optionalString(json, 'notes') ?? '';

    final Version version;
    try {
      version = Version.parse(versionText);
    } on FormatException catch (error) {
      throw FormatException(
        'Invalid cached semantic version "$versionText".',
        error,
      );
    }

    final pageUri = Uri.tryParse(pageUrl);
    if (pageUri == null ||
        !pageUri.isAbsolute ||
        pageUri.scheme != 'https' ||
        pageUri.host.isEmpty ||
        pageUri.userInfo.isNotEmpty) {
      throw FormatException('Invalid cached release page URL "$pageUrl".');
    }

    final publishedAt = DateTime.tryParse(publishedAtText);
    if (publishedAt == null) {
      throw FormatException(
        'Invalid cached publication time "$publishedAtText".',
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
      throw FormatException('Invalid cached release metadata.', error);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseInfo &&
          id == other.id &&
          version == other.version &&
          tagName == other.tagName &&
          name == other.name &&
          notes == other.notes &&
          pageUri == other.pageUri &&
          publishedAt == other.publishedAt;

  @override
  int get hashCode =>
      Object.hash(id, version, tagName, name, notes, pageUri, publishedAt);

  @override
  String toString() => 'ReleaseInfo($tagName, $pageUri)';
}

/// A release and HTTP validator cached for a particular [sourceId].
final class ReleaseCacheEntry {
  /// Creates a cache entry.
  ReleaseCacheEntry({
    required this.sourceId,
    required this.release,
    required DateTime validatedAt,
    this.etag,
  }) : validatedAt = validatedAt.toUtc() {
    if (sourceId.isEmpty || sourceId.trim() != sourceId) {
      throw ArgumentError.value(
        sourceId,
        'sourceId',
        'Must be non-empty and have no surrounding whitespace.',
      );
    }
    _validateOptionalEtag(etag);
  }

  /// Stable identity of the source that produced [release].
  final String sourceId;

  /// Last successfully fetched release.
  final ReleaseInfo release;

  /// Opaque HTTP entity tag, preserved exactly for `If-None-Match`.
  final String? etag;

  /// Last successful validation time, normalized to UTC.
  final DateTime validatedAt;

  /// Encodes this entry for application-owned cache persistence.
  Map<String, Object?> toJson() => <String, Object?>{
    'sourceId': sourceId,
    'release': release.toJson(),
    'etag': etag,
    'validatedAt': validatedAt.toIso8601String(),
  };

  /// Decodes an entry previously produced by [toJson].
  ///
  /// Throws [FormatException] when persisted data is absent or malformed.
  factory ReleaseCacheEntry.fromJson(Map<String, Object?> json) {
    final sourceId = _requiredString(json, 'sourceId');
    final etag = _optionalString(json, 'etag');
    final validatedAtText = _requiredString(json, 'validatedAt');
    final releaseValue = json['release'];
    if (releaseValue is! Map<Object?, Object?>) {
      throw const FormatException('Cached field "release" must be an object.');
    }

    final releaseJson = <String, Object?>{};
    for (final entry in releaseValue.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const FormatException(
          'Cached release object contains a non-string key.',
        );
      }
      releaseJson[key] = entry.value;
    }

    final validatedAt = DateTime.tryParse(validatedAtText);
    if (validatedAt == null) {
      throw FormatException(
        'Invalid cached validation time "$validatedAtText".',
      );
    }

    try {
      return ReleaseCacheEntry(
        sourceId: sourceId,
        release: ReleaseInfo.fromJson(releaseJson),
        etag: etag,
        validatedAt: validatedAt,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid cached release entry.', error);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseCacheEntry &&
          sourceId == other.sourceId &&
          release == other.release &&
          etag == other.etag &&
          validatedAt == other.validatedAt;

  @override
  int get hashCode => Object.hash(sourceId, release, etag, validatedAt);
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('Cached field "$key" must be an integer.');
  }
  return value;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Cached field "$key" must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Cached field "$key" must be a string or null.');
  }
  return value;
}

void _validateOptionalEtag(String? etag) {
  if (etag == null) {
    return;
  }
  if (etag.isEmpty ||
      etag.codeUnits.any(
        (codeUnit) =>
            (codeUnit < 0x20 && codeUnit != 0x09) ||
            codeUnit == 0x7f ||
            codeUnit > 0xff,
      )) {
    throw ArgumentError.value(
      etag,
      'etag',
      'Must be a non-empty valid HTTP header value.',
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
    throw ArgumentError.value(
      tagName,
      'tagName',
      'Must contain a semantic version: $error',
    );
  }
}
