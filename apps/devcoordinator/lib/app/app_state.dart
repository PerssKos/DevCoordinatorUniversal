import 'package:coordinator_client/coordinator_client.dart';
import 'package:devcoordinator_design/devcoordinator_design.dart';
import 'package:release_update/release_update.dart';

import '../core/storage/settings_store.dart';

enum AppSection {
  overview,
  projects,
  servers,
  containers,
  ports,
  events,
  settings,
  more,
}

/// Whether the coordinator can be trusted for decisions and remote actions.
///
/// A stale state can retain the last successful inventory for reference, but
/// it must never authorize a mutation or another data-dependent remote read.
enum ConnectionAvailability { disconnected, available, stale, unavailable }

enum ConnectionPhase {
  bootstrapping,
  disconnected,
  validatingEndpoint,
  launchingBrowser,
  awaitingCallback,
  exchangingCode,
  refreshingSession,
  loadingInventory,
  connected,
  stale,
  offline,
  authenticationRequired,
  revoked,
  incompatible,
  denied,
}

/// Semantic outcome of the latest user-visible update operation.
///
/// Keeping this separate from [AppState.updateMessage] prevents translated or
/// upstream text from being treated as an error detector.
enum UpdateMessageKind { informational, success, error }

final class AppState {
  const AppState({
    required this.appearance,
    required this.settings,
    this.availability = ConnectionAvailability.disconnected,
    this.section = AppSection.overview,
    this.inventory,
    this.nativeInventory,
    this.nativeMeta,
    this.nativeSession,
    this.nativeEvents = const <NativeGatewayEvent>[],
    this.nativeEventsCursor,
    this.nativeEventsHasMore = true,
    this.nativeEventsLoading = false,
    this.nativeEventsError,
    this.lastNativeOperation,
    this.connectionPhase = ConnectionPhase.disconnected,
    this.availableRelease,
    this.lastLease,
    this.lastActionResult,
    this.lastActionLabel,
    this.connectionError,
    this.updateMessage,
    this.updateMessageKind,
    this.busy = false,
    this.refreshing = false,
    this.checkingUpdates = false,
    this.actionKey,
  });

  factory AppState.initial() => const AppState(
    appearance: AppearancePreferences(),
    settings: PersistedAppSettings(),
    busy: true,
  );

  final AppearancePreferences appearance;
  final PersistedAppSettings settings;
  final ConnectionAvailability availability;
  final AppSection section;
  final CoordinatorInventory? inventory;
  final NativeGatewayInventory? nativeInventory;
  final NativeGatewayMeta? nativeMeta;
  final NativeGatewaySession? nativeSession;
  final List<NativeGatewayEvent> nativeEvents;
  final String? nativeEventsCursor;
  final bool nativeEventsHasMore;
  final bool nativeEventsLoading;
  final String? nativeEventsError;
  final NativeGatewayOperation? lastNativeOperation;
  final ConnectionPhase connectionPhase;
  final ReleaseInfo? availableRelease;
  final CoordinatorLease? lastLease;
  final CoordinatorActionResult? lastActionResult;
  final String? lastActionLabel;
  final String? connectionError;
  final String? updateMessage;
  final UpdateMessageKind? updateMessageKind;
  final bool busy;
  final bool refreshing;
  final bool checkingUpdates;
  final String? actionKey;

  bool get isConnected =>
      availability == ConnectionAvailability.available &&
      settings.connection != null &&
      (inventory != null || nativeInventory != null);

  bool get hasStaleInventory =>
      availability == ConnectionAvailability.stale &&
      (inventory != null || nativeInventory != null);

  bool get isNativeConnection =>
      settings.connection?.kind == StoredConnectionKind.nativeGatewayV2;

  bool get canMutate => isConnected && !refreshing && actionKey == null;

  bool get canReadRemoteData => canMutate;

  bool get canRefresh =>
      settings.connection != null && !refreshing && actionKey == null;

