import 'package:coordinator_client/coordinator_client.dart';
import 'package:devcoordinator_design/devcoordinator_design.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/coordinator/legacy_action_policy.dart';
import '../core/storage/secure_token_store.dart';
import '../core/storage/settings_store.dart';
import 'app_services.dart';
import 'app_state.dart';

final class AppController extends ChangeNotifier {
  factory AppController({
    required AppSettingsStore settingsStore,
    required SecureTokenStore tokenStore,
    required AppCoordinatorServiceFactory coordinatorFactory,
    required AppUpdateService updateService,
    Future<PackageInfo> Function()? packageInfoLoader,
  }) {
    return AppController._(
      settingsStore,
      tokenStore,
      coordinatorFactory,
      updateService,
      packageInfoLoader ?? PackageInfo.fromPlatform,
    );
  }

  AppController._(
    this._settingsStore,
    this._tokenStore,
    this._coordinatorFactory,
    this._updateService,
    this._packageInfoLoader,
  );

  final AppSettingsStore _settingsStore;
  final SecureTokenStore _tokenStore;
  final AppCoordinatorServiceFactory _coordinatorFactory;
  final AppUpdateService _updateService;
  final Future<PackageInfo> Function() _packageInfoLoader;

  AppCoordinatorService? _coordinator;
  AppState _state = AppState.initial();
  AppState get state => _state;

  bool supports(CoordinatorCapability capability) =>
      _coordinator?.supports(capability) ?? false;

  Future<void> initialize() async {
    try {
      var settings = await _settingsStore.read();
      String? cleanupError;
      String? sessionCredential;
      final coldLaunchErrors = <String>[];
      try {
        // Always retry the exact pre-session-only key, including when an
        // earlier partial cleanup left neither a profile nor a marker.
        await _tokenStore.purgeLegacyValue();
      } catch (error) {
        coldLaunchErrors.add('credential: ${_safeMessage(error)}');
      }
      if (settings.credentialCleanupPending) {
        final cleanup = await _beginCredentialCleanup(
          settings.copyWith(
            clearConnection: true,
            credentialCleanupPending: true,
          ),
          priorErrors: coldLaunchErrors,
        );
        settings = cleanup.settings;
        if (cleanup.errors.isNotEmpty) {
          cleanupError = _credentialCleanupMessage(cleanup.errors);
        }
      } else if (coldLaunchErrors.isNotEmpty) {
        final cleanup = await _retryColdLaunchLegacyPurge(
          settings,
          priorErrors: coldLaunchErrors,
        );
        settings = cleanup.settings;
        if (cleanup.errors.isNotEmpty) {
          cleanupError = _credentialCleanupMessage(cleanup.errors);
        }
      }
      if (cleanupError == null &&
          !settings.credentialCleanupPending &&
          settings.connection != null) {
        try {
          // This returns only a process-session credential. It can never
          // recover a bearer from a previous app process.
          sessionCredential = await _tokenStore.read();
        } catch (error) {
          final pendingSettings = settings.copyWith(
            clearConnection: true,
            credentialCleanupPending: true,
          );
          final cleanup = await _beginCredentialCleanup(
            pendingSettings,
            priorErrors: <String>['credential: ${_safeMessage(error)}'],
          );
          settings = cleanup.settings;
          if (cleanup.errors.isNotEmpty) {
            cleanupError = _credentialCleanupMessage(cleanup.errors);
          }
        }
      }
      _state = _state.copyWith(
        settings: settings,
        appearance: _appearanceFrom(settings),
        availability: settings.connection == null
            ? ConnectionAvailability.disconnected
            : ConnectionAvailability.unavailable,
        busy: false,
        connectionError: cleanupError,
        clearConnectionError: cleanupError == null,
      );
      notifyListeners();

      if (cleanupError == null &&
          settings.connection != null &&
          sessionCredential != null &&
          sessionCredential.isNotEmpty) {
        await _connectSaved(settings.connection!, sessionCredential);
      }

      if (settings.updateChecksEnabled) {
        await checkForUpdates(manual: false);
      }
    } catch (error) {
      _state = _state.copyWith(
        busy: false,
        connectionError: _safeMessage(error),
        availability: ConnectionAvailability.unavailable,
      );
      notifyListeners();
    }
  }

