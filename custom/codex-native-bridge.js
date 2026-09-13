(function () {
  'use strict';

  var pending = new Map();
  var seq = 0;

  function nativeHandler() {
    return window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ibCodexBridge;
  }

  function makeId() {
    seq += 1;
    return 'ibcodex-' + Date.now().toString(36) + '-' + seq.toString(36) + '-' + Math.random().toString(36).slice(2, 10);
  }

  function request(method, params, options) {
    options = options || {};
    var handler = nativeHandler();
    if (!handler || typeof handler.postMessage !== 'function') {
      return Promise.reject(new Error('Codex native bridge is unavailable'));
    }

    var id = makeId();
    var body = Object.assign({}, params || {});
    if (String(method) === 'chat') body._bridge_request_id = id;

    return new Promise(function (resolve, reject) {
      var timeout = window.setTimeout(function () {
        pending.delete(id);
        reject(new Error('Codex native bridge timed out'));
      }, Number(options.timeout || 120000));

      pending.set(id, {
        resolve: resolve,
        reject: reject,
        onEvent: typeof options.onEvent === 'function' ? options.onEvent : null,
        timeout: timeout
      });

      handler.postMessage({ id: id, method: String(method), params: body });
    });
  }

  function settle(id, payload) {
    var entry = pending.get(String(id || ''));
    if (!entry) return;
    pending.delete(String(id));
    window.clearTimeout(entry.timeout);
    if (payload && payload.ok) entry.resolve(payload.result == null ? null : payload.result);
    else entry.reject(new Error(payload && payload.error ? String(payload.error) : 'Native Codex request failed'));
  }

  function emit(id, event) {
    var entry = pending.get(String(id || ''));
    if (!entry || !entry.onEvent) return;
    try { entry.onEvent(event || {}); } catch (error) { window.setTimeout(function () { throw error; }, 0); }
  }

  window.IBCodexBridge = {
    available: function () { return !!nativeHandler(); },
    request: request,
    status: function () { return request('status'); },
    login: function () { return request('login', {}, { timeout: 300000 }); },
    logout: function () { return request('logout'); },
    models: function () { return request('models'); },
    chat: function (params, onEvent) { return request('chat', params || {}, { onEvent: onEvent, timeout: 300000 }); },
    cancel: function (requestId) { return request('cancel', { request_id: String(requestId || '') }); },
    _resolve: settle,
    _event: emit
  };

  window.dispatchEvent(new CustomEvent('ibcodex:bridge-ready', { detail: { available: !!nativeHandler() } }));
}());
