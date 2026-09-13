# Native authentication integration boundary

This branch keeps the working friends-template deployment architecture intact and defines the smallest safe seam for a future native iOS authentication transport.

## Baseline that must remain unchanged

The existing static PWA, CY UI, model picker, conversation mapping, gateway deployment, and device-code login continue to work as the default/fallback path. The upstream `index.html` stays untouched.

## Why the native path is separate

The validated mobile login implementation depends on iOS-native browser authentication and a localhost callback listener. A static GitHub Pages PWA cannot provide that listener or iOS Keychain storage by itself. Therefore the native login must live in an iOS host layer rather than being copied into browser JavaScript.

## Narrow interface

A native host may expose four capabilities to the existing web UI:

- account status / login / logout
- available model list
- streamed chat request
- cancellation

The web layer should never receive or persist OpenAI access or refresh credentials. The native host owns credential refresh and secure storage. The web layer only sends model, conversation messages, and prompt context, then receives text deltas, completion state, usage metadata, or an error.

## Fallback rule

If the native host is unavailable or native authentication fails, the existing gateway + device-code flow remains available. Do not remove `gateway/`, `custom/cy-gateway.js`, or the current device-login endpoints while introducing the native path.

## Integration order

1. Keep the friends-template branch deployable and green.
2. Add a host-transport adapter without changing the upstream page.
3. Implement the native iOS side using the already validated authentication and transport code.
4. Test login, refresh, model loading, streaming, cancellation, logout, and fallback on a real device.
5. Only after real-device validation should the native path become selectable in the UI.

This document intentionally contains no credentials, private tokens, borrowed login identity, or gateway secrets.
