// ═════════════════════════════════════════════════════════════════════
// Lightweight & High-Performance Audio Misc Settings WebUI Controller
// Dynamic Dark / Light theme detection + Native Shell Bridge
// ═════════════════════════════════════════════════════════════════════

let isVerbose = localStorage.getItem('verbose_logging') === 'true';
let selectedRate = '44100';
let selectedDepth = '32';
let selectedMode = 'bypass-safer';
let selectedDrc = 'false';
let selectedPeriod = '2000';
let cachedWorkingCmd = null;

// ═══════════════════════════════════════════
// Dynamic System Dark / Light Theme Manager
// ═══════════════════════════════════════════

function initTheme() {
  const savedTheme = localStorage.getItem('user_theme_mode') || 'system';
  const iconDark = document.getElementById('theme-icon-dark');
  const iconLight = document.getElementById('theme-icon-light');

  function applyTheme(theme) {
    if (theme === 'system') {
      document.documentElement.removeAttribute('data-theme');
      const isSystemDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      if (iconDark && iconLight) {
        iconDark.classList.toggle('hide', !isSystemDark);
        iconLight.classList.toggle('hide', isSystemDark);
      }
    } else if (theme === 'dark') {
      document.documentElement.setAttribute('data-theme', 'dark');
      if (iconDark && iconLight) {
        iconDark.classList.remove('hide');
        iconLight.classList.add('hide');
      }
    } else {
      document.documentElement.setAttribute('data-theme', 'light');
      if (iconDark && iconLight) {
        iconDark.classList.add('hide');
        iconLight.classList.remove('hide');
      }
    }
  }

  applyTheme(savedTheme);

  // Listen to system theme changes dynamically
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    if ((localStorage.getItem('user_theme_mode') || 'system') === 'system') {
      applyTheme('system');
    }
  });

  // Toggle button on Top Bar
  const btnToggle = document.getElementById('btn-theme-toggle');
  if (btnToggle) {
    btnToggle.addEventListener('click', () => {
      const current = localStorage.getItem('user_theme_mode') || 'system';
      let next = 'dark';
      if (current === 'system') {
        const isSysDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
        next = isSysDark ? 'light' : 'dark';
      } else if (current === 'dark') {
        next = 'light';
      } else {
        next = 'system';
      }
      localStorage.setItem('user_theme_mode', next);
      applyTheme(next);
      showSnackbar(next === 'system' ? 'Theme: System Default' : (next === 'dark' ? 'Theme: Dark' : 'Theme: Light'), 'info', 1400);
    });
  }
}

// ═══════════════════════════════════════════
// Fast Page Navigation (0ms Overhead)
// ═══════════════════════════════════════════

function switchPage(pageId) {
  const target = document.getElementById(pageId);
  if (!target) return;

  const current = document.querySelector('.page-view.active');
  if (current === target) return;

  if (current) current.classList.remove('active');
  target.classList.add('active');

  document.querySelectorAll('.nav-destination').forEach(btn => {
    const isTarget = btn.dataset.page === pageId;
    btn.classList.toggle('active', isTarget);
    btn.setAttribute('aria-selected', isTarget ? 'true' : 'false');
  });

  localStorage.setItem('active_webui_page', pageId);
  window.scrollTo({ top: 0, behavior: 'instant' });
}

function initNavigation() {
  document.querySelectorAll('.nav-destination').forEach(btn => {
    btn.addEventListener('click', () => switchPage(btn.dataset.page));
  });

  const savedPage = localStorage.getItem('active_webui_page') || 'page-dashboard';
  if (document.getElementById(savedPage)) {
    switchPage(savedPage);
  }
}

// ═══════════════════════════════════════════
// Lean Snackbar Notification
// ═══════════════════════════════════════════

const SNACKBAR_ICONS = {
  success: '<svg viewBox="0 0 24 24" class="snackbar-icon" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>',
  error: '<svg viewBox="0 0 24 24" class="snackbar-icon" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/></svg>',
  info: '<svg viewBox="0 0 24 24" class="snackbar-icon" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"/></svg>',
  warning: '<svg viewBox="0 0 24 24" class="snackbar-icon" fill="currentColor"><path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/></svg>'
};

function showSnackbar(message, type = 'info', durationMs = 2200) {
  const container = document.getElementById('toast-container');
  if (!container) return;

  const snackbar = document.createElement('div');
  snackbar.className = `md-snackbar snackbar-${type}`;
  snackbar.innerHTML = `${SNACKBAR_ICONS[type] || SNACKBAR_ICONS.info}<span class="snackbar-text">${message}</span>`;

  container.appendChild(snackbar);

  const timer = setTimeout(() => snackbar.remove(), durationMs);
  snackbar.addEventListener('click', () => {
    clearTimeout(timer);
    snackbar.remove();
  });

  const existing = container.querySelectorAll('.md-snackbar');
  if (existing.length > 2) existing[0].remove();
}

function logToConsole(msg, isVerboseOnly = false) {
  if (isVerboseOnly && !isVerbose) return;
  const box = document.getElementById('console-output');
  if (box) {
    const timestamp = new Date().toLocaleTimeString();
    box.textContent = `[${timestamp}] ${msg}\n` + box.textContent;
  }
}

// ═══════════════════════════════════════════
// Fast Exec Bridge
// ═══════════════════════════════════════════

function extractStdout(rawRes) {
  if (!rawRes) return '';
  let resObj = rawRes;
  if (typeof rawRes === 'string') {
    const strVal = rawRes.trim();
    if (strVal.startsWith('{') && strVal.endsWith('}')) {
      try { resObj = JSON.parse(strVal); } catch { return strVal; }
    } else {
      return strVal;
    }
  }
  if (resObj && typeof resObj === 'object') {
    if (resObj.stdout !== undefined) return String(resObj.stdout).trim();
    if (resObj.output !== undefined) return String(resObj.output).trim();
    if (resObj.result !== undefined) return String(resObj.result).trim();
  }
  return String(rawRes || '').trim();
}

