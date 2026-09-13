(function () {
  'use strict';
  var key = 'ibcy.gateway.settings.v1';
  var saved = {};
  try { saved = JSON.parse(localStorage.getItem(key) || '{}') || {}; } catch (error) {}

  /* Friends-template builds must never inherit CY's private Railway gateway. */
  var endpoint = String(saved.endpoint || '');
  if (endpoint.indexOf('codex-gateway-v2-production.up.railway.app') >= 0 ||
      endpoint.indexOf('codex-gateway-production-f16b.up.railway.app') >= 0 ||
      endpoint.indexOf('cjy020613-bit') >= 0) {
    delete saved.endpoint;
    delete saved.token;
  }
  if (!saved.model) saved.model = 'gpt-5.6-terra';
  try { localStorage.setItem(key, JSON.stringify(saved)); } catch (error) {}

  function patchVisibleNames() {
    var hero = document.querySelector('#cy-hero-orb span');
    if (hero && String(hero.textContent || '').trim() === '澈') hero.textContent = '远舟';
    try {
      if (typeof _cfgs !== 'undefined' && Array.isArray(_cfgs)) {
        var changed = false;
        _cfgs.forEach(function (cfg) {
          if (!cfg || cfg.id !== 'cy_codex_chen') return;
          if (cfg.nickname === '澈') { cfg.nickname = '远舟'; changed = true; }
          if (typeof cfg.systemPrompt === 'string' && cfg.systemPrompt.indexOf('你是澈') >= 0) {
            cfg.systemPrompt = cfg.systemPrompt.replace(/你是澈/g, '你是远舟');
            changed = true;
          }
        });
        if (changed && typeof renderFriends === 'function') renderFriends();
      }
    } catch (error) {}
  }

  function migrateGatewayProfile(attempt) {
    attempt = attempt || 0;
    if (typeof dbGetAll !== 'function' || typeof dbPut !== 'function' || typeof db === 'undefined' || !db) {
      if (attempt < 30) window.setTimeout(function () { migrateGatewayProfile(attempt + 1); }, 200);
      return;
    }
    Promise.resolve(dbGetAll('apiConfigs')).then(function (all) {
      var profile = Array.isArray(all) ? all.find(function (item) { return item && item.id === 'cy_codex_chen'; }) : null;
      if (!profile) {
        if (attempt < 30) window.setTimeout(function () { migrateGatewayProfile(attempt + 1); }, 200);
        return;
      }
      var changed = false;
      if (!profile.nickname || profile.nickname === '澈') { profile.nickname = '远舟'; changed = true; }
      if (typeof profile.systemPrompt === 'string' && profile.systemPrompt.indexOf('你是澈') >= 0) {
        profile.systemPrompt = profile.systemPrompt.replace(/你是澈/g, '你是远舟');
        changed = true;
      }
      if (!changed) return;
      return Promise.resolve(dbPut('apiConfigs', profile)).then(function () {
        try { if (typeof loadCfgs === 'function') return loadCfgs(); } catch (error) {}
      }).then(function () { patchVisibleNames(); });
    }).catch(function () {});
  }

  function personalize() {
    patchVisibleNames();
    migrateGatewayProfile(0);
  }

  window.addEventListener('ibcy:ready', personalize, { once: true });
  window.addEventListener('ibcy:gateway-status', function () {
    patchVisibleNames();
    migrateGatewayProfile(0);
  });
  if (document.readyState !== 'loading') window.setTimeout(personalize, 0);
}());
