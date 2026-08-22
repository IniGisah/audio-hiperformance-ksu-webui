#!/system/bin/sh

# Audio Misc Settings - On-The-Fly Sample Rate, Bit Depth, & Audio Policy Switcher
# Usage: set_audio_samplerate.sh [--rate <hz>] [--depth <bits>] [--mode <policy_mode>] [--drc <true|false>] [--period <usec>] [--reset] [apply]

export PATH="/system/bin:/system/xbin:/vendor/bin:$PATH"

SCRIPT_DIR="${0%/*}"

# Find active module path for samplerate.conf persistence
CONF_FILE=""
for p in "$SCRIPT_DIR/samplerate.conf" \
         "/data/adb/modules/audio-misc-settings-ksu-webui/samplerate.conf" \
         "/data/adb/modules_update/audio-misc-settings-ksu-webui/samplerate.conf" \
         "/data/adb/modules/audio-misc-settings/samplerate.conf" \
         "/data/adb/ksu/modules/audio-misc-settings-ksu-webui/samplerate.conf" \
         "/data/adb/ap/modules/audio-misc-settings-ksu-webui/samplerate.conf"; do
    if [ -f "$p" ]; then
        CONF_FILE="$p"
        break
    fi
done

if [ -z "$CONF_FILE" ]; then
    for p in "$SCRIPT_DIR/samplerate.conf" \
             "/data/adb/modules/audio-misc-settings-ksu-webui/samplerate.conf" \
             "/data/adb/modules_update/audio-misc-settings-ksu-webui/samplerate.conf" \
             "/data/adb/modules/audio-misc-settings/samplerate.conf"; do
        if [ -w "${p%/*}" ]; then
            CONF_FILE="$p"
            break
        fi
    done
fi

if [ -z "$CONF_FILE" ]; then
    CONF_FILE="$SCRIPT_DIR/samplerate.conf"
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
    local key="$1" val="$2"
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

# Reload audioserver cleanly
reloadAudioServers() {
    local i
    for i in $(seq 1 3); do
        if [ "$(getprop sys.boot_completed)" = "1" ] && [ -n "$(getprop init.svc.audioserver)" ]; then
            break
        fi
        sleep 0.5
    done

    # Restart AIDL audio HAL if active
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

    if [ -n "$(getprop init.svc.audioserver)" ]; then
        setprop ctl.restart audioserver
        sleep 0.3
        if [ "$(getprop init.svc.audioserver)" != "running" ]; then
            local pid="$(getprop init.svc_debug_pid.audioserver)"
            if [ -n "$pid" ]; then
                kill -HUP "$pid" >/dev/null 2>&1
            fi
            for i in $(seq 1 10); do
                sleep 0.2
                if [ "$(getprop init.svc.audioserver)" = "running" ]; then
                    break
                fi
            done
        fi
        return 0
    else
        return 1
    fi
}

# Check if 7.0 Audio HAL
IsSeventhAudio() {
    if [ -z "$(ls /vendor/lib64/android.hardware.audio@7.?.so 2>/dev/null)" ] && \
       [ -z "$(ls /vendor/lib/android.hardware.audio@7.?.so 2>/dev/null)" ] && \
       [ -z "$(ls /system/lib64/android.hardware.audio@7.?.so 2>/dev/null)" ] && \
       [ -z "$(ls /system/lib/android.hardware.audio@7.?.so 2>/dev/null)" ]; then
        return 1
    elif [ "$(getprop ro.build.product)" = "jfltexx" ]; then
        return 1
    else
        return 0
    fi
}

