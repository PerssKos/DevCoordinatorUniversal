import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';
import 'package:release_update/release_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_services.dart';

/// App-facing update adapter.
///
/// Production builds select their repository and Store handoff with Dart
/// defines: `UPDATE_REPOSITORY=owner/repository`,
/// `UPDATE_DESTINATION_URL=https://…`, and (where assigned by the Store)
/// `UPDATE_STORE_PRODUCT_ID=…`.
/// No maintainer credential is embedded in the application.
final class RepositoryAppUpdateService implements AppUpdateService {
  RepositoryAppUpdateService({
    required this.target,
    http.Client? httpClient,
    String repositorySlug = const String.fromEnvironment('UPDATE_REPOSITORY'),
    String destinationUrl = const String.fromEnvironment(
      'UPDATE_DESTINATION_URL',
    ),
    String storeProductId = const String.fromEnvironment(
      'UPDATE_STORE_PRODUCT_ID',
    ),
    Future<bool> Function(Uri destination)? launcher,
    DateTime Function()? clock,
    UpdatePolicy? policy,
  }) : _client = httpClient ?? http.Client(),
       _repositorySlug = repositorySlug.trim(),
       _destinationUri = _parseDestination(destinationUrl),
       _storeProductId = target.normalizedStoreProductIdentity(
         storeProductId.trim(),
       ),
       _launcher = launcher ?? _launchExternal,
       _clock = clock ?? DateTime.now,
       _policy = policy ?? UpdatePolicy() {
    if (target.isDirect && _destinationUri != null) {
      throw ArgumentError(
        'Direct builds must not set UPDATE_DESTINATION_URL; their update '
        'action opens the exact verified repository asset.',
      );
    }
    if (!target.isDirect && _destinationUri == null) {
      throw ArgumentError(
        '${target.channel.configurationValue} builds require an explicit '
        'HTTPS UPDATE_DESTINATION_URL.',
      );
    }
    target.requireValidStoreConfiguration(
      destination: _destinationUri,
      configuredProductId: _storeProductId,
    );
  }

  final http.Client _client;
  final AppUpdateTarget target;
  final String _repositorySlug;
  final Uri? _destinationUri;
  final String _storeProductId;
  final Future<bool> Function(Uri destination) _launcher;
  final DateTime Function() _clock;
  final UpdatePolicy _policy;

  @override
  Future<AppUpdateResult> check({
    required String currentVersion,
    required bool manual,
    DateTime? lastCheckedAt,
    Map<String, Object?>? releaseCache,
    Map<String, Object?>? updateSuppression,
  }) async {
    if (_repositorySlug.isEmpty) {
      if (manual) {
        throw StateError(
          'Release source is not configured for this build. Rebuild with '
          'UPDATE_REPOSITORY=owner/repository.',
        );
      }
      return AppUpdateResult(
        releaseCache: releaseCache,
        updateSuppression: updateSuppression,
      );
    }

    final installed = _parseInstalledVersion(currentVersion);
    final cache = _decodeCatalogCache(releaseCache);
    final suppression = _decodeSuppression(updateSuppression);
    final now = _clock().toUtc();

    final repository = _configuredRepository();
    final source = _sourceFor(repository);
    final result = await ReleaseCatalogChecker(source: source).check(
      cache: cache,
      reason: manual ? UpdateCheckReason.manual : UpdateCheckReason.automatic,
      now: now,
    );
    final releases = result.cache.releases;
    for (final release in releases) {
      _requireConfiguredRepositoryRelease(release, repository);
    }
    final selection = const ReleaseCatalogPolicy().select(
      releases: releases,
      isEligible: (release) => _hasEligibleTargetAsset(release, repository),
    );
    final latestPublished = selection.latestPublished;
    final latestCompatible = selection.latestCompatible;
    if (latestCompatible == null) {
      return AppUpdateResult(
        message: manual
            ? _noCompatibleUpdateMessage(
                installed: installed,
                latestPublished: latestPublished,
                latestCompatible: null,
                catalogBound: source.maximumCatalogSize,
              )
            : null,
        checkedAt: result.cache.validatedAt,
        releaseCache: result.cache.toJson(),
        updateSuppression: suppression.toJson(),
      );
    }

    final decision = _policy.evaluate(
      currentVersion: installed,
      latestRelease: latestCompatible,
      suppression: suppression,
      now: now,
    );
    final newerIncompatibleExists =
        latestPublished != null &&
        compareSemVerPrecedence(
              latestPublished.version,
              latestCompatible.version,
            ) >
            0 &&
        compareSemVerPrecedence(latestPublished.version, installed) > 0;
    return AppUpdateResult(
      release: decision.shouldPrompt ? decision.latestRelease : null,
      message: manual
          ? newerIncompatibleExists &&
                    (decision.kind == UpdateDecisionKind.upToDate ||
                        decision.kind == UpdateDecisionKind.remoteOlder)
                ? _noCompatibleUpdateMessage(
                    installed: installed,
                    latestPublished: latestPublished,
                    latestCompatible: latestCompatible,
                    catalogBound: source.maximumCatalogSize,
                  )
                : _manualMessage(decision)
          : null,
      checkedAt: result.cache.validatedAt,
      releaseCache: result.cache.toJson(),
      updateSuppression: suppression.toJson(),
    );
  }

