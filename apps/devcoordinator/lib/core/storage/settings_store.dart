import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum StoredConnectionKind { localLegacyV1, nativeGatewayV2 }

final class StoredConnectionProfile {
  const StoredConnectionProfile({
    required this.kind,
    required this.baseUrl,
    required this.label,
    this.agent,
    this.defaultProject,
  });

  final StoredConnectionKind kind;
  final String baseUrl;
  final String label;
  final String? agent;
  final String? defaultProject;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'baseUrl': baseUrl,
    'label': label,
    if (agent != null) 'agent': agent,
    if (defaultProject != null) 'defaultProject': defaultProject,
  };

  static StoredConnectionProfile? fromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final kindName = value['kind'];
    final baseUrl = value['baseUrl'];
    final label = value['label'];
    if (kindName is! String || baseUrl is! String || label is! String) {
      return null;
    }
    final kind = StoredConnectionKind.values
        .where((candidate) => candidate.name == kindName)
        .firstOrNull;
    if (kind == null || baseUrl.trim().isEmpty || label.trim().isEmpty) {
      return null;
    }
    return StoredConnectionProfile(
      kind: kind,
      baseUrl: baseUrl,
      label: label,
      agent: value['agent'] is String ? value['agent'] as String : null,
      defaultProject: value['defaultProject'] is String
          ? value['defaultProject'] as String
          : null,
    );
  }
}

final class PersistedAppSettings {
  const PersistedAppSettings({
    this.styleName = 'one_ui_inspired',
    this.brightnessName = 'system',
    this.updateChecksEnabled = true,
    this.lastUpdateCheck,
    this.releaseCache,
    this.updateSuppression,
    this.connection,
    this.credentialCleanupPending = false,
  });

  final String styleName;
  final String brightnessName;
  final bool updateChecksEnabled;
  final DateTime? lastUpdateCheck;
  final Map<String, Object?>? releaseCache;
  final Map<String, Object?>? updateSuppression;
  final StoredConnectionProfile? connection;
  final bool credentialCleanupPending;

  PersistedAppSettings copyWith({
    String? styleName,
    String? brightnessName,
    bool? updateChecksEnabled,
    DateTime? lastUpdateCheck,
    bool clearLastUpdateCheck = false,
    Map<String, Object?>? releaseCache,
    bool clearReleaseCache = false,
    Map<String, Object?>? updateSuppression,
    bool clearUpdateSuppression = false,
    StoredConnectionProfile? connection,
    bool clearConnection = false,
    bool? credentialCleanupPending,
  }) {
    return PersistedAppSettings(
      styleName: styleName ?? this.styleName,
      brightnessName: brightnessName ?? this.brightnessName,
      updateChecksEnabled: updateChecksEnabled ?? this.updateChecksEnabled,
      lastUpdateCheck: clearLastUpdateCheck
          ? null
          : (lastUpdateCheck ?? this.lastUpdateCheck),
      releaseCache: clearReleaseCache
          ? null
          : (releaseCache ?? this.releaseCache),
      updateSuppression: clearUpdateSuppression
          ? null
          : (updateSuppression ?? this.updateSuppression),
      connection: clearConnection ? null : (connection ?? this.connection),
      credentialCleanupPending:
          credentialCleanupPending ?? this.credentialCleanupPending,
    );
  }
}

abstract interface class AppSettingsStore {
  Future<PersistedAppSettings> read();

  Future<void> write(PersistedAppSettings settings);

  /// Persists the fail-closed credential cleanup or revocation gate
  /// independently of the connection profile.
  Future<void> setCredentialCleanupPending(bool pending);
}

final class PlatformAppSettingsStore implements AppSettingsStore {
  PlatformAppSettingsStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _styleKey = 'appearance.style';
  static const _brightnessKey = 'appearance.brightness';
  static const _updatesEnabledKey = 'updates.enabled';
  static const _lastUpdateCheckKey = 'updates.lastCheck';
  static const _releaseCacheKey = 'updates.releaseCache';
  static const _updateSuppressionKey = 'updates.suppression';
  static const _legacyIgnoredVersionKey = 'updates.ignoredVersion';
  static const _legacyReleaseEtagKey = 'updates.etag';
  static const _connectionKey = 'connection.profile';
  static const _credentialCleanupPendingKey =
      'connection.credentialCleanupPending';

  final SharedPreferencesAsync _preferences;

  @override
  Future<PersistedAppSettings> read() async {
    final connection = StoredConnectionProfile.fromJson(
      await _readObject(_connectionKey),
    );
    final releaseCache = await _readObject(_releaseCacheKey);
    var updateSuppression = await _readObject(_updateSuppressionKey);
    final legacyIgnoredVersion = await _preferences.getString(
      _legacyIgnoredVersionKey,
    );
    if (updateSuppression == null && legacyIgnoredVersion != null) {
      updateSuppression = <String, Object?>{
        'ignoredThroughVersion': legacyIgnoredVersion,
        'deferredThroughVersion': null,
        'deferredUntil': null,
      };
    }

    final lastCheckText = await _preferences.getString(_lastUpdateCheckKey);
    return PersistedAppSettings(
      styleName: await _preferences.getString(_styleKey) ?? 'one_ui_inspired',
      brightnessName: await _preferences.getString(_brightnessKey) ?? 'system',
      updateChecksEnabled:
          await _preferences.getBool(_updatesEnabledKey) ?? true,
      lastUpdateCheck: lastCheckText == null
          ? null
          : DateTime.tryParse(lastCheckText)?.toUtc(),
      releaseCache: releaseCache,
      updateSuppression: updateSuppression,
      connection: connection,
      credentialCleanupPending:
          await _preferences.getBool(_credentialCleanupPendingKey) ?? false,
    );
  }

  @override
  Future<void> write(PersistedAppSettings settings) async {
    await Future.wait<void>(<Future<void>>[
      _preferences.setString(_styleKey, settings.styleName),
      _preferences.setString(_brightnessKey, settings.brightnessName),
      _preferences.setBool(_updatesEnabledKey, settings.updateChecksEnabled),
      _writeNullable(
        _lastUpdateCheckKey,
        settings.lastUpdateCheck?.toUtc().toIso8601String(),
      ),
      _writeNullable(
        _releaseCacheKey,
        settings.releaseCache == null
            ? null
            : jsonEncode(settings.releaseCache),
      ),
      _writeNullable(
        _updateSuppressionKey,
        settings.updateSuppression == null
            ? null
            : jsonEncode(settings.updateSuppression),
      ),
      _writeNullable(
        _connectionKey,
        settings.connection == null
            ? null
            : jsonEncode(settings.connection!.toJson()),
      ),
      _preferences.remove(_legacyIgnoredVersionKey),
      _preferences.remove(_legacyReleaseEtagKey),
    ]);
  }

  @override
  Future<void> setCredentialCleanupPending(bool pending) {
    return _preferences.setBool(_credentialCleanupPendingKey, pending);
  }

  Future<Map<String, Object?>?> _readObject(String key) async {
    final encoded = await _preferences.getString(key);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      return decoded is Map<String, dynamic>
          ? Map<String, Object?>.from(decoded)
          : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeNullable(String key, String? value) {
    return value == null
        ? _preferences.remove(key)
        : _preferences.setString(key, value);
  }
}
