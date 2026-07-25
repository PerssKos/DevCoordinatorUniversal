# Extending the application

The workspace keeps domain behavior, visual language, transport, storage, and
release policy replaceable without allowing a feature to bypass safety rules.

## Dependency direction

```text
apps/devcoordinator
  ├── packages/coordinator_client
  ├── packages/devcoordinator_design
  └── packages/release_update
```

Internal packages do not import the application. Feature screens call
`AppController`; the composition root injects coordinator, storage, and update
services. Native runners contain platform packaging only.

## Add a visual style

1. Add one stable storage value to `VisualStyle`; preserve the fallback for
   unknown values so downgrades remain usable.
2. Define light, dark, high-contrast-light, and high-contrast-dark semantic
   token sets in `devcoordinator_design`.
3. Extend `AppThemes.forStyle`. Feature code must continue to use `App*`
   components and semantic status tones instead of branching on the style.
4. Test every brightness/contrast combination, text scaling, narrow and wide
   geometry, keyboard focus, and reduced motion. Do not bundle proprietary
   vendor fonts, icons, or copied assets.

## Add a coordinator transport

1. Implement `AppCoordinatorService` and its factory adapter outside feature
   widgets. Map only exact known capabilities; ignore unknown ones.
2. Validate the endpoint before any credential is read. Remote endpoints are
   HTTPS-only. The legacy host bearer remains process-session-only; future
   installed-client refresh credentials require a separate platform secure
   store with explicit rotation, revocation, and cleanup semantics.
3. Parse responses into the typed models in `coordinator_client`. HTTP success
   never overrides a semantic failure, partial result, or needs-attention
   result.
4. Treat a broken dispatched mutation as outcome-unknown unless the protocol
   supplies a verified idempotent operation result. Require authoritative
   reconciliation before another mutation.
5. Add contract, adapter, denial, timeout, redaction, and recovery tests before
   exposing the connection mode.

## Add a capability profile

1. Define the provider contract in `contracts/native-gateway.openapi.yaml`.
   Keep `x-implementation-status: deferred` until both provider and consumer
   exist and advertise the capability.
2. Add typed DTOs and a transport adapter; do not pass raw maps into widgets.
3. Add the collection-first UI, honest loading/empty/error/stale states, exact
   target confirmation, and a retained result.
4. Gate every action by fresh connection state, advertised server capability,
   user scope/grant, object allowed action, and revision.
5. Run the strict OpenAPI validator, package tests, widget tests, and a real
   provider/client end-to-end test. Remove the matching completion-ledger item
   only in that verified change.

## Add an update channel

Implement `AppUpdateService` at the composition boundary. The update decision
package remains provider-neutral; a platform adapter may open Play, Microsoft
Store, Mac App Store, or a signed direct-release page. It must return failure
when the platform did not accept the handoff and must never silently install an
unsigned artifact.

## Regenerate application icons

Edit the primary vector at `assets/branding/app_icon.svg` and its legacy
circular Android companion at `assets/branding/app_icon_round.svg`, then run
`tool/generate_app_icons.sh`. The script uses `ffmpeg` to regenerate tracked
Android density assets, the macOS asset catalog, and the Windows executable
icon. Adaptive Android launchers use the vector foreground and the dedicated
API 33 monochrome layer.
