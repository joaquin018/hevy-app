(() => {
  const current = '__DEPLOY_VERSION__';
  // Local Flutter development has no deployment version.
  if (current.startsWith('__')) return;
  let checking = false;
  let notified = false;
  async function check() {
    if (checking || notified || document.hidden) return;
    checking = true;
    try {
      const response = await fetch('/deploy-version.json', { cache: 'no-store' });
      if (!response.ok) return;
      const { version } = await response.json();
      if (!/^[a-f0-9]{64}$/.test(version) || version === current) return;
      notified = true;
      const banner = document.createElement('aside');
      banner.setAttribute('role', 'status');
      banner.style.cssText = 'position:fixed;top:env(safe-area-inset-top,0);left:12px;right:12px;z-index:2147483647;background:#171a22;color:white;border:1px solid #7c8cff;border-radius:12px;padding:16px;font:14px system-ui;display:flex;align-items:center;gap:16px;box-shadow:0 4px 20px #0008';
      const message = document.createElement('span');
      message.textContent = 'Actualización disponible. Guarda tus cambios antes de actualizar.';
      message.style.flex = '1';
      const button = document.createElement('button');
      button.textContent = 'Actualizar';
      button.style.cssText = 'background:#7c8cff;color:white;border:0;border-radius:8px;padding:12px;cursor:pointer';
      button.onclick = () => location.reload();
      banner.append(message, button);
      document.body.append(banner);
    } catch (_) {
      // Offline or a deployment in progress: retry on the next check.
    } finally { checking = false; }
  }
  setInterval(check, 60000);
  window.addEventListener('online', check);
  document.addEventListener('visibilitychange', check);
  check();
})();
