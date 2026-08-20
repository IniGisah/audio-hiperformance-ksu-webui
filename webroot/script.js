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

async function execCmdVerbose(cmd) {
  logToConsole(`[EXEC] ${cmd}`, true);
  try {
    let res = null;
    if (window.ksu && typeof window.ksu.exec === 'function') {
      try {
        res = await window.ksu.exec(cmd, '{}');
        logToConsole(`[window.ksu.exec(cmd, '{}')] returned`, true);
      } catch (e) {
        logToConsole(`[window.ksu.exec 2 args err] ${e.message || e}`, true);
      }
      if (!res) {
        try {
          res = await window.ksu.exec(cmd);
          logToConsole(`[window.ksu.exec(cmd)] returned`, true);
        } catch (e) {
          logToConsole(`[window.ksu.exec 1 arg err] ${e.message || e}`, true);
        }
      }
    } else if (typeof ksu !== 'undefined' && typeof ksu.exec === 'function') {
      try {
        res = await ksu.exec(cmd, '{}');
        logToConsole(`[ksu.exec(cmd, '{}')] returned`, true);
      } catch (e) {
        logToConsole(`[ksu.exec 2 args err] ${e.message || e}`, true);
      }
      if (!res) {
        try {
          res = await ksu.exec(cmd);
          logToConsole(`[ksu.exec(cmd)] returned`, true);
        } catch (e) {
          logToConsole(`[ksu.exec 1 arg err] ${e.message || e}`, true);
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

// Button Loading Helper
function setButtonLoading(btnId, isLoading, loadingText) {
  const btn = document.getElementById(btnId);
  if (!btn) return;

  if (isLoading) {
    btn.dataset.originalHtml = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = `
      <svg class="spinner" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <circle cx="12" cy="12" r="10" stroke-opacity="0.25"></circle>
        <path d="M12 2a10 10 0 0 1 10 10" stroke-opacity="1"></path>
      </svg>
      ${loadingText}
    `;
  } else {
    btn.disabled = false;
    if (btn.dataset.originalHtml) {
      btn.innerHTML = btn.dataset.originalHtml;
    }
  }
}

// Card Pulse Overlay Helper
function setCardsLoading(isLoading) {
  const cards = document.querySelectorAll('.card');
  cards.forEach(card => {
    if (isLoading) card.classList.add('is-loading');
    else card.classList.remove('is-loading');
  });
}

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

      document.getElementById('out-device-name').textContent = data.active_route || 'Built-in Speaker';
      document.getElementById('out-sample-rate').textContent = data.sample_rate || '48,000 Hz';
      document.getElementById('out-bitrate').textContent = data.bitrate || '16-bit PCM';
      document.getElementById('out-dac-info').textContent = data.is_usb ? `${data.dac_name || 'USB DAC'} • ${data.sync_mode || 'ASYNC'}` : 'No USB DAC Connected';
      document.getElementById('out-bt-codec').textContent = data.is_bt ? `${data.bt_name || 'Bluetooth'} • ${data.bt_codec || 'A2DP'}` : 'Bluetooth Audio Disconnected';

      document.getElementById('prop-vol-steps').textContent = (data.vol_steps || '100') + ' steps';

      const resamplerVal = data.resampler || 'Default (Dynamic Hi-Fi)';
      let resamplerLabel = resamplerVal;
      if (resamplerVal === '7') resamplerLabel = '7 (Mastering Quality / 179 dB)';
      else if (resamplerVal === '4') resamplerLabel = '4 (Mid-Grade / Power Saver)';
      else if (/^\d+$/.test(resamplerVal)) resamplerLabel = resamplerVal + ' (Custom)';
      document.getElementById('prop-resampler-quality').textContent = resamplerLabel;

      document.getElementById('prop-effects-status').textContent = (data.ignore_fx === 'true') ? 'Disabled (Direct Pass)' : 'Active';
      document.getElementById('prop-spatializer-status').textContent = (data.spatializer === 'false') ? 'Disabled' : 'Enabled';
      document.getElementById('prop-safemedia-status').textContent = (data.safemedia === 'true') ? 'Bypassed' : 'Default';
      document.getElementById('prop-usb-period').textContent = (data.usb_period || '2000') + ' μs';

      // New audiophile properties
      const propOffload = document.getElementById('prop-offload-24bit');
      if (propOffload) propOffload.textContent = (data.offload_24bit === 'true') ? 'Enabled (24-bit HAL)' : 'Disabled';

      const propPsd = document.getElementById('prop-psd-stopband');
      if (propPsd) {
        const psdVal = data.psd_stopband || 'default';
        propPsd.textContent = (psdVal !== 'default') ? psdVal + ' dB (Clinical SRC)' : 'Default (System)';
      }

      const propFlinger = document.getElementById('prop-flinger-standby');
      if (propFlinger) {
        const flingerVal = data.flinger_standby || 'default';
        if (flingerVal === '200') propFlinger.textContent = '200 ms (Warm Path)';
        else if (flingerVal === '60') propFlinger.textContent = '60 ms (Quick Standby)';
        else if (flingerVal !== 'default') propFlinger.textContent = flingerVal + ' ms';
        else propFlinger.textContent = 'Default (System)';
      }

      // Audiophile & Mode Specific Props
      const modeVal = data.mode || 'audiophile';
      const isAudiophile = modeVal === 'audiophile';
      
      const badgeMode = document.getElementById('active-mode-badge');
      if (badgeMode) {
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

      const propIntCodec = document.getElementById('prop-int-codec');
      if (propIntCodec) propIntCodec.textContent = (data.int_codec === 'true') ? 'Enabled (Direct Pipeline)' : 'Standard';

      const propAdmBuffering = document.getElementById('prop-adm-buffering');
      if (propAdmBuffering) {
        const admVal = data.adm_buffering || '6';
        if (admVal === '6') propAdmBuffering.textContent = '6 ms (Low-Jitter Bounds)';
        else if (admVal === '10') propAdmBuffering.textContent = '10 ms (Power Saver)';
        else propAdmBuffering.textContent = admVal + ' ms';
      }

      const propDeepBuffer = document.getElementById('prop-deep-buffer');
      if (propDeepBuffer) propDeepBuffer.textContent = (data.deep_buffer === 'false') ? 'Disabled (Bypassed)' : 'Enabled (Power Saving)';

      const propTinymix = document.getElementById('prop-tinymix-status');
      if (propTinymix) propTinymix.textContent = data.has_tinymix ? (isAudiophile ? 'LOHIFI Bias (Active)' : 'ULP Power Mode') : 'Not Available';

      document.getElementById('info-platform').textContent = data.platform || 'Android Platform';
      document.getElementById('info-arch').textContent = data.arch || 'arm64-v8a';
      document.getElementById('info-audioserver-pid').textContent = data.audioserver_pid ? `PID ${data.audioserver_pid}` : 'running';

      const stateBadge = document.getElementById('output-state-badge');
      if (stateBadge) {
        stateBadge.textContent = data.is_usb ? 'USB Route Active' : (data.is_bt ? 'Bluetooth Active' : 'Speaker Active');
      }

      logToConsole(`[SUCCESS] Profile=[${modeVal}] | Route=[${data.active_route}] | SampleRate=[${data.sample_rate}] | DAC=[${data.dac_name || 'USB DAC'}]`);
      return;
    } catch (e) {
      logToConsole(`[JSON PARSE ERR] ${e.message}`);
    }
  }

  logToConsole('Notice: Backend status query returned empty or invalid JSON.');
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
  try {
    await Promise.all([updateModuleStatus(), loadAudioOutputSession()]);
  } finally {
    setCardsLoading(false);
  }
}

async function switchAudioMode(targetMode) {
  const isAudiophile = targetMode === 'audiophile';
  const btnId = isAudiophile ? 'btn-mode-audiophile' : 'btn-mode-power-saver';
  logToConsole(`Switching audio profile to: ${targetMode}...`);
  setButtonLoading(btnId, true, 'Applying Profile...');

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
  } finally {
    setButtonLoading(btnId, false);
  }
}

// Event Listeners
document.addEventListener('DOMContentLoaded', () => {
  const toggleVerbose = document.getElementById('toggle-verbose');
  if (toggleVerbose) {
    toggleVerbose.checked = isVerbose;
    toggleVerbose.addEventListener('change', (e) => {
      isVerbose = e.target.checked;
      localStorage.setItem('verbose_logging', isVerbose);
      logToConsole(isVerbose ? 'Verbose logging enabled.' : 'Verbose logging disabled.');
    });
  }

  refreshAll();

  document.getElementById('btn-refresh').addEventListener('click', async () => {
    logToConsole('Refreshing status...');
    setButtonLoading('btn-refresh', true, 'Refreshing...');
    try {
      await refreshAll();
    } finally {
      setButtonLoading('btn-refresh', false);
    }
  });

  document.getElementById('btn-restart-audio').addEventListener('click', async () => {
    logToConsole('Executing: setprop ctl.restart audioserver');
    setButtonLoading('btn-restart-audio', true, 'Restarting...');
    try {
      await execCmdVerbose('/system/bin/setprop ctl.restart audioserver');
      logToConsole('Audioserver restart signal sent successfully.');
      await new Promise(r => setTimeout(r, 1200));
      await refreshAll();
    } finally {
      setButtonLoading('btn-restart-audio', false);
    }
  });

  document.getElementById('btn-apply-volume').addEventListener('click', async () => {
    logToConsole('Executing: settings put system volume_steps_music 100');
    setButtonLoading('btn-apply-volume', true, 'Applying...');
    try {
      await execCmdVerbose('/system/bin/settings put system volume_steps_music 100');
      logToConsole('Volume steps set to 100.');
      await new Promise(r => setTimeout(r, 800));
      await refreshAll();
    } finally {
      setButtonLoading('btn-apply-volume', false);
    }
  });

  const btnTinymix = document.getElementById('btn-tinymix-hw');
  if (btnTinymix) {
    btnTinymix.addEventListener('click', async () => {
      logToConsole('Executing ALSA tinymix hardware gain calibration...');
      setButtonLoading('btn-tinymix-hw', true, 'Applying...');
      try {
        await execCmdVerbose('/system/bin/sh /data/adb/modules/audio-misc-settings-ksu-webui/set_audio_mode.sh tinymix_only');
        logToConsole('ALSA hardware gain applied successfully.');
        await refreshAll();
      } finally {
        setButtonLoading('btn-tinymix-hw', false);
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
  });
});