  void selectSection(AppSection section) {
    if (_state.section == section) return;
    _state = _state.copyWith(section: section);
    notifyListeners();
  }

  Future<void> setAppearance({
    required String styleName,
    required String brightnessName,
  }) async {
    final settings = _state.settings.copyWith(
      styleName: styleName,
      brightnessName: brightnessName,
    );
    await _settingsStore.write(settings);
    _state = _state.copyWith(
      settings: settings,
      appearance: _appearanceFrom(settings),
    );
    notifyListeners();
  }

  Future<void> setUpdateChecksEnabled(bool enabled) async {
    final settings = _state.settings.copyWith(updateChecksEnabled: enabled);
    await _settingsStore.write(settings);
    _state = _state.copyWith(settings: settings);
    notifyListeners();
    if (enabled) {
      await checkForUpdates(manual: false);
    }
  }

  /// Rechecks the cached release source when the app returns to the foreground.
  ///
  /// The release package applies the persisted daily schedule, so frequent
  /// foreground transitions do not produce frequent network requests.
  Future<void> handleAppResumed() async {
    if (_state.busy || !_state.settings.updateChecksEnabled) return;
    await checkForUpdates(manual: false);
  }

  Future<void> connect({
    required StoredConnectionProfile profile,
    required String credential,
  }) async {
    if (_state.settings.credentialCleanupPending) {
      _state = _state.copyWith(
        connectionError:
            'Saved credential cleanup must succeed before another connection '
            'can be created.',
      );
      notifyListeners();
      return;
    }
    final previousState = _state;
    _state = _state.copyWith(
      busy: true,
      availability: ConnectionAvailability.unavailable,
      clearConnectionError: true,
      clearInventory: true,
    );
    notifyListeners();
    AppCoordinatorService? candidate;
    String? previousCredential;
    var tokenWriteStarted = false;
    var settingsWriteStarted = false;
    try {
      if (previousState.settings.connection != null) {
        previousCredential = await _tokenStore.read();
      }
      candidate = await _coordinatorFactory.connect(
        profile: profile,
        credential: credential,
      );
      final inventory = await candidate.loadInventory();
      tokenWriteStarted = true;
      await _tokenStore.write(credential);
      final settings = previousState.settings.copyWith(connection: profile);
      settingsWriteStarted = true;
      await _settingsStore.write(settings);
      _coordinator?.close();
      _coordinator = candidate;
      candidate = null;
      _state = previousState.copyWith(
        settings: settings,
        inventory: inventory,
        availability: ConnectionAvailability.available,
        busy: false,
        clearConnectionError: true,
      );
    } catch (error) {
      final rollbackErrors = <String>[];
      if (settingsWriteStarted) {
        try {
          await _settingsStore.write(previousState.settings);
        } catch (rollbackError) {
          rollbackErrors.add('settings: ${_safeMessage(rollbackError)}');
        }
      }
      if (tokenWriteStarted) {
        try {
          if (previousCredential == null || previousCredential.isEmpty) {
            await _tokenStore.clear();
          } else {
            await _tokenStore.write(previousCredential);
          }
        } catch (rollbackError) {
          rollbackErrors.add('credential: ${_safeMessage(rollbackError)}');
        }
      }
      final rollbackMessage = rollbackErrors.isEmpty
          ? ''
          : ' The previous saved connection could not be fully restored '
                '(${rollbackErrors.join('; ')}).';
      if (rollbackErrors.isEmpty) {
        _state = previousState.copyWith(
          busy: false,
          connectionError: '${_safeMessage(error)}$rollbackMessage',
        );
      } else {
        _coordinator?.close();
        _coordinator = null;
        final pendingSettings = previousState.settings.copyWith(
          clearConnection: true,
          credentialCleanupPending: true,
        );
        final cleanup = await _beginCredentialCleanup(pendingSettings);
        if (cleanup.settings.credentialCleanupPending) {
          rollbackErrors.addAll(cleanup.errors);
        }
        final recoveryMessage = cleanup.settings.credentialCleanupPending
            ? _credentialCleanupMessage(rollbackErrors)
            : 'The ambiguous saved connection was cleared; connect again.';
        _state = previousState.copyWith(
          settings: cleanup.settings,
          availability: ConnectionAvailability.disconnected,
          busy: false,
          clearInventory: true,
          connectionError:
              '${_safeMessage(error)}$rollbackMessage $recoveryMessage',
        );
      }
    } finally {
      candidate?.close();
    }
    notifyListeners();
  }

