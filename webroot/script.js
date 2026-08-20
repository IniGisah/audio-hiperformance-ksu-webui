// KernelSU WebUI JS Bridge & Audio Output Session Controller (Verbose Diagnostics)

let isVerbose = localStorage.getItem('verbose_logging') === 'true';

function logToConsole(msg, isVerboseOnly = false) {
  if (isVerboseOnly && !isVerbose) return;
  const box = document.getElementById('console-output');
  if (box) {
    const timestamp = new Date().toLocaleTimeString();
    box.textContent = `[${timestamp}] ${msg}\n` + box.textContent;
  }
}

// ═══════════════════════════════════════════
// Toast Notification System
// ═══════════════════════════════════════════

const TOAST_ICONS = {
  success: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>',
  error: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>',
  info: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>',
  warning: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>'
};

function showToast(message, type = 'info', durationMs = 3000) {
  const container = document.getElementById('toast-container');
  if (!container) return;

  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.style.setProperty('--toast-duration', `${durationMs}ms`);
  toast.innerHTML = `
    <span class="toast-icon">${TOAST_ICONS[type] || TOAST_ICONS.info}</span>
    <span class="toast-message">${message}</span>
    <div class="toast-progress"></div>
  `;

  container.appendChild(toast);

  // Auto-remove after duration
  const timer = setTimeout(() => {
    toast.classList.add('toast-exit');
    toast.addEventListener('animationend', () => toast.remove(), { once: true });
  }, durationMs);

  // Click to dismiss early
  toast.addEventListener('click', () => {
    clearTimeout(timer);
    toast.classList.add('toast-exit');
    toast.addEventListener('animationend', () => toast.remove(), { once: true });
  });

  // Limit to 4 visible toasts
  const toasts = container.querySelectorAll('.toast:not(.toast-exit)');
  if (toasts.length > 4) {
    toasts[0].classList.add('toast-exit');
    toasts[0].addEventListener('animationend', () => toasts[0].remove(), { once: true });
  }
}

// ═══════════════════════════════════════════
// Skeleton Loading System
// ═══════════════════════════════════════════

function setSkeletonLoading(isLoading) {
  const selectors = [
    '.prop-val', '.info-value', '.output-badge',
    '#active-mode-badge'
  ];

  selectors.forEach(sel => {
    document.querySelectorAll(sel).forEach(el => {
      if (isLoading && el.textContent.includes('Loading') || isLoading && el.textContent.includes('Detecting') || isLoading && el.textContent.includes('Checking') || isLoading && el.textContent.includes('Scanning')) {
        el.classList.add('skeleton-text');
      } else {
        el.classList.remove('skeleton-text');
      }
    });
  });
}

// ═══════════════════════════════════════════
// Value Change Flash Animation
// ═══════════════════════════════════════════

const previousValues = {};

function updateElementWithFlash(id, newValue) {
  const el = document.getElementById(id);
  if (!el) return;

  el.classList.remove('skeleton-text');
  const oldValue = previousValues[id];
  el.textContent = newValue;

  if (oldValue !== undefined && oldValue !== newValue) {
    el.classList.remove('value-updated');
    // Force reflow to restart animation
    void el.offsetWidth;
    el.classList.add('value-updated');
  }

  previousValues[id] = newValue;
}

// ═══════════════════════════════════════════
// KSU Exec Bridge
// ═══════════════════════════════════════════

function extractStdout(rawRes) {
  logToConsole(`[RAW TYPE] ${typeof rawRes}`, true);
  if (rawRes === null || rawRes === undefined) return '';

  let resObj = rawRes;
  let strVal = '';

  if (typeof rawRes === 'string') {
    strVal = rawRes.trim();
    logToConsole(`[RAW STR len=${rawRes.length}] ${JSON.stringify(rawRes).substring(0, 150)}`, true);
    if (strVal.startsWith('{') && strVal.endsWith('}')) {
      try {
        resObj = JSON.parse(strVal);
        logToConsole(`[PARSED KSU OBJ] keys=${Object.keys(resObj).join(',')}`, true);
      } catch (e) {
        return strVal;
      }
    } else {
      return strVal;
    }
  }

  if (resObj && typeof resObj === 'object') {
    logToConsole(`[OBJ METADATA] keys=${Object.keys(resObj).join(',')} | errno=${resObj.errno} | code=${resObj.code} | stderr=${resObj.stderr || 'none'}`, true);
    if (resObj.stdout !== undefined && resObj.stdout !== null) {
      return String(resObj.stdout).trim();
    }
    if (resObj.output !== undefined && resObj.output !== null) {
      return String(resObj.output).trim();
    }
    if (resObj.result !== undefined && resObj.result !== null) {
      return String(resObj.result).trim();
    }
    return strVal || String(rawRes || '').trim();
  }

  return String(rawRes || '').trim();
}