# Get Active Policy XML Path
getActivePolicyFile() {
    local active_xml=""
    if type dumpsys >/dev/null 2>&1; then
        local raw_src="$(timeout 1 dumpsys media.audio_policy 2>/dev/null | awk '/^ Config source: / { print $3 }')"
        if [ -n "$raw_src" ] && [ "$raw_src" != "AIDL" ] && [ "$raw_src" != "HAL" ] && [ -r "$raw_src" ]; then
            active_xml="$raw_src"
        fi
    fi

    if [ -n "$active_xml" ] && [ -r "$active_xml" ]; then
        echo "$active_xml"
        return 0
    fi

    # Fallbacks for Qualcomm SKU / Board / Standard paths
    local board="$(getprop ro.board.platform)"
    local sku="$(getprop ro.boot.product.vendor.sku)"
    [ -z "$sku" ] && sku="$(getprop ro.boot.hardware.sku)"

    for f in "/vendor/etc/audio/sku_${sku}/audio_policy_configuration.xml" \
             "/vendor/etc/audio/sku_${board}/audio_policy_configuration.xml" \
             "/vendor/etc/audio/audio_policy_configuration.xml" \
             "/vendor/etc/audio_policy_configuration_${board}.xml" \
             "/vendor/etc/audio_policy_configuration_sec.xml" \
             "/vendor/etc/audio_policy_configuration.xml" \
             "/system/vendor/etc/audio_policy_configuration.xml"; do
        if [ -r "$f" ]; then
            echo "$f"
            return 0
        fi
    done
    echo "/vendor/etc/audio_policy_configuration.xml"
}

getVolumeFile() {
    if [ $# -gt 0 ] && [ -r "$1" ]; then
        grep -m 1 -e '<xi:include[[:space:]]*href[[:space:]]*=[[:space:]]*".*audio_policy_volumes.*\.xml"' "$1" 2>/dev/null | awk -F '"' '{ print $2 }'
    fi
}

getDefaultVolumeFile() {
    if [ $# -gt 0 ] && [ -r "$1" ]; then
        grep -m 1 -e '<xi:include[[:space:]]*href[[:space:]]*=[[:space:]]*".*default_volume_tables.*\.xml"' "$1" 2>/dev/null | awk -F '"' '{ print $2 }'
    fi
}

# Find templates directory
TEMPLATES_DIR=""
for d in "$SCRIPT_DIR/templates" \
         "/data/adb/modules/audio-misc-settings-ksu-webui/templates" \
         "/data/adb/modules/audio-misc-settings/templates" \
         "/data/adb/ksu/modules/audio-misc-settings-ksu-webui/templates"; do
    if [ -d "$d" ]; then
        TEMPLATES_DIR="$d"
        break
    fi
done

if [ -z "$TEMPLATES_DIR" ]; then
    TEMPLATES_DIR="$SCRIPT_DIR/templates"
fi

GEN_FILE="/data/local/tmp/audio_conf_generated.xml"
GEN_AIDL_FILE="/data/local/tmp/audio_primary_generated.xml"
AIDL_PRIMARY_FILE="/vendor/etc/audio/audio_module_config_primary.xml"

# Read saved configuration if available
CURR_RATE="44100"
CURR_DEPTH="32"
CURR_MODE="auto"
CURR_DRC="false"
CURR_PERIOD="2000"

if [ -r "$CONF_FILE" ]; then
    r="$(grep '^RATE=' "$CONF_FILE" | cut -d= -f2 | tr -d ' \r')"
    [ -n "$r" ] && CURR_RATE="$r"
    d="$(grep '^DEPTH=' "$CONF_FILE" | cut -d= -f2 | tr -d ' \r')"
    [ -n "$d" ] && CURR_DEPTH="$d"
    m="$(grep '^MODE=' "$CONF_FILE" | cut -d= -f2 | tr -d ' \r')"
    [ -n "$m" ] && CURR_MODE="$m"
    c="$(grep '^DRC=' "$CONF_FILE" | cut -d= -f2 | tr -d ' \r')"
    [ -n "$c" ] && CURR_DRC="$c"
    p="$(grep '^PERIOD=' "$CONF_FILE" | cut -d= -f2 | tr -d ' \r')"
    [ -n "$p" ] && CURR_PERIOD="$p"
fi

TARGET_RATE="$CURR_RATE"
TARGET_DEPTH="$CURR_DEPTH"
TARGET_MODE="$CURR_MODE"
TARGET_DRC="$CURR_DRC"
TARGET_PERIOD="$CURR_PERIOD"
RESET_MODE=0

# Parse CLI arguments
while [ $# -gt 0 ]; do
    case "$1" in
        "-r" | "--rate" | "rate" )
            shift
            [ $# -gt 0 ] && TARGET_RATE="$1"
            shift
            ;;
        "-d" | "--depth" | "depth" )
            shift
            [ $# -gt 0 ] && TARGET_DEPTH="$1"
            shift
            ;;
        "-m" | "--mode" | "mode" )
            shift
            [ $# -gt 0 ] && TARGET_MODE="$1"
            shift
            ;;
        "--drc" | "drc" )
            shift
            [ $# -gt 0 ] && TARGET_DRC="$1"
            shift
            ;;
        "-p" | "--period" | "period" )
            shift
            [ $# -gt 0 ] && TARGET_PERIOD="$1"
            shift
            ;;
        "--reset" | "reset" )
            RESET_MODE=1
            shift
            ;;
        "apply" )
            # Just re-apply existing config
            shift
            ;;
        * )
            # Positional fallback: rate [depth] [mode]
            if [ -z "$POS_SEEN" ]; then
                TARGET_RATE="$1"
                POS_SEEN=1
            elif [ "$POS_SEEN" = "1" ]; then
                TARGET_DEPTH="$1"
                POS_SEEN=2
            elif [ "$POS_SEEN" = "2" ]; then
                TARGET_MODE="$1"
                POS_SEEN=3
            fi
            shift
            ;;
    esac