  Future<void> _connectSaved(
    StoredConnectionProfile profile,
    String credential,
  ) async {
    AppCoordinatorService? candidate;
    try {
      candidate = await _coordinatorFactory.connect(
        profile: profile,
        credential: credential,
      );
      final inventory = await candidate.loadInventory();
      _coordinator?.close();
      _coordinator = candidate;
      candidate = null;
      _state = _state.copyWith(
        inventory: inventory,
        availability: ConnectionAvailability.available,
        clearConnectionError: true,
      );
    } catch (error) {
      _setConnectionError(_safeMessage(error));
      return;
    } finally {
      candidate?.close();
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    final settings = _state.settings.copyWith(
      clearConnection: true,
      credentialCleanupPending: true,
    );
    _coordinator?.close();
    _coordinator = null;
    _state = _state.copyWith(
      settings: settings,
      availability: ConnectionAvailability.disconnected,
      clearInventory: true,
      clearConnectionError: true,
      clearActionKey: true,
      section: AppSection.overview,
    );
    notifyListeners();

    final cleanup = await _beginCredentialCleanup(settings);
    _state = _state.copyWith(settings: cleanup.settings);
    if (cleanup.errors.isNotEmpty) {
      _state = _state.copyWith(
        connectionError: _credentialCleanupMessage(cleanup.errors),
      );
    } else {
      _state = _state.copyWith(clearConnectionError: true);
    }
    notifyListeners();
  }

  Future<bool> retryCredentialCleanup() async {
    if (!_state.settings.credentialCleanupPending) return true;
    final cleanup = await _beginCredentialCleanup(
      _state.settings.copyWith(
        clearConnection: true,
        credentialCleanupPending: true,
      ),
    );
    _state = _state.copyWith(settings: cleanup.settings);
    if (cleanup.errors.isEmpty) {
      _state = _state.copyWith(clearConnectionError: true);
      notifyListeners();
      return true;
    }
    _state = _state.copyWith(
      connectionError: _credentialCleanupMessage(cleanup.errors),
    );
    notifyListeners();
    return false;
  }

  Future<void> refresh() async {
    final coordinator = _coordinator;
    if (coordinator == null || !_state.canRefresh) return;
    _state = _state.copyWith(refreshing: true, clearConnectionError: true);
    notifyListeners();
    try {
      final inventory = await coordinator.loadInventory();
      _state = _state.copyWith(
        inventory: inventory,
        availability: ConnectionAvailability.available,
        refreshing: false,
        clearConnectionError: true,
      );
    } catch (error) {
      _state = _state.copyWith(
        refreshing: false,
        connectionError: _safeMessage(error),
        availability: _availabilityAfterRemoteFailure(),
      );
    }
    notifyListeners();
  }

  Future<void> runServerAction(
    CoordinatorServer server,
    CoordinatorResourceAction action, {
    String? presentationLabel,
  }) {
    if (_coordinator != null &&
        _state.canMutate &&
        supports(CoordinatorCapability.serverLifecycle)) {
      if (!_isCurrentServerTarget(server)) {
        return _reportBlockedMutation(
          'Server controls require the exact server from the current '
          'committed inventory.',
        );
      }
      final policy = legacyServerControlPolicy(server);
      final allowed = switch (action) {
        CoordinatorResourceAction.start =>
          policy == LegacyServerControlPolicy.startOnly,
        CoordinatorResourceAction.stop || CoordinatorResourceAction.restart =>
          policy == LegacyServerControlPolicy.restartAndStop,
      };
      if (!allowed) {
        return _reportBlockedMutation(
          'Server controls are blocked until the lifecycle state and listener '
          'identity are conclusive.',
        );
      }
    }
    final targetLabel = _presentationTarget(
      presentationLabel,
      _resourceName(server.name, 'server'),
    );
    return _runAction(
      'server:${server.id}:${action.name}',
      '${_actionTitle(action.name)} $targetLabel',
      CoordinatorCapability.serverLifecycle,
      (service) => service.actOnServer(server, action),
    );
  }

  Future<void> runProjectAction(
    CoordinatorProject project,
    CoordinatorProjectAction action, {
    String? presentationLabel,
  }) {
    final targetLabel = _presentationTarget(
      presentationLabel,
      _projectActionName(project),
    );
    return _runAction(
      'project:${project.id}:${action.name}',
      '${_actionTitle(action.name)} $targetLabel',
      CoordinatorCapability.projectLifecycle,
      (service) => service.actOnProject(project, action),
    );
  }

  Future<void> runContainerAction(
    CoordinatorContainer container,
    CoordinatorResourceAction action, {
    String? presentationLabel,
  }) {
    final targetLabel = _presentationTarget(
      presentationLabel,
      _resourceName(container.name, 'container'),
    );
    return _runAction(
      'container:${container.id}:${action.name}',
      '${_actionTitle(action.name)} $targetLabel',
      CoordinatorCapability.containerLifecycle,
      (service) => service.actOnContainer(container, action),
    );
  }

  Future<CoordinatorLogResult?> readServerLogs(CoordinatorServer server) {
    return _readLogs(
      'server:${server.id}:logs',
      CoordinatorCapability.logsRead,
      (service) => service.readServerLogs(server),
    );
  }

  Future<CoordinatorLogResult?> readContainerLogs(
    CoordinatorContainer container,
  ) {
    return _readLogs(
      'container:${container.id}:logs',
      CoordinatorCapability.logsRead,
      (service) => service.readContainerLogs(container),
    );
  }

  Future<CoordinatorLease?> leasePort({
    required CoordinatorProject project,
    required CoordinatorServer server,
    required int firstPort,
    required int lastPort,
    int? preferredPort,
    Duration? ttl,
    String? purpose,
  }) async {
    final coordinator = _coordinator;
    if (coordinator == null ||
        !_state.canMutate ||
        !supports(CoordinatorCapability.portLeases)) {
      return null;
    }
    if (!_isCommittedLeaseTarget(project, server)) {
      _state = _state.copyWith(
        connectionError:
            'Port leasing requires an exact enrolled server owned by the '
            'selected project in the current inventory.',
      );
      notifyListeners();
      return null;
    }
    _state = _state.copyWith(
      actionKey: 'ports:lease',
      clearConnectionError: true,
    );
    notifyListeners();
    late final CoordinatorLease lease;
    try {
      lease = await coordinator.leasePort(
        project: project,
        server: server,
        firstPort: firstPort,
        lastPort: lastPort,
        preferredPort: preferredPort,
        ttl: ttl,
        purpose: purpose,
      );
      _state = _state.copyWith(lastLease: lease, clearConnectionError: true);
      notifyListeners();
    } on CoordinatorMutationOutcomeUnknownException {
      _state = _state.copyWith(
        clearActionKey: true,
        connectionError: _unknownMutationMessage,
        availability: _availabilityAfterRemoteFailure(),
      );
      notifyListeners();
      return null;
    } catch (error) {
      _state = _state.copyWith(
        clearActionKey: true,
        connectionError: _safeMessage(error),
        availability: _availabilityAfterRemoteFailure(),
      );
      notifyListeners();
      return null;
    }

    try {
      final inventory = await coordinator.loadInventory();
      _state = _state.copyWith(
        inventory: inventory,
        availability: ConnectionAvailability.available,
        clearActionKey: true,
        clearConnectionError: true,
      );
    } catch (error) {
      _state = _state.copyWith(
        availability: _availabilityAfterRemoteFailure(),
        clearActionKey: true,
        connectionError:
            'Port ${lease.port} was leased, but the latest inventory could not '
            'be loaded. The retained snapshot is read-only until refresh '
            'succeeds: ${_safeMessage(error)}',
      );
    }
    notifyListeners();
    return lease;
  }

  bool _isCommittedLeaseTarget(
    CoordinatorProject project,
    CoordinatorServer server,
  ) {
    final inventory = _state.inventory;
    if (inventory == null) return false;
    final projectMatches = inventory.projects.where(
      (candidate) =>
          candidate.id == project.id &&
          candidate.canonicalRoot == project.canonicalRoot,
    );
    if (projectMatches.length != 1) return false;
    final serverMatches = inventory.servers.where(
      (candidate) =>
          candidate.id == server.id &&
          candidate.name == server.name &&
          candidate.repoId == project.id &&
          candidate.projectRoot == project.canonicalRoot,
    );
    if (serverMatches.length != 1) return false;
    final wireTargetMatches = inventory.servers.where(
      (candidate) =>
          candidate.name == server.name &&
          candidate.repoId == project.id &&
          candidate.projectRoot == project.canonicalRoot,
    );
    return wireTargetMatches.length == 1;
  }

  Future<void> releasePort(
    CoordinatorLease lease, {
    String? presentationLabel,
  }) {
    if (_coordinator != null &&
        _state.canMutate &&
        supports(CoordinatorCapability.portLeases)) {
      if (!_isCurrentLeaseTarget(lease)) {
        return _reportBlockedMutation(
          'Port release requires the exact lease from the current committed '
          'inventory.',
        );
      }
      if (!isLeaseReleasable(lease, now: DateTime.now())) {
        return _reportBlockedMutation(
          'This retained port lease is not active or has expired; it cannot '
          'be released.',
        );
      }
    }
    final targetLabel = _presentationTarget(
      presentationLabel,
      'port ${lease.port}',
    );
    return _runAction(
      'port:${lease.id}:release',
      'Release $targetLabel',
      CoordinatorCapability.portLeases,
      (service) => service.releasePort(lease),
      clearLastLease: _state.lastLease?.id == lease.id,
    );
  }

  void dismissLastLease() {
    if (_state.lastLease == null) return;
    _state = _state.copyWith(clearLastLease: true);
    notifyListeners();
  }

  Future<CoordinatorLogResult?> _readLogs(
    String key,
    CoordinatorCapability capability,
    Future<CoordinatorLogResult> Function(AppCoordinatorService service) action,
  ) async {
    final coordinator = _coordinator;
    if (coordinator == null ||
        !_state.canReadRemoteData ||
        !supports(capability)) {
      return null;
    }
    _state = _state.copyWith(actionKey: key, clearConnectionError: true);
    notifyListeners();
    try {
      final result = await action(coordinator);
      _state = _state.copyWith(
        clearActionKey: true,
        clearConnectionError: true,
      );
      notifyListeners();
      return result;
    } catch (error) {
      _state = _state.copyWith(
        clearActionKey: true,
        connectionError: _safeMessage(error),
        availability: _availabilityAfterRemoteFailure(),
      );
      notifyListeners();
      return null;
    }
  }

  Future<void> _runAction(
    String key,
    String label,
    CoordinatorCapability capability,
    Future<CoordinatorActionResult> Function(AppCoordinatorService service)
    action, {
    bool clearLastLease = false,
  }) async {
    final coordinator = _coordinator;
    if (coordinator == null || !_state.canMutate || !supports(capability)) {
      return;
    }
    _state = _state.copyWith(actionKey: key, clearConnectionError: true);
    notifyListeners();
    late final CoordinatorActionResult result;
    try {
      result = await action(coordinator);
      _state = _state.copyWith(
        lastActionResult: result,
        lastActionLabel: label,
        clearLastLease: clearLastLease,
        clearConnectionError: true,
      );
      notifyListeners();
    } on CoordinatorMutationOutcomeUnknownException {
      _state = _state.copyWith(
        clearActionKey: true,
        connectionError: _unknownMutationMessage,
        availability: _availabilityAfterRemoteFailure(),
      );
      notifyListeners();
      return;
    } catch (error) {
      _state = _state.copyWith(
        clearActionKey: true,
        connectionError: _safeMessage(error),
        availability: _availabilityAfterRemoteFailure(),
      );
      notifyListeners();
      return;
    }

    try {
      final inventory = await coordinator.loadInventory();
      _state = _state.copyWith(
        inventory: inventory,
        availability: ConnectionAvailability.available,
        clearActionKey: true,
        clearConnectionError: true,
      );
    } catch (error) {
      _state = _state.copyWith(
        availability: _availabilityAfterRemoteFailure(),
        clearActionKey: true,
        connectionError:
            'The action completed, but the latest inventory could not be '
            'loaded. The retained snapshot is read-only until refresh '
            'succeeds: ${_safeMessage(error)}',
      );
    }
    notifyListeners();
  }

  Future<void> checkForUpdates({required bool manual}) async {
    if (_state.checkingUpdates) return;
    _state = _state.copyWith(checkingUpdates: true, clearUpdateMessage: true);
    notifyListeners();
    try {
      final packageInfo = await _packageInfoLoader();
      final result = await _updateService.check(
        currentVersion: packageInfo.version,
        manual: manual,
        lastCheckedAt: _state.settings.lastUpdateCheck,
        releaseCache: _state.settings.releaseCache,
        updateSuppression: _state.settings.updateSuppression,
      );
      final settings = _state.settings.copyWith(
        lastUpdateCheck: result.checkedAt,
        releaseCache: result.releaseCache,
        updateSuppression: result.updateSuppression,
      );
      Object? persistenceError;
      try {
        await _settingsStore.write(settings);
      } catch (error) {
        persistenceError = error;
      }
      final persistenceMessage = persistenceError == null
          ? null
          : 'The update result is available, but its local check state could '
                'not be saved: ${_safeMessage(persistenceError)}';
      _state = _state.copyWith(
        settings: persistenceError == null ? settings : _state.settings,
        availableRelease: result.release,
        clearAvailableRelease: result.release == null,
        updateMessage: persistenceMessage ?? result.message,
        updateMessageKind: persistenceError != null
            ? UpdateMessageKind.error
            : result.message == null
            ? null
            : result.release == null
            ? UpdateMessageKind.informational
            : UpdateMessageKind.success,
        clearUpdateMessage:
            persistenceMessage == null && result.message == null,
        checkingUpdates: false,
      );
    } catch (error) {
      _state = _state.copyWith(
        checkingUpdates: false,
        updateMessage: manual ? _safeMessage(error) : null,
        updateMessageKind: manual ? UpdateMessageKind.error : null,
        clearUpdateMessage: !manual,
      );
    }
    notifyListeners();
  }

  /// Opens the available release and reports whether the platform accepted it.
  ///
  /// Launcher failures are recoverable UI state and never escape as uncaught
  /// exceptions from an asynchronous button callback.
  Future<bool> openAvailableRelease() async {
    final release = _state.availableRelease;
    if (release == null) {
      _state = _state.copyWith(
        updateMessage: 'The available release is no longer present.',
        updateMessageKind: UpdateMessageKind.error,
      );
      notifyListeners();
      return false;
    }
    try {
      await _updateService.openRelease(release);
      if (_state.updateMessageKind == UpdateMessageKind.error) {
        _state = _state.copyWith(clearUpdateMessage: true);
        notifyListeners();
      }
      return true;
    } catch (error) {
      _state = _state.copyWith(
        updateMessage: _safeMessage(error),
        updateMessageKind: UpdateMessageKind.error,
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> ignoreAvailableRelease() async {
    final release = _state.availableRelease;
    if (release == null) return _reportMissingAvailableRelease();
    try {
      final suppression = _updateService.ignore(
        release: release,
        currentSuppression: _state.settings.updateSuppression,
      );
      final settings = _state.settings.copyWith(updateSuppression: suppression);
      await _settingsStore.write(settings);
      _state = _state.copyWith(
        settings: settings,
        clearAvailableRelease: true,
        clearUpdateMessage: _state.updateMessageKind == UpdateMessageKind.error,
      );
      notifyListeners();
      return true;
    } catch (error) {
      _reportUpdateActionFailure(error);
      return false;
    }
  }

  Future<bool> deferAvailableRelease() async {
    final release = _state.availableRelease;
    if (release == null) return _reportMissingAvailableRelease();
    try {
      final suppression = _updateService.remindLater(
        release: release,
        currentSuppression: _state.settings.updateSuppression,
      );
      final settings = _state.settings.copyWith(updateSuppression: suppression);
      await _settingsStore.write(settings);
      _state = _state.copyWith(
        settings: settings,
        clearAvailableRelease: true,
        clearUpdateMessage: _state.updateMessageKind == UpdateMessageKind.error,
      );
      notifyListeners();
      return true;
    } catch (error) {
      _reportUpdateActionFailure(error);
      return false;
    }
  }

  void clearMessage() {
    _state = _state.copyWith(
      clearConnectionError: true,
      clearUpdateMessage: true,
    );
    notifyListeners();
  }

  void _setConnectionError(String message) {
    _state = _state.copyWith(
      connectionError: message,
      availability: _availabilityAfterRemoteFailure(),
    );
    notifyListeners();
  }

  bool _isCurrentServerTarget(CoordinatorServer server) {
    final inventory = _state.inventory;
    if (inventory == null ||
        server.id.trim().isEmpty ||
        server.name.trim().isEmpty ||
        (server.repoId?.trim().isEmpty ?? true) ||
        (server.projectRoot?.trim().isEmpty ?? true)) {
      return false;
    }
    return inventory.servers
            .where((candidate) => identical(candidate, server))
            .length ==
        1;
  }

  bool _isCurrentLeaseTarget(CoordinatorLease lease) {
    final inventory = _state.inventory;
    if (inventory == null ||
        lease.id.trim().isEmpty ||
        (lease.repoId?.trim().isEmpty ?? true) ||
        (lease.projectRoot?.trim().isEmpty ?? true)) {
      return false;
    }
    return inventory.leases
            .where((candidate) => identical(candidate, lease))
            .length ==
        1;
  }

  Future<void> _reportBlockedMutation(String message) {
    _state = _state.copyWith(clearActionKey: true, connectionError: message);
    notifyListeners();
    return Future<void>.value();
  }

  Future<({PersistedAppSettings settings, List<String> errors})>
  _retryColdLaunchLegacyPurge(
    PersistedAppSettings settings, {
    required List<String> priorErrors,
  }) async {
    final errors = <String>[...priorErrors];
    try {
      await _settingsStore.setCredentialCleanupPending(true);
    } catch (error) {
      errors.add('cleanup marker: ${_safeMessage(error)}');
    }

    var purged = false;
    try {
      await _tokenStore.purgeLegacyValue();
      purged = true;
    } catch (error) {
      errors.add('credential retry: ${_safeMessage(error)}');
    }
    if (purged) {
      try {
        await _settingsStore.setCredentialCleanupPending(false);
        // The profile is non-secret form state. A transient legacy-key failure
        // is not disconnect intent, so retain it once cleanup is confirmed.
        return (
          settings: settings.copyWith(credentialCleanupPending: false),
          errors: const <String>[],
        );
      } catch (error) {
        errors.add('cleanup marker: ${_safeMessage(error)}');
      }
    }

    final pendingSettings = settings.copyWith(
      clearConnection: true,
      credentialCleanupPending: true,
    );
    try {
      await _settingsStore.write(pendingSettings);
    } catch (error) {
      errors.add('settings: ${_safeMessage(error)}');
    }
    return (settings: pendingSettings, errors: errors);
  }

  Future<({PersistedAppSettings settings, List<String> errors})>
  _beginCredentialCleanup(
    PersistedAppSettings pendingSettings, {
    List<String> priorErrors = const <String>[],
  }) async {
    final attemptErrors = <String>[...priorErrors];
    try {
      await _settingsStore.setCredentialCleanupPending(true);
    } catch (error) {
      attemptErrors.add('cleanup marker: ${_safeMessage(error)}');
    }
    final cleanup = await _completeCredentialCleanup(pendingSettings);
    if (!cleanup.settings.credentialCleanupPending) {
      // A successful credential purge, profile removal, and final marker clear
      // supersede transient errors from the start of this same attempt.
      return (settings: cleanup.settings, errors: cleanup.errors);
    }
    return (
      settings: cleanup.settings,
      errors: <String>[...attemptErrors, ...cleanup.errors],
    );
  }

  Future<({PersistedAppSettings settings, List<String> errors})>
  _completeCredentialCleanup(PersistedAppSettings pendingSettings) async {
    final errors = <String>[];
    var credentialCleared = false;
    var settingsCleared = false;
    try {
      await _tokenStore.clear();
      credentialCleared = true;
    } catch (error) {
      errors.add('credential: ${_safeMessage(error)}');
    }
    try {
      await _settingsStore.write(pendingSettings);
      settingsCleared = true;
    } catch (error) {
      errors.add('settings: ${_safeMessage(error)}');
    }

    if (credentialCleared && settingsCleared) {
      try {
        await _settingsStore.setCredentialCleanupPending(false);
        return (
          settings: pendingSettings.copyWith(credentialCleanupPending: false),
          errors: errors,
        );
      } catch (error) {
        errors.add('cleanup marker: ${_safeMessage(error)}');
      }
    }
    return (settings: pendingSettings, errors: errors);
  }

  static String _credentialCleanupMessage(List<String> errors) {
    return 'The live connection was closed, but saved credential cleanup is '
        'incomplete (${errors.join('; ')}). Retry cleanup before connecting.';
  }

  bool _reportMissingAvailableRelease() {
    _state = _state.copyWith(
      updateMessage: 'The available release is no longer present.',
      updateMessageKind: UpdateMessageKind.error,
    );
    notifyListeners();
    return false;
  }

  void _reportUpdateActionFailure(Object error) {
    _state = _state.copyWith(
      updateMessage: _safeMessage(error),
      updateMessageKind: UpdateMessageKind.error,
    );
    notifyListeners();
  }

  ConnectionAvailability _availabilityAfterRemoteFailure() {
    return _state.inventory == null
        ? ConnectionAvailability.unavailable
        : ConnectionAvailability.stale;
  }

  static AppearancePreferences _appearanceFrom(PersistedAppSettings settings) {
    return AppearancePreferences(
      visualStyle: VisualStyle.fromStorage(settings.styleName),
      themeMode: ThemeModePreference.fromStorage(settings.brightnessName),
    );
  }

  static String _safeMessage(Object error) {
    final message = error.toString().replaceFirst(
      RegExp(r'^[A-Za-z0-9_]+Exception:\s*'),
      '',
    );
    if (message.length <= 600) return message;
    return '${message.substring(0, 597)}…';
  }

  static String _actionTitle(String action) {
    if (action.isEmpty) return 'Run';
    return '${action[0].toUpperCase()}${action.substring(1)}';
  }

  static String _resourceName(String value, String fallback) {
    final normalized = value.trim();
    return normalized.isEmpty ? fallback : normalized;
  }

  static String _presentationTarget(String? value, String fallback) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? fallback : normalized;
  }

  static String _projectActionName(CoordinatorProject project) {
    final displayName = project.displayName.trim();
    if (displayName.isNotEmpty) return displayName;
    return 'project';
  }

  static const String _unknownMutationMessage =
      'The command may have completed, but its outcome is unknown. Refresh '
      'the coordinator state before trying again.';

  @override
  void dispose() {
    _coordinator?.close();
    _coordinator = null;
    super.dispose();
  }
}
