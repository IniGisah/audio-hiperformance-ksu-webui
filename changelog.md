## Change logs

# v3.0.0
* **Android Audio Architecture Live Telemetry Pipeline**:
  * Real-time 5-layer telemetry pipeline (AudioTrack API -> AudioFlinger -> Audio Effects -> Vendor Audio HAL -> Linux ALSA Kernel).
  * True live stream source decoding inspection from `dumpsys media_session` and `dumpsys media.audio_flinger` (identifying native Apple Music ALAC Lossless, YouTube Music, Tidal, Poweramp, and bit-exact stream formats).
  * Interactive Stage Inspector Dialog dynamically reporting real-time PID, channel masks, DSP status, and ALSA descriptor states.
* **Rock-Solid Power Saver & Battery Mode Overhaul**:
  * Fixed float resampler crash in `libaudioprocessing.so` when playing 24/32-bit float streams (Apple Music / FLAC).
  * Safe 120dB Polyphase Sinc tuning eliminating high-frequency smearing on fractional sample rate conversions (44.1k -> 384k).
  * Synchronized profile states and UI buttons across Dashboard and Tuning tabs.
* **Universal Magisk, KernelSU, KernelSU Next & APatch Support**:
  * Added `#MAGISK` universal header in `update-binary` for 1-click installation via Magisk Manager (v24+ / v26+ / v27+).
  * Auto-detection of `resetprop` across Magisk (`/data/adb/magisk`), KernelSU (`/data/adb/ksu`), and APatch (`/data/adb/ap`).
* **Magisk Action Button (`action.sh`)**:
  * 1-Click interactive diagnostics and control directly inside Magisk Manager v26+.
  * Full real-time pipeline diagnostic report (Active Route, Hardware DAC, Bluetooth Codec, Sample Rate, Bit Depth, Audiophile Profile, 96k Unlock Status).
* **Terminal CLI Tool (`audiomisc`)**:
  * Installed `/system/bin/audiomisc` command for Termux, terminal emulator, and ADB shell users (`su -c audiomisc`).
  * Supports both interactive menu and fast one-shot CLI commands (`status`, `rate`, `depth`, `mode`, `drc`, `period`, `tinymix`, `restart`, `reset`).
* **Multi-Host WebUI Compatibility**:
  * Added out-of-the-box support for [KsuWebUIStandalone](https://github.com/MeowDump/KsuWebUIStandalone) (recommended lightweight WebUI for Magisk users).
  * Extended WebUI JavaScript bridge to auto-detect `window.ksu`, `window.mmrl`, and `window.ap`.

# v2.2.0
* **On-The-Fly Manual Sample Rate & Bit Depth Switcher**:
  * Users can select sample rates manually (44.1 kHz, 48 kHz, 88.2 kHz, 96 kHz, 176.4 kHz, 192 kHz, 352.8 kHz, 384 kHz, 705.6 kHz, 768 kHz) and bit depths (16, 24, 32-bit PCM, 32-bit Float) on the fly without rebooting.
  * Dynamically generates audio policy XML and overlays it with graceful `audioserver` reload.
* **USB DAC Hardware Capability Detection**:
  * Automatically parses `/proc/asound/card*/stream0` to detect the exact list of supported sample rates and bit depths for connected USB DACs.
  * Highlights supported hardware rates dynamically in the WebUI.
* **96kHz Limit Unlocker Integration (Old Devices / Mi 6X / SDM660 Support)**:
  * Integrated binary unlocking of `libalsautils.so` (clearing 96kHz cap up to 768kHz) and patched `/vendor/etc/audio_platform_configuration.xml`.
  * Added explicit support for legacy platforms (`sdm660`, `bengal`, `holi`, MTK, and 32-bit devices).
* **Audio Policy Architecture Engine**:
  * Bundled complete templates for 7.0 HAL and pre-7.0 legacy HALs (`Bypass Offload`, `Bypass Offload Safer`, `Direct PCM`, `Hardware Offload`, `HiFi Playback`, `Legacy / Safe`, `USB Only`).
* **Dynamic Range Control (DRC) & USB Transfer Period Controls**:
  * Toggle DRC on/off on the fly for pure uncompressed dynamics.
  * Configurable USB transfer packet interval presets (2000 µs, 2250 µs, 3875 µs, 4000 µs, 5000 µs).
* **Enhanced WebUI**:
  * Futuristic audiophile glassmorphism theme with tactile segmented button grids, glowing status indicators, and real-time session monitoring.
* Merged work laptop updates:
  * Dynamic Audio Profile Manager (`Audiophile Hi-Fi Mode` vs `Power Saver Mode`) via `set_audio_mode.sh` & `mode.conf`
  * Low-level ALSA hardware register calibration (`tinymix`) with Apple USB DAC 100% gain volume override
  * Systemless audio policy XML topology patching (`disableDrcAudioPolicyConfig` & `patchBitPerfectAudioPolicyConfig`)
  * Interactive KernelSU WebUI with real-time profile switcher, tinymix hardware gain calibration, and audiophile metric badges
* HyperOS & Flagship SoC Pure-Audio Stability Overhaul:
  * Eliminated dangerous shared library zeroing (`libdlbvol.so` & `libvolumelistener.so`) preventing `audioserver` SIGSEGV crashes
  * Safely disabled OEM `EffectPolicy` to prevent video playback (YouTube / ExoPlayer) freezes
  * Added native SoC profiles for Snapdragon 8 Elite (`sun`), Snapdragon 8 Gen 3 (`pineapple`), and Dimensity 9200/9300/9400 (`mt69*`)
  * Enhanced `uninstall.sh` to thoroughly clean persistent properties from `/data/property/persistent_properties`

# v1.3.11
* Changed an error message for no Magisk mirrors
* Stop AOCXD daemon on Tensor devices

# v1.3.10
* Tuned for POCO F3 (Android 15)
* Nullifying the volume listener for no compressing audio (maybe a peak limiter) on Motorola devices
