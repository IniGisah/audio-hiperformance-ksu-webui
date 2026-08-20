## Change logs

# v2.1.0
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
