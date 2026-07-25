import 'package:devcoordinator/core/update/repository_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('rejects update destinations that can downgrade transport security', () {
    expect(
      () => RepositoryAppUpdateService(
        destinationUrl: 'http://downloads.example.test/app',
      ),
      throwsArgumentError,
    );
    expect(
      () => RepositoryAppUpdateService(
        destinationUrl: 'https://user:secret@downloads.example.test/app',
      ),
      throwsArgumentError,
    );
  });

  test('accepts an absolute HTTPS update destination', () {
    expect(
      () => RepositoryAppUpdateService(
        destinationUrl: 'https://downloads.example.test/app',
      ),
      returnsNormally,
    );
  });

  test(
    'reports an unconfigured release source only on manual checks',
    () async {
      final service = RepositoryAppUpdateService(repositorySlug: '');

      await expectLater(
        service.check(currentVersion: '1.0.0', manual: true),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('UPDATE_REPOSITORY=owner/repository'),
          ),
        ),
      );

      final automatic = await service.check(
        currentVersion: '1.0.0',
        manual: false,
      );
      expect(automatic.message, isNull);
      expect(automatic.release, isNull);
    },
  );

  test('treats a false platform-launch result as a failed open', () async {
    final service = RepositoryAppUpdateService(
      destinationUrl: 'https://downloads.example.test/app',
      launcher: (_) async => false,
    );

    await expectLater(
      service.openRelease(releaseFixture()),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Could not open'),
        ),
      ),
    );
  });
}
