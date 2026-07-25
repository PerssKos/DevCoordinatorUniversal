import 'package:devcoordinator/core/storage/secure_token_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'connection.credential': 'persisted-by-an-earlier-build',
    });
  });

  test('never returns or writes a durable bearer', () async {
    const platformStorage = FlutterSecureStorage();
    final store = PlatformSecureTokenStore(storage: platformStorage);

    expect(await store.read(), isNull);
    expect(
      await platformStorage.read(key: 'connection.credential'),
      'persisted-by-an-earlier-build',
    );

    await store.purgeLegacyValue();
    expect(await platformStorage.read(key: 'connection.credential'), isNull);

    await store.write('s' * 40);

    expect(await platformStorage.read(key: 'connection.credential'), isNull);
    expect(await store.read(), 's' * 40);
  });

  test('legacy purge failure does not discard the session bearer', () async {
    final platformStorage = _ControllableSecureStorage();
    final store = PlatformSecureTokenStore(storage: platformStorage);
    await store.write('s' * 40);

    platformStorage.deleteError = StateError('keychain locked');
    await expectLater(store.purgeLegacyValue(), throwsStateError);

    platformStorage.deleteError = null;
    expect(await store.read(), 's' * 40);
  });

  test('drops the session bearer before a legacy-key delete failure', () async {
    final platformStorage = _ControllableSecureStorage();
    final store = PlatformSecureTokenStore(storage: platformStorage);
    await store.write('s' * 40);

    platformStorage.deleteError = StateError('keychain locked');
    await expectLater(store.clear(), throwsStateError);

    platformStorage.deleteError = null;
    expect(await store.read(), isNull);
  });
}

final class _ControllableSecureStorage extends FlutterSecureStorage {
  Object? deleteError;

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    final error = deleteError;
    if (error != null) return Future<void>.error(error);
    return super.delete(
      key: key,
      iOptions: iOptions,
      aOptions: aOptions,
      lOptions: lOptions,
      webOptions: webOptions,
      mOptions: mOptions,
      wOptions: wOptions,
    );
  }
}
