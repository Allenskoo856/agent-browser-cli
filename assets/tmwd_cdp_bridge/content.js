;(function(){ if (/streamlit/i.test(document.title)) return;

// Remove meta CSP tags
document.querySelectorAll('meta[http-equiv="Content-Security-Policy"]').forEach(e => e.remove());

/**
 * Render a bottom-right badge that reflects the real bridge connection status.
 */
(function(){
  if(window.self!==window.top)return;
  const d=document.createElement('div');
  d.id='agent-browser-cli-ind';
  d.style.cssText='position:fixed;bottom:8px;right:8px;color:white;padding:4px 7px;border-radius:4px;font-size:11px;font-weight:bold;z-index:99999;cursor:pointer;box-shadow:0 2px 4px rgba(0,0,0,0.2);opacity:0.5;';
  /**
   * Show the badge only when the bridge is really connected.
   */
  function setBadgeState(connected, detail) {
    // Hide the indicator completely when offline to avoid persistent page noise.
    d.style.display = connected ? 'block' : 'none';
    d.innerText = 'agent_browser_cli: 已连接';
    d.style.background = '#4CAF50';
    d.dataset.connected = connected ? '1' : '0';
    d.dataset.detail = detail || '';
  }
  /**
   * Poll background status and update the badge visibility.
   */
  async function refreshBadgeState() {
    try {
      const resp = await chrome.runtime.sendMessage({ cmd: 'status' });
      const connected = !!resp?.ok && !!resp?.data?.wsConnected;
      setBadgeState(connected, resp?.data?.wsUrl || '');
    } catch (e) {
      setBadgeState(false, e.message || '');
    }
  }
  d.addEventListener('click',()=>alert((d.dataset.connected === '1' ? '会话活跃' : '会话未连接') + '\nURL: ' + location.href + (d.dataset.detail ? '\nBridge: ' + d.dataset.detail : '')));
  (document.body||document.documentElement).appendChild(d);
  setBadgeState(false, '');
  refreshBadgeState();
  setInterval(refreshBadgeState, 3000);
})();

new MutationObserver(muts => {
  for (const m of muts) for (const n of m.addedNodes) {
    if (n.id === TID || (n.querySelector && n.querySelector('#' + TID))) {
      const el = n.id === TID ? n : n.querySelector('#' + TID);
      handle(el);
    }
  }
}).observe(document.documentElement, { childList: true, subtree: true });

/**
 * Consume page-side bridge requests and forward them to the extension background worker.
 */
async function handle(el) {
  try {
    const req = el.textContent.trim() ? JSON.parse(el.textContent) : { cmd: 'cookies' };
    const cmd = req.cmd || 'cookies';
    let resp;
    if (cmd === 'cookies') {
      resp = await chrome.runtime.sendMessage({ cmd: 'cookies', url: req.url || location.href });
    } else if (cmd === 'cdp') {
      resp = await chrome.runtime.sendMessage({ cmd: 'cdp', method: req.method, params: req.params || {}, tabId: req.tabId });
    } else if (cmd === 'batch') {
      resp = await chrome.runtime.sendMessage({ cmd: 'batch', commands: req.commands, tabId: req.tabId });
    } else if (cmd === 'tabs') {
      resp = await chrome.runtime.sendMessage({ cmd: 'tabs', method: req.method, tabId: req.tabId });
    } else if (cmd === 'openTab') {
      resp = await chrome.runtime.sendMessage({ cmd: 'openTab', url: req.url, active: req.active });
    } else {
      resp = { ok: false, error: 'unknown cmd: ' + cmd };
    }
    el.textContent = JSON.stringify(resp);
  } catch (e) {
    el.textContent = JSON.stringify({ ok: false, error: e.message });
  }
}
})();