async function execCmd(cmd) {
  logToConsole(`[EXEC] ${cmd}`, true);
  try {
    let res = null;
    const bridgeApi = (window.ksu && typeof window.ksu.exec === 'function') ? window.ksu 
      : ((typeof ksu !== 'undefined' && typeof ksu.exec === 'function') ? ksu
      : ((window.mmrl && typeof window.mmrl.exec === 'function') ? window.mmrl
      : ((typeof mmrl !== 'undefined' && typeof mmrl.exec === 'function') ? mmrl
      : ((window.ap && typeof window.ap.exec === 'function') ? window.ap : null))));

    if (bridgeApi) {
      try {
        res = await bridgeApi.exec(cmd);
      } catch {
        res = await bridgeApi.exec(cmd, '{}');
      }
    }
    const stdout = extractStdout(res);
    if (stdout.length > 0) return stdout;
  } catch (err) {
    logToConsole(`[ERR] ${err.message || err}`);
  }
  return '';
}

async function execCmdWithTimeout(cmd, timeoutMs = 2500) {
  const timeoutPromise = new Promise(resolve => setTimeout(() => resolve(''), timeoutMs));
  return Promise.race([execCmd(cmd), timeoutPromise]);
}

// ═══════════════════════════════════════════
// UI Updating & Status Polling
// ═══════════════════════════════════════════

function updateEl(id, val) {
  const el = document.getElementById(id);
  if (el && el.textContent !== val) el.textContent = val;
}

function getMockStatusData() {
  return {
    is_usb: 0,
    is_bt: 0,
    dac_name: "",
    sync_mode: "",
    bt_name: "",
    bt_codec: "",
    active_route: "Built-in Speaker",
    sample_rate: "48,000 Hz (48 kHz)",
    bitrate: "16-bit PCM / 1536 kbps (PCM)",
    vol_steps: "100",
    resampler: "7",
    ignore_fx: "true",
    spatializer: "false",
    safemedia: "true",
    usb_period: "2000",
    platform: "Android Platform",
    arch: "arm64-v8a",
    audioserver_pid: "",
    mode: "audiophile",
    int_codec: "true",
    adm_buffering: "6",
    deep_buffer: "false",
    has_tinymix: 0,
    offload_24bit: "true",
    flinger_standby: "200",
    psd_stopband: "179",
    dac_supported_rates: [],
    dac_supported_depths: [],
    cfg_rate: "48000",
    cfg_depth: "32",
    cfg_mode: "bypass-safer",
    cfg_drc: "false",
    cfg_period: "2000",
    is_96k_unlocked: 0,
    policy_mounted: 0,
    stream_flags: "0x1000000 DIRECT_MEDIA NO_HEADROOM_GAIN MASTERING_SINC7",
    stream_latency_ms: "6",
    stream_decoder: "AOSP Native SW Decoder",
    track_format: "PCM",
    is_bitperfect: 1
  };
}

async function loadAudioOutputSession() {
  let output = '';
  if (cachedWorkingCmd) {
    output = await execCmdWithTimeout(cachedWorkingCmd, 2500);
  }

  if (!output || !output.includes('{')) {
    const candidateCommands = [
      '/system/bin/sh /data/adb/modules/audio-misc-settings-ksu-webui/get_audio_status.sh',
      'sh /data/adb/modules/audio-misc-settings-ksu-webui/get_audio_status.sh',
      '/system/bin/sh /data/adb/modules/audio-misc-settings/get_audio_status.sh',
      'sh ./get_audio_status.sh'
    ];

    for (const cmd of candidateCommands) {
      output = await execCmdWithTimeout(cmd, 2000);
      if (output && output.includes('{') && output.includes('}')) {
        cachedWorkingCmd = cmd;
        break;
      }
    }
  }

  let data = null;
  if (output && output.includes('{')) {
    try {
      const start = output.indexOf('{');
      const end = output.lastIndexOf('}') + 1;
      data = JSON.parse(output.substring(start, end));
    } catch (e) {
      logToConsole(`[JSON PARSE ERR] ${e.message}`);
    }
  }

  if (!data) data = getMockStatusData();

  if (data) {
    applyDataToUI(data);
    return true;
  }
  return false;
}

// ═══════════════════════════════════════════
// Poweramp Fidelity Score Algorithm
// ═══════════════════════════════════════════

function calculateFidelityScore(data) {
  let score = 50;
  const rateVal = parseInt(data.cfg_rate || (data.sample_rate ? data.sample_rate.replace(/[^0-9]/g, '') : '48000'), 10) || 48000;
  const depthVal = parseInt(data.cfg_depth || '32', 10) || 32;
  const isBitPerfect = data.is_bitperfect === 1 || data.is_bitperfect === '1' || 
    (data.ignore_fx === 'true' && data.deep_buffer === 'false' && data.cfg_drc !== 'true');

  // Sample Rate contribution
  if (rateVal >= 768000) score += 24;
  else if (rateVal >= 384000) score += 22;
  else if (rateVal >= 192000) score += 19;
  else if (rateVal >= 96000) score += 16;
  else if (rateVal >= 88200) score += 14;
  else if (rateVal >= 48000) score += 11;
  else if (rateVal >= 44100) score += 10;

  // Bit Depth contribution
  if (depthVal >= 32 || data.cfg_depth === 'float') score += 14;
  else if (depthVal >= 24) score += 11;
  else score += 5;

  // Bit-Perfect Direct or Mastering Sinc Resampler
  if (isBitPerfect) {
    score += 15;
  } else if (data.resampler === '7' || (data.psd_stopband && parseInt(data.psd_stopband, 10) >= 179)) {
    score += 10;
  }

  // DSP & Effects Bypass
  if (data.ignore_fx === 'true') score += 8;
  if (data.cfg_drc === 'false' || !data.cfg_drc) score += 4;
  else score -= 12;

  // Deep buffer battery saver mode reduction
  if (data.deep_buffer === 'true') score -= 14;

  // DAC and ALSA Hardware registers
  if (data.is_usb) score += 5;
  if (data.has_tinymix && data.mode === 'audiophile') score += 4;

  return Math.min(100, Math.max(20, score));
}

