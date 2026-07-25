import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Process-session storage for the legacy loopback bearer.
///
/// Current builds never persist this bearer. Implementations may delete the
/// legacy secure-storage key written by earlier builds, but [read] must never
/// return that persisted value. A new process therefore starts without a
/// credential even when every cleanup write failed before the prior process
/// exited.
abstract interface class SecureTokenStore {
  /// Returns only a credential written during this process session.
  Future<String?> read();

  /// Deletes the exact durable key used by pre-session-only builds.
  ///
  /// This operation must not read that value or change the current process
  /// session credential. The controller invokes it on every cold launch so an
  /// orphaned key is retried even when no profile or cleanup marker remains.
  Future<void> purgeLegacyValue();

  /// Retains [token] only for this process session.
  Future<void> write(String token);

  /// Drops the session credential before purging any legacy persisted value.
  Future<void> clear();
}

final class PlatformSecureTokenStore implements SecureTokenStore {
  PlatformSecureTokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'devcoordinator_connection',
            ),
          );

  static const _tokenKey = 'connection.credential';

  final FlutterSecureStorage _storage;
  String? _sessionToken;

  @override
  Future<String?> read() async => _sessionToken;

  @override
  Future<void> purgeLegacyValue() => _storage.delete(key: _tokenKey);

  @override
  Future<void> write(String token) async {
    final normalized = token.trim();
    if (normalized.length < 32) {
      throw ArgumentError.value(
        token.length,
        'token length',
        'Credential must contain at least 32 characters.',
      );
    }
    await purgeLegacyValue();
    _sessionToken = normalized;
  }

  @override
  Future<void> clear() async {
    _sessionToken = null;
    await purgeLegacyValue();
  }
}