  AppState copyWith({
    AppearancePreferences? appearance,
    PersistedAppSettings? settings,
    ConnectionAvailability? availability,
    AppSection? section,
    CoordinatorInventory? inventory,
    bool clearInventory = false,
    NativeGatewayInventory? nativeInventory,
    bool clearNativeInventory = false,
    NativeGatewayMeta? nativeMeta,
    bool clearNativeMeta = false,
    NativeGatewaySession? nativeSession,
    bool clearNativeSession = false,
    List<NativeGatewayEvent>? nativeEvents,
    bool clearNativeEvents = false,
    String? nativeEventsCursor,
    bool clearNativeEventsCursor = false,
    bool? nativeEventsHasMore,
    bool? nativeEventsLoading,
    String? nativeEventsError,
    bool clearNativeEventsError = false,
    NativeGatewayOperation? lastNativeOperation,
    bool clearLastNativeOperation = false,
    ConnectionPhase? connectionPhase,
    ReleaseInfo? availableRelease,
    bool clearAvailableRelease = false,
    CoordinatorLease? lastLease,
    bool clearLastLease = false,
    CoordinatorActionResult? lastActionResult,
    String? lastActionLabel,
    bool clearLastActionResult = false,
    String? connectionError,
    bool clearConnectionError = false,
    String? updateMessage,
    UpdateMessageKind? updateMessageKind,
    bool clearUpdateMessage = false,
    bool? busy,
    bool? refreshing,
    bool? checkingUpdates,
    String? actionKey,
    bool clearActionKey = false,
  }) {
    return AppState(
      appearance: appearance ?? this.appearance,
      settings: settings ?? this.settings,
      availability: availability ?? this.availability,
      section: section ?? this.section,
      inventory: clearInventory ? null : (inventory ?? this.inventory),
      nativeInventory: clearNativeInventory
          ? null
          : (nativeInventory ?? this.nativeInventory),
      nativeMeta: clearNativeMeta ? null : (nativeMeta ?? this.nativeMeta),
      nativeSession: clearNativeSession
          ? null
          : (nativeSession ?? this.nativeSession),
      nativeEvents: clearNativeEvents
          ? const <NativeGatewayEvent>[]
          : (nativeEvents ?? this.nativeEvents),
      nativeEventsCursor: clearNativeEventsCursor
          ? null
          : (nativeEventsCursor ?? this.nativeEventsCursor),
      nativeEventsHasMore: nativeEventsHasMore ?? this.nativeEventsHasMore,
      nativeEventsLoading: nativeEventsLoading ?? this.nativeEventsLoading,
      nativeEventsError: clearNativeEventsError
          ? null
          : (nativeEventsError ?? this.nativeEventsError),
      lastNativeOperation: clearLastNativeOperation
          ? null
          : (lastNativeOperation ?? this.lastNativeOperation),
      connectionPhase: connectionPhase ?? this.connectionPhase,
      availableRelease: clearAvailableRelease
          ? null
          : (availableRelease ?? this.availableRelease),
      lastLease: clearLastLease ? null : (lastLease ?? this.lastLease),
      lastActionResult: clearLastActionResult
          ? null
          : (lastActionResult ?? this.lastActionResult),
      lastActionLabel: clearLastActionResult
          ? null
          : (lastActionLabel ?? this.lastActionLabel),
      connectionError: clearConnectionError
          ? null
          : (connectionError ?? this.connectionError),
      updateMessage: clearUpdateMessage
          ? null
          : (updateMessage ?? this.updateMessage),
      updateMessageKind: clearUpdateMessage
          ? null
          : (updateMessageKind ?? this.updateMessageKind),
      busy: busy ?? this.busy,
      refreshing: refreshing ?? this.refreshing,
      checkingUpdates: checkingUpdates ?? this.checkingUpdates,
      actionKey: clearActionKey ? null : (actionKey ?? this.actionKey),
    );
  }
}
