# Native authentication integration boundary

This branch keeps the working friends-template deployment architecture intact and defines the smallest safe seam for a future native iOS authentication transport.

## Baseline that must remain unchanged

The existing static PWA, CY UI, model picker, conversation mapping, gateway deployment, and device-code login continue to work as the default/fallback path. The upstream `index.html` stays untouched.

## Why the native path is separate

The validated mobile login implementation depends on iOS-native browser authentication and a localhost callback listener. A static GitHub Pages PWA cannot provide that listener or iOS Keychain storage by itself. Therefore the native login must live in an iOS host layer rather than being copied into browser JavaScript.

## Web/native contract

When a native host is present it injects `window.IBCYHostTransport` before the CY gateway module initializes. The object is deliberately small:

```js
window.IBCYHostTransport = {
  available() {},
  status() {},
  login() {},
  logout() {},
  models() {},
  chat(body, options) {}
};
```

Expected behavior:

- `available()` returns whether the host bridge can currently be used.
- `status()` resolves to an object containing at least `logged_in`; account/source/usage metadata are optional.
- `login()` completes the native login flow and resolves only after the host has a usable credential, or rejects on cancel/failure.
- `logout()` clears the host-owned login state.
- `models()` resolves to an array, `{data:[...]}`, `{models:[...]}`, or `{items:[...]}`.
- `chat(body, options)` receives the already-enriched InternalBeyond chat body and returns a standard browser `Response` using the same OpenAI-compatible SSE shape that the current page already consumes.

A native wrapper may set `window.IBCY_PREFERRED_TRANSPORT = 'host'` before page startup to make the host path the initial choice. If the host is unavailable the web app falls back to the existing gateway behavior.

The web layer never needs OpenAI access or refresh credentials. Credential refresh and secure storage stay entirely inside the native host. Only model choice, conversation messages, prompt context, streamed text, completion state, usage metadata, and errors cross the bridge.

## Fallback rule

If the native host is unavailable or native authentication fails, the existing gateway + device-code flow remains available. Do not remove `gateway/`, `custom/cy-gateway.js`, or the current device-login endpoints while introducing the native path.

## Integration order

1. Keep the friends-template branch deployable and green.
2. Keep the host-transport adapter isolated from the upstream page.
3. Implement the native iOS side using the already validated authentication and transport code.
4. Test login, refresh, model loading, streaming, cancellation, logout, and gateway fallback on a real device.
5. Only after real-device validation should the host path become the normal default inside the wrapper.

This document intentionally contains no credentials, private tokens, borrowed login identity, or gateway secrets.
