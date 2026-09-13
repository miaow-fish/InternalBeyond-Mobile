import { readFile } from 'node:fs/promises';

const [gateway, picker, docs, contract, coordinator, authAdapter, transportAdapter, webView] = await Promise.all([
  readFile('custom/cy-gateway.js', 'utf8'),
  readFile('custom/cy-model-picker.js', 'utf8'),
  readFile('NATIVE_AUTH_INTEGRATION.md', 'utf8'),
  readFile('native-ios/CodexHostContract.swift', 'utf8'),
  readFile('native-ios/AshoreCodexHostAdapter.swift', 'utf8'),
  readFile('native-ios/AshoreAuthSessionAdapter.swift', 'utf8'),
  readFile('native-ios/AshoreStreamTransportAdapter.swift', 'utf8'),
  readFile('native-ios/InternalBeyondWebView.swift', 'utf8')
]);

for (const marker of [
  'window.IBCYHostTransport',
  "HOST_ENDPOINT = 'https://ibcy-host.invalid/v1/chat/completions'",
  "window.IBCY_PREFERRED_TRANSPORT === 'host'",
  'transport.chat(body',
  'hostTransport().status()',
  'hostTransport().login()',
  "current.endpoint === HOST_ENDPOINT ? ''",
  "current.apiKey === 'host-managed' ? ''"
]) {
  if (!gateway.includes(marker)) throw new Error(`gateway host transport marker missing: ${marker}`);
}

if (!gateway.includes("request('/v1/codex/login/device'") || !gateway.includes('settings.endpoint && settings.token')) {
  throw new Error('gateway/device-code fallback was removed while adding host transport');
}

if (!picker.includes('transport.models()') || !picker.includes('usingHost(settings)')) {
  throw new Error('model picker is not wired to the optional host transport');
}

for (const marker of ['AshoreAuthSession.persist()', 'CodexProvider.freshCredential()', 'credential envelope', 'Keychain']) {
  if (!docs.includes(marker)) throw new Error(`credential lifecycle documentation missing: ${marker}`);
}

if (!contract.includes('protocol IBCYCodexHostProviding') || !contract.includes('@MainActor\nprotocol IBCYAuthSessionProviding')) {
  throw new Error('native host protocol boundary is incomplete');
}

if (!coordinator.includes('try await auth.ensureFreshCredential()') || !coordinator.includes('IBCYCodexTransportProviding')) {
  throw new Error('Ashore host coordinator does not preserve fresh-credential gating');
}

for (const marker of ['AshoreAuthSession(', 'CodexProvider.freshCredential', 'KeychainCredentialStore']) {
  if (!authAdapter.includes(marker)) throw new Error(`real Ashore auth adapter missing: ${marker}`);
}

for (const marker of ['AshoreTransport', 'transport.stream(', 'type: "delta"', 'type: "completed"', 'IBCYNativeHostFactory']) {
  if (!transportAdapter.includes(marker)) throw new Error(`stream transport adapter missing: ${marker}`);
}

for (const marker of ['WKWebView', 'window.IBCYHostTransport', "window.IBCY_PREFERRED_TRANSPORT = 'host'", 'text/event-stream', 'ibcyHost']) {
  if (!webView.includes(marker)) throw new Error(`WebKit host bridge missing: ${marker}`);
}

console.log('CY optional native host transport seam OK');