  @override
  Map<String, Object?> ignore({
    required ReleaseInfo release,
    Map<String, Object?>? currentSuppression,
  }) {
    return _policy
        .ignore(
          state: _decodeSuppression(currentSuppression),
          version: release.version,
        )
        .toJson();
  }

  @override
  Map<String, Object?> remindLater({
    required ReleaseInfo release,
    Map<String, Object?>? currentSuppression,
  }) {
    return _policy
        .remindLater(
          state: _decodeSuppression(currentSuppression),
          version: release.version,
          now: _clock().toUtc(),
        )
        .toJson();
  }

  @override
  Future<void> openRelease(ReleaseInfo release) async {
    final repository = _configuredRepository();
    _requireConfiguredRepositoryRelease(release, repository);
    final compatibilityAsset = _requireEligibleTargetAsset(release, repository);
    final destination = target.isDirect
        ? compatibilityAsset.downloadUri
        : _destinationUri!;
    final opened = await _launcher(destination);
    if (!opened) {
      throw StateError('Could not open the configured update destination.');
    }
  }

  static Future<bool> _launchExternal(Uri destination) {
    return launchUrl(destination, mode: LaunchMode.externalApplication);
  }

  _ConfiguredGitHubRepository _configuredRepository() {
    final parts = _repositorySlug.split('/');
    if (parts.length != 2 ||
        parts.any(
          (part) =>
              part.trim().isEmpty ||
              part.trim() != part ||
              part == '.' ||
              part == '..' ||
              part.contains('\\'),
        )) {
      throw StateError(
        'UPDATE_REPOSITORY must use the exact owner/repository form.',
      );
    }
    return _ConfiguredGitHubRepository(owner: parts[0], repository: parts[1]);
  }

  GitHubReleaseSource _sourceFor(_ConfiguredGitHubRepository repository) {
    return GitHubReleaseSource(
      client: _client,
      owner: repository.owner,
      repository: repository.repository,
      userAgent: 'DevCoordinator-Universal',
    );
  }

  static void _requireConfiguredRepositoryRelease(
    ReleaseInfo release,
    _ConfiguredGitHubRepository repository,
  ) {
    final uri = release.pageUri;
    final segments = uri.pathSegments;
    final exactReleasePage =
        _isSafeDestination(uri) &&
        uri.host.toLowerCase() == 'github.com' &&
        uri.port == 443 &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        segments.length == 5 &&
        segments[0] == repository.owner &&
        segments[1] == repository.repository &&
        segments[2] == 'releases' &&
        segments[3] == 'tag' &&
        segments[4] == release.tagName;
    if (!exactReleasePage) {
      throw StateError(
        'The release page does not belong to the configured GitHub repository.',
      );
    }
  }

  static Version _parseInstalledVersion(String value) {
    try {
      return Version.parse(value);
    } on FormatException catch (error) {
      throw StateError(
        'Installed application version "$value" is not semantic: $error',
      );
    }
  }

  static ReleaseCatalogCacheEntry? _decodeCatalogCache(
    Map<String, Object?>? value,
  ) {
    if (value == null) return null;
    try {
      return ReleaseCatalogCacheEntry.fromJson(value);
    } on FormatException {
      // A cache written by the previous single-/latest endpoint has no bounded
      // catalog or asset inventory. Discarding it forces a safe refresh and
      // prevents its ETag from crossing endpoint contracts.
      return null;
    }
  }

  static UpdateSuppression _decodeSuppression(Map<String, Object?>? value) {
    if (value == null) return const UpdateSuppression.none();
    try {
      return UpdateSuppression.fromJson(value);
    } on FormatException {
      return const UpdateSuppression.none();
    }
  }