done

# Handle RESET
if [ "$RESET_MODE" = "1" ]; then
    activePolicy="$(getActivePolicyFile)"
    if grep -q "$activePolicy" /proc/self/mountinfo 2>/dev/null; then
        umount "$activePolicy" >/dev/null 2>&1
    fi
    if grep -q "/vendor/etc/usb_audio_policy_configuration.xml" /proc/self/mountinfo 2>/dev/null; then
        umount "/vendor/etc/usb_audio_policy_configuration.xml" >/dev/null 2>&1
    fi
    if [ -r "$AIDL_PRIMARY_FILE" ] && grep -q "$AIDL_PRIMARY_FILE" /proc/self/mountinfo 2>/dev/null; then
        umount "$AIDL_PRIMARY_FILE" >/dev/null 2>&1
    fi
    rm -f "$GEN_FILE" "$GEN_AIDL_FILE" 2>/dev/null

    cat <<EOF > "$CONF_FILE" 2>/dev/null
RATE=44100
DEPTH=32
MODE=auto
DRC=false
PERIOD=2000
EOF

    reloadAudioServers
    echo '{"status":"success","action":"reset","message":"Audio policy reset to stock system configuration"}'
    exit 0
fi

# Normalize Sample Rate
case "$TARGET_RATE" in
    "44k" | "44.1k" | "44100" ) TARGET_RATE="44100" ;;
    "48k" | "48000" ) TARGET_RATE="48000" ;;
    "88k" | "88.2k" | "88200" ) TARGET_RATE="88200" ;;
    "96k" | "96000" ) TARGET_RATE="96000" ;;
    "176k" | "176.4k" | "176400" ) TARGET_RATE="176400" ;;
    "192k" | "192000" ) TARGET_RATE="192000" ;;
    "352k" | "353k" | "352.8k" | "352800" ) TARGET_RATE="352800" ;;
    "384k" | "384000" ) TARGET_RATE="384000" ;;
    "705k" | "706k" | "705.6k" | "705600" ) TARGET_RATE="705600" ;;
    "768k" | "768000" ) TARGET_RATE="768000" ;;
    * )
        if ! expr "$TARGET_RATE" : '^[0-9]\+$' >/dev/null 2>&1 || [ "$TARGET_RATE" -lt 44100 ] || [ "$TARGET_RATE" -gt 768000 ]; then
            TARGET_RATE="44100"
        fi
        ;;
