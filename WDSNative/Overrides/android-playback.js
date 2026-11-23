/* Android app integration; resources.zip remains unchanged. */
(() => {
  'use strict';
  const frames = new Map();
  let player = null;
  let started = false;
  let stopped = false;
  let appForeground = window.WDSAndroid?.isAppForeground?.() !== false;
  let sound = null;
  let soundHeld = false;
  let soundWasPaused = false;
  const media = new Set();
  const pausedMedia = new Map();
  let owner = window;
  try {
    if (parent !== window && parent.WDSAndroidPlayback) owner = parent;
  } catch (_) {}

  const nativeSync = () => {
    for (const frame of frames.keys()) {
      try {
        if (frame !== window && (!frame.frameElement || !frame.frameElement.isConnected)) frames.delete(frame);
      } catch (_) { frames.delete(frame); }
    }
    const active = isForeground() && [...frames.values()].some(Boolean);
    window.WDSAndroid?.setAutoPlaybackActive(active);
  };
  const report = active => {
    if (owner === window) {
      frames.set(window, active);
      nativeSync();
    } else {
      owner.WDSAndroidPlayback.set(window, active && isForeground());
    }
  };
  const sync = () => {
    report(isForeground() && started && player?._isAuto === true && !player._isAdventureEnded);
  };
  const isForeground = () => appForeground && !stopped && !document.hidden;
  const pauseMedia = element => {
    if (!element.paused && !element.ended) {
      pausedMedia.set(element, element.currentSrc || element.src);
      element.pause();
    }
  };
  const watchMedia = element => {
    if (!element || media.has(element)) return element;
    media.add(element);
    const guard = () => { if (!isForeground()) pauseMedia(element); };
    element.addEventListener('play', guard);
    element.addEventListener('playing', guard);
    guard();
    return element;
  };
  const applyForeground = () => {
    const active = isForeground();
    if (sound) {
      if (!active && !soundHeld) {
        soundWasPaused = !!sound.context.paused;
        soundHeld = true;
        // Pixi Sound pauses its Web Audio context and all sound instances,
        // covering BGM, voices, effects and the HTML Audio fallback.
        sound.pauseAll();
      } else if (active && soundHeld) {
        soundHeld = false;
        if (!soundWasPaused) sound.resumeAll();
      }
    }
    document.querySelectorAll('audio,video').forEach(watchMedia);
    if (!active) {
      for (const element of media) pauseMedia(element);
    } else {
      for (const [element, src] of pausedMedia) {
        pausedMedia.delete(element);
        if (!element.ended && (element.currentSrc || element.src) === src)
          Promise.resolve(element.play()).catch(() => {});
      }
    }
    // The reader preview is a same-origin iframe with its own audio context.
    for (const frame of document.querySelectorAll('iframe')) {
      try { frame.contentWindow?.WDSAndroidPlayback?.setAppForeground(active); } catch (_) {}
    }
    sync();
  };
  const api = {
    start(instance) { player = instance; started = true; sync(); },
    stop(instance) {
      if (instance && player && instance !== player) return;
      started = false;
      sync();
    },
    set(frame, active) { frames.set(frame, !!active); nativeSync(); },
    drop(frame) { frames.delete(frame); nativeSync(); },
    bindSound(instance) { sound = instance; applyForeground(); },
    watchMedia,
    // The Android Activity already pauses audio and JavaScript timers. Preserve
    // the player's Auto choice instead of using its browser hide -> Auto OFF rule.
    onPlayerBlur() { applyForeground(); },
    // The app option is the default for newly opened players. Explicit Auto
    // state passed by an episode continuation still carries forward normally.
    initialAutoMode(inherited) {
      return window.WDSAndroid?.isAutoModeEnabled?.() === true ? 'true' : inherited;
    },
    setAppForeground(active) { appForeground = !!active; applyForeground(); },
  };
  window.WDSAndroidPlayback = api;
  // Auto is a player state, so silent transitions keep the screen awake too.
  const timer = setInterval(sync, 200);
  document.addEventListener('visibilitychange', applyForeground);
  addEventListener('pagehide', () => {
    stopped = true;
    started = false;
    applyForeground();
    clearInterval(timer);
    if (owner === window) {
      frames.clear();
      nativeSync();
    } else {
      try { owner.WDSAndroidPlayback.drop(window); } catch (_) {}
    }
  }, { once: true });
  applyForeground();
})();
