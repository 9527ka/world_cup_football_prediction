/**
 * Floating live-stream overlay.
 *
 * Injected on demand into the page body so users can watch a m3u8 feed
 * while still interacting with the Flutter app (browse matches, place bets).
 *
 * Public API (called from Flutter via dart:js_interop):
 *   window.openLiveStream(url, home, away)
 *   window.closeLiveStream()
 *
 * Behavior:
 *   - One overlay at a time (re-opening with a new url replaces the iframe src).
 *   - Drag by header (mouse + touch).
 *   - Three size presets (small / medium / large).
 *   - Minimize collapses to a 56×56 floating dock pill in bottom-right.
 *   - Close fully tears down the iframe so the m3u8 fetch stops.
 *
 * Why an iframe instead of inline <video>: the player page (live.html)
 * already implements HLS.js + Safari fallback + error handling. Reusing it
 * keeps the player logic in one place and survives the iframe being torn
 * down/recreated when the user picks a different match.
 */
(function() {
  'use strict';

  let overlay = null;     // host DIV
  let iframe = null;      // child iframe loading live.html
  let titleEl = null;
  let isMinimized = false;
  let currentSize = 'medium'; // 'small' | 'medium' | 'large'

  // ── public API ───────────────────────────────────────────────────────

  window.openLiveStream = function(url, home, away) {
    if (!url) return;
    ensureOverlay();
    titleEl.textContent = (home && away) ? (home + ' vs ' + away) : '赛事直播';
    const params = new URLSearchParams({ url: url });
    if (home) params.set('home', home);
    if (away) params.set('away', away);
    iframe.src = '/live.html?' + params.toString();
    show();
    if (isMinimized) restore();
  };

  window.closeLiveStream = function() {
    if (!overlay) return;
    iframe.src = 'about:blank'; // stop the upstream m3u8 fetch immediately
    overlay.style.display = 'none';
  };

  // ── construction ─────────────────────────────────────────────────────

  function ensureOverlay() {
    if (overlay) return;

    const styleEl = document.createElement('style');
    styleEl.textContent = `
      #live-overlay {
        position: fixed;
        right: 12px;
        bottom: 76px;
        z-index: 2147483646;
        background: #111;
        border-radius: 10px;
        box-shadow: 0 10px 30px rgba(0,0,0,.45), 0 0 0 1px rgba(255,255,255,.05);
        overflow: hidden;
        font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif;
        color: #fff;
        user-select: none;
        -webkit-user-select: none;
        touch-action: none;
        display: none;
      }
      #live-overlay.size-small  { width: 240px; height: 158px; }
      #live-overlay.size-medium { width: 320px; height: 200px; }
      #live-overlay.size-large  { width: 420px; height: 254px; }
      #live-overlay.minimized {
        width: 56px; height: 56px;
        border-radius: 28px;
        cursor: pointer;
      }
      #live-overlay-header {
        height: 28px;
        display: flex; align-items: center;
        background: rgba(0,0,0,.85);
        border-bottom: 1px solid #222;
        cursor: move;
        padding: 0 6px 0 10px;
      }
      #live-overlay.minimized #live-overlay-header,
      #live-overlay.minimized #live-overlay-iframe,
      #live-overlay.minimized #live-overlay-resizer {
        display: none;
      }
      #live-overlay.minimized #live-overlay-min-icon {
        display: flex;
      }
      #live-overlay-min-icon {
        display: none;
        position: absolute; inset: 0;
        align-items: center; justify-content: center;
        background: linear-gradient(180deg, #ff4040 0%, #c8001a 100%);
        border-radius: 28px;
        font-weight: 800; font-size: 11px;
        letter-spacing: .5px;
      }
      #live-overlay-title {
        flex: 1;
        font-size: 11px; font-weight: 600;
        white-space: nowrap; text-overflow: ellipsis; overflow: hidden;
        max-width: 100%;
      }
      #live-overlay-dot {
        display: inline-block; width: 6px; height: 6px; border-radius: 50%;
        background: #f44; margin-right: 5px;
        animation: lo-pulse 1.4s ease-in-out infinite;
      }
      @keyframes lo-pulse {
        0%, 100% { opacity: 1; }
        50%      { opacity: .35; }
      }
      .live-overlay-btn {
        width: 22px; height: 22px;
        display: inline-flex; align-items: center; justify-content: center;
        border-radius: 4px;
        cursor: pointer;
        margin-left: 2px;
        opacity: .85;
      }
      .live-overlay-btn:hover { background: rgba(255,255,255,.12); opacity: 1; }
      .live-overlay-btn:active { background: rgba(255,255,255,.20); }
      .live-overlay-btn svg { width: 14px; height: 14px; stroke: #fff; }
      #live-overlay-iframe {
        width: 100%;
        height: calc(100% - 28px);
        border: 0;
        background: #000;
        display: block;
      }
      #live-overlay-resizer {
        position: absolute;
        left: 0; bottom: 0;
        width: 16px; height: 16px;
        cursor: nesw-resize;
        background: linear-gradient(45deg, transparent 0%, transparent 45%, rgba(255,255,255,.4) 45%, rgba(255,255,255,.4) 55%, transparent 55%);
      }
      @media (max-width: 480px) {
        #live-overlay.size-large { width: calc(100vw - 24px); height: 220px; }
      }
    `;
    document.head.appendChild(styleEl);

    overlay = document.createElement('div');
    overlay.id = 'live-overlay';
    overlay.classList.add('size-medium');
    overlay.innerHTML = `
      <div id="live-overlay-header">
        <span id="live-overlay-dot"></span>
        <div id="live-overlay-title">赛事直播</div>
        <div class="live-overlay-btn" data-action="size" title="切换大小">
          <svg viewBox="0 0 24 24" fill="none" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 3 3 3 3 9"></polyline><polyline points="15 21 21 21 21 15"></polyline></svg>
        </div>
        <div class="live-overlay-btn" data-action="minimize" title="最小化">
          <svg viewBox="0 0 24 24" fill="none" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><line x1="5" y1="12" x2="19" y2="12"></line></svg>
        </div>
        <div class="live-overlay-btn" data-action="close" title="关闭">
          <svg viewBox="0 0 24 24" fill="none" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><line x1="6" y1="6" x2="18" y2="18"></line><line x1="6" y1="18" x2="18" y2="6"></line></svg>
        </div>
      </div>
      <iframe id="live-overlay-iframe" allow="autoplay; fullscreen; encrypted-media" allowfullscreen></iframe>
      <div id="live-overlay-min-icon">LIVE</div>
    `;
    document.body.appendChild(overlay);

    iframe = overlay.querySelector('#live-overlay-iframe');
    titleEl = overlay.querySelector('#live-overlay-title');

    wireButtons();
    wireDrag();
  }

  function show() {
    overlay.style.display = 'block';
  }

  function wireButtons() {
    overlay.addEventListener('click', e => {
      const btn = e.target.closest('.live-overlay-btn');
      if (btn) {
        const action = btn.getAttribute('data-action');
        e.stopPropagation();
        if (action === 'close') {
          window.closeLiveStream();
        } else if (action === 'minimize') {
          minimize();
        } else if (action === 'size') {
          cycleSize();
        }
        return;
      }
      // Click on minimized pill restores.
      if (isMinimized) restore();
    });
  }

  function minimize() {
    overlay.classList.add('minimized');
    isMinimized = true;
  }
  function restore() {
    overlay.classList.remove('minimized');
    isMinimized = false;
  }
  function cycleSize() {
    const order = ['small', 'medium', 'large'];
    const idx = order.indexOf(currentSize);
    const next = order[(idx + 1) % order.length];
    overlay.classList.remove('size-' + currentSize);
    overlay.classList.add('size-' + next);
    currentSize = next;
  }

  // ── drag (mouse + touch) ─────────────────────────────────────────────

  function wireDrag() {
    let dragging = false;
    let startX = 0, startY = 0;
    let origLeft = 0, origTop = 0;

    function onDown(clientX, clientY, e) {
      // Don't drag when clicking buttons.
      if (e.target.closest('.live-overlay-btn')) return;
      // Allow drag from header OR from the minimized pill body.
      const fromHeader = e.target.closest('#live-overlay-header');
      if (!fromHeader && !isMinimized) return;
      dragging = true;
      const r = overlay.getBoundingClientRect();
      origLeft = r.left;
      origTop = r.top;
      startX = clientX;
      startY = clientY;
      // switch from right/bottom anchor to left/top so dragging is intuitive
      overlay.style.left = origLeft + 'px';
      overlay.style.top = origTop + 'px';
      overlay.style.right = 'auto';
      overlay.style.bottom = 'auto';
      document.body.style.userSelect = 'none';
    }
    function onMove(clientX, clientY) {
      if (!dragging) return;
      const dx = clientX - startX;
      const dy = clientY - startY;
      const r = overlay.getBoundingClientRect();
      const newLeft = Math.max(0, Math.min(window.innerWidth - r.width, origLeft + dx));
      const newTop = Math.max(0, Math.min(window.innerHeight - r.height, origTop + dy));
      overlay.style.left = newLeft + 'px';
      overlay.style.top = newTop + 'px';
    }
    function onUp() {
      dragging = false;
      document.body.style.userSelect = '';
    }

    overlay.addEventListener('mousedown', e => onDown(e.clientX, e.clientY, e));
    document.addEventListener('mousemove', e => onMove(e.clientX, e.clientY));
    document.addEventListener('mouseup', onUp);

    overlay.addEventListener('touchstart', e => {
      const t = e.touches[0]; if (!t) return;
      onDown(t.clientX, t.clientY, e);
    }, { passive: true });
    document.addEventListener('touchmove', e => {
      const t = e.touches[0]; if (!t || !dragging) return;
      onMove(t.clientX, t.clientY);
      e.preventDefault();
    }, { passive: false });
    document.addEventListener('touchend', onUp);
    document.addEventListener('touchcancel', onUp);
  }
})();