esac

# Normalize Bit Depth / Format
AUDIO_FORMAT="AUDIO_FORMAT_PCM_32_BIT"
case "$TARGET_DEPTH" in
    "16" | "16bit" | "16_BIT" )
        TARGET_DEPTH="16"
        AUDIO_FORMAT="AUDIO_FORMAT_PCM_16_BIT"
        ;;
    "24" | "24bit" | "24_BIT" )
        TARGET_DEPTH="24"
        AUDIO_FORMAT="AUDIO_FORMAT_PCM_24_BIT_PACKED"
        ;;
    "32" | "32bit" | "32_BIT" )
        TARGET_DEPTH="32"
        AUDIO_FORMAT="AUDIO_FORMAT_PCM_32_BIT"
        ;;
    "float" | "FLOAT" | "32float" )
        TARGET_DEPTH="float"
        AUDIO_FORMAT="AUDIO_FORMAT_PCM_FLOAT"
        ;;
    * )
        TARGET_DEPTH="32"
        AUDIO_FORMAT="AUDIO_FORMAT_PCM_32_BIT"
        ;;
esac

# Normalize DRC
if [ "$TARGET_DRC" = "1" ] || [ "$TARGET_DRC" = "true" ] || [ "$TARGET_DRC" = "enable" ]; then
    TARGET_DRC="true"
else
    TARGET_DRC="false"
fi

# Normalize Policy Mode
case "$TARGET_MODE" in
    "bypass" | "bypass-offload" ) TARGET_MODE="bypass" ;;
    "bypass-safer" | "bypass-offload-safer" ) TARGET_MODE="bypass-safer" ;;
    "offload" ) TARGET_MODE="offload" ;;
    "offload-direct" | "direct" ) TARGET_MODE="offload-direct" ;;
    "offload-safer" ) TARGET_MODE="offload-safer" ;;
    "offload-hifi" | "offload-hifi-playback" ) TARGET_MODE="offload-hifi-playback" ;;
    "legacy" ) TARGET_MODE="legacy" ;;
    "safe" ) TARGET_MODE="safe" ;;
    "safest" ) TARGET_MODE="safest" ;;
    "safest-auto" ) TARGET_MODE="safest-auto" ;;
    "usb" | "usb-only" ) TARGET_MODE="usb" ;;
    * ) TARGET_MODE="bypass-safer" ;;
esac

# Resolve target XML file & volume XML files
POLICY_FILE="$(getActivePolicyFile)"
VOLUME_FILE="$(getVolumeFile "$POLICY_FILE")"
DEFAULT_VOLUME_FILE="$(getDefaultVolumeFile "$POLICY_FILE")"

[ -z "$VOLUME_FILE" ] && VOLUME_FILE="/vendor/etc/audio_policy_volumes.xml"
[ -z "$DEFAULT_VOLUME_FILE" ] && DEFAULT_VOLUME_FILE="/vendor/etc/default_volume_tables.xml"

# Bluetooth & USB module names
BT_MODULE="bluetooth"
USB_MODULE="usb"

if [ -r "/vendor/lib64/hw/audio.bluetooth_qti.default.so" ] || [ -r "/vendor/lib/hw/audio.bluetooth_qti.default.so" ]; then
    board="$(getprop ro.board.platform)"
    if [ "$board" = "pineapple" ] || [ "$board" = "taro" ]; then
        BT_MODULE="bluetooth_qti"
    fi
fi

if [ -r "/vendor/lib64/hw/audio.usbv2.default.so" ] && [ ! -r "/vendor/lib64/hw/audio.usb.default.so" ]; then
    USB_MODULE="usbv2"