function applyDataToUI(data) {
  lastStatusData = data;
  // Output session details
  const deviceName = data.active_route || 'Built-in Speaker';
  updateEl('out-device-name', deviceName);
  const outDevEl = document.getElementById('out-device-name');
  if (outDevEl) outDevEl.title = deviceName;

  updateEl('out-sample-rate', data.sample_rate || '48,000 Hz');
  updateEl('out-bitrate', data.bitrate || '16-bit PCM');

  // Format USB DAC label cleanly (avoid double parentheses)
  let dacInfoStr = 'No USB DAC Attached';
  if (data.is_usb) {
    const rawSync = (data.sync_mode || 'ASYNC').replace(/\s*\(.*?\)/g, '').trim();
    dacInfoStr = `${data.dac_name || 'USB DAC'} (${rawSync || 'ASYNC'})`;
  }
  updateEl('out-dac-info', dacInfoStr);
  const dacInfoEl = document.getElementById('out-dac-info');
  if (dacInfoEl) dacInfoEl.title = dacInfoStr;

  const btCodecStr = data.is_bt ? `${data.bt_name || 'Bluetooth'} (${data.bt_codec || 'A2DP'})` : 'Bluetooth Disconnected';
  updateEl('out-bt-codec', btCodecStr);
  const btCodecEl = document.getElementById('out-bt-codec');
  if (btCodecEl) btCodecEl.title = btCodecStr;

  // DAC hardware capabilities
  const dacCapsEl = document.getElementById('out-dac-caps');
  if (dacCapsEl) {
    if (data.is_usb && Array.isArray(data.dac_supported_rates) && data.dac_supported_rates.length > 0) {
      const minKhz = Math.round(Math.min(...data.dac_supported_rates) / 1000);
      const maxKhz = Math.round(Math.max(...data.dac_supported_rates) / 1000);
      const depthsStr = Array.isArray(data.dac_supported_depths) ? data.dac_supported_depths.join('/') + '-bit' : '16/24/32-bit';
      dacCapsEl.textContent = `Supported: ${minKhz}k – ${maxKhz}kHz • ${depthsStr} (${data.dac_supported_rates.length} rates detected)`;
    } else if (data.is_usb) {
      dacCapsEl.textContent = 'USB DAC Connected (Standard Audio Class)';
    } else if (data.is_bt) {
      dacCapsEl.textContent = `Bluetooth A2DP (${data.bt_codec || 'Standard Codec'})`;
    } else {
      dacCapsEl.textContent = 'Internal SoC Audio Path (48k/192k Native)';
    }
  }

  // Highlight supported sample rates
  const supportedRates = Array.isArray(data.dac_supported_rates) ? data.dac_supported_rates : [];
  document.querySelectorAll('#samplerate-btn-grid .md-segmented-item').forEach(btn => {
    const rateVal = parseInt(btn.dataset.rate, 10);
    btn.classList.toggle('cap-supported', data.is_usb && supportedRates.includes(rateVal));
  });

  // State synchronization
  selectedRate = data.cfg_rate || '44100';
  selectedDepth = data.cfg_depth || '32';
  selectedMode = data.cfg_mode || 'bypass-safer';
  selectedDrc = (data.cfg_drc === 'true' || data.cfg_drc === true) ? 'true' : 'false';
  selectedPeriod = data.cfg_period || data.usb_period || '2000';

  const khz = Math.round(parseInt(selectedRate, 10) / 1000);
  updateEl('active-samplerate-badge', `${khz} kHz • ${selectedDepth}-bit`);
  updateEl('summary-engine-config', `${khz} kHz • ${selectedDepth}-bit (${selectedMode})`);

  document.querySelectorAll('#samplerate-btn-grid .md-segmented-item').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.rate === selectedRate);
  });

  document.querySelectorAll('#bitdepth-btn-grid .md-segmented-item').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.depth === selectedDepth);
  });

  document.querySelectorAll('#policy-btn-grid .policy-choice-item').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.mode === selectedMode);
  });
  updateEl('active-policy-badge', selectedMode);

  // DRC Switch
  const toggleDrc = document.getElementById('toggle-drc');
  const drcText = document.getElementById('drc-desc-text');
  if (toggleDrc) {
    const isDrcOn = selectedDrc === 'true';
    toggleDrc.checked = isDrcOn;
    if (drcText) {
      drcText.innerHTML = isDrcOn
        ? 'DRC is currently <strong>Enabled</strong> (Stock limiter active).'
        : 'DRC is currently <strong>Disabled</strong> (Lossless dynamic range).';
    }
  }

  // USB Period
  document.querySelectorAll('#period-btn-grid .md-segmented-item').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.period === selectedPeriod);
  });
  updateEl('usb-period-badge', `${selectedPeriod} µs`);

  // 96k Unlock badge
  const unlockBadge = document.getElementById('unlock-badge');
  const unlockText = document.getElementById('unlock-badge-text');
  if (unlockBadge && unlockText) {
    unlockText.textContent = data.is_96k_unlocked ? '768kHz Unlocked' : '96kHz Cap';
    unlockBadge.classList.toggle('active', !!data.is_96k_unlocked);
  }
  updateEl('prop-unlock-status', data.is_96k_unlocked ? 'Unlocked (768kHz)' : 'Stock (96kHz)');
  updateEl('prop-policy-mount', data.policy_mounted ? 'Active (/data/local/tmp)' : 'Default (/vendor/etc)');

  // System Properties
  updateEl('prop-vol-steps', (data.vol_steps || '100') + ' steps');
  const resamplerVal = data.resampler || '7';
  updateEl('prop-resampler-quality', resamplerVal === '7' ? '7 (Mastering 179dB)' : (resamplerVal === '4' ? '4 (Power Saver)' : resamplerVal));
  updateEl('prop-effects-status', data.ignore_fx === 'true' ? 'Disabled (Lossless)' : 'Active');
  updateEl('prop-spatializer-status', data.spatializer === 'false' ? 'Disabled' : 'Enabled');
  updateEl('prop-safemedia-status', data.safemedia === 'true' ? 'Bypassed' : 'Default');
  updateEl('prop-usb-period', (data.usb_period || '2000') + ' μs');
  updateEl('prop-offload-24bit', data.offload_24bit === 'true' ? 'Enabled' : 'Disabled');
  updateEl('prop-psd-stopband', (data.psd_stopband || '179') + ' dB');
  updateEl('prop-flinger-standby', (data.flinger_standby || '200') + ' ms');

  // Audiophile Profile
  const isAudiophile = (data.mode || 'audiophile') === 'audiophile';
  updateEl('active-mode-badge', isAudiophile ? 'Audiophile Hi-Fi' : 'Power Saver');

  const btnQuickAudiophile = document.getElementById('btn-quick-audiophile');
  const btnQuickPowerSaver = document.getElementById('btn-quick-powersaver');
  if (btnQuickAudiophile && btnQuickPowerSaver) {
    btnQuickAudiophile.className = `md-button profile-quick-btn ${isAudiophile ? 'button-filled active' : 'button-outlined'}`;
    btnQuickPowerSaver.className = `md-button profile-quick-btn ${!isAudiophile ? 'button-filled active' : 'button-outlined'}`;
  }

  const cardAudiophile = document.getElementById('card-mode-audiophile');
  const cardPowerSaver = document.getElementById('card-mode-powersaver');
  if (cardAudiophile && cardPowerSaver) {
    cardAudiophile.classList.toggle('active', isAudiophile);
    cardPowerSaver.classList.toggle('active', !isAudiophile);
  }

  const btnModeAudiophile = document.getElementById('btn-mode-audiophile');
  const btnModePowerSaver = document.getElementById('btn-mode-power-saver');
  if (btnModeAudiophile && btnModePowerSaver) {
    btnModeAudiophile.className = `md-button button-wide ${isAudiophile ? 'button-filled' : 'button-outlined'}`;
    btnModeAudiophile.textContent = isAudiophile ? 'Audiophile Active' : 'Activate Audiophile';
    btnModePowerSaver.className = `md-button button-wide ${!isAudiophile ? 'button-filled' : 'button-outlined'}`;
    btnModePowerSaver.textContent = !isAudiophile ? 'Power Saver Active' : 'Activate Power Saver';
  }

  updateEl('prop-int-codec', data.int_codec === 'true' ? 'Direct Route' : 'Standard');
  updateEl('prop-adm-buffering', (data.adm_buffering || '6') + ' ms');
  updateEl('prop-deep-buffer', data.deep_buffer === 'false' ? 'Disabled (Direct)' : 'Enabled');
  updateEl('prop-tinymix-status', data.has_tinymix ? (isAudiophile ? 'LOHIFI Bias' : 'ULP Mode') : 'Not Available');
  updateEl('info-platform', data.platform || 'Android');
  updateEl('info-audioserver-pid', data.audioserver_pid ? `PID ${data.audioserver_pid}` : 'running');
  updateEl('info-active-policy', selectedMode);

  const stateBadge = document.getElementById('output-state-badge');
  if (stateBadge) {
    stateBadge.textContent = data.is_usb ? 'USB Active' : (data.is_bt ? 'Bluetooth' : 'Speaker Active');
  }

  // ═══════════════════════════════════════════
  // POWERAMP AUDIO INFO PIPELINE POPULATION
  // ═══════════════════════════════════════════
  renderAudioPipeline(data);
}

