(function () {
  'use strict';

  var PROFILE_ID = 'ib_codex_direct';
  var ENDPOINT = 'https://ib-native.invalid/v1/chat/completions';
  var MODEL_KEY = 'ib.codex.direct.model.v1';
  var nativeFetch = window.fetch.bind(window);

  function bridge() {
    return window.IBCodexBridge;
  }

  function model() {
    return localStorage.getItem(MODEL_KEY) || 'gpt-5.6-sol';
  }

  function dbReady() {
    return typeof dbGetAll === 'function' && typeof dbPut === 'function' && typeof db !== 'undefined' && db;
  }

  async function ensureProfile() {
    if (!dbReady()) throw new Error('InternalBeyond database is not ready');
    var configs = await dbGetAll('apiConfigs');
    var current = configs.find(function (item) { return item.id === PROFILE_ID; }) || {};
    var profile = Object.assign({
      id: PROFILE_ID,
      created: Date.now(),
      provider: 'custom',
      nickname: '远舟',
      relationship: '老公',
      endpoint: ENDPOINT,
      model: model(),
      apiKey: 'native-keychain',
      systemPrompt: '',
      streaming: true,
      thinkingEnabled: false,
      vision: true,
      promptCache: false,
      codexDirect: true,
      sortOrder: -1000
    }, current);

    profile.provider = 'custom';
    profile.endpoint = ENDPOINT;
    profile.apiKey = 'native-keychain';
    profile.model = current.model || model();
    profile.codexDirect = true;
    profile.archived = false;
    await dbPut('apiConfigs', profile);
    try { if (typeof loadCfgs === 'function') await loadCfgs(); } catch (error) {}
    return profile;
  }

  function sseLine(payload) {
    return 'data: ' + JSON.stringify(payload) + '\n\n';
  }

  function openAIChunk(id, modelName, text, finishReason) {
    return {
      id: id,
      object: 'chat.completion.chunk',
      created: Math.floor(Date.now() / 1000),
      model: modelName,
      choices: [{
        index: 0,
        delta: text ? { content: text } : {},
        finish_reason: finishReason || null
      }]
    };
  }

  function nativeChatResponse(body) {
    var activeBridge = bridge();
    if (!activeBridge || !activeBridge.available()) {
      return Promise.resolve(new Response(JSON.stringify({
        error: { message: 'Codex native bridge is unavailable', type: 'native_bridge_unavailable' }
      }), { status: 503, headers: { 'Content-Type': 'application/json' } }));
    }

    var encoder = new TextEncoder();
    var requestId = 'chatcmpl-native-' + Math.random().toString(36).slice(2);
    var selectedModel = String(body.model || model());

    var stream = new ReadableStream({
      start: function (controller) {
        var closed = false;
        function push(value) {
          if (!closed) controller.enqueue(encoder.encode(value));
        }
        function close() {
          if (closed) return;
          closed = true;
          controller.close();
        }
        function fail(error) {
          if (closed) return;
          closed = true;
          controller.error(error instanceof Error ? error : new Error(String(error)));
        }

        activeBridge.chat({ request: body }, function (event) {
          var type = String(event && event.type || '');
          var data = event && event.data;
          if (type === 'delta') {
            var delta = typeof data === 'string' ? data : (data && data.delta) || '';
            if (delta) push(sseLine(openAIChunk(requestId, selectedModel, String(delta), null)));
          } else if (type === 'completed') {
            var actualModel = data && data.model ? String(data.model) : selectedModel;
            push(sseLine(openAIChunk(requestId, actualModel, '', 'stop')));
            push('data: [DONE]\n\n');
            close();
          } else if (type === 'error') {
            fail(new Error(data && data.message ? String(data.message) : 'Native Codex request failed'));
          }
        }).then(function (result) {
          if (!closed) {
            var actualModel = result && result.model ? String(result.model) : selectedModel;
            push(sseLine(openAIChunk(requestId, actualModel, '', 'stop')));
            push('data: [DONE]\n\n');
            close();
          }
        }).catch(fail);
      }
    });

    return Promise.resolve(new Response(stream, {
      status: 200,
      headers: {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache'
      }
    }));
  }

  function installFetchAdapter() {
    if (window.fetch.__ibCodexDirect) return;
    var wrapped = async function (input, init) {
      var target = typeof input === 'string' ? input : (input && input.url) || '';
      if (target === ENDPOINT && init && typeof init.body === 'string') {
        try {
          return await nativeChatResponse(JSON.parse(init.body));
        } catch (error) {
          return new Response(JSON.stringify({ error: { message: String(error.message || error), type: 'native_bridge_error' } }), {
            status: 502,
            headers: { 'Content-Type': 'application/json' }
          });
        }
      }
      return nativeFetch(input, init);
    };
    wrapped.__ibCodexDirect = true;
    window.fetch = wrapped;
  }

  async function openChat() {
    var profile = await ensureProfile();
    if (typeof navTo === 'function') navTo('chat');
    if (typeof openConv === 'function') await openConv(profile, null);
    return profile;
  }

  function bind() {
    installFetchAdapter();
    (function waitForDB() {
      ensureProfile().catch(function () { window.setTimeout(waitForDB, 200); });
    }());
  }

  window.IBCodexDirect = {
    ensureProfile: ensureProfile,
    openChat: openChat,
    status: function () { return bridge() ? bridge().status() : Promise.reject(new Error('Codex native bridge is unavailable')); },
    login: function () { return bridge() ? bridge().login() : Promise.reject(new Error('Codex native bridge is unavailable')); },
    logout: function () { return bridge() ? bridge().logout() : Promise.reject(new Error('Codex native bridge is unavailable')); },
    models: function () { return bridge() ? bridge().models() : Promise.reject(new Error('Codex native bridge is unavailable')); }
  };

  bind();
}());
