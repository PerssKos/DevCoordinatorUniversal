import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'native_oauth.dart';

final class NativeRefreshCredential {
  NativeRefreshCredential({
    required this.bindingKey,
    required this.refreshToken,
    required Iterable<String> scopes,
    required this.updatedAt,
    this.deviceSessionId,
    this.revocationPending = false,
  }) : scopes = Set.unmodifiable(scopes);

  final String bindingKey;
  final String refreshToken;
  final Set<String> scopes;
  final DateTime updatedAt;
  final String? deviceSessionId;
  final bool revocationPending;

  NativeRefreshCredential copyWith({
    String? refreshToken,
    Iterable<String>? scopes,
    DateTime? updatedAt,
    String? deviceSessionId,
    bool? revocationPending,
  }) {
    return NativeRefreshCredential(
      bindingKey: bindingKey,
      refreshToken: refreshToken ?? this.refreshToken,
      scopes: scopes ?? this.scopes,
      updatedAt: updatedAt ?? this.updatedAt,
      deviceSessionId: deviceSessionId ?? this.deviceSessionId,
      revocationPending: revocationPending ?? this.revocationPending,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'bindingKey': bindingKey,
    'refreshToken': refreshToken,
    'scopes': scopes.toList()..sort(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (deviceSessionId != null) 'deviceSessionId': deviceSessionId,
    'revocationPending': revocationPending,
  };

  static NativeRefreshCredential? fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['bindingKey'] is! String ||
        value['refreshToken'] is! String ||
        value['scopes'] is! List<dynamic> ||
        value['updatedAt'] is! String ||
        value['revocationPending'] is! bool) {
      return null;
    }
    final scopesValue = value['scopes'] as List<dynamic>;
    if (scopesValue.any((scope) => scope is! String)) {
      return null;
    }
    final updatedAt = DateTime.tryParse(value['updatedAt'] as String)?.toUtc();
    final deviceSessionId = value['deviceSessionId'];
    if (updatedAt == null ||
        (deviceSessionId != null && deviceSessionId is! String)) {
      return null;
    }
    final bindingKey = value['bindingKey'] as String;
    final refreshToken = value['refreshToken'] as String;
    if (bindingKey.isEmpty ||
        bindingKey.length > 4096 ||
        refreshToken.length < 16 ||
        refreshToken.length > 8192 ||
        RegExp(r'\s').hasMatch(refreshToken)) {
      return null;
    }
    return NativeRefreshCredential(
      bindingKey: bindingKey,
      refreshToken: refreshToken,
      scopes: scopesValue.cast<String>(),
      updatedAt: updatedAt,
      deviceSessionId: deviceSessionId as String?,
      revocationPending: value['revocationPending'] as bool,
    );
  }
}

final class NativePendingAuthorization {
  const NativePendingAuthorization({
    required this.bindingKey,
    required this.state,
    required this.verifier,
    required this.createdAt,
  });

  final String bindingKey;
  final String state;
  final String verifier;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'bindingKey': bindingKey,
    'state': state,
    'verifier': verifier,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static NativePendingAuthorization? fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['bindingKey'] is! String ||
        value['state'] is! String ||
        value['verifier'] is! String ||
        value['createdAt'] is! String) {
      return null;
    }
    final createdAt = DateTime.tryParse(value['createdAt'] as String)?.toUtc();
    final state = value['state'] as String;
    final verifier = value['verifier'] as String;
    if (createdAt == null ||
        state.length < 32 ||
        state.length > 128 ||
        verifier.length < 43 ||
        verifier.length > 128) {
      return null;
    }
    return NativePendingAuthorization(
      bindingKey: value['bindingKey'] as String,
      state: state,
      verifier: verifier,
      createdAt: createdAt,
    );
  }
}

abstract interface class NativeSessionStore {
  Future<NativeRefreshCredential?> readCredential();

  Future<void> writeCredential(NativeRefreshCredential credential);

  Future<void> clearCredential();

  Future<NativePendingAuthorization?> readPendingAuthorization();

  Future<void> writePendingAuthorization(
    NativePendingAuthorization authorization,
  );

  Future<void> clearPendingAuthorization();
}

final class PlatformNativeSessionStore implements NativeSessionStore {
  PlatformNativeSessionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'devcoordinator_native_session',
            ),
          );

  static const _credentialKey = 'native.session.refresh.v1';
  static const _pendingAuthorizationKey = 'native.session.pending_auth.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<NativeRefreshCredential?> readCredential() {
    return _read(_credentialKey, NativeRefreshCredential.fromJson);
  }

  @override
  Future<void> writeCredential(NativeRefreshCredential credential) {
    return _storage.write(
      key: _credentialKey,
      value: jsonEncode(credential.toJson()),
    );
  }

  @override
  Future<void> clearCredential() => _storage.delete(key: _credentialKey);

  @override
  Future<NativePendingAuthorization?> readPendingAuthorization() {
    return _read(_pendingAuthorizationKey, NativePendingAuthorization.fromJson);
  }

  @override
  Future<void> writePendingAuthorization(
    NativePendingAuthorization authorization,
  ) {
    return _storage.write(
      key: _pendingAuthorizationKey,
      value: jsonEncode(authorization.toJson()),
    );
  }

  @override
  Future<void> clearPendingAuthorization() {
    return _storage.delete(key: _pendingAuthorizationKey);
  }

  Future<T?> _read<T>(String key, T? Function(Object? value) decode) async {
    final encoded = await _storage.read(key: key);
    if (encoded == null) {
      return null;
    }
    try {
      final decoded = decode(jsonDecode(encoded));
      if (decoded == null) {
        throw const NativeOAuthException(
          'Saved native session data is invalid.',
          authenticationRequired: true,
        );
      }
      return decoded;
    } on FormatException {
      throw const NativeOAuthException(
        'Saved native session data is invalid.',
        authenticationRequired: true,
      );
    }
  }
}