async function yieldToBrowser() {
  return new Promise(resolve => {
    requestAnimationFrame(() => setTimeout(resolve, 0));
  });
}

async function execCmdVerbose(cmd) {
  logToConsole(`[EXEC] ${cmd}`, true);
  try {
    let res = null;
    const ksuApi = (window.ksu && typeof window.ksu.exec === 'function') 
      ? window.ksu 
      : ((typeof ksu !== 'undefined' && typeof ksu.exec === 'function') ? ksu : null);

    if (ksuApi) {
      try {
        res = await ksuApi.exec(cmd);
        logToConsole(`[ksu.exec(cmd)] returned`, true);
      } catch (e1) {
        logToConsole(`[ksu.exec 1 arg err] ${e1.message || e1}`, true);
        try {
          res = await ksuApi.exec(cmd, '{}');
          logToConsole(`[ksu.exec(cmd, '{}')] returned`, true);
        } catch (e2) {
          logToConsole(`[ksu.exec 2 args err] ${e2.message || e2}`, true);
        }
      }
    } else {
      logToConsole(`[NO KSU API DETECTED] window.ksu=${typeof window.ksu}, ksu=${typeof ksu}`, true);
    }

    const stdout = extractStdout(res);
    logToConsole(`[RES STDOUT] len=${stdout.length}`, true);
    if (stdout.length > 0) return stdout;
    else if (res) logToConsole(`[RES RAW TYPE] ${typeof res}: ${JSON.stringify(res).substring(0, 100)}`, true);
    else logToConsole(`[RES NULL] KernelSU exec returned null/undefined.`, true);
  } catch (err) {
    logToConsole(`[EXEC ERR] ${err.message || err}`);
    console.warn('Execution error for:', cmd, err);
  }
  return '';
}

// ═══════════════════════════════════════════
// Button Loading Helper
// ═══════════════════════════════════════════

async function setButtonLoading(btnId, isLoading, loadingText) {
  const btn = document.getElementById(btnId);
  if (!btn) return;

  if (isLoading) {
    if (!btn.dataset.originalHtml) {
      btn.dataset.originalHtml = btn.innerHTML;
    }
    btn.disabled = true;
    btn.innerHTML = `
      <svg class="spinner" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <circle cx="12" cy="12" r="10" stroke-opacity="0.25"></circle>
        <path d="M12 2a10 10 0 0 1 10 10" stroke-opacity="1"></path>
      </svg>
      <span>${loadingText}</span>
    `;
    await yieldToBrowser();
  } else {
    btn.disabled = false;
    if (btn.dataset.originalHtml) {
      btn.innerHTML = btn.dataset.originalHtml;
      delete btn.dataset.originalHtml;
    }
  }
}

// Card Pulse Overlay Helper
async function setCardsLoading(isLoading) {
  const cards = document.querySelectorAll('.card');
  cards.forEach(card => {
    if (isLoading) card.classList.add('is-loading');
    else card.classList.remove('is-loading');
  });
  if (isLoading) await yieldToBrowser();
}

// ═══════════════════════════════════════════
// Audio Status Query
// ═══════════════════════════════════════════

let cachedWorkingCmd = null;

async function execCmdWithTimeout(cmd, timeoutMs = 3000) {
  const timeoutPromise = new Promise((resolve) => {
    setTimeout(() => resolve(''), timeoutMs);
  });
  return Promise.race([execCmdVerbose(cmd), timeoutPromise]);
}