fi

OVERLAY_TARGET="$POLICY_FILE"
TEMPLATE_FILE=""

if IsSeventhAudio; then
    case "$TARGET_MODE" in
        "bypass" ) TEMPLATE_FILE="$TEMPLATES_DIR/bypass_offload_template.xml" ;;
        "bypass-safer" ) TEMPLATE_FILE="$TEMPLATES_DIR/bypass_offload_safer_template.xml" ;;
        "offload" ) TEMPLATE_FILE="$TEMPLATES_DIR/offload_template.xml" ;;
        "offload-safer" ) TEMPLATE_FILE="$TEMPLATES_DIR/offload_safer_template.xml" ;;
        "offload-direct" ) TEMPLATE_FILE="$TEMPLATES_DIR/offload_direct_template.xml" ;;
        "offload-hifi-playback" ) TEMPLATE_FILE="$TEMPLATES_DIR/offload_hifi_playback_template.xml" ;;
        "legacy" ) TEMPLATE_FILE="$TEMPLATES_DIR/Old/legacy_template.xml" ;;
        "safe" ) TEMPLATE_FILE="$TEMPLATES_DIR/bypass_offload_safer_template.xml" ;;
        "safest" ) TEMPLATE_FILE="$TEMPLATES_DIR/Old/safest_template.xml" ;;
        "safest-auto" ) TEMPLATE_FILE="$TEMPLATES_DIR/bypass_offload_template.xml" ;;
        "usb" )
            TEMPLATE_FILE="$TEMPLATES_DIR/Old/usb_only_template.xml"
            OVERLAY_TARGET="/vendor/etc/usb_audio_policy_configuration.xml"
            ;;
        * ) TEMPLATE_FILE="$TEMPLATES_DIR/bypass_offload_safer_template.xml" ;;
    esac
else
    case "$TARGET_MODE" in
        "bypass" ) TEMPLATE_FILE="$TEMPLATES_DIR/Old/bypass_offload_template.xml" ;;
        "bypass-safer" )
            case "$(getprop ro.board.platform)" in
                mt* ) TEMPLATE_FILE="$TEMPLATES_DIR/Old/bypass_offload_safer_mtk_template.xml" ;;
                * ) TEMPLATE_FILE="$TEMPLATES_DIR/Old/bypass_offload_safer_template.xml" ;;
            esac
            ;;
        "offload" ) TEMPLATE_FILE="$TEMPLATES_DIR/Old/offload_template.xml" ;;
        "offload-direct" ) TEMPLATE_FILE="$TEMPLATES_DIR/Old/offload_direct_template.xml" ;;
        "offload-hifi-playback" ) TEMPLATE_FILE="$TEMPLATES_DIR/Old/offload_hifi_playback_template.xml" ;;
        "legacy" ) TEMPLATE_FILE="$TEMPLATES_DIR/Old/legacy_template.xml" ;;
        "safe" ) TEMPLATE_FILE="$TEMPLATES_DIR/Old/safe_template.xml" ;;
        "safest" ) TEMPLATE_FILE="$TEMPLATES_DIR/Old/safest_template.xml" ;;
        "safest-auto" ) TEMPLATE_FILE="$TEMPLATES_DIR/Old/safest_auto_template.xml" ;;
        "usb" )
            TEMPLATE_FILE="$TEMPLATES_DIR/Old/usb_only_template.xml"
            OVERLAY_TARGET="/vendor/etc/usb_audio_policy_configuration.xml"
            ;;
        * ) TEMPLATE_FILE="$TEMPLATES_DIR/Old/bypass_offload_safer_template.xml" ;;
    esac
fi

if [ ! -r "$TEMPLATE_FILE" ]; then
    echo "{\"status\":\"error\",\"message\":\"Audio policy template not found: ${TEMPLATE_FILE}\"}"
    exit 1
fi

