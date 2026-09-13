(function () {
  'use strict';

  var pill;
  var sheet;
  var state = { loggedIn: false, checking: false, account: null };

  function bridge() { return window.IBCodexBridge; }

  function esc(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function ensureStyles() {
    if (document.getElementById('ib-codex-direct-style')) return;
    var style = document.createElement('style');
    style.id = 'ib-codex-direct-style';
    style.textContent = [
      '#ib-codex-pill{position:fixed;right:16px;bottom:88px;z-index:2147483000;border:0;border-radius:999px;padding:10px 14px;background:rgba(24,24,27,.84);color:#fff;backdrop-filter:blur(18px);font:600 13px -apple-system,BlinkMacSystemFont,sans-serif;box-shadow:0 8px 30px rgba(0,0,0,.18)}',
      '#ib-codex-pill[data-state="online"]{background:rgba(31,92,61,.9)}',
      '#ib-codex-mask{position:fixed;inset:0;z-index:2147483001;background:rgba(0,0,0,.28);display:flex;align-items:flex-end;justify-content:center;padding:18px}',
      '#ib-codex-mask[hidden]{display:none}',
      '#ib-codex-sheet{width:min(520px,100%);border-radius:24px;background:#fff;color:#171717;padding:18px;box-shadow:0 24px 80px rgba(0,0,0,.28);font-family:-apple-system,BlinkMacSystemFont,sans-serif}',
      '#ib-codex-sheet h3{margin:0 0 4px;font-size:18px}',
      '#ib-codex-sheet p{margin:6px 0 14px;color:#666;font-size:13px;line-height:1.55}',
      '.ib-codex-row{display:flex;gap:8px;align-items:center;margin-top:10px}',
      '.ib-codex-row button{flex:1;border:0;border-radius:14px;padding:11px 12px;font-weight:650}',
      '.ib-codex-primary{background:#111;color:#fff}',
      '.ib-codex-secondary{background:#f1f1f3;color:#222}',
      '#ib-codex-detail{padding:12px;border-radius:16px;background:#f7f7f8;font-size:13px;line-height:1.55;word-break:break-word}',
      '#ib-codex-model{width:100%;box-sizing:border-box;border:1px solid #ddd;border-radius:12px;padding:10px 12px;background:#fff;margin-top:10px}'
    ].join('');
    document.head.appendChild(style);
  }

  function paint() {
    if (!pill) return;
    pill.dataset.state = state.loggedIn ? 'online' : (state.checking ? 'checking' : 'offline');
    pill.textContent = state.loggedIn ? '远舟已连接' : (state.checking ? '远舟连接中…' : '远舟连接');
    if (!sheet || sheet.hidden) return;
    var detail = sheet.querySelector('#ib-codex-detail');
    var login = sheet.querySelector('#ib-codex-login');
    var logout = sheet.querySelector('#ib-codex-logout');
    var account = state.account || {};
    detail.innerHTML = state.loggedIn
      ? '<b>ChatGPT 已登录</b><br>' + esc(account.email || account.name || account.account_id || 'Codex 直连已就绪')
      : '<b>尚未登录</b><br>登录会交给 iPhone 原生层处理，网页不会保存凭证。';
    login.hidden = !!state.loggedIn;
    logout.hidden = !state.loggedIn;
  }

  async function refresh() {
    var active = bridge();
    if (!active || !active.available()) {
      state = { loggedIn: false, checking: false, account: null };
      paint();
      return null;
    }
    state.checking = true;
    paint();
    try {
      var result = await active.status();
      state.loggedIn = !!(result && (result.logged_in || result.loggedIn));
      state.account = result && (result.account || result) || null;
      return result;
    } finally {
      state.checking = false;
      paint();
    }
  }

  async function login() {
    var active = bridge();
    if (!active || !active.available()) throw new Error('Native Codex bridge unavailable');
    state.checking = true;
    paint();
    try {
      await active.login();
      await refresh();
      await loadModels();
    } finally {
      state.checking = false;
      paint();
    }
  }

  async function logout() {
    var active = bridge();
    if (!active || !active.available()) return;
    await active.logout();
    await refresh();
  }

  async function loadModels() {
    var select = sheet && sheet.querySelector('#ib-codex-model');
    if (!select || !state.loggedIn) return;
    try {
      var result = await bridge().models();
      var items = Array.isArray(result) ? result : (result && (result.models || result.data)) || [];
      var models = items.map(function (item) {
        return typeof item === 'string' ? item : String(item.slug || item.id || item.model || '');
      }).filter(Boolean);
      if (!models.length) return;
      var current = localStorage.getItem('ib.codex.direct.model.v1') || models[0];
      select.innerHTML = models.map(function (name) {
        return '<option value="' + esc(name) + '"' + (name === current ? ' selected' : '') + '>' + esc(name) + '</option>';
      }).join('');
    } catch (error) {}
  }

  function open() {
    ensureSheet();
    sheet.hidden = false;
    refresh().then(loadModels).catch(function (error) {
      var detail = sheet.querySelector('#ib-codex-detail');
      detail.textContent = String(error.message || error);
    });
  }

  function close() { if (sheet) sheet.hidden = true; }

  function ensureSheet() {
    if (sheet) return;
    sheet = document.createElement('div');
    sheet.id = 'ib-codex-mask';
    sheet.hidden = true;
    sheet.innerHTML = '<section id="ib-codex-sheet" role="dialog" aria-modal="true">' +
      '<h3>远舟连接</h3>' +
      '<p>ChatGPT / Codex 登录与凭证由 iPhone 原生层管理。</p>' +
      '<div id="ib-codex-detail">正在检查…</div>' +
      '<select id="ib-codex-model" aria-label="Codex 模型"></select>' +
      '<div class="ib-codex-row"><button id="ib-codex-login" class="ib-codex-primary">登录 ChatGPT</button><button id="ib-codex-logout" class="ib-codex-secondary">退出登录</button><button id="ib-codex-close" class="ib-codex-secondary">关闭</button></div>' +
      '</section>';
    document.body.appendChild(sheet);
    sheet.addEventListener('click', function (event) { if (event.target === sheet) close(); });
    sheet.querySelector('#ib-codex-close').addEventListener('click', close);
    sheet.querySelector('#ib-codex-login').addEventListener('click', function () { login().catch(showError); });
    sheet.querySelector('#ib-codex-logout').addEventListener('click', function () { logout().catch(showError); });
    sheet.querySelector('#ib-codex-model').addEventListener('change', function (event) {
      localStorage.setItem('ib.codex.direct.model.v1', event.target.value);
      if (window.IBCodexDirect && window.IBCodexDirect.ensureProfile) window.IBCodexDirect.ensureProfile().catch(function () {});
    });
  }

  function showError(error) {
    ensureSheet();
    sheet.querySelector('#ib-codex-detail').textContent = String(error.message || error);
  }

  function bind() {
    ensureStyles();
    pill = document.createElement('button');
    pill.id = 'ib-codex-pill';
    pill.type = 'button';
    pill.textContent = '远舟连接';
    pill.addEventListener('click', open);
    document.body.appendChild(pill);
    refresh().catch(function () {});
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', bind, { once: true });
  else bind();

  window.IBCodexDirectUI = { open: open, refresh: refresh };
}());
