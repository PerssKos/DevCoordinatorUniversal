import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';

import 'native_oauth.dart';

abstract interface class NativeAuthorizationCallbackRouter {
  Future<void> initialize();

  Uri? takeBufferedCallback(String state);

  Future<Uri> waitForCallback(
    String state, {
    Duration timeout = const Duration(minutes: 5),
  });

  void close();
}

final class PlatformNativeAuthorizationCallbackRouter
    implements NativeAuthorizationCallbackRouter {
  PlatformNativeAuthorizationCallbackRouter({AppLinks? appLinks})
    : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;
  final List<Uri> _buffer = <Uri>[];
  final List<_CallbackWaiter> _waiters = <_CallbackWaiter>[];
  StreamSubscription<Uri>? _subscription;
  bool _initialized = false;
  bool _closed = false;

  @override
  Future<void> initialize() async {
    if (_initialized || _closed) {
      return;
    }
    _initialized = true;
    final initial = await _appLinks.getInitialLink();
    if (initial != null) {
      _accept(initial);
    }
    _subscription = _appLinks.uriLinkStream.listen(
      _accept,
      onError: (_) {
        // A transient platform-link error must not destroy a pending OAuth
        // transaction. Its timeout remains the user-visible failure boundary.
      },
    );
  }

  @override
  Uri? takeBufferedCallback(String state) {
    for (var index = 0; index < _buffer.length; index += 1) {
      final candidate = _buffer[index];
      if (_hasExactState(candidate, state)) {
        _buffer.removeAt(index);
        return candidate;
      }
    }
    return null;
  }

  @override
  Future<Uri> waitForCallback(
    String state, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (_closed) {
      throw const NativeOAuthException(
        'Authorization callback receiver is closed.',
      );
    }
    final buffered = takeBufferedCallback(state);
    if (buffered != null) {
      return buffered;
    }
    final waiter = _CallbackWaiter(state);
    _waiters.add(waiter);
    try {
      return await waiter.completer.future.timeout(
        timeout,
        onTimeout: () => throw const NativeOAuthException(
          'Browser sign-in timed out or was cancelled.',
          authenticationRequired: true,
        ),
      );
    } finally {
      _waiters.remove(waiter);
    }
  }

  void _accept(Uri uri) {
    if (_closed || !isExactNativeOAuthCallback(uri)) {
      return;
    }
    for (final waiter in List<_CallbackWaiter>.of(_waiters)) {
      if (_hasExactState(uri, waiter.state) && !waiter.completer.isCompleted) {
        waiter.completer.complete(uri);
        return;
      }
    }
    if (_buffer.length == 8) {
      _buffer.removeAt(0);
    }
    _buffer.add(uri);
  }

  static bool _hasExactState(Uri uri, String state) {
    final states = uri.queryParametersAll['state'];
    return states != null && states.length == 1 && states.single == state;
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    unawaited(_subscription?.cancel());
    for (final waiter in _waiters) {
      if (!waiter.completer.isCompleted) {
        waiter.completer.completeError(
          const NativeOAuthException(
            'Authorization callback receiver was closed.',
          ),
        );
      }
    }
    _waiters.clear();
    _buffer.clear();
  }
}

abstract interface class NativeSystemBrowserLauncher {
  Future<void> open(Uri uri);
}

final class PlatformNativeSystemBrowserLauncher
    implements NativeSystemBrowserLauncher {
  const PlatformNativeSystemBrowserLauncher();

  @override
  Future<void> open(Uri uri) async {
    final accepted = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!accepted) {
      throw const NativeOAuthException(
        'The system browser could not be opened.',
        authenticationRequired: true,
      );
    }
  }
}

final class _CallbackWaiter {
  _CallbackWaiter(this.state);

  final String state;
  final Completer<Uri> completer = Completer<Uri>();
}
