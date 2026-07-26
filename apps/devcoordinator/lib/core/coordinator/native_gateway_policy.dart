import 'package:coordinator_client/coordinator_client.dart';

import '../storage/settings_store.dart';

/// The only remote native gateway accepted by the production application.
const canonicalProductionNativeGatewayUrl =
    'https://console.classified.guru/api/v2';

/// Resolves a stored native profile without allowing preferences or an older
/// build to select a different authorization origin.
CoordinatorEndpoint canonicalNativeGatewayEndpoint(
  StoredConnectionProfile profile,
) {
  if (profile.kind != StoredConnectionKind.nativeGatewayV2) {
    throw ArgumentError.value(
      profile.kind,
      'profile.kind',
      'must be nativeGatewayV2',
    );
  }
  if (profile.baseUrl != canonicalProductionNativeGatewayUrl) {
    throw const CoordinatorEndpointException(
      'This build accepts only the canonical production native gateway.',
    );
  }
  return CoordinatorEndpoint.nativeV2(
    Uri.parse(canonicalProductionNativeGatewayUrl),
  );
}