async function loadAudioOutputSession() {
  logToConsole('Querying audio status via KernelSU exec API...');

  let output = '';
  if (cachedWorkingCmd) {
    output = await execCmdWithTimeout(cachedWorkingCmd, 3000);
  }

  if (!output || !output.includes('{')) {
    const commandsToTry = [
      '/system/bin/sh /data/adb/modules/audio-misc-settings-ksu-webui/get_audio_status.sh',
      'sh /data/adb/modules/audio-misc-settings-ksu-webui/get_audio_status.sh',
      '/system/bin/sh /data/adb/modules/audio-misc-settings/get_audio_status.sh',
      '/system/bin/sh ../get_audio_status.sh',
      '/system/bin/sh ./get_audio_status.sh'
    ];

    for (const cmd of commandsToTry) {
      output = await execCmdWithTimeout(cmd, 2500);
      if (output && output.includes('{') && output.includes('}')) {
        cachedWorkingCmd = cmd;
        logToConsole(`[CACHE] Found working script path: ${cmd}`, true);
        break;
      }
    }
  }

  if (output && output.includes('{')) {
    try {
      const jsonStart = output.indexOf('{');
      const jsonEnd = output.lastIndexOf('}') + 1;
      const jsonText = output.substring(jsonStart, jsonEnd);
      logToConsole(`[JSON RAW] ${jsonText}`, true);

      const data = JSON.parse(jsonText);

      // Use updateElementWithFlash for value-change animations
      updateElementWithFlash('out-device-name', data.active_route || 'Built-in Speaker');
      updateElementWithFlash('out-sample-rate', data.sample_rate || '48,000 Hz');
      updateElementWithFlash('out-bitrate', data.bitrate || '16-bit PCM');
      updateElementWithFlash('out-dac-info', data.is_usb ? `${data.dac_name || 'USB DAC'} • ${data.sync_mode || 'ASYNC'}` : 'No USB DAC Connected');
      updateElementWithFlash('out-bt-codec', data.is_bt ? `${data.bt_name || 'Bluetooth'} • ${data.bt_codec || 'A2DP'}` : 'Bluetooth Audio Disconnected');

      updateElementWithFlash('prop-vol-steps', (data.vol_steps || '100') + ' steps');

      const resamplerVal = data.resampler || 'Default (Dynamic Hi-Fi)';
      let resamplerLabel = resamplerVal;
      if (resamplerVal === '7') resamplerLabel = '7 (Mastering Quality / 179 dB)';
      else if (resamplerVal === '4') resamplerLabel = '4 (Mid-Grade / Power Saver)';
      else if (/^\d+$/.test(resamplerVal)) resamplerLabel = resamplerVal + ' (Custom)';
      updateElementWithFlash('prop-resampler-quality', resamplerLabel);

      updateElementWithFlash('prop-effects-status', (data.ignore_fx === 'true') ? 'Disabled (Direct Pass)' : 'Active');
      updateElementWithFlash('prop-spatializer-status', (data.spatializer === 'false') ? 'Disabled' : 'Enabled');
      updateElementWithFlash('prop-safemedia-status', (data.safemedia === 'true') ? 'Bypassed' : 'Default');
      updateElementWithFlash('prop-usb-period', (data.usb_period || '2000') + ' μs');

      // New audiophile properties
      updateElementWithFlash('prop-offload-24bit', (data.offload_24bit === 'true') ? 'Enabled (24-bit HAL)' : 'Disabled');

      const psdVal = data.psd_stopband || 'default';
      updateElementWithFlash('prop-psd-stopband', (psdVal !== 'default') ? psdVal + ' dB (Clinical SRC)' : 'Default (System)');

      const flingerVal = data.flinger_standby || 'default';
      let flingerLabel = 'Default (System)';
      if (flingerVal === '200') flingerLabel = '200 ms (Warm Path)';
      else if (flingerVal === '60') flingerLabel = '60 ms (Quick Standby)';
      else if (flingerVal !== 'default') flingerLabel = flingerVal + ' ms';
      updateElementWithFlash('prop-flinger-standby', flingerLabel);

      // Audiophile & Mode Specific Props
      const modeVal = data.mode || 'audiophile';
      const isAudiophile = modeVal === 'audiophile';
      
      const badgeMode = document.getElementById('active-mode-badge');
      if (badgeMode) {
        badgeMode.classList.remove('skeleton-text');
        badgeMode.textContent = isAudiophile ? 'Audiophile Hi-Fi Mode' : 'Power Saver Mode';
        badgeMode.className = `badge mode-badge ${isAudiophile ? 'audiophile' : 'powersaver'}`;
      }

      const btnAudiophile = document.getElementById('btn-mode-audiophile');
      const btnPowerSaver = document.getElementById('btn-mode-power-saver');
      if (btnAudiophile && btnPowerSaver) {
        if (isAudiophile) {
          btnAudiophile.classList.add('active');
          btnPowerSaver.classList.remove('active');
        } else {
          btnPowerSaver.classList.add('active');
          btnAudiophile.classList.remove('active');
        }
      }

      updateElementWithFlash('prop-int-codec', (data.int_codec === 'true') ? 'Enabled (Direct Pipeline)' : 'Standard');

      const admVal = data.adm_buffering || '6';
      let admLabel = admVal + ' ms';
      if (admVal === '6') admLabel = '6 ms (Low-Jitter Bounds)';
      else if (admVal === '10') admLabel = '10 ms (Power Saver)';
      updateElementWithFlash('prop-adm-buffering', admLabel);

      updateElementWithFlash('prop-deep-buffer', (data.deep_buffer === 'false') ? 'Disabled (Bypassed)' : 'Enabled (Power Saving)');

      const propTinymix = document.getElementById('prop-tinymix-status');
      if (propTinymix) {
        propTinymix.classList.remove('skeleton-text');
        propTinymix.textContent = data.has_tinymix ? (isAudiophile ? 'LOHIFI Bias (Active)' : 'ULP Power Mode') : 'Not Available';
      }

      updateElementWithFlash('info-platform', data.platform || 'Android Platform');
      updateElementWithFlash('info-arch', data.arch || 'arm64-v8a');
      updateElementWithFlash('info-audioserver-pid', data.audioserver_pid ? `PID ${data.audioserver_pid}` : 'running');

      const stateBadge = document.getElementById('output-state-badge');
      if (stateBadge) {
        stateBadge.classList.remove('skeleton-text');
        stateBadge.textContent = data.is_usb ? 'USB Route Active' : (data.is_bt ? 'Bluetooth Active' : 'Speaker Active');
      }

      logToConsole(`[SUCCESS] Profile=[${modeVal}] | Route=[${data.active_route}] | SampleRate=[${data.sample_rate}] | DAC=[${data.dac_name || 'USB DAC'}]`);
      return true;
    } catch (e) {
      logToConsole(`[JSON PARSE ERR] ${e.message}`);
    }
  }

  logToConsole('Notice: Backend status query returned empty or invalid JSON.');
  return false;
}