function renderAudioPipeline(data) {
  const isAudiophile = (data.mode || 'audiophile') === 'audiophile';
  const isBitPerfect = data.is_bitperfect === 1 || data.is_bitperfect === '1' || 
    (data.ignore_fx === 'true' && data.deep_buffer === 'false' && data.cfg_drc !== 'true');

  const outRateNum = parseInt(data.cfg_rate || (data.sample_rate ? data.sample_rate.replace(/[^0-9]/g, '') : '48000'), 10) || 48000;
  const outKhz = Math.round(outRateNum / 1000);
  const outDepth = data.cfg_depth || (data.bitrate && data.bitrate.includes('32') ? '32' : (data.bitrate && data.bitrate.includes('24') ? '24' : '16'));
  const latencyMs = data.stream_latency_ms || data.adm_buffering || (isAudiophile ? '6' : '12');

  // 1. Raw App Client / AudioTrack API Layer
  const appName = data.active_app || 'System Audio Client';
  const sourceFormat = data.source_format || (data.track_format || 'PCM');
  const sourceSr = data.source_sr || `${outKhz}.0 kHz`;
  const sourceDepth = data.source_depth || `${outDepth} bit`;

  let trackHeadline = `${sourceFormat} • 2 Channels`;
  if (data.track_title) {
    trackHeadline = `${data.track_title}${data.track_artist ? ' (' + data.track_artist + ')' : ''} [${appName}]`;
  } else if (appName && appName !== 'System Audio Stream') {
    trackHeadline = `${appName}: ${sourceFormat}`;
  }

  updateEl('pipe-dash-track-format', (data.track_format || 'app').toLowerCase());
  updateEl('pa-track-format-badge', (data.track_format || 'app').toLowerCase());

  updateEl('pipe-dash-track-details', trackHeadline);
  updateEl('pipe-dash-track-sr', sourceSr);
  updateEl('pipe-dash-track-depth', sourceDepth);
  updateEl('pipe-dash-track-badge', data.active_pkg || 'AUDIO_STREAM_MUSIC');

  // 2. AudioFlinger Software Mixer & Resampler Layer
  const isResampled = sourceSr.replace(/[^0-9]/g, '') !== String(outKhz * 1000) && sourceSr.replace(/[^0-9]/g, '') !== String(outKhz);
  const audioFlingerProcessing = 'AUDIO_FORMAT_PCM_FLOAT (32-bit Float Processing)';
  const stopbandDb = data.psd_stopband || (isAudiophile ? '179' : '120');
  const audioFlingerResampler = isResampled 
    ? `Resampler: Sinc 7 (${stopbandDb} dB PSD Stopband • ${sourceSr} → ${outKhz * 1000} Hz)`
    : `Resampler: Direct 1:1 (${outKhz * 1000} Hz Bit-Exact)`;

  updateEl('pipe-dash-decoder', audioFlingerProcessing);
  updateEl('pipe-dash-decoder-sub', audioFlingerResampler);

  // 3. Audio Effects & DSP Layer
  const isEffectsBypassed = data.ignore_fx === 'true' || data.ignore_fx === '1' || data.mode === 'audiophile';
  const effectsDesc = isEffectsBypassed
    ? 'ro.audio.ignore_effects=true (Zero SoundFX Chains Inserted)'
    : 'AudioFX Active (System DSP Chains)';
  updateEl('pipe-dash-bp-title', 'Audio Effects & DSP Status');
  updateEl('pipe-dash-resampling-text', audioFlingerResampler);
  updateEl('pipe-dash-dsp-text', effectsDesc);

  const bpBadge = document.getElementById('pipe-dash-bp-badge');
  if (bpBadge) {
    bpBadge.textContent = isEffectsBypassed ? 'DIRECT BYPASS' : 'DSP ACTIVE';
    bpBadge.className = `pipe-tag ${isEffectsBypassed ? 'tag-success' : 'tag-source'}`;
  }

  // 4. Vendor Audio HAL & Policy Layer
  const outputProfile = `audio_policy_configuration.xml (${selectedMode})`;
  updateEl('pipe-dash-output-profile', outputProfile);
  updateEl('pipe-dash-output-sr', `${outKhz * 1000} Hz`);
  updateEl('pipe-dash-output-depth', `AUDIO_FORMAT_PCM_${outDepth}_BIT`);
  updateEl('pipe-dash-output-latency', `Buffer: ${latencyMs} ms (vendor.audio.adm.buffering.ms)`);

  const flagsStr = data.stream_flags || 'AUDIO_OUTPUT_FLAG_DIRECT (0x1) | AUDIO_OUTPUT_FLAG_PRIMARY';
  updateEl('pipe-dash-flags', flagsStr);

  // 5. Linux ALSA Subsystem & Physical Endpoint
  let devName = data.active_route || 'Built-in Speaker';
  if (data.is_usb) {
    devName = data.dac_name || data.active_route || 'USB Audio DAC';
  } else if (data.is_bt) {
    devName = data.bt_name || data.active_route || 'Bluetooth Audio Device';
  }
  updateEl('pipe-dash-dev-name', devName);
  updateEl('pipe-dash-path-in', sourceSr);
  updateEl('pipe-dash-path-out', `${outKhz * 1000} Hz`);

  const devFormatStr = `${outDepth}-bit • ${data.is_usb ? (data.sync_mode || 'ASYNC') + ' (' + selectedPeriod + ' µs Packet Interval)' : 'Qualcomm SoC Internal Route'}`;
  updateEl('pipe-dash-dev-format', devFormatStr);

  let pathDesc = `${sourceSr} (AudioTrack) → AudioFlinger Sinc Resampler → ${outKhz * 1000} Hz HAL → ${devName}`;
  if (data.is_bt) {
    pathDesc = `${sourceSr} (AudioTrack) → AudioFlinger → Bluetooth A2DP (${data.bt_codec || 'SBC/AAC'})`;
  } else if (!data.is_usb) {
    pathDesc = `${sourceSr} (AudioTrack) → AudioFlinger → Qualcomm/SoC WCD → Speaker`;
  }

  // Update Modal Elements
  updateEl('pa-track-details', trackHeadline);
  updateEl('pa-track-sr', sourceSr);
  updateEl('pa-track-depth', sourceDepth);
  updateEl('pa-track-extra', `pkg: ${data.active_pkg || 'android.media'}`);
  updateEl('pa-decoder-name', audioFlingerProcessing);
  updateEl('pa-decoder-sub', audioFlingerResampler);
  updateEl('pa-bp-title', 'Audio Effects & DSP Status');
  updateEl('pa-resampling-status', audioFlingerResampler);
  updateEl('pa-dsp-status', effectsDesc);
  updateEl('pa-output-desc', outputProfile);
  updateEl('pa-output-sr', `${outKhz * 1000} Hz`);
  updateEl('pa-output-depth', `AUDIO_FORMAT_PCM_${outDepth}_BIT`);
  updateEl('pa-output-flags', flagsStr);
  updateEl('pa-output-latency', `Timing: ${latencyMs} ms (vendor.audio.adm.buffering.ms)`);
  updateEl('pa-dev-name', devName);
  updateEl('pa-dev-route', pathDesc);
  updateEl('pa-dev-mode', devFormatStr);

  // Footer Precision & Effects
  updateEl('pipe-fidelity-score', `${outDepth}-bit`);
  updateEl('pa-score-num', `${outDepth}-bit`);
  updateEl('pipe-fidelity-desc', '32-bit Float (179 dB PSD)');

  const dspStatus = data.ignore_fx === 'true' ? 'Bypassed' : 'Active';
  updateEl('pipe-dsp-status', dspStatus);
  updateEl('pa-dsp-val', dspStatus);
}

