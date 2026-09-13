import { readFile } from 'node:fs/promises';

const [gateway, picker, docs] = await Promise.all([
  readFile('custom/cy-gateway.js', 'utf8'),
  readFile('custom/cy-model-picker.js', 'utf8'),
  readFile('NATIVE_AUTH_INTEGRATION.md', 'utf8')
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

if (!docs.includes('window.IBCYHostTransport') || !docs.includes('The web layer never needs OpenAI access or refresh credentials')) {
  throw new Error('native host contract documentation is incomplete');
}

console.log('CY optional native host transport seam OK');