  static String _manualMessage(UpdateDecision decision) {
    return switch (decision.kind) {
      UpdateDecisionKind.updateAvailable =>
        'Version ${decision.latestRelease.version} is available.',
      UpdateDecisionKind.upToDate => 'You are using the latest release.',
      UpdateDecisionKind.remoteOlder =>
        'This build is newer than the latest published release.',
      UpdateDecisionKind.ignored =>
        'The latest published release is ignored on this device.',
      UpdateDecisionKind.deferred =>
        'Reminder deferred until ${decision.nextPromptAt?.toLocal()}.',
    };
  }

  bool _hasEligibleTargetAsset(
    ReleaseInfo release,
    _ConfiguredGitHubRepository repository,
  ) {
    return _eligibleTargetAsset(release, repository) != null;
  }

  ReleaseAsset? _eligibleTargetAsset(
    ReleaseInfo release,
    _ConfiguredGitHubRepository repository,
  ) {
    final expectedName = _expectedCompatibilityAssetName(release.version);
    final matches = release.assets
        .where((asset) => asset.name == expectedName)
        .toList(growable: false);
    if (matches.isEmpty) {
      return null;
    }
    if (matches.length != 1) {
      throw StateError(
        'Release ${release.tagName} contains an ambiguous target asset named '
        '"$expectedName".',
      );
    }
    final asset = matches.single;
    if (asset.sizeInBytes == null || asset.sizeInBytes! <= 0) {
      throw StateError(
        'Release asset "$expectedName" has no positive provider byte size.',
      );
    }
    _requireOwnedAsset(release, asset, repository);
    return asset;
  }

  ReleaseAsset _requireEligibleTargetAsset(
    ReleaseInfo release,
    _ConfiguredGitHubRepository repository,
  ) {
    final asset = _eligibleTargetAsset(release, repository);
    if (asset == null) {
      throw StateError(
        'Release ${release.tagName} does not contain the exact '
        '${target.description} asset '
        '"${_expectedCompatibilityAssetName(release.version)}".',
      );
    }
    return asset;
  }

  static void _requireOwnedAsset(
    ReleaseInfo release,
    ReleaseAsset asset,
    _ConfiguredGitHubRepository repository,
  ) {
    final uri = asset.downloadUri;
    final segments = uri.pathSegments;
    final exactOwnedAsset =
        _isSafeDestination(uri) &&
        uri.host.toLowerCase() == 'github.com' &&
        uri.port == 443 &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        segments.length == 6 &&
        segments[0] == repository.owner &&
        segments[1] == repository.repository &&
        segments[2] == 'releases' &&
        segments[3] == 'download' &&
        segments[4] == release.tagName &&
        segments[5] == asset.name;
    if (!exactOwnedAsset) {
      throw StateError(
        'Release asset "${asset.name}" does not belong to the configured '
        'GitHub repository and tag.',
      );
    }
  }

  String _noCompatibleUpdateMessage({
    required Version installed,
    required ReleaseInfo? latestPublished,
    required ReleaseInfo? latestCompatible,
    required int catalogBound,
  }) {
    if (latestPublished == null) {
      return 'No stable releases are published in the configured repository.';
    }
    final publishedComparison = compareSemVerPrecedence(
      latestPublished.version,
      installed,
    );
    if (publishedComparison <= 0) {
      return publishedComparison == 0
          ? 'You are using the latest published release.'
          : 'This build is newer than the latest published release.';
    }
    final compatibleText = latestCompatible == null
        ? 'No compatible release was found'
        : 'The latest compatible release is ${latestCompatible.version}';
    return 'Version ${latestPublished.version} is published, but it has no '
        'newer update for this ${target.description}. Expected the exact '
        'owned asset '
        '"${_expectedCompatibilityAssetName(latestPublished.version)}". '
        '$compatibleText among the $catalogBound most recent releases.';
  }

  String _expectedCompatibilityAssetName(Version version) => target
      .expectedCompatibilityAssetName(version, storeProductId: _storeProductId);

  static Uri? _parseDestination(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    final uri = Uri.tryParse(normalized);
    if (uri == null || !_isSafeDestination(uri)) {
      throw ArgumentError.value(
        value,
        'destinationUrl',
        'Must be an absolute HTTPS URL without embedded credentials.',
      );
    }
    return uri;
  }

  static bool _isSafeDestination(Uri uri) {
    return uri.isAbsolute &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }
}

