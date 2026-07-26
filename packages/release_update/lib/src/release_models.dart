import 'package:pub_semver/pub_semver.dart';

import 'release_limits.dart';
import 'semver_precedence.dart';

/// One immutable downloadable artifact attached to a release.
///
/// Provider adapters may expose more metadata, but update policy only relies on
/// the stable identifier, exact file name, HTTPS download URI, media type, and
/// byte size represented here.
final class ReleaseAsset {
  /// Creates validated release-asset metadata.
  ReleaseAsset({
    required this.id,
    required this.name,
    required this.downloadUri,
    this.contentType,
    this.sizeInBytes,
  }) {
    if (id <= 0) {
      throw ArgumentError.value(id, 'id', 'Must be positive.');
    }
    if (name.isEmpty ||
        name.length > maximumAssetNameLength ||
        name.trim() != name ||
        name.contains('/') ||
        name.contains('\\') ||
        name.codeUnits.any((codeUnit) => codeUnit < 0x20 || codeUnit == 0x7f)) {
      throw ArgumentError.value(
        name,
        'name',
        'Must be one non-empty file name without surrounding whitespace, '
            'path separators, or control characters.',
      );
    }
    if (!downloadUri.isAbsolute ||
        downloadUri.toString().length > maximumUriLength ||
        downloadUri.scheme != 'https' ||
        downloadUri.host.isEmpty ||
        downloadUri.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        downloadUri,
        'downloadUri',
        'Must be an absolute HTTPS URI without embedded credentials.',
      );
    }
    final mediaType = contentType;
    if (mediaType != null &&
        (mediaType.isEmpty ||
            mediaType.length > maximumContentTypeLength ||
            mediaType.trim() != mediaType)) {
      throw ArgumentError.value(
        mediaType,
        'contentType',
        'Must be null or a non-empty value without surrounding whitespace.',
      );
    }
    final byteSize = sizeInBytes;
    if (byteSize != null && byteSize < 0) {
      throw ArgumentError.value(
        byteSize,
        'sizeInBytes',
        'Must be null or non-negative.',
      );
    }
  }

  /// Provider-assigned immutable asset identifier.
  final int id;

  /// Exact provider file name.
  final String name;

  /// Provider download URI.
  final Uri downloadUri;

  /// Provider media type, when available.
  final String? contentType;

  /// Provider byte size, when available.
  final int? sizeInBytes;

  /// Encodes this value for application-owned cache persistence.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'downloadUrl': downloadUri.toString(),
    'contentType': contentType,
    'sizeInBytes': sizeInBytes,
  };

  /// Decodes a value previously produced by [toJson].
  factory ReleaseAsset.fromJson(Map<String, Object?> json) {
    final id = _requiredInt(json, 'id');
    final name = _requiredString(
      json,
      'name',
      maximumLength: maximumAssetNameLength,
    );
    final downloadUrl = _requiredString(
      json,
      'downloadUrl',
      maximumLength: maximumUriLength,
    );
    final contentType = _optionalString(
      json,
      'contentType',
      maximumLength: maximumContentTypeLength,
    );
    final sizeInBytes = _optionalInt(json, 'sizeInBytes');
    final downloadUri = Uri.tryParse(downloadUrl);
    if (downloadUri == null) {
      throw FormatException('Invalid cached asset URL "$downloadUrl".');
    }
    try {
      return ReleaseAsset(
        id: id,
        name: name,
        downloadUri: downloadUri,
        contentType: contentType,
        sizeInBytes: sizeInBytes,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid cached release asset.', error);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseAsset &&
          id == other.id &&
          name == other.name &&
          downloadUri == other.downloadUri &&
          contentType == other.contentType &&
          sizeInBytes == other.sizeInBytes;

  @override
  int get hashCode =>
      Object.hash(id, name, downloadUri, contentType, sizeInBytes);

  @override
  String toString() => 'ReleaseAsset($name, $downloadUri)';
}

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
    List<ReleaseAsset> assets = const <ReleaseAsset>[],
  }) : publishedAt = publishedAt.toUtc(),
       assets = List<ReleaseAsset>.unmodifiable(assets) {
    if (id <= 0) {
      throw ArgumentError.value(id, 'id', 'Must be positive.');
    }
    if (tagName.isEmpty ||
        tagName.length > maximumTagNameLength ||
        tagName.trim() != tagName) {
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
        pageUri.toString().length > maximumUriLength ||
        pageUri.scheme != 'https' ||
        pageUri.host.isEmpty ||
        pageUri.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        pageUri,
        'pageUri',
        'Must be an absolute HTTPS URI without embedded credentials.',
      );
    }
    final releaseName = name;
    if (releaseName != null &&
        (releaseName.length > maximumReleaseNameLength ||
            releaseName.codeUnits.any(_isControlCodeUnit))) {
      throw ArgumentError.value(
        releaseName,
        'name',
        'Must not exceed $maximumReleaseNameLength characters or contain '
            'control characters.',
      );
    }
    if (notes.length > maximumReleaseNotesLength) {
      throw ArgumentError.value(
        notes,
        'notes',
        'Must not exceed $maximumReleaseNotesLength characters.',
      );
    }
    if (assets.length > maximumReleaseAssets) {
      throw ArgumentError.value(
        assets,
        'assets',
        'Must not contain more than $maximumReleaseAssets entries.',
      );
    }
    final assetIds = <int>{};
    final assetNames = <String>{};
    for (final asset in assets) {
      if (!assetIds.add(asset.id) || !assetNames.add(asset.name)) {
        throw ArgumentError.value(
          assets,
          'assets',
          'Must not contain duplicate asset identifiers or names.',
        );
      }
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

  /// Downloadable artifacts attached to this release.
  final List<ReleaseAsset> assets;

  /// Encodes this value for application-owned cache persistence.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'version': version.toString(),
    'tagName': tagName,
    'name': name,
    'notes': notes,
    'pageUrl': pageUri.toString(),
    'publishedAt': publishedAt.toIso8601String(),
    'assets': assets.map((asset) => asset.toJson()).toList(growable: false),
  };

  /// Decodes a value previously produced by [toJson].
  ///
  /// Throws [FormatException] when persisted data is absent or malformed.
  factory ReleaseInfo.fromJson(Map<String, Object?> json) {
    final id = _requiredInt(json, 'id');
    final versionText = _requiredString(
      json,
      'version',
      maximumLength: maximumTagNameLength,
    );
    final tagName = _requiredString(
      json,
      'tagName',
      maximumLength: maximumTagNameLength,
    );
    final pageUrl = _requiredString(
      json,
      'pageUrl',
      maximumLength: maximumUriLength,
    );
    final publishedAtText = _requiredString(
      json,
      'publishedAt',
      maximumLength: maximumTimestampLength,
    );
    final name = _optionalString(
      json,
      'name',
      maximumLength: maximumReleaseNameLength,
    );
    final notes =
        _optionalString(
          json,
          'notes',
          maximumLength: maximumReleaseNotesLength,
        ) ??
        '';
    final assets = _decodeCachedAssets(json['assets']);

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
        assets: assets,
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
          publishedAt == other.publishedAt &&
          _listEquals(assets, other.assets);

  @override
  int get hashCode => Object.hash(
    id,
    version,
    tagName,
    name,
    notes,
    pageUri,
    publishedAt,
    Object.hashAll(assets),
  );

  @override
  String toString() => 'ReleaseInfo($tagName, $pageUri)';
}

