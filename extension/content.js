// 33rpm content script: reads YouTube Music playback state and relays it to the service worker.
(() => {
  // A re-injected copy (after an extension reload) replaces the old one.
  window.__33rpm?.stop?.();

  const POLL_MS = 1000;
  const HEARTBEAT_PLAYING_MS = 5000;
  const HEARTBEAT_PAUSED_MS = 15000;

  let timer = null;
  let last = null;
  let lastSentAt = 0;
  let lastQueueKey = '';

  const QUEUE_LENGTH = 8;
  const videoIdIn = (url) => /\/vi(?:_webp)?\/([A-Za-z0-9_-]{6,20})\//.exec(url || '')?.[1] || null;

  const $ = (sel) => document.querySelector(sel);
  const text = (el) => (el?.textContent || '').trim();

  function getVideo() {
    return $('video.html5-main-video') || $('video');
  }

  // Ask Google's image CDN for a large square instead of the 60px/120px thumbnail.
  function upscale(url) {
    if (!url) return null;
    if (/googleusercontent\.com|ggpht\.com/.test(url)) {
      if (/=w\d+-h\d+[^/]*$/.test(url)) return url.replace(/=w\d+-h\d+[^/]*$/, '=w1200-h1200-l90-rj');
      if (/=s\d+[^/]*$/.test(url)) return url.replace(/=s\d+[^/]*$/, '=s1200');
      return url + '=w1200-h1200-l90-rj';
    }
    return url;
  }

  function largestArtwork(artwork) {
    if (!artwork?.length) return null;
    const area = (a) => {
      const m = /(\d+)x(\d+)/.exec(a.sizes || '');
      return m ? Number(m[1]) * Number(m[2]) : 0;
    };
    return [...artwork].sort((a, b) => area(b) - area(a))[0].src;
  }

  function snapshot() {
    const md = navigator.mediaSession?.metadata;
    const bar = $('ytmusic-player-bar');

    // Player bar byline looks like "Artist • Album • 2021" (or "Artist • 1.2M views • 3K likes" for videos).
    const byline = text(bar?.querySelector('.byline')).split(' • ').map((s) => s.trim());

    const title = md?.title || text(bar?.querySelector('.title'));
    if (!title) return { track: null, state: 'paused', position: 0, duration: 0 };

    const artist = md?.artist || byline[0] || '';
    const album = md?.album || (byline.length >= 3 && !/views|likes/.test(byline[1]) ? byline[1] : '');

    const rawArt =
      largestArtwork(md?.artwork) ||
      bar?.querySelector('img.image')?.src ||
      $('#song-image img')?.src ||
      null;

    const video = getVideo();
    let position = video ? video.currentTime : 0;
    let duration = video && Number.isFinite(video.duration) ? video.duration : 0;
    if (!duration) {
      const progress = $('#progress-bar');
      duration = Number(progress?.getAttribute('aria-valuemax')) || 0;
      position = Number(progress?.getAttribute('aria-valuenow')) || position;
    }

    let playing;
    if (video) playing = !video.paused && !video.ended;
    else playing = navigator.mediaSession?.playbackState === 'playing';

    // The embedded player's title link always points at the loaded song; the page URL only does on /watch pages
    // (playing from a playlist or album page keeps the URL on that page).
    const idFrom = (href) => {
      try { return href ? new URL(href, location.origin).searchParams.get('v') : null; } catch { return null; }
    };
    const videoId = idFrom($('.ytp-title-link')?.getAttribute('href')) || idFrom(location.href);

    return {
      track: {
        title,
        artist,
        album,
        artwork: upscale(rawArt),
        artworkFallback: rawArt,
        videoId: videoId && /^[A-Za-z0-9_-]{6,20}$/.test(videoId) ? videoId : null,
      },
      state: playing ? 'playing' : 'paused',
      position: Math.max(0, position || 0),
      duration: Math.max(0, duration || 0),
    };
  }

  function sameTrack(a, b) {
    if (!a || !b) return a === b;
    return a.title === b.title && a.artist === b.artist && a.album === b.album && a.artwork === b.artwork &&
      a.videoId === b.videoId;
  }

  function send(msg) {
    if (!chrome.runtime?.id) {
      // Extension was reloaded or removed; this copy is orphaned.
      stop();
      return;
    }
    chrome.runtime.sendMessage(msg).catch(() => {});
  }

  function tick(force = false) {
    const snap = snapshot();
    const now = Date.now();
    let changed = force || !last || !sameTrack(snap.track, last.track) || snap.state !== last.state ||
      Math.abs(snap.duration - last.duration) > 1;

    // Detect seeks: position drifted from where it should be by more than 2s.
    if (!changed && last && snap.track) {
      const expected = last.state === 'playing' ? last.position + (now - last.at) / 1000 : last.position;
      if (Math.abs(snap.position - expected) > 2) changed = true;
    }

    const heartbeat = snap.state === 'playing' ? HEARTBEAT_PLAYING_MS : HEARTBEAT_PAUSED_MS;
    if (changed || now - lastSentAt > heartbeat) {
      send({ type: 'state', ...snap });
      lastSentAt = now;
      last = { ...snap, at: now };
    }
    sendQueueIfChanged();
  }

  // The songs after the current one in YouTube Music's queue ("Up next"). It stays in the DOM on every page.
  function readQueue() {
    const items = [...document.querySelectorAll('ytmusic-player-queue-item')];
    const current = items.findIndex((el) => el.hasAttribute('selected'));
    return items.slice(current + 1, current + 1 + QUEUE_LENGTH).map((el) => {
      const thumb = el.querySelector('img')?.getAttribute('src') || '';
      return {
        title: text(el.querySelector('.song-title')),
        artist: text(el.querySelector('.byline')).split(' • ')[0],
        videoId: videoIdIn(thumb),
        thumb: thumb.startsWith('http') ? thumb : null,
      };
    }).filter((q) => q.title);
  }

  function sendQueueIfChanged(force = false) {
    const queue = readQueue();
    const key = queue.map((q) => q.videoId || q.title).join('|');
    if (force || key !== lastQueueKey) {
      lastQueueKey = key;
      send({ type: 'queue', items: queue });
    }
  }

  function playFromQueue(videoId) {
    const items = [...document.querySelectorAll('ytmusic-player-queue-item')];
    const item = items.find((el) => videoIdIn(el.querySelector('img')?.getAttribute('src')) === videoId);
    if (!item) return false;
    (item.querySelector('ytmusic-play-button-renderer') || item).click();
    return true;
  }

  function click(sel) {
    const el = $(sel);
    if (!el) return false;
    el.click();
    return true;
  }

  function runCommand(action, msg = {}) {
    const video = getVideo();
    switch (action) {
      case 'playQueue':
        playFromQueue(msg.videoId);
        break;
      case 'playPause':
        if (!click('ytmusic-player-bar #play-pause-button') && video) {
          video.paused ? video.play() : video.pause();
        }
        break;
      case 'play':
        if (video?.paused && !click('ytmusic-player-bar #play-pause-button')) video.play();
        break;
      case 'pause':
        if (video && !video.paused && !click('ytmusic-player-bar #play-pause-button')) video.pause();
        break;
      case 'next':
        click('ytmusic-player-bar .next-button');
        break;
      case 'previous':
        click('ytmusic-player-bar .previous-button');
        break;
    }
    setTimeout(() => tick(true), 200);
  }

  function onMessage(msg, _sender, sendResponse) {
    if (msg?.type === 'command') {
      runCommand(msg.action, msg);
      sendResponse({ ok: true });
    } else if (msg?.type === 'resync') {
      tick(true);
      sendQueueIfChanged(true);
      sendResponse({ ok: true });
    }
  }

  // Media events don't bubble, but a capturing listener on document still sees them.
  const mediaEvents = ['play', 'pause', 'ended', 'seeked', 'loadedmetadata', 'emptied'];
  const onMedia = () => tick();
  const onHide = () => send({ type: 'gone' });

  function stop() {
    clearInterval(timer);
    mediaEvents.forEach((e) => document.removeEventListener(e, onMedia, true));
    window.removeEventListener('pagehide', onHide);
    try { chrome.runtime.onMessage.removeListener(onMessage); } catch {}
  }

  mediaEvents.forEach((e) => document.addEventListener(e, onMedia, true));
  window.addEventListener('pagehide', onHide);
  chrome.runtime.onMessage.addListener(onMessage);
  timer = setInterval(tick, POLL_MS);
  tick(true);

  window.__33rpm = { stop };
})();