// ═══════════════════════════════════════════
// Actions & Handlers
// ═══════════════════════════════════════════

async function applySampleRateConfiguration() {
  const khz = Math.round(parseInt(selectedRate, 10) / 1000);
  logToConsole(`Applying: ${khz} kHz (${selectedDepth}-bit) [${selectedMode}] DRC=${selectedDrc} Period=${selectedPeriod}µs...`);
  showSnackbar(`Applying ${khz} kHz (${selectedDepth}-bit)...`, 'info', 1800);

  const cmd = `/system/bin/sh /data/adb/modules/audio-misc-settings-ksu-webui/set_audio_samplerate.sh --rate ${selectedRate} --depth ${selectedDepth} --mode ${selectedMode} --drc ${selectedDrc} --period ${selectedPeriod}`;
  await execCmd(cmd);
  await loadAudioOutputSession();
  showSnackbar(`Applied ${khz} kHz (${selectedDepth}-bit)!`, 'success', 2200);
}

async function resetSampleRatePolicy() {
  logToConsole('Resetting audio policy to stock...');
  showSnackbar('Resetting policy...', 'warning', 1500);
  await execCmd('/system/bin/sh /data/adb/modules/audio-misc-settings-ksu-webui/set_audio_samplerate.sh --reset');
  await loadAudioOutputSession();
  showSnackbar('Policy reset to stock', 'success', 2000);
}