/// A bounded stable-release catalog and validator cached for one source.
final class ReleaseCatalogCacheEntry {
  /// Creates a catalog cache entry.
  ReleaseCatalogCacheEntry({
    required this.sourceId,
    required List<ReleaseInfo> releases,
    required DateTime validatedAt,
    this.etag,
  }) : releases = List<ReleaseInfo>.unmodifiable(releases),
       validatedAt = validatedAt.toUtc() {
    if (sourceId.isEmpty ||
        sourceId.length > maximumSourceIdLength ||
        sourceId.trim() != sourceId) {
      throw ArgumentError.value(
        sourceId,
        'sourceId',
        'Must be non-empty and have no surrounding whitespace.',
      );
    }
    _validateOptionalEtag(etag);
    if (releases.length > maximumReleaseCatalogEntries) {
      throw ArgumentError.value(
        releases,
        'releases',
        'Must not contain more than $maximumReleaseCatalogEntries entries.',
      );
    }
    final ids = <int>{};
    final versions = <Version>[];
    for (final release in releases) {
      final hasAmbiguousVersion = versions.any(
        (version) => compareSemVerPrecedence(version, release.version) == 0,
      );
      if (!ids.add(release.id) || hasAmbiguousVersion) {
        throw ArgumentError.value(
          releases,
          'releases',
          'Must not contain duplicate release identifiers or ambiguous '
              'semantic-version precedence.',
        );
      }
      versions.add(release.version);
    }
  }

  /// Stable identity of the catalog source.
  final String sourceId;

  /// Bounded stable releases returned by the provider.
  final List<ReleaseInfo> releases;

  /// Opaque HTTP entity tag, preserved exactly for `If-None-Match`.
  final String? etag;

