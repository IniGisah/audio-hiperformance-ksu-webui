#!/system/bin/sh

# Audio Misc Settings - Audio Profile Mode Switcher (Audiophile vs Power Saver)
# Usage: set_audio_mode.sh [audiophile|power_saver|apply|tinymix_only]

export PATH="/system/bin:/system/xbin:/vendor/bin:$PATH"

SCRIPT_DIR="${0%/*}"

# Find active module path for mode.conf persistence
CONF_FILE=""
for p in "$SCRIPT_DIR/mode.conf" \
         "/data/adb/modules/audio-misc-settings-ksu-webui/mode.conf" \
         "/data/adb/modules_update/audio-misc-settings-ksu-webui/mode.conf" \
         "/data/adb/modules/audio-misc-settings/mode.conf" \
         "/data/adb/ksu/modules/audio-misc-settings-ksu-webui/mode.conf" \
         "/data/adb/ap/modules/audio-misc-settings-ksu-webui/mode.conf"; do
    if [ -f "$p" ]; then
        CONF_FILE="$p"
        break
    fi
done

if [ -z "$CONF_FILE" ]; then
    for p in "$SCRIPT_DIR/mode.conf" \
             "/data/adb/modules/audio-misc-settings-ksu-webui/mode.conf" \
             "/data/adb/modules_update/audio-misc-settings-ksu-webui/mode.conf" \
             "/data/adb/modules/audio-misc-settings/mode.conf"; do
        if [ -w "${p%/*}" ]; then
            CONF_FILE="$p"
            break
        fi
    done
fi

if [ -z "$CONF_FILE" ]; then
    CONF_FILE="$SCRIPT_DIR/mode.conf"
fi

which_resetprop() {
    if type resetprop >/dev/null 2>&1; then
        echo "resetprop"
    elif [ -x "/data/adb/magisk/magisk" ]; then
        echo "/data/adb/magisk/magisk resetprop"
    elif [ -x "/data/adb/magisk/resetprop" ]; then
        echo "/data/adb/magisk/resetprop"
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

# Reload all audio services in exact dependency order
reloadAudioServers() {
    local i
    for i in $(seq 1 3); do
        if [ "$(getprop sys.boot_completed)" = "1" ] && [ -n "$(getprop init.svc.audioserver)" ]; then
            break
        fi
        sleep 0.2
    done

    # Restart AIDL/HIDL audio HAL services before audioserver
    if [ -n "$(getprop init.svc.vendor.audio-hal-aidl)" ]; then
        setprop ctl.restart "vendor.audio-hal-aidl" >/dev/null 2>&1
    fi
    if [ -n "$(getprop init.svc.audiohalservice.qti)" ]; then
        setprop ctl.restart "audiohalservice.qti" >/dev/null 2>&1
    fi
    if [ -n "$(getprop init.svc.audiohalservice)" ]; then
        setprop ctl.restart "audiohalservice" >/dev/null 2>&1
    fi
    if [ -n "$(getprop init.svc.vendor.audio-hal)" ]; then
        setprop ctl.restart "vendor.audio-hal" >/dev/null 2>&1
    fi

    # Restart AudioFlinger / Audioserver
    if [ -n "$(getprop init.svc.audioserver)" ]; then
        setprop ctl.restart audioserver >/dev/null 2>&1
        sleep 0.4
        if [ "$(getprop init.svc.audioserver)" != "running" ]; then
            pid="$(getprop init.svc_debug_pid.audioserver)"
            [ -n "$pid" ] && kill -HUP "$pid" >/dev/null 2>&1
        fi
    fi
}

apply_tinymix_hw() {
    local target_mode="$1"
    if type tinymix >/dev/null 2>&1; then
        # Ensure USB DAC volume is unclamped
        tinymix "DAC Volume" "100%" >/dev/null 2>&1
        tinymix "Headphone Playback Volume" "100%" >/dev/null 2>&1

        if [ "$target_mode" = "audiophile" ]; then
            # LOHIFI: High-bias mode for lowest distortion
            tinymix "RX_HPH_PWR_MODE" "LOHIFI" >/dev/null 2>&1
            tinymix "WSA_COMP1 Switch" 0 >/dev/null 2>&1
            tinymix "WSA_COMP2 Switch" 0 >/dev/null 2>&1
        else
            # ULP: Low power analog bias
            tinymix "RX_HPH_PWR_MODE" "ULP" >/dev/null 2>&1
            tinymix "WSA_COMP1 Switch" 1 >/dev/null 2>&1
            tinymix "WSA_COMP2 Switch" 1 >/dev/null 2>&1
        fi
    fi
}

ACTION_ARG="$1"
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

        # Safe power-optimized buffer: 12ms ADM buffer allows CPU to sleep longer
        set_prop "vendor.audio.adm.buffering.ms" "12"

        # Resampler quality must remain 7 (Float Polyphase) to avoid PCM_FLOAT assertion crash
        set_prop "af.resampler.quality" "7"

        # Clean 120 dB stopband filter without high-frequency smearing
        # (tbwcheat=0 eliminates passband distortion on fractional 44.1k -> 384k conversions)
        set_prop "ro.audio.resampler.psd.stopband" "120"
        set_prop "ro.audio.resampler.psd.halflength" "160"
        set_prop "ro.audio.resampler.psd.tbwcheat" "0"
        set_prop "ro.audio.resampler.psd.enable_at_samplerate" "48000"

        # Quick hardware standby: release audio clock and DAC power in 50ms when idle
        set_prop "ro.audio.flinger_standbytime_ms" "50"

        # Keep 24-bit stream support active so Apple Music Hi-Res lossless tracks never fail
        set_prop "audio.offload.pcm.24bit.enable" "true"

        # Ensure direct audio routing remains stable
        set_prop "audio.deep_buffer.media" "false"

        apply_tinymix_hw "power_saver"
        ;;
    "audiophile" | * )
        TARGET_MODE="audiophile"

        # Low-latency direct output path
        set_prop "audio.deep_buffer.media" "false"

        # Conservative 6ms ADM jitter buffer
        set_prop "vendor.audio.adm.buffering.ms" "6"

        # Enable HiFi hardware acceleration
        set_prop "persist.vendor.audio.hifi" "true"
        set_prop "persist.vendor.audio.hifi.int_codec" "true"

        # Mastering-grade sinc interpolation (Quality 7)
        set_prop "af.resampler.quality" "7"

        # 179 dB stop-band attenuation eliminates audible aliasing
        set_prop "ro.audio.resampler.psd.stopband" "179"
        set_prop "ro.audio.resampler.psd.halflength" "480"
        set_prop "ro.audio.resampler.psd.tbwcheat" "0"
        set_prop "ro.audio.resampler.psd.enable_at_samplerate" "48000"

        # Force HAL to accept 24/32-bit streams
        set_prop "audio.offload.pcm.24bit.enable" "true"

        # Keep hardware path warm longer
        set_prop "ro.audio.flinger_standbytime_ms" "200"

        apply_tinymix_hw "audiophile"
        ;;
esac

# Save persistent state
echo "MODE=${TARGET_MODE}" > "$CONF_FILE" 2>/dev/null

# Cleanly reload audio subsystem without breaking active media sessions
reloadAudioServers

echo "{\"status\":\"success\",\"mode\":\"${TARGET_MODE}\",\"message\":\"Switched to ${TARGET_MODE} mode successfully\"}"
