# Android Audio Architecture & Module Engineering Deep Dive

## Table of Contents
1. [Standard Android Audio Architecture & The 48kHz Bottleneck](#1-standard-android-audio-architecture--the-48khz-bottleneck)
2. [How This Module Unlocks Bit-Perfect Playback for Streaming Apps](#2-how-this-module-unlocks-bit-perfect-playback-for-streaming-apps)
3. [Layer-by-Layer Breakdown of Module Optimizations](#3-layer-by-layer-breakdown-of-module-optimizations)
4. [Streaming App Compatibility & Behavior Matrix](#4-streaming-app-compatibility--behavior-matrix)
5. [Audiophile Hi-Fi Mode vs. Battery Saver Mode](#5-audiophile-hi-fi-mode-vs-battery-saver-mode)

---

## 1. Standard Android Audio Architecture & The 48kHz Bottleneck

In a stock Android operating system, audio flows through several software abstraction layers before reaching your USB DAC or speakers:

```
┌────────────────────────────────────────────────────────┐
│ App Layer (Apple Music, Tidal, Spotify, YouTube Music) │
└──────────────────────────┬─────────────────────────────┘
                           │ (AudioTrack API)
┌──────────────────────────▼─────────────────────────────┐
│ AudioFlinger (Audio Server & Software Mixer)           │
│  - Downsamples / Upsamples all audio to 48kHz          │
│  - Truncates 24/32-bit audio to 16-bit integer         │
│  - Injects DSP / SoundFX / Volume Limiters             │
└──────────────────────────┬─────────────────────────────┘
                           │ (HAL Interface)
┌──────────────────────────▼─────────────────────────────┐
│ Vendor Audio HAL (Qualcomm / MediaTek / Tensor)         │
│  - Enforces `deep_buffer` (max 48kHz)                  │
│  - Clamps USB clock & sample rates to 96kHz            │
└──────────────────────────┬─────────────────────────────┘
                           │ (ALSA PCM)
┌──────────────────────────▼─────────────────────────────┐
│ Linux Kernel & ALSA USB Audio Driver                   │
└──────────────────────────┬─────────────────────────────┘
                           │ (USB Isochronous / Async)
┌──────────────────────────▼─────────────────────────────┐
│ External USB DAC (e.g. MOONDROP DAWN PRO 2)            │
└────────────────────────────────────────────────────────┘
```

### Why Stock Android Mangies Audio Quality:
1. **The 48kHz Fixed Mixer Bottleneck:** By default, Android's `AudioFlinger` mixes all active audio streams into a single fixed 48,000 Hz / 16-bit stream. If you play a 44.1kHz track (CD quality) or a 96kHz/192kHz track (Hi-Res Lossless), Android forcibly resamples it to 48kHz using a low-complexity resampler to save CPU power.
2. **`deep_buffer` Battery Optimization:** Android routes all media music to `deep_buffer` (a large 200ms audio buffer). `deep_buffer` only supports 44.1kHz and 48kHz, immediately choking any high-resolution stream.
3. **Hidden DSP & Dynamic Compression:** OEM sound enhancement layers (Dolby Atmos, Xiaomi MiSound, volume limiters) insert non-linear equalizers and peak limiters that alter the frequency response and destroy dynamic range.
4. **Driver Sample Rate Locks:** Vendor libraries (`libalsautils.so`) often hardcode sample rate locks at 96kHz or 192kHz, preventing DACs from operating at 352.8kHz, 384kHz, or 768kHz.

---

## 2. How This Module Unlocks Bit-Perfect Playback for Streaming Apps

This module modifies the entire Android audio pipeline so that **system-level streaming apps achieve near bit-perfect direct output** without needing custom USB drivers:

```
[ Apple Music / Tidal Hi-Res Stream (96kHz 24-bit) ]
                     │
                     ▼
[ AudioTrack: Direct / Offload Request ]
                     │
                     ▼
[ AudioPolicy / HAL: deep_buffer BYPASSED ]  <-- (audio.deep_buffer.media=false)
                     │
                     ▼
[ AudioFlinger: Zero DSP / Effects Ignored ] <-- (ro.audio.ignore_effects=true)
                     │
                     ▼
[ HAL: Bit-Perfect Direct Stream Granted ]   <-- (AUDIO_OUTPUT_FLAG_BIT_PERFECT)
                     │
                     ▼
[ 24/32-bit Native Stream Maintained ]       <-- (audio.offload.pcm.24bit.enable=true)
                     │
                     ▼
[ Linux Kernel ALSA Driver (Zero Lock) ]    <-- (libalsautils.so patched to 768kHz)
                     │
                     ▼
[ USB DAC: Plays Native 96kHz / 384kHz ]    <-- (Bit-Exact, Bit-Perfect Stream)
```

---

## 3. Layer-by-Layer Breakdown of Module Optimizations

### Layer 1: Audio Policy Configuration (`audio_policy_configuration.xml`)
- **`AUDIO_OUTPUT_FLAG_BIT_PERFECT` Injection:** Injects bit-perfect output flags into direct stream profiles, signaling AudioPolicyManager that incoming Hi-Res streams should retain their native sample rates (`FOLLOW_SR`).
- **Speaker Dynamic Range Compression (DRC) Disabled:** Disables `speaker_drc_enabled="false"` in the global audio configuration XML.
- **Spatializer Flags Removed:** Strips spatializer wrappers from Bluetooth and USB audio policies.

### Layer 2: Android System Properties (`system.prop` & `set_audio_mode.sh`)
- **`audio.deep_buffer.media=false`:** Forces media playback out of the 48kHz `deep_buffer` and into the low-latency Direct/Primary output thread.
- **`audio.offload.pcm.24bit.enable=true`:** Forces the Qualcomm HAL to accept 24-bit/32-bit audio streams on offload and direct paths.
- **`vendor.audio.flac.sw.decoder.24bit=true`:** Unlocks native 24-bit high-resolution software decoding for FLAC lossless streams.
- **`ro.audio.ignore_effects=true`:** Bypasses audio effect processing (compressors, volume limiters, OEM spatializers).
- **`af.resampler.quality=7`:** Enables mastering-grade sinc interpolation with 179 dB stopband attenuation (`ro.audio.resampler.psd.stopband=179`) and long filter kernels (`ro.audio.resampler.psd.halflength=480`) whenever any resampling occurs.
- **`vendor.audio.adm.buffering.ms=6`:** Sets an ultra-tight 6ms ADM buffer bounds to minimize timing jitter.

### Layer 3: Binary Patches (`libalsautils.so` & `libalsautilsv2.so`)
- **Clearing 96kHz / 192kHz Driver Lock:** Binary-patches the Qualcomm ALSA utility shared library to unlock frequencies up to **768,000 Hz (768 kHz)**.
- **USB Period Alignment (`vendor.audio.usb.perio=2000`):** Replaces legacy SELinux-restricted properties with vendor namespace properties and sets 2000μs high-speed USB transfer packets.

### Layer 4: ALSA Hardware Mixer (tinymix)
- **`DAC Volume` & `Headphone Playback Volume` 100%:** Fixes the notorious hardware volume attenuation bug on Apple and standard USB-C DAC dongles.
- **`RX_HPH_PWR_MODE LOHIFI`:** Enables high-bias mode on Qualcomm WCD codecs for minimal Total Harmonic Distortion (THD) under headphone loads.

---

## 4. Streaming App Compatibility & Behavior Matrix

| App | Playback Engine | Output Mode | Sample Rate Behavior with Module |
|---|---|---|---|
| **Apple Music** | Native AudioTrack / Direct PCM | Direct / Offload | ✅ **Native Bit-Perfect** up to 192kHz / 24-bit Lossless |
| **Tidal** | Native AudioTrack | Direct / Bit-Perfect | ✅ **Native Bit-Perfect** up to 192kHz / 24-bit Max Flac |
| **Qobuz** | Native AudioTrack | Direct High-Res | ✅ **Native Bit-Perfect** up to 192kHz / 24-bit |
| **Poweramp** | Built-in USB Exclusive Driver | USB Exclusive | ✅ **Native Bit-Perfect** directly via kernel USB node |
| **UAPP / Neutron** | Custom USB Audio Driver | Direct ALSA / Bit-Perfect | ✅ **Native Bit-Perfect** up to 384kHz / 768kHz DSD |
| **YouTube Music** | Standard AudioTrack (AAC/Opus) | Direct / Resampler 7 | ✅ **48kHz High-Fidelity** with Sinc 7 Resampler |
| **Spotify** | Standard AudioTrack (Ogg Vorbis) | Direct / Resampler 7 | ✅ **44.1k/48kHz Studio Resampled** |

---

## 5. Audiophile Hi-Fi Mode vs. Battery Saver Mode

| Feature / Setting | Audiophile Hi-Fi Mode | Power Saver Mode |
|---|---|---|
| **Deep Buffer Bypass** | `false` (Direct low-latency path) | `true` (200ms CPU sleep intervals) |
| **Resampler Algorithm** | `7` (Mastering Sinc / 179 dB PSD) | `4` (Mid-grade interpolation) |
| **24-bit PCM Offload** | `true` (Enabled) | `true` (Enabled for Hi-Res compatibility) |
| **Hardware HiFi Mode** | `true` (`persist.vendor.audio.hifi`) | `false` (Low power hardware mode) |
| **ADM Jitter Buffer** | `6 ms` (Low jitter) | `10 ms` (Fewer CPU wakeups) |
| **AudioFlinger Standby** | `200 ms` (Warm hardware path) | `60 ms` (Quick hardware sleep) |
| **ALSA Hardware Bias** | `LOHIFI` High Bias, ADC1=6 | `ULP` Ultra-Low Power, ADC1=4 |
| **Best Used For** | Critical listening with USB DAC | Everyday video, podcasts, background music |
