#!/system/bin/sh

# Audio Misc Settings - Audio Profile Mode Switcher (Audiophile vs Power Saver)
# Usage: set_audio_mode.sh [audiophile|power_saver|apply|tinymix_only]

export PATH="/system/bin:/system/xbin:/vendor/bin:$PATH"

SCRIPT_DIR="${0%/*}"

# Find active module path for mode.conf persistence
CONF_FILE=""
for p in "$SCRIPT_DIR/mode.conf" \
         "/data/adb/modules/audio-misc-settings-ksu-webui/mode.conf" \
         "/data/adb/modules/audio-misc-settings/mode.conf" \
         "/data/adb/ksu/modules/audio-misc-settings-ksu-webui/mode.conf" \
         "/data/adb/ap/modules/audio-misc-settings-ksu-webui/mode.conf"; do
    if [ -w "$p" ] || [ -w "${p%/*}" ]; then
        CONF_FILE="$p"
        break
    fi
done

if [ -z "$CONF_FILE" ]; then
    CONF_FILE="$SCRIPT_DIR/mode.conf"
fi

which_resetprop() {
    if type resetprop >/dev/null 2>&1; then
        echo "resetprop"
    elif [ -x "/data/adb/ksu/bin/resetprop" ]; then
        echo "/data/adb/ksu/bin/resetprop"
    elif [ -x "/data/adb/ap/bin/resetprop" ]; then
        echo "/data/adb/ap/bin/resetprop"
    elif type resetprop_phh >/dev/null 2>&1; then
        echo "resetprop_phh"
    else
        echo ""
    fi
}

RP="$(which_resetprop)"

set_prop() {
    local key="$1"
    local val="$2"
    if [ -n "$RP" ]; then
        "$RP" --delete "$key" >/dev/null 2>&1
        "$RP" "$key" "$val" >/dev/null 2>&1
    else
        setprop "$key" "$val" >/dev/null 2>&1
    fi
}

delete_prop() {
    local key="$1"
    if [ -n "$RP" ]; then
        "$RP" --delete "$key" >/dev/null 2>&1
    fi
}

apply_tinymix_hw() {
    local target_mode="$1"
    if type tinymix >/dev/null 2>&1; then
        # Apple USB DAC 100% Volume Override Fix
        tinymix "DAC Volume" "100%" >/dev/null 2>&1
        tinymix "Headphone Playback Volume" "100%" >/dev/null 2>&1

        if [ "$target_mode" = "audiophile" ]; then
            # LOHIFI: High-bias mode to lower THD under load
            tinymix "RX_HPH_PWR_MODE" "LOHIFI" >/dev/null 2>&1
            # Disable hardware dynamic range compression for transient integrity
            tinymix "WSA_COMP1 Switch" 0 >/dev/null 2>&1
            tinymix "WSA_COMP2 Switch" 0 >/dev/null 2>&1
            # Reference analog gain for optimal SNR
            tinymix "ADC1 Volume" 6 >/dev/null 2>&1
            # Enable direct TDM routing where available
            tinymix "MultiMedia1 Mixer PRI_TDM_RX_0" 1 >/dev/null 2>&1
        else
            # ULP: Ultra-Low Power mode for battery savings
            tinymix "RX_HPH_PWR_MODE" "ULP" >/dev/null 2>&1
            # Re-enable hardware compression for power efficiency
            tinymix "WSA_COMP1 Switch" 1 >/dev/null 2>&1
            tinymix "WSA_COMP2 Switch" 1 >/dev/null 2>&1
            # Restore default attenuated gain
            tinymix "ADC1 Volume" 4 >/dev/null 2>&1
            # Disable direct TDM routing
            tinymix "MultiMedia1 Mixer PRI_TDM_RX_0" 0 >/dev/null 2>&1
        fi
    fi
}

TARGET_MODE="$1"

if [ "$TARGET_MODE" = "tinymix_only" ]; then
    CURR_MODE="audiophile"
    if [ -r "$CONF_FILE" ]; then
        CURR_MODE="$(grep '^MODE=' "$CONF_FILE" | cut -d= -f2 | tr -d ' \r')"
    fi
    apply_tinymix_hw "$CURR_MODE"
    echo "{\"status\":\"success\",\"mode\":\"${CURR_MODE}\",\"message\":\"Applied tinymix hardware gain settings\"}"
    exit 0
fi