/// Runtime platform whose installer identity an update must match.
enum AppUpdatePlatform {
  android(slug: 'android', label: 'Android', directExtension: 'apk'),
  macos(slug: 'macos', label: 'macOS', directExtension: 'dmg'),
  windows(slug: 'windows', label: 'Windows', directExtension: 'msix');

  const AppUpdatePlatform({
    required this.slug,
    required this.label,
    required this.directExtension,
  });

  final String slug;
  final String label;
  final String directExtension;
}

/// Distribution mechanism owned by the installed build.
enum AppUpdateDistributionChannel {
  direct('direct', 'direct', 'direct'),
  play('play', 'Google Play', 'google-play'),
  macAppStore('mac_app_store', 'Mac App Store', 'mac-app-store'),
  microsoftStore('microsoft_store', 'Microsoft Store', 'microsoft-store');

  const AppUpdateDistributionChannel(
    this.configurationValue,
    this.label,
    this.assetSlug,
  );

  final String configurationValue;
  final String label;
  final String assetSlug;

  static AppUpdateDistributionChannel parse(String value) {
    for (final channel in values) {
      if (channel.configurationValue == value) {
        return channel;
      }
    }
    throw ArgumentError.value(
      value,
      'UPDATE_DISTRIBUTION_CHANNEL',
      'Must be one of direct, play, mac_app_store, or microsoft_store.',
    );
  }
}

/// Explicit platform/channel identity for one installed application build.
final class AppUpdateTarget {
  factory AppUpdateTarget({
    required AppUpdatePlatform platform,
    required AppUpdateDistributionChannel channel,
  }) {
    final compatible = switch (channel) {
      AppUpdateDistributionChannel.direct => true,
      AppUpdateDistributionChannel.play =>
        platform == AppUpdatePlatform.android,
      AppUpdateDistributionChannel.macAppStore =>
        platform == AppUpdatePlatform.macos,
      AppUpdateDistributionChannel.microsoftStore =>
        platform == AppUpdatePlatform.windows,
    };
    if (!compatible) {
      throw ArgumentError(
        '${channel.configurationValue} is not a valid distribution channel '
        'for ${platform.slug}.',
      );
    }
    return AppUpdateTarget._(platform: platform, channel: channel);
  }

  const AppUpdateTarget._({required this.platform, required this.channel});

  /// Resolves the current native target and compile-time distribution channel.
  factory AppUpdateTarget.current({
    String distributionChannel = const String.fromEnvironment(
      'UPDATE_DISTRIBUTION_CHANNEL',
      defaultValue: 'direct',
    ),
  }) {
    final AppUpdatePlatform platform;
    if (Platform.isAndroid) {
      platform = AppUpdatePlatform.android;
    } else if (Platform.isMacOS) {
      platform = AppUpdatePlatform.macos;
    } else if (Platform.isWindows) {
      platform = AppUpdatePlatform.windows;
    } else {
      throw UnsupportedError(
        'DevCoordinator updates support Android, macOS, and Windows builds.',
      );
    }
    return AppUpdateTarget(
      platform: platform,
      channel: AppUpdateDistributionChannel.parse(distributionChannel),
    );
  }

  final AppUpdatePlatform platform;
  final AppUpdateDistributionChannel channel;

  bool get isDirect => channel == AppUpdateDistributionChannel.direct;

  String get description => '${channel.label} ${platform.label} build';

  String expectedDirectAssetName(Version version) {
    if (!isDirect) {
      throw StateError(
        '${channel.configurationValue} does not use direct repository assets.',
      );
    }
    return 'DevCoordinator-$version-${platform.slug}.'
        '${platform.directExtension}';
  }

  /// Exact repository asset proving this version exists for this build target.
  ///
  /// Direct builds use their installer. Store builds use a small
  /// repository-owned marker uploaded only after that exact Store version is
  /// published.
  String expectedCompatibilityAssetName(
    Version version, {
    String storeProductId = '',
  }) {
    if (isDirect) {
      return expectedDirectAssetName(version);
    }
    final identity = normalizedStoreProductIdentity(storeProductId);
    return 'DevCoordinator-$version-${platform.slug}-'
        '${channel.assetSlug}-$identity.release.json';
  }