# Render generated XML
mkdir -p "/data/local/tmp" 2>/dev/null
rm -f "$GEN_FILE" 2>/dev/null

sed -e "s|%DRC_ENABLED%|${TARGET_DRC}|g" \
    -e "s|%USB_MODULE%|${USB_MODULE}|g" \
    -e "s|%BT_MODULE%|${BT_MODULE}|g" \
    -e "s|%SAMPLING_RATE%|${TARGET_RATE}|g" \
    -e "s|%AUDIO_FORMAT%|${AUDIO_FORMAT}|g" \
    -e "s|%VOLUME_FILE%|${VOLUME_FILE}|g" \
    -e "s|%DEFAULT_VOLUME_FILE%|${DEFAULT_VOLUME_FILE}|g" \
    "$TEMPLATE_FILE" > "$GEN_FILE"

if [ $? -ne 0 ] || [ ! -s "$GEN_FILE" ]; then
    echo "{\"status\":\"error\",\"message\":\"Failed to generate audio policy XML\"}"
    exit 1
fi

chmod 644 "$GEN_FILE"
chcon u:object_r:vendor_configs_file:s0 "$GEN_FILE" 2>/dev/null

# Bind mount generated XML over target
if [ -r "$OVERLAY_TARGET" ]; then
    umount -l "$OVERLAY_TARGET" >/dev/null 2>&1
    mount -o bind "$GEN_FILE" "$OVERLAY_TARGET"
fi

# Patch and mount AIDL primary configuration if present (Qualcomm Snapdragon 8 Gen 3/4 / sun / pineapple)
if [ -r "$AIDL_PRIMARY_FILE" ]; then
    umount -l "$AIDL_PRIMARY_FILE" >/dev/null 2>&1
    rm -f "$GEN_AIDL_FILE" 2>/dev/null
    AIDL_RATES="${TARGET_RATE} 352800 192000 176400 128000 96000 88200 64000 48000 44100 32000 24000 22050 16000 12000 11025 8000"
    sed -e "s/samplingRates=\"48000\"/samplingRates=\"${AIDL_RATES}\"/g" \
        "$AIDL_PRIMARY_FILE" > "$GEN_AIDL_FILE"

    if [ -s "$GEN_AIDL_FILE" ]; then
        chmod 644 "$GEN_AIDL_FILE"
        chcon u:object_r:vendor_configs_file:s0 "$GEN_AIDL_FILE" 2>/dev/null
        mount -o bind "$GEN_AIDL_FILE" "$AIDL_PRIMARY_FILE"
    fi
fi

# Update USB Period & Audio Properties
if [ -n "$TARGET_PERIOD" ] && expr "$TARGET_PERIOD" : '^[0-9]\+$' >/dev/null 2>&1; then
    set_prop "vendor.audio.usb.perio" "$TARGET_PERIOD"
    set_prop "vendor.audio.usb.out.period_us" "$TARGET_PERIOD"
fi

# Set resampler properties aligned with target sample rate
set_prop "ro.audio.resampler.psd.enable_at_samplerate" "$TARGET_RATE"

# Save persistent configuration
cat <<EOF > "$CONF_FILE" 2>/dev/null
RATE=${TARGET_RATE}
DEPTH=${TARGET_DEPTH}
MODE=${TARGET_MODE}
DRC=${TARGET_DRC}
PERIOD=${TARGET_PERIOD}
EOF

# Reload audioserver
reloadAudioServers

khz=$(( TARGET_RATE / 1000 ))
echo "{\"status\":\"success\",\"rate\":${TARGET_RATE},\"khz\":${khz},\"depth\":\"${TARGET_DEPTH}\",\"mode\":\"${TARGET_MODE}\",\"drc\":${TARGET_DRC},\"period\":${TARGET_PERIOD},\"message\":\"Switched to ${khz} kHz (${TARGET_DEPTH}-bit) [${TARGET_MODE}] successfully\"}"