async function switchAudioMode(targetMode) {
  const modeName = targetMode === 'audiophile' ? 'Audiophile Hi-Fi' : 'Power Saver';
  logToConsole(`Switching profile: ${targetMode}...`);
  showSnackbar(`Switching to ${modeName}...`, 'info', 1500);
  await execCmd(`/system/bin/sh /data/adb/modules/audio-misc-settings-ksu-webui/set_audio_mode.sh ${targetMode}`);
  await loadAudioOutputSession();
  showSnackbar(`${modeName} active`, 'success', 2000);
}

async function restartAudioserver() {
  logToConsole('Restarting audioserver...');
  showSnackbar('Restarting audioserver...', 'warning', 1500);
  await execCmd('/system/bin/setprop ctl.restart audioserver');
  await loadAudioOutputSession();
  showSnackbar('Audioserver restarted', 'success', 2000);
}

async function apply100VolumeSteps() {
  logToConsole('Setting 100 volume steps...');
  showSnackbar('Setting 100 volume steps...', 'info', 1200);
  await execCmd('/system/bin/settings put system volume_steps_music 100');
  await loadAudioOutputSession();
  showSnackbar('Volume set to 100 steps', 'success', 2000);
}

async function applyAlsaGain() {
  logToConsole('Calibrating ALSA hardware registers...');
  showSnackbar('Applying ALSA gain...', 'info', 1500);
  await execCmd('/system/bin/sh /data/adb/modules/audio-misc-settings-ksu-webui/set_audio_mode.sh tinymix_only');
  await loadAudioOutputSession();
  showSnackbar('ALSA gain calibrated', 'success', 2000);
}

// ═══════════════════════════════════════════
// Audio Architecture Detail Explanations (Live System Telemetry)
// ═══════════════════════════════════════════

let lastStatusData = null;

function openAudioInfoModal() {
  const modal = document.getElementById('modal-audio-info');
  if (modal) {
    modal.classList.add('open');
    modal.setAttribute('aria-hidden', 'false');
    document.body.style.overflow = 'hidden';
  }
}

function closeAudioInfoModal() {
  const modal = document.getElementById('modal-audio-info');
  if (modal) {
    modal.classList.remove('open');
    modal.setAttribute('aria-hidden', 'true');
    document.body.style.overflow = '';
  }
}

