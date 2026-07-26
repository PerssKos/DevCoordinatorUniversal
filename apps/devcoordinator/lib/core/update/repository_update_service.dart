import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';
import 'package:release_update/release_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_services.dart';

/// App-facing update adapter.
///
/// Production builds select their repository and optional store/direct
/// destination with Dart defines:
/// `UPDATE_REPOSITORY=owner/repository` and `UPDATE_DESTINATION_URL=https://…`.
/// No maintainer credential is embedded in the application.
final class RepositoryAppUpdateService implements AppUpdateService {
  RepositoryAppUpdateService({
    http.Client? httpClient,
    String repositorySlug = const String.fromEnvironment('UPDATE_REPOSITORY'),
    String destinationUrl = const String.fromEnvironment(
      'UPDATE_DESTINATION_URL',
    ),
    Future<bool> Function(Uri destination)? launcher,
    DateTime Function()? clock,
    UpdatePolicy? policy,
  }) : _client = httpClient ?? http.Client(),
       _repositorySlug = repositorySlug.trim(),
       _destinationUri = _parseDestination(destinationUrl),
       _launcher = launcher ?? _launchExternal,
       _clock = clock ?? DateTime.now,
       _policy = policy ?? UpdatePolicy();

  final http.Client _client;
  final String _repositorySlug;
  final Uri? _destinationUri;
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
    final cache = _decodeCache(releaseCache);
    final suppression = _decodeSuppression(updateSuppression);
    final now = _clock().toUtc();

    final repository = _configuredRepository();
    final source = _sourceFor(repository);
    final result = await ReleaseUpdateChecker(source: source, policy: _policy)
        .check(
          currentVersion: installed,
          cache: cache,
          suppression: suppression,
          reason: manual
              ? UpdateCheckReason.manual
              : UpdateCheckReason.automatic,
          now: now,
        );
    final decision = result.decision;
    _requireConfiguredRepositoryRelease(decision.latestRelease, repository);
    return AppUpdateResult(
      release: decision.shouldPrompt ? decision.latestRelease : null,
      message: manual ? _manualMessage(decision) : null,
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
    final configuredDestination = _destinationUri;
    final Uri destination;
    if (configuredDestination != null) {
      destination = configuredDestination;
    } else {
      _requireConfiguredRepositoryRelease(release, _configuredRepository());
      destination = release.pageUri;
    }
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
        parts.any((part) => part.trim().isEmpty || part.trim() != part)) {
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

  static ReleaseCacheEntry? _decodeCache(Map<String, Object?>? value) {
    if (value == null) return null;
    try {
      return ReleaseCacheEntry.fromJson(value);
    } on FormatException {
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

final class _ConfiguredGitHubRepository {
  const _ConfiguredGitHubRepository({
    required this.owner,
    required this.repository,
  });

  final String owner;
  final String repository;
}