async function updateModuleStatus() {
  const badge = document.getElementById('status-badge');

  const vendorCheck = await execCmdWithTimeout('/system/bin/ls -d /vendor /system/vendor', 2000);
  if (vendorCheck && vendorCheck.trim()) {
    badge.textContent = 'Active (ZeroMount / OverlayFS)';
    badge.className = 'badge status-badge active';
  } else {
    badge.textContent = 'Active (Module Loaded)';
    badge.className = 'badge status-badge active';
  }
}

async function refreshAll() {
  setCardsLoading(true);
  setSkeletonLoading(true);
  try {
    const [, success] = await Promise.all([updateModuleStatus(), loadAudioOutputSession()]);
    setSkeletonLoading(false);
    return success;
  } catch (err) {
    setSkeletonLoading(false);
    return false;
  } finally {
    setCardsLoading(false);
  }
}

// ═══════════════════════════════════════════
// Mode Switching
// ═══════════════════════════════════════════

async function switchAudioMode(targetMode) {
  const isAudiophile = targetMode === 'audiophile';
  const btnId = isAudiophile ? 'btn-mode-audiophile' : 'btn-mode-power-saver';
  const otherBtnId = isAudiophile ? 'btn-mode-power-saver' : 'btn-mode-audiophile';
  const modeName = isAudiophile ? 'Audiophile Hi-Fi' : 'Power Saver';

  logToConsole(`Switching audio profile to: ${targetMode}...`);
  showToast(`Switching to ${modeName} mode...`, 'info', 2000);
  await setButtonLoading(btnId, true, 'Applying Profile...');

  // Disable the other mode button too
  const otherBtn = document.getElementById(otherBtnId);
  if (otherBtn) otherBtn.disabled = true;

  const commands = [
    `/system/bin/sh /data/adb/modules/audio-misc-settings-ksu-webui/set_audio_mode.sh ${targetMode}`,
    `sh /data/adb/modules/audio-misc-settings-ksu-webui/set_audio_mode.sh ${targetMode}`,
    `/system/bin/sh /data/adb/modules/audio-misc-settings/set_audio_mode.sh ${targetMode}`
  ];

  try {
    let success = false;
    for (const cmd of commands) {
      const res = await execCmdWithTimeout(cmd, 4000);
      if (res && (res.includes('success') || res.includes('Switched'))) {
        success = true;
        logToConsole(`Audio mode switch response: ${res}`);
        break;
      }
    }
    if (!success) {
      await execCmdVerbose(`/system/bin/sh /data/adb/modules/audio-misc-settings-ksu-webui/set_audio_mode.sh ${targetMode}`);
    }
    await new Promise(r => setTimeout(r, 1200));
    await refreshAll();
    showToast(`${modeName} mode applied successfully`, 'success');
  } catch (err) {
    showToast(`Failed to switch mode: ${err.message || 'Unknown error'}`, 'error');
  } finally {
    await setButtonLoading(btnId, false);
    if (otherBtn) otherBtn.disabled = false;
  }
}

