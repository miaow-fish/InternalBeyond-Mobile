# Codex gateway authentication strategy

This fork uses an OAuth-first login flow for ChatGPT/Codex subscription access.

## Primary flow

Use the official `openai-codex` SDK browser login:

- `AsyncCodex.login_chatgpt()`
- return only `login_id` + `auth_url` to the browser
- the browser opens the official OpenAI authorization page
- the gateway waits for the SDK login completion event
- OpenAI credentials remain in the server-side Codex auth store under `CODEX_HOME`

The browser must never receive access tokens, refresh tokens, `auth.json`, or API keys.

## Fallback flow

Keep device-code login available behind an explicit fallback setting:

- `AsyncCodex.login_chatgpt_device_code()`
- use only when browser OAuth is unavailable or broken
- do not require users to run `codex login` manually for normal operation

This keeps the gateway resilient if the browser login contract changes while avoiding a hard dependency on CLI-driven login.

## Security rules

- Never commit `CODEX_HOME`, auth caches, tokens, or gateway pairing secrets.
- Store authentication state only on the gateway host.
- Use a separate high-entropy gateway pairing token for IB-Mobile -> gateway requests.
- Restrict CORS to the user's own deployed front-end origin.
- Keep the Codex runtime sandbox read-only for normal chat.
- Expose logout and login-cancel endpoints.
- Treat OAuth as a transport/login improvement, not as a reason to assume no long-lived credentials exist on the server.

## Compatibility

The implementation should support both auth modes without changing the chat API contract, so switching from browser OAuth to device-code fallback does not require front-end rewrites.