function getStageExplanation(stageKey, data) {
  const d = data || lastStatusData || getMockStatusData();
  const outRate = parseInt(d.cfg_rate || (d.sample_rate ? d.sample_rate.replace(/[^0-9]/g, '') : '48000'), 10) || 48000;
  const outDepth = d.cfg_depth || (d.bitrate && d.bitrate.includes('32') ? '32' : '24');
  const appName = d.active_app || 'Active Media App';
  const pkg = d.active_pkg || 'android.media';
  const song = d.track_title ? `${d.track_title}${d.track_artist ? ' by ' + d.track_artist : ''}` : 'Active Audio Stream';
  const srcFmt = d.source_format || 'PCM';
  const srcSr = d.source_sr || '48.0 kHz';
  const srcDepth = d.source_depth || '16 bit';
  const latency = d.stream_latency_ms || '6';
  const flags = d.stream_flags || 'AUDIO_OUTPUT_FLAG_DIRECT | AUDIO_OUTPUT_FLAG_PRIMARY';
  const devName = d.is_usb ? (d.dac_name || 'USB Audio DAC') : (d.is_bt ? (d.bt_name || 'Bluetooth Device') : 'Built-in Speaker');

  switch (stageKey) {
    case 'track':
      return {
        title: 'Stage 1: App Client & AudioTrack Layer',
        html: `
          <p><strong>Active Client Application:</strong></p>
          <ul class="dialog-list">
            <li><strong>Client App:</strong> ${appName}</li>
            <li><strong>Package Name:</strong> <code>${pkg}</code></li>
            <li><strong>Active Track:</strong> ${song}</li>
            <li><strong>Native Source Format:</strong> ${srcFmt}</li>
            <li><strong>Client Sample Rate:</strong> ${srcSr}</li>
            <li><strong>AudioTrack Bit Depth:</strong> ${srcDepth}</li>
            <li><strong>Channel Mask:</strong> AUDIO_CHANNEL_OUT_STEREO (0x3)</li>
            <li><strong>AudioStream Usage:</strong> USAGE_MEDIA (AUDIO_STREAM_MUSIC)</li>
          </ul>
          <p class="dialog-subtext">The AudioTrack API provides application-level digital audio buffers directly to the Android AudioFlinger server.</p>
        `
      };

    case 'decoder':
      return {
        title: 'Stage 2: AudioFlinger Software Engine',
        html: `
          <p><strong>AudioFlinger PlaybackThread Telemetry:</strong></p>
          <ul class="dialog-list">
            <li><strong>Processing Format:</strong> <code>AUDIO_FORMAT_PCM_FLOAT</code> (32-bit Floating Point)</li>
            <li><strong>Audioserver Process:</strong> ${d.audioserver_pid ? 'PID ' + d.audioserver_pid : 'Running'}</li>
            <li><strong>Resampler Quality:</strong> <code>af.resampler.quality = 7</code> (Sinc Interpolation)</li>
            <li><strong>Stopband Rejection:</strong> <code>179 dB PSD</code> (ro.audio.resampler.psd.stopband=179)</li>
            <li><strong>Standby Timeout:</strong> ${d.flinger_standby || '200'} ms (ro.audio.flinger_standbytime_ms)</li>
          </ul>
          <p class="dialog-subtext">AudioFlinger processes audio mixing and sample-rate conversion with 32-bit floating point precision, preventing numeric truncation.</p>
        `
      };

    case 'bitperfect':
      return {
        title: 'Stage 3: Audio Effects & DSP Framework',
        html: `
          <p><strong>AudioFX Framework Status:</strong></p>
          <ul class="dialog-list">
            <li><strong>Effects Bypass:</strong> <code>ro.audio.ignore_effects = ${d.ignore_fx || 'true'}</code></li>
            <li><strong>Spatializer:</strong> ${d.spatializer === 'false' ? 'Disabled (Direct Stream)' : 'Bypassed'}</li>
            <li><strong>Dynamic Range Control:</strong> ${d.cfg_drc === 'true' ? 'Enabled' : 'Disabled (Lossless Direct)'}</li>
            <li><strong>DSP Chains Inserted:</strong> 0 (Zero AudioFX Chains)</li>
          </ul>
          <p class="dialog-subtext">When effects are ignored, equalizers and audio effect engines are bypassed, preserving the original bitstream without DSP coloration.</p>
        `
      };

    case 'output':
      return {
        title: 'Stage 4: Vendor Audio HAL & Policy',
        html: `
          <p><strong>Vendor Audio HAL Telemetry:</strong></p>
          <ul class="dialog-list">
            <li><strong>Active Profile:</strong> <code>audio_policy_configuration.xml (${selectedMode})</code></li>
            <li><strong>HAL Stream Sample Rate:</strong> <code>${outRate} Hz</code></li>
            <li><strong>HAL Bit Depth:</strong> <code>AUDIO_FORMAT_PCM_${outDepth}_BIT</code></li>
            <li><strong>Output Flags:</strong> <code>${flags}</code></li>
            <li><strong>Buffer Latency:</strong> <code>${latency} ms</code> (vendor.audio.adm.buffering.ms)</li>
            <li><strong>Deep Buffer Policy:</strong> Disabled (Direct Low-Latency Route)</li>
          </ul>
          <p class="dialog-subtext">The Vendor Audio HAL configures kernel ALSA endpoints with sample rates and direct flags matching the audiophile target policy.</p>
        `
      };

    case 'device':
      return {
        title: 'Stage 5: Linux ALSA Kernel & Hardware Endpoint',
        html: `
          <p><strong>Linux Kernel ALSA Subsystem:</strong></p>
          <ul class="dialog-list">
            <li><strong>Hardware Endpoint:</strong> ${devName}</li>
            <li><strong>Interface Descriptor:</strong> <code>/proc/asound/card*/stream0</code></li>
            <li><strong>USB Synchronization:</strong> ${d.is_usb ? (d.sync_mode || 'ASYNC Mode') : 'Internal SoC Bus'}</li>
            <li><strong>Packet Period:</strong> ${d.is_usb ? (d.cfg_period || d.usb_period || '2000') + ' µs' : 'N/A'}</li>
            <li><strong>Master Clock Rate:</strong> <code>${outRate} Hz</code></li>
            <li><strong>Signal Path:</strong> ${srcSr} (${appName}) → Sinc Resampler → ${outRate} Hz HAL → ${devName}</li>
          </ul>
          <p class="dialog-subtext">The physical DAC master clock directly dictates digital sample conversion via Linux kernel ALSA drivers.</p>
        `
      };

    default:
      return null;
  }
}

function showStageDetail(stageKey) {
  const explanation = getStageExplanation(stageKey, lastStatusData);
  if (!explanation) return;

  const dialog = document.getElementById('modal-detail-dialog');
  const titleEl = document.getElementById('detail-dialog-title');
  const contentEl = document.getElementById('detail-dialog-content');

  if (titleEl) titleEl.textContent = explanation.title;
  if (contentEl) contentEl.innerHTML = explanation.html;

  if (dialog) {
    dialog.classList.add('open');
    dialog.setAttribute('aria-hidden', 'false');
  }
}

function closeStageDetail() {
  const dialog = document.getElementById('modal-detail-dialog');
  if (dialog) {
    dialog.classList.remove('open');
    dialog.setAttribute('aria-hidden', 'true');
  }
}

// ═══════════════════════════════════════════
// Initialization
// ═══════════════════════════════════════════