  /// Last successful validation time, normalized to UTC.
  final DateTime validatedAt;

  /// Encodes this entry for application-owned cache persistence.
  Map<String, Object?> toJson() => <String, Object?>{
    'sourceId': sourceId,
    'releases': releases
        .map((release) => release.toJson())
        .toList(growable: false),
    'etag': etag,
    'validatedAt': validatedAt.toIso8601String(),
  };

  /// Decodes an entry previously produced by [toJson].
  factory ReleaseCatalogCacheEntry.fromJson(Map<String, Object?> json) {
    final sourceId = _requiredString(
      json,
      'sourceId',
      maximumLength: maximumSourceIdLength,
    );
    final etag = _optionalString(
      json,
      'etag',
      maximumLength: maximumEtagLength,
    );
    final validatedAtText = _requiredString(
      json,
      'validatedAt',
      maximumLength: maximumTimestampLength,
    );
    final releasesValue = json['releases'];
    if (releasesValue is! List<Object?>) {
      throw const FormatException('Cached field "releases" must be an array.');
    }
    if (releasesValue.length > maximumReleaseCatalogEntries) {
      throw const FormatException(
        'Cached field "releases" exceeds the supported bound.',
      );
    }
    final releases = <ReleaseInfo>[];
    for (final value in releasesValue) {
      releases.add(ReleaseInfo.fromJson(_stringKeyedMap(value, 'release')));
    }
    final validatedAt = DateTime.tryParse(validatedAtText);
    if (validatedAt == null) {
      throw FormatException(
        'Invalid cached validation time "$validatedAtText".',
      );
    }
    try {
      return ReleaseCatalogCacheEntry(
        sourceId: sourceId,
        releases: releases,
        etag: etag,
        validatedAt: validatedAt,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid cached release catalog.', error);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseCatalogCacheEntry &&
          sourceId == other.sourceId &&
          _listEquals(releases, other.releases) &&
          etag == other.etag &&
          validatedAt == other.validatedAt;

  @override
  int get hashCode =>
      Object.hash(sourceId, Object.hashAll(releases), etag, validatedAt);
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
    if (sourceId.isEmpty ||
        sourceId.length > maximumSourceIdLength ||
        sourceId.trim() != sourceId) {
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
    final sourceId = _requiredString(
      json,
      'sourceId',
      maximumLength: maximumSourceIdLength,
    );
    final etag = _optionalString(
      json,
      'etag',
      maximumLength: maximumEtagLength,
    );
    final validatedAtText = _requiredString(
      json,
      'validatedAt',
      maximumLength: maximumTimestampLength,
    );
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

int? _optionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! int) {
    throw FormatException('Cached field "$key" must be an integer or null.');
  }
  return value;
}

String _requiredString(
  Map<String, Object?> json,
  String key, {
  int? maximumLength,
}) {
  final value = json[key];
  if (value is! String ||
      value.isEmpty ||
      (maximumLength != null && value.length > maximumLength)) {
    throw FormatException('Cached field "$key" must be a non-empty string.');
  }
  return value;
}

String? _optionalString(
  Map<String, Object?> json,
  String key, {
  int? maximumLength,
}) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String ||
      (maximumLength != null && value.length > maximumLength)) {
    throw FormatException('Cached field "$key" must be a string or null.');
  }
  return value;
}

List<ReleaseAsset> _decodeCachedAssets(Object? value) {
  // Caches written before release assets were modeled remain readable. They
  // deliberately become an empty list so a direct channel fails closed until
  // its next catalog refresh instead of trusting an unrecorded artifact.
  if (value == null) {
    return const <ReleaseAsset>[];
  }
  if (value is! List<Object?>) {
    throw const FormatException('Cached field "assets" must be an array.');
  }
  if (value.length > maximumReleaseAssets) {
    throw const FormatException(
      'Cached field "assets" exceeds the supported bound.',
    );
  }
  return List<ReleaseAsset>.unmodifiable(
    value.map(
      (asset) => ReleaseAsset.fromJson(_stringKeyedMap(asset, 'asset')),
    ),
  );
}

Map<String, Object?> _stringKeyedMap(Object? value, String label) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('Cached $label must be an object.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key case final String key) {
      result[key] = entry.value;
    } else {
      throw FormatException('Cached $label contains a non-string key.');
    }
  }
  return result;
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _validateOptionalEtag(String? etag) {
  if (etag == null) {
    return;
  }
  if (etag.isEmpty ||
      etag.length > maximumEtagLength ||
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

bool _isControlCodeUnit(int codeUnit) => codeUnit < 0x20 || codeUnit == 0x7f;

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