if [ -z "$TARGET_MODE" ] || [ "$TARGET_MODE" = "apply" ]; then
    if [ -r "$CONF_FILE" ]; then
        TARGET_MODE="$(grep '^MODE=' "$CONF_FILE" | cut -d= -f2 | tr -d ' \r')"
    fi
    if [ -z "$TARGET_MODE" ]; then
        TARGET_MODE="audiophile"
    fi
fi

case "$TARGET_MODE" in
    "power_saver" | "battery" | "saver" )
        TARGET_MODE="power_saver"

        # Deep buffer: re-enable for 200ms CPU sleep cycles between audio bursts
        set_prop "audio.deep_buffer.media" "true"

        # Larger ADM buffer: fewer CPU wakeups = less power draw
        set_prop "vendor.audio.adm.buffering.ms" "10"

        # Disable HiFi hardware mode to reduce power consumption
        set_prop "persist.vendor.audio.hifi" "false"
        set_prop "persist.vendor.audio.hifi.int_codec" "false"

        # Mid-grade resampler: lower CPU usage than mastering quality
        set_prop "af.resampler.quality" "4"

        # Quick AudioFlinger standby: release hardware fast when idle
        set_prop "ro.audio.flinger_standbytime_ms" "60"

        # Delete audiophile-specific PSD resampler props to reduce processing overhead
        delete_prop "ro.audio.resampler.psd.enable_at_samplerate"
        delete_prop "ro.audio.resampler.psd.stopband"
        delete_prop "ro.audio.resampler.psd.halflength"
        delete_prop "ro.audio.resampler.psd.tbwcheat"
        delete_prop "audio.offload.pcm.24bit.enable"

        apply_tinymix_hw "power_saver"
        ;;
    "audiophile" | * )
        TARGET_MODE="audiophile"

        # Bypass deep buffer: force low-latency direct/primary output path
        set_prop "audio.deep_buffer.media" "false"

        # Conservative ADM jitter buffer (universal-safe across all SoCs)
        set_prop "vendor.audio.adm.buffering.ms" "6"

        # Enable HiFi hardware acceleration on supported SoCs
        set_prop "persist.vendor.audio.hifi" "true"
        set_prop "persist.vendor.audio.hifi.int_codec" "true"

        # Mastering-grade sinc interpolation for AudioFlinger resampler
        set_prop "af.resampler.quality" "7"

        # PSD (Polyphase Sinc with Downsampling) resampler configuration
        #   179 dB stop-band attenuation eliminates audible aliasing
        set_prop "ro.audio.resampler.psd.stopband" "179"
        #   Longer sinc filter kernel for maximum precision
        set_prop "ro.audio.resampler.psd.halflength" "480"
        #   Disable transition-band shortcuts for clinical accuracy
        set_prop "ro.audio.resampler.psd.tbwcheat" "0"
        #   Enable PSD resampler at all sample rates ≥ 48kHz
        set_prop "ro.audio.resampler.psd.enable_at_samplerate" "48000"

        # Force HAL to accept 24-bit streams on offload paths
        set_prop "audio.offload.pcm.24bit.enable" "true"

        # Keep hardware path warm longer to reduce pop/click on playback resume
        set_prop "ro.audio.flinger_standbytime_ms" "200"

        apply_tinymix_hw "audiophile"
        ;;
esac

# Save state
echo "MODE=${TARGET_MODE}" > "$CONF_FILE" 2>/dev/null

# Restart audioserver ONLY if property values actually changed (avoids dropping active Bluetooth sessions on boot)
CURR_DEEP="$(getprop audio.deep_buffer.media)"
RESTART_NEEDED=0

if [ "$TARGET_MODE" = "audiophile" ] && [ "$CURR_DEEP" != "false" ]; then
    RESTART_NEEDED=1
elif [ "$TARGET_MODE" = "power_saver" ] && [ "$CURR_DEEP" != "true" ]; then
    RESTART_NEEDED=1
fi

if [ "$RESTART_NEEDED" = "1" ]; then
    if [ -n "$(getprop init.svc.audioserver)" ]; then
        setprop ctl.restart audioserver
        sleep 1
        if [ "$(getprop init.svc.audioserver)" != "running" ]; then
            pid="$(getprop init.svc_debug_pid.audioserver)"
            if [ -n "$pid" ]; then
                kill -HUP "$pid" >/dev/null 2>&1
            fi
        fi
    fi
fi

echo "{\"status\":\"success\",\"mode\":\"${TARGET_MODE}\",\"message\":\"Switched to ${TARGET_MODE} mode successfully\"}"
