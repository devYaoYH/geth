(() => {
  // Homepage loads custom.js from <head>, before <body> exists — defer until
  // the DOM is ready, and guard against the double-inclusion re-running us.
  const boot = () => {
  if (document.getElementById('geth-bg') || document.getElementById('geth-chatbar')) return;

  const domain = window.location.hostname.split('.').slice(1).join('.') || window.location.hostname;

  // --- rotating scenery backdrop -------------------------------------------
  // Generated scenes served from this node (/images, mounted read-only).
  // Start with the scene that fits the hour, then drift through the set.
  const scenes = [
    { src: '/images/dawn-peaks.svg', hours: [5, 10] },
    { src: '/images/misty-lake.svg', hours: [10, 15] },
    { src: '/images/golden-dunes.svg', hours: [15, 18] },
    { src: '/images/ocean-dusk.svg', hours: [18, 21] },
    { src: '/images/aurora-night.svg', hours: [21, 29] }, // wraps past midnight
  ];
  const hour = new Date().getHours();
  let sceneIndex = scenes.findIndex(({ hours: [a, b] }) => hour >= a && hour < b);
  if (sceneIndex === -1) sceneIndex = scenes.findIndex(({ hours: [a, b] }) => hour + 24 >= a && hour + 24 < b);
  if (sceneIndex === -1) sceneIndex = 0;

  const bg = document.createElement('div');
  bg.id = 'geth-bg';
  bg.className = 'geth-bg';
  bg.setAttribute('aria-hidden', 'true');
  const layers = [document.createElement('div'), document.createElement('div')];
  layers.forEach((layer) => {
    layer.className = 'geth-bg__layer';
    bg.appendChild(layer);
  });
  document.body.prepend(bg);
  scenes.forEach(({ src }) => { new Image().src = src; }); // warm the cache

  let activeLayer = 0;
  const showScene = (index) => {
    const next = 1 - activeLayer;
    layers[next].style.backgroundImage = `url("${scenes[index].src}")`;
    layers[next].classList.add('is-visible');
    layers[activeLayer].classList.remove('is-visible');
    activeLayer = next;
  };
  showScene(sceneIndex);
  setInterval(() => {
    sceneIndex = (sceneIndex + 1) % scenes.length;
    showScene(sceneIndex);
  }, 4 * 60 * 1000);

  // --- floating composer, centred and lifted off the bottom ----------------
  const chatbar = document.createElement('section');
  chatbar.id = 'geth-chatbar';
  chatbar.innerHTML = `
    <form class="geth-chatbar__composer">
      <label class="geth-visually-hidden" for="geth-request">Ask your engineering org</label>
      <textarea id="geth-request" name="prompt" rows="1" maxlength="12000" placeholder="What would you like to make happen?"></textarea>
      <label class="geth-visually-hidden" for="geth-model">Answering model</label>
      <select id="geth-model" name="model">
        <option value="claude-sonnet">Sonnet · deep</option>
        <option value="claude-haiku">Haiku · quick</option>
      </select>
      <button type="submit"><span>Send</span><span class="geth-chatbar__spinner" aria-hidden="true"></span></button>
    </form>
    <p class="geth-chatbar__hint">Enter to send · Shift + Enter for a new line</p>`;
  document.body.appendChild(chatbar);

  const composer = chatbar.querySelector('.geth-chatbar__composer');
  const prompt = composer?.elements.prompt;
  const modelSelect = composer?.elements.model;
  const sendButton = composer?.querySelector('button[type="submit"]');

  // The options above mirror the assistant key's model allowlist (sonnet +
  // haiku — see config/litellm.yaml and the key minted by sso-setup.sh).
  // Remember the last choice; Open WebUI otherwise defaults to whichever
  // model LiteLLM lists first.
  const savedModel = localStorage.getItem('geth-chat-model');
  if (savedModel && modelSelect && [...modelSelect.options].some((o) => o.value === savedModel)) {
    modelSelect.value = savedModel;
  }
  modelSelect?.addEventListener('change', () => localStorage.setItem('geth-chat-model', modelSelect.value));

  // Multiline input grows the bar upward (the composer is anchored by
  // `bottom`, so extra height extends toward the top) until the CSS
  // max-height cap, after which the textarea scrolls internally.
  const autosize = () => {
    if (!prompt) return;
    prompt.style.height = 'auto';
    const cap = parseFloat(getComputedStyle(prompt).maxHeight) || 144;
    prompt.style.height = `${Math.min(prompt.scrollHeight, cap)}px`;
  };
  prompt?.addEventListener('input', autosize);

  const submitPrompt = () => {
    const value = prompt?.value.trim();
    if (!value || !sendButton) return;

    sendButton.disabled = true;
    sendButton.classList.add('is-sending');
    sendButton.querySelector('span')?.replaceChildren('Opening…');
    const destination = new URL(`https://chat.${domain}/`);
    // Open WebUI's supported URL params: `q` submits this as the first
    // message and `models` picks the answering model for the new chat.
    destination.searchParams.set('q', value);
    if (modelSelect?.value) destination.searchParams.set('models', modelSelect.value);
    window.location.assign(destination);
  };
  composer?.addEventListener('submit', (event) => {
    event.preventDefault();
    submitPrompt();
  });
  prompt?.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      submitPrompt();
    }
  });

  // --- global composer; Home tiles; polished tab controls -------------------
  // The composer belongs to the page shell, not any one Homepage tab. Keeping
  // the body padding on at every tab avoids cards ending beneath the sheet.
  const tabIcons = {
    Home: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1Z"/></svg>',
    Workshop: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="m14.7 6.3 3 3M3 21l4.7-1.2L19.4 8.1a2.1 2.1 0 0 0-3-3L4.7 16.8 3 21Z"/><path d="m12 5 7 7"/></svg>',
    Operations: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="7" rx="1.5"/><rect x="3" y="14" width="18" height="7" rx="1.5"/><path d="M7 6.5h.01M7 17.5h.01M11 6.5h6M11 17.5h6"/></svg>',
    Security: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3 20 6v5c0 5.1-3.4 8.7-8 10-4.6-1.3-8-4.9-8-10V6Z"/><path d="m8.5 12 2.2 2.2 4.8-4.8"/></svg>',
  };

  const decorateTabs = () => {
    document.querySelectorAll('[role="tab"]').forEach((tab) => {
      const label = tab.textContent.trim();
      if (!tabIcons[label] || tab.querySelector('.geth-tab-icon')) return;
      const icon = document.createElement('span');
      icon.className = 'geth-tab-icon';
      icon.setAttribute('aria-hidden', 'true');
      icon.innerHTML = tabIcons[label];
      tab.prepend(icon);
    });
  };

  const syncChrome = () => {
    chatbar.hidden = false;
    document.documentElement.classList.add('geth-chatbar-open');
    decorateTabs();

    document.querySelectorAll('.services-group').forEach((group) => {
      const heading = group.querySelector('h1, h2, h3')?.textContent.trim();
      group.classList.toggle('geth-tile-group', heading === 'Apps');
    });

  };
  new MutationObserver(syncChrome).observe(document.body, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: ['aria-selected'],
  });
  syncChrome();

  // --- on-demand app tile: snake -------------------------------------------
  // The snake tile is rendered by Homepage from services.yaml with id=snake-tile.
  // We replace its href-based link with a custom launch/stop button that calls
  // the launcher API at launch.<domain>, behind ring1.

  const LAUNCHER_BASE = `https://launch.${domain}`;

  const snakeTile = () => document.getElementById('snake-tile');

  const snakeStatus = async () => {
    try {
      const r = await fetch(`${LAUNCHER_BASE}/api/status/snake`);
      if (!r.ok) return 'stopped';
      const data = await r.json();
      return data.status;
    } catch { return 'stopped'; }
  };

  const snakeLaunch = async () => {
    try {
      const r = await fetch(`${LAUNCHER_BASE}/api/launch/snake`, { method: 'POST' });
      return r.ok;
    } catch { return false; }
  };

  const snakeStop = async () => {
    try {
      const r = await fetch(`${LAUNCHER_BASE}/api/stop/snake`, { method: 'POST' });
      return r.ok;
    } catch { return false; }
  };

  const renderSnakeTile = (status) => {
    const tile = snakeTile();
    if (!tile) return;

    // Remove the anchor link wrapper so we can replace with our own controls
    const link = tile.querySelector('a');
    if (link) {
      const parent = link.parentElement;
      while (link.firstChild) parent.insertBefore(link.firstChild, link);
      link.remove();
    }

    // Find or create the action container
    let action = tile.querySelector('.snake-action');
    if (!action) {
      action = document.createElement('div');
      action.className = 'snake-action';
      action.style.cssText = 'margin-top:8px;text-align:center;';
      tile.appendChild(action);
    }

    if (status === 'running') {
      action.innerHTML = '<button class="snake-btn snake-stop" style="background:#ef4444;color:#fff;border:none;border-radius:6px;padding:6px 16px;cursor:pointer;font-size:13px;">Stop ×</button>';
      action.querySelector('.snake-stop').onclick = async (e) => {
        e.preventDefault();
        action.innerHTML = '<span style="color:#9aa4b2;font-size:13px;">Stopping…</span>';
        await snakeStop();
        // Wait briefly then re-check
        setTimeout(async () => renderSnakeTile(await snakeStatus()), 2000);
      };
      // Also make the tile navigate to the game
      tile.style.cursor = 'pointer';
      tile.onclick = (e) => {
        if (e.target.closest('.snake-stop')) return;
        window.open(`https://game.${domain}`, '_blank');
      };
      tile.title = 'Click to open the game';
    } else if (status === 'starting') {
      action.innerHTML = '<span style="color:#f59e0b;font-size:13px;">⟳ Starting…</span>';
      // Poll until running
      setTimeout(async () => {
        const s = await snakeStatus();
        if (s === 'running' || s === 'starting') {
          renderSnakeTile(s);
        } else {
          renderSnakeTile('stopped');
        }
      }, 2000);
    } else {
      action.innerHTML = '<button class="snake-btn snake-play" style="background:#22c55e;color:#fff;border:none;border-radius:6px;padding:6px 16px;cursor:pointer;font-size:13px;">Play Snake</button>';
      action.querySelector('.snake-play').onclick = async (e) => {
        e.preventDefault();
        renderSnakeTile('starting');
        const ok = await snakeLaunch();
        if (ok) {
          // Poll for readiness
          const poll = setInterval(async () => {
            const s = await snakeStatus();
            if (s === 'running') {
              clearInterval(poll);
              renderSnakeTile('running');
              window.open(`https://game.${domain}`, '_blank');
            }
          }, 1500);
          // Timeout after 30s
          setTimeout(() => clearInterval(poll), 30000);
        } else {
          renderSnakeTile('stopped');
        }
      };
      tile.style.cursor = '';
      tile.onclick = null;
      tile.title = '';
    }
  };

  const initSnakeTile = async () => {
    const tile = snakeTile();
    if (!tile) return;
    const status = await snakeStatus();
    renderSnakeTile(status);
    // Re-check every 30s
    setInterval(async () => {
      const s = await snakeStatus();
      renderSnakeTile(s);
    }, 30000);
  };

  // Wait for the tile to appear (Homepage renders async)
  const observer = new MutationObserver(() => {
    if (snakeTile()) {
      observer.disconnect();
      initSnakeTile();
    }
  });
  observer.observe(document.body, { subtree: true, childList: true });
  // Also try immediately in case it's already rendered
  initSnakeTile();

  // Homepage only honours the hash on a fresh load, and renders every card
  // link with target="_blank". Internal hash links (e.g. the Home "Waiting on
  // you" card → /#workshop) should switch tabs in place instead: intercept the
  // click before React's anchor handles it and drive the tab directly.
  const switchToHashTab = (hash) => {
    const name = hash.replace(/^#/, '').toLowerCase();
    const tab = [...document.querySelectorAll('[role="tab"]')]
      .find((t) => t.textContent.trim().toLowerCase() === name);
    tab?.click();
    return !!tab;
  };
  document.addEventListener('click', (event) => {
    const link = event.target.closest?.('a[href^="/#"]');
    if (!link) return;
    const hash = link.getAttribute('href').slice(1);
    if (switchToHashTab(hash)) {
      event.preventDefault();
      event.stopPropagation();
      history.replaceState(null, '', hash);
    }
  }, true);
  window.addEventListener('hashchange', () => switchToHashTab(window.location.hash));
  };

  if (document.body) boot();
  else document.addEventListener('DOMContentLoaded', boot, { once: true });
})();
