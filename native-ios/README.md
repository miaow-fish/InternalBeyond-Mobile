# Native iOS integration

This folder contains the native boundary for a Codex-direct iOS host around the existing InternalBeyond-Mobile web UI.

## Architecture

```text
InternalBeyond web UI
    |
    | OpenAI-compatible chat request
    v
custom/codex-direct-adapter.js
    |
    | RPC + streaming events
    v
custom/codex-native-bridge.js
    |
    | WKScriptMessageHandler: ibCodexBridge
    v
CodexWebBridgeHandler.swift
    |
    v
NativeCodexProvider.swift
    |                 |
    v                 v
Auth coordinator   Codex transport
(Keychain/login)   (models/SSE chat)
```

The web layer must not receive access tokens, refresh tokens or Keychain values. It only receives login status, model metadata and streamed assistant output.

## Current files

- `CodexBridgeContract.swift` — JSON RPC and streaming event contract.
- `CodexWebBridgeHandler.swift` — WKWebView message handler.
- `NativeCodexProvider.swift` — authentication/transport composition boundary.
- `InternalBeyondWebView.swift` — minimal SwiftUI WKWebView host.
- `../custom/codex-native-bridge.js` — Promise/event bridge exposed to the page as `window.IBCodexBridge`.
- `../custom/codex-direct-adapter.js` — creates a normal InternalBeyond custom-provider profile and converts native stream events into the OpenAI-compatible SSE shape already understood by IB.

## iOS target wiring

1. Add the Swift files in this directory to the iOS target.
2. Add `custom/codex-native-bridge.js` and `custom/codex-direct-adapter.js` to Copy Bundle Resources with the resource names `codex-native-bridge.js` and `codex-direct-adapter.js`.
3. Provide concrete implementations of `CodexAuthCoordinating` and `CodexTransporting` using the separately verified native code.
4. Construct `NativeCodexProvider(auth:transport:)`.
5. Present `InternalBeyondWebView(startURL:provider:)`.

The original 3 MB `index.html` intentionally remains untouched. This keeps the integration resilient to upstream InternalBeyond updates.

## Security boundary

- Password entry belongs to the external identity-provider page, not InternalBeyond.
- Long-lived credentials belong to the native secure-storage layer only.
- JavaScript/IndexedDB/localStorage must never contain refresh credentials.
- InternalBeyond backups must remain independent from authentication state.
- Logout should destroy native credentials without deleting chat history.

## Next implementation step

Implement the concrete auth coordinator and transport from the already validated iOS flow, then add a small "远舟连接" status/login sheet in the web layer that only calls `IBCodexBridge.status/login/logout/models`.