  /// Returns the exact, filename-safe application identity for this channel.
  String normalizedStoreProductIdentity(String configuredProductId) {
    final productId = configuredProductId.trim();
    return switch (channel) {
      AppUpdateDistributionChannel.direct =>
        productId.isEmpty
            ? ''
            : throw ArgumentError(
                'Direct builds must not set UPDATE_STORE_PRODUCT_ID.',
              ),
      AppUpdateDistributionChannel.play =>
        productId.isEmpty || productId == 'io.github.holyglory.devcoordinator'
            ? 'io.github.holyglory.devcoordinator'
            : throw ArgumentError(
                'Google Play identity must match the Android package.',
              ),
      AppUpdateDistributionChannel.macAppStore =>
        _isValidAppleProductId(productId)
            ? productId
            : throw ArgumentError(
                'Mac App Store builds require the numeric Apple application '
                'ID in UPDATE_STORE_PRODUCT_ID.',
              ),
      AppUpdateDistributionChannel.microsoftStore =>
        _isValidMicrosoftProductId(productId)
            ? _asciiUppercase(productId)
            : throw ArgumentError(
                'Microsoft Store builds require the 12-character Store ID in '
                'UPDATE_STORE_PRODUCT_ID.',
              ),
    };
  }

  /// Rejects Store handoffs that do not identify this app at the channel's
  /// official HTTPS origin. Direct builds must not carry a Store identity.
  void requireValidStoreConfiguration({
    required Uri? destination,
    required String configuredProductId,
  }) {
    final productId = normalizedStoreProductIdentity(configuredProductId);
    if (isDirect) {
      return;
    }
    if (destination == null) {
      return;
    }
    final valid = switch (channel) {
      AppUpdateDistributionChannel.play => _isExactPlayDestination(destination),
      AppUpdateDistributionChannel.macAppStore =>
        _isExactMacAppStoreDestination(destination, productId),
      AppUpdateDistributionChannel.microsoftStore =>
        _isExactMicrosoftStoreDestination(destination, productId),
      AppUpdateDistributionChannel.direct => false,
    };
    if (!valid) {
      throw ArgumentError(
        'UPDATE_DESTINATION_URL does not identify this application at the '
        'official ${channel.label} origin, or UPDATE_STORE_PRODUCT_ID is '
        'missing/invalid.',
      );
    }
  }

  static bool _isExactPlayDestination(Uri uri) {
    const packageId = 'io.github.holyglory.devcoordinator';
    final parameters = uri.queryParametersAll;
    return _isExactHttpsOrigin(uri, 'play.google.com') &&
        uri.path == '/store/apps/details' &&
        !uri.hasFragment &&
        parameters.length == 1 &&
        parameters['id']?.length == 1 &&
        parameters['id']!.single == packageId;
  }

  static bool _isExactMacAppStoreDestination(Uri uri, String productId) {
    return _isExactHttpsOrigin(uri, 'apps.apple.com') &&
        uri.pathSegments.length == 2 &&
        uri.pathSegments[0] == 'app' &&
        uri.pathSegments[1] == 'id$productId' &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  static bool _isExactMicrosoftStoreDestination(Uri uri, String productId) {
    final segment = uri.pathSegments.length == 2 ? uri.pathSegments[1] : '';
    return _isExactHttpsOrigin(uri, 'apps.microsoft.com') &&
        uri.pathSegments.length == 2 &&
        uri.pathSegments[0] == 'detail' &&
        _isValidMicrosoftProductId(segment) &&
        _asciiUppercase(segment) == productId &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  static bool _isValidAppleProductId(String productId) =>
      productId.length >= 6 &&
      productId.length <= 20 &&
      productId.codeUnits.every(_isAsciiDigit);

  static bool _isValidMicrosoftProductId(String productId) {
    return productId.length == 12 &&
        productId.codeUnits.every(
          (codeUnit) =>
              _isAsciiDigit(codeUnit) ||
              (codeUnit >= 65 && codeUnit <= 90) ||
              (codeUnit >= 97 && codeUnit <= 122),
        );
  }

  static String _asciiUppercase(String value) => String.fromCharCodes(
    value.codeUnits.map(
      (codeUnit) =>
          codeUnit >= 97 && codeUnit <= 122 ? codeUnit - 32 : codeUnit,
    ),
  );

  static bool _isExactHttpsOrigin(Uri uri, String host) =>
      uri.scheme == 'https' &&
      uri.host.toLowerCase() == host &&
      uri.port == 443 &&
      uri.userInfo.isEmpty;

  static bool _isAsciiDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;
}

final class _ConfiguredGitHubRepository {
  const _ConfiguredGitHubRepository({
    required this.owner,
    required this.repository,
  });

  final String owner;
  final String repository;
}
