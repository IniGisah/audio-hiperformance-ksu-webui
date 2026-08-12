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

apply_tinymix_hw() {
    local target_mode="$1"
    if type tinymix >/dev/null 2>&1; then
        # Apple USB DAC 100% Volume Override Fix
        tinymix "DAC Volume" "100%" >/dev/null 2>&1
        tinymix "Headphone Playback Volume" "100%" >/dev/null 2>&1
        
        if [ "$target_mode" = "audiophile" ]; then
            tinymix "RX_HPH_PWR_MODE" "LOHIFI" >/dev/null 2>&1
            tinymix "WSA_COMP1 Switch" 0 >/dev/null 2>&1
            tinymix "WSA_COMP2 Switch" 0 >/dev/null 2>&1
            tinymix "ADC1 Volume" 6 >/dev/null 2>&1
        else
            tinymix "RX_HPH_PWR_MODE" "ULP" >/dev/null 2>&1
            tinymix "WSA_COMP1 Switch" 1 >/dev/null 2>&1
            tinymix "WSA_COMP2 Switch" 1 >/dev/null 2>&1
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
        set_prop "audio.deep_buffer.media" "true"
        set_prop "vendor.audio.adm.buffering.ms" "10"
        set_prop "persist.vendor.audio.hifi" "false"
        set_prop "persist.vendor.audio.hifi.int_codec" "false"
        if [ -n "$RP" ]; then
            "$RP" --delete "af.resampler.quality" >/dev/null 2>&1
            "$RP" --delete "audio.offload.pcm.24bit.enable" >/dev/null 2>&1
        fi
        apply_tinymix_hw "power_saver"
        ;;
    "audiophile" | * )
        TARGET_MODE="audiophile"
        set_prop "audio.deep_buffer.media" "false"
        set_prop "vendor.audio.adm.buffering.ms" "6"
        set_prop "persist.vendor.audio.hifi" "true"
        set_prop "persist.vendor.audio.hifi.int_codec" "true"
        if [ -n "$RP" ]; then
            "$RP" --delete "af.resampler.quality" >/dev/null 2>&1
            "$RP" --delete "audio.offload.pcm.24bit.enable" >/dev/null 2>&1
            "$RP" --delete "ro.audio.flinger_standbytime_ms" >/dev/null 2>&1
            "$RP" --delete "ro.audio.resampler.psd.enable_at_samplerate" >/dev/null 2>&1
            "$RP" --delete "ro.audio.resampler.psd.stopband" >/dev/null 2>&1
            "$RP" --delete "ro.audio.resampler.psd.halflength" >/dev/null 2>&1
            "$RP" --delete "ro.audio.resampler.psd.tbwcheat" >/dev/null 2>&1
        fi
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

