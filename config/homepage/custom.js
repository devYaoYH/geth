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

  // --- keep the chatbar Home-only; tag the Apps group as icon tiles --------
  const syncChrome = () => {
    const activeTab = [...document.querySelectorAll('[role="tab"]')]
      .find((tab) => tab.getAttribute('aria-selected') === 'true');
    const onHome = activeTab ? activeTab.textContent.trim() === 'Home' : true;
    chatbar.hidden = !onHome;
    document.documentElement.classList.toggle('geth-chatbar-open', onHome);

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