// ═══════════════════════════════════════════
// Event Listeners & Initialization
// ═══════════════════════════════════════════

document.addEventListener('DOMContentLoaded', () => {
  const toggleVerbose = document.getElementById('toggle-verbose');
  if (toggleVerbose) {
    toggleVerbose.checked = isVerbose;
    toggleVerbose.addEventListener('change', (e) => {
      isVerbose = e.target.checked;
      localStorage.setItem('verbose_logging', isVerbose);
      logToConsole(isVerbose ? 'Verbose logging enabled.' : 'Verbose logging disabled.');
      showToast(isVerbose ? 'Verbose logging enabled' : 'Verbose logging disabled', 'info', 2000);
    });
  }

  // Initial skeleton state
  setSkeletonLoading(true);
  refreshAll();

  document.getElementById('btn-refresh').addEventListener('click', async () => {
    logToConsole('Refreshing status...');
    await setButtonLoading('btn-refresh', true, 'Refreshing...');
    try {
      const success = await refreshAll();
      if (success) showToast('Status refreshed', 'success', 2000);
    } finally {
      await setButtonLoading('btn-refresh', false);
    }
  });

  document.getElementById('btn-restart-audio').addEventListener('click', async () => {
    logToConsole('Executing: setprop ctl.restart audioserver');
    showToast('Restarting audioserver...', 'warning', 2000);
    await setButtonLoading('btn-restart-audio', true, 'Restarting...');
    try {
      await execCmdVerbose('/system/bin/setprop ctl.restart audioserver');
      logToConsole('Audioserver restart signal sent successfully.');
      await new Promise(r => setTimeout(r, 1200));
      await refreshAll();
      showToast('Audioserver restarted successfully', 'success');
    } catch (err) {
      showToast('Audioserver restart failed', 'error');
    } finally {
      await setButtonLoading('btn-restart-audio', false);
    }
  });

  document.getElementById('btn-apply-volume').addEventListener('click', async () => {
    logToConsole('Executing: settings put system volume_steps_music 100');
    await setButtonLoading('btn-apply-volume', true, 'Applying...');
    try {
      await execCmdVerbose('/system/bin/settings put system volume_steps_music 100');
      logToConsole('Volume steps set to 100.');
      await new Promise(r => setTimeout(r, 800));
      await refreshAll();
      showToast('Volume steps set to 100', 'success', 2500);
    } finally {
      await setButtonLoading('btn-apply-volume', false);
    }
  });

  const btnTinymix = document.getElementById('btn-tinymix-hw');
  if (btnTinymix) {
    btnTinymix.addEventListener('click', async () => {
      logToConsole('Executing ALSA tinymix hardware gain calibration...');
      showToast('Applying ALSA hardware gain...', 'info', 2000);
      await setButtonLoading('btn-tinymix-hw', true, 'Applying...');
      try {
        await execCmdVerbose('/system/bin/sh /data/adb/modules/audio-misc-settings-ksu-webui/set_audio_mode.sh tinymix_only');
        logToConsole('ALSA hardware gain applied successfully.');
        await refreshAll();
        showToast('ALSA hardware gain applied', 'success');
      } finally {
        await setButtonLoading('btn-tinymix-hw', false);
      }
    });
  }

  const btnAudiophile = document.getElementById('btn-mode-audiophile');
  if (btnAudiophile) {
    btnAudiophile.addEventListener('click', () => switchAudioMode('audiophile'));
  }

  const btnPowerSaver = document.getElementById('btn-mode-power-saver');
  if (btnPowerSaver) {
    btnPowerSaver.addEventListener('click', () => switchAudioMode('power_saver'));
  }

  document.getElementById('btn-clear-console').addEventListener('click', () => {
    document.getElementById('console-output').textContent = 'Console cleared.';
    showToast('Console cleared', 'info', 1500);
  });
});
