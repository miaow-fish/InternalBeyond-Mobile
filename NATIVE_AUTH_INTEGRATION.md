# Native authentication integration boundary

This branch keeps the working friends-template deployment architecture intact and adds the smallest native iOS seam needed to host the same PWA inside WebKit.

## Baseline that remains unchanged

The existing static PWA, CY UI, model picker, conversation mapping, gateway deployment, and device-code login remain the default/fallback path. The upstream `index.html` stays untouched.

## Why the native path is separate

The validated mobile login implementation depends on iOS browser authorization, local callback handling, and Keychain-backed state. A static GitHub Pages PWA cannot provide those capabilities by itself, so the native path lives in a thin iOS host rather than being copied into browser JavaScript.

## Verified credential lifecycle

The native implementation reuses the existing Ashore code rather than reimplementing it:

- `Credentials.swift` owns the credential envelope, account/expiry decoding, storage protocol, and Keychain store.
- `AshoreAuthSession.persist()` remains the login persistence point.
- `CodexProvider.freshCredential()` remains the expiry/refresh/replacement point before authenticated work.
- Browser JavaScript never receives persisted session secrets.

## Web/native contract

When a native host is present it injects `window.IBCYHostTransport` before the CY gateway module initializes:

```js
window.IBCYHostTransport = {
  available() {},
  status() {},
  login() {},
  logout() {},
  models() {},
  chat(body, options) {},
  cancel(requestID) {}
};
```

`window.IBCY_PREFERRED_TRANSPORT = 'host'` selects the native path inside the wrapper. If the host is unavailable, the existing gateway/device-code route remains available.

## Native Swift pieces on this branch

- `native-ios/CodexHostContract.swift` defines the JSON-shaped capability boundary.
- `native-ios/AshoreCodexHostAdapter.swift` coordinates auth and transport while requiring a fresh credential before model/chat work.
- `native-ios/AshoreAuthSessionAdapter.swift` adapts the real `AshoreAuthSession` and the verified refresh helper without moving storage into the web layer.
- `native-ios/AshoreStreamTransportAdapter.swift` adapts the validated streaming transport and converts its events into bridge events.
- `native-ios/InternalBeyondWebView.swift` is the thin `WKWebView` host. It injects the native transport at document start, streams chat deltas back as the same OpenAI-compatible SSE shape the PWA already consumes, and owns cancellation at the WebKit request boundary.

The transport adapter accepts a native `modelIDs` list when it is constructed. That keeps model discovery/configuration on the native side and avoids baking a possibly stale model catalog into the public web bundle.

The first transport adapter intentionally flattens prior browser messages into the instruction context while keeping the latest user turn separate. This avoids guessing an unpublished `ProviderMessage` initializer while preserving the existing validated Ashore network path. It can be upgraded to structured history later without changing the WebKit/web contract.

## Minimal app composition

The native app only needs to construct the host provider and point the WebView at the deployed PWA:

```swift
let provider = IBCYNativeHostFactory.make(modelIDs: availableModelIDs)
InternalBeyondWebView(startURL: deployedURL, provider: provider)
```

The existing PWA remains deployable and usable without the wrapper.

## Fallback rule

Do not remove `gateway/`, `custom/cy-gateway.js`, or the device-login endpoints while introducing the native path. The native wrapper is additive.

## Validation order

1. Keep the friends-template baseline deployable and green.
2. Verify the wrapper can load the deployed PWA and expose the host selector.
3. Test login and cold-start restore on a real device.
4. Test forced-expiry refresh and replacement storage.
5. Test model loading, streaming, cancellation, logout, and gateway fallback.
6. Only after real-device validation make the wrapper path the normal mobile default.

This document contains no private tokens or gateway secrets.