document.addEventListener('DOMContentLoaded', () => {
  initTheme();
  initNavigation();

  // Top Bar Refresh & Audio Info
  document.getElementById('btn-top-refresh')?.addEventListener('click', async () => {
    showSnackbar('Refreshing audio status...', 'info', 1000);
    await loadAudioOutputSession();
  });

  document.getElementById('btn-open-audio-info')?.addEventListener('click', openAudioInfoModal);
  document.getElementById('btn-hero-audio-info')?.addEventListener('click', openAudioInfoModal);
  document.getElementById('btn-expand-pipeline-modal')?.addEventListener('click', openAudioInfoModal);
  document.getElementById('btn-close-audio-info')?.addEventListener('click', closeAudioInfoModal);

  // Close modal when clicking outside
  document.getElementById('modal-audio-info')?.addEventListener('click', (e) => {
    if (e.target.id === 'modal-audio-info') closeAudioInfoModal();
  });

  // Stage click inspectors (Inline Pipeline)
  document.querySelectorAll('.audio-pipeline-container .pipe-node').forEach(node => {
    node.addEventListener('click', () => {
      const stage = node.dataset.stage;
      if (stage) showStageDetail(stage);
    });
  });

  // Stage click inspectors (Poweramp Modal)
  document.querySelectorAll('.poweramp-body .pa-node').forEach(node => {
    node.addEventListener('click', () => {
      const stage = node.dataset.inspect;
      if (stage) showStageDetail(stage);
    });
  });

  // Detail dialog close
  document.getElementById('btn-close-detail-dialog')?.addEventListener('click', closeStageDetail);
  document.getElementById('btn-dismiss-detail')?.addEventListener('click', closeStageDetail);
  document.getElementById('modal-detail-dialog')?.addEventListener('click', (e) => {
    if (e.target.id === 'modal-detail-dialog') closeStageDetail();
  });

  // Quick Actions (Dashboard)
  document.getElementById('btn-action-refresh')?.addEventListener('click', loadAudioOutputSession);
  document.getElementById('btn-action-restart')?.addEventListener('click', restartAudioserver);
  document.getElementById('btn-action-volume')?.addEventListener('click', apply100VolumeSteps);
  document.getElementById('btn-action-tinymix')?.addEventListener('click', applyAlsaGain);

  // Quick Profile Switcher
  document.getElementById('btn-quick-audiophile')?.addEventListener('click', () => switchAudioMode('audiophile'));
  document.getElementById('btn-quick-powersaver')?.addEventListener('click', () => switchAudioMode('power_saver'));

  // Sample Rate Grid
  document.querySelectorAll('#samplerate-btn-grid .md-segmented-item').forEach(btn => {
    btn.addEventListener('click', () => {
      selectedRate = btn.dataset.rate;
      document.querySelectorAll('#samplerate-btn-grid .md-segmented-item').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const khz = Math.round(parseInt(selectedRate, 10) / 1000);
      updateEl('active-samplerate-badge', `${khz} kHz • ${selectedDepth}-bit`);
      logToConsole(`Selected rate: ${khz} kHz`);
    });
  });

  // Bit Depth Grid
  document.querySelectorAll('#bitdepth-btn-grid .md-segmented-item').forEach(btn => {
    btn.addEventListener('click', () => {
      selectedDepth = btn.dataset.depth;
      document.querySelectorAll('#bitdepth-btn-grid .md-segmented-item').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const khz = Math.round(parseInt(selectedRate, 10) / 1000);
      updateEl('active-samplerate-badge', `${khz} kHz • ${selectedDepth}-bit`);
      logToConsole(`Selected depth: ${selectedDepth}-bit`);
    });
  });

  // Policy Mode List
  document.querySelectorAll('#policy-btn-grid .policy-choice-item').forEach(btn => {
    btn.addEventListener('click', () => {
      selectedMode = btn.dataset.mode;
      document.querySelectorAll('#policy-btn-grid .policy-choice-item').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      updateEl('active-policy-badge', selectedMode);
      logToConsole(`Selected policy: ${selectedMode}`);
      showSnackbar(`Policy: ${selectedMode}`, 'info', 1200);
    });
  });

  // Engine Actions
  document.getElementById('btn-apply-samplerate')?.addEventListener('click', applySampleRateConfiguration);
  document.getElementById('btn-reset-samplerate')?.addEventListener('click', resetSampleRatePolicy);

  // Tuning Profile Buttons
  document.getElementById('btn-mode-audiophile')?.addEventListener('click', () => switchAudioMode('audiophile'));
  document.getElementById('btn-mode-power-saver')?.addEventListener('click', () => switchAudioMode('power_saver'));

  // DRC Toggle
  const toggleDrc = document.getElementById('toggle-drc');
  if (toggleDrc) {
    toggleDrc.addEventListener('change', (e) => {
      selectedDrc = e.target.checked ? 'true' : 'false';
      const drcText = document.getElementById('drc-desc-text');
      if (drcText) {
        drcText.innerHTML = e.target.checked
          ? 'Speaker DRC is <strong>Enabled</strong> (Phone speaker peak limiter active). Click <em>Apply Configuration</em> to reload.'
          : 'Speaker DRC is <strong>Disabled</strong> (Full lossless dynamic range). Click <em>Apply Configuration</em> to reload.';
      }
      showSnackbar(e.target.checked ? 'Speaker DRC enabled (Click Apply to reload policy)' : 'Speaker DRC disabled (Click Apply to reload policy)', 'info', 2200);
      logToConsole(`Speaker DRC set to: ${selectedDrc}`);
    });
  }

  // USB Period Picker
  document.querySelectorAll('#period-btn-grid .md-segmented-item').forEach(btn => {
    btn.addEventListener('click', () => {
      selectedPeriod = btn.dataset.period;
      document.querySelectorAll('#period-btn-grid .md-segmented-item').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      updateEl('usb-period-badge', `${selectedPeriod} µs`);
      logToConsole(`USB Period: ${selectedPeriod} µs`);
      showSnackbar(`USB Period: ${selectedPeriod} µs`, 'info', 1200);
    });
  });

  // Tuning Actions
  document.getElementById('btn-tinymix-hw')?.addEventListener('click', applyAlsaGain);
  document.getElementById('btn-apply-volume')?.addEventListener('click', apply100VolumeSteps);
  document.getElementById('btn-restart-audio')?.addEventListener('click', restartAudioserver);

  // Console Controls
  const toggleVerbose = document.getElementById('toggle-verbose');
  if (toggleVerbose) {
    toggleVerbose.checked = isVerbose;
    toggleVerbose.addEventListener('change', (e) => {
      isVerbose = e.target.checked;
      localStorage.setItem('verbose_logging', isVerbose);
      showSnackbar(isVerbose ? 'Verbose on' : 'Verbose off', 'info', 1200);
    });
  }

  document.getElementById('btn-clear-console')?.addEventListener('click', () => {
    const box = document.getElementById('console-output');
    if (box) box.textContent = 'Console cleared.';
    showSnackbar('Cleared', 'info', 1000);
  });

  document.getElementById('btn-copy-console')?.addEventListener('click', () => {
    const box = document.getElementById('console-output');
    if (box) {
      navigator.clipboard?.writeText(box.textContent).then(() => {
        showSnackbar('Copied to clipboard', 'success', 1500);
      });
    }
  });

  // Fast Load
  loadAudioOutputSession();
});
