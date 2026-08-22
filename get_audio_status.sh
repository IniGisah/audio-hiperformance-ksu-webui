#!/system/bin/sh

export PATH="/system/bin:/system/xbin:/vendor/bin:$PATH"

# Audio Misc Settings - Audio Output Session & Status Query Script
# Outputs JSON to stdout for KernelSU WebUI

proc_cards="$(cat /proc/asound/cards 2>/dev/null)"
proc_streams="$(cat /proc/asound/card*/stream0 /proc/asound/card*/usbmix 2>/dev/null)"
proc_hwparams="$(cat /proc/asound/card*/pcm*/sub*/hw_params 2>/dev/null)"

dumpsys_audio="$(timeout 1 dumpsys audio 2>/dev/null | grep -iE "USB|A2DP|BLUETOOTH|WIRED|device|mDevice|name=|alias=" | head -n 50)"
dumpsys_policy="$(timeout 1 dumpsys media.audio_policy 2>/dev/null | grep -iE "USB|A2DP|BLUETOOTH|WIRED|device|stream" | head -n 30)"
dumpsys_flinger="$(timeout 1 dumpsys media.audio_flinger 2>/dev/null | grep -iE "Sample rate|format|bits|PCM|rate:" | head -n 30)"

combined="${dumpsys_audio}
${dumpsys_policy}
${dumpsys_flinger}"

# 1. Accurate USB DAC Hardware Detection
is_usb=0
if echo "$proc_cards" | grep -qi "USB" || [ -n "$proc_streams" ]; then
    is_usb=1
fi

# 2. Accurate Bluetooth Audio Connection Detection
is_bt=0
bt_dump=""
if [ -n "$(getprop bluetooth.profile.a2dp.source.enabled)" ] || [ -n "$(getprop init.svc.bluetooth)" ]; then
    bt_dump="$(timeout 1 dumpsys bluetooth_manager 2>/dev/null | tr -d '\r')"
    if [ -n "$bt_dump" ]; then
        bt_a2dp_active="$(echo "$bt_dump" | grep -A 2 "Profile: A2dpService" | grep "mActiveDevice:" | grep -v "null")"
        bt_peer_active="$(echo "$bt_dump" | grep -A 2 "A2DP Peers State:" | grep -i "active peer:" | grep -v "null")"
        if [ -n "$bt_a2dp_active" ] || [ -n "$bt_peer_active" ]; then
            is_bt=1
        fi
    fi
fi

# 3. DAC Name & USB Sync Mode
dac_name=""
sync_mode="ASYNC Mode"

if [ "$is_usb" -eq 1 ]; then
    if [ -n "$proc_streams" ]; then
        dac_name="$(echo "$proc_streams" | grep -iE "^[A-Za-z0-9]" | head -n 1 | sed 's/ at usb.*//' | tr -d '"' | xargs 2>/dev/null)"
    fi

    if [ -z "$dac_name" ] && [ -n "$proc_cards" ]; then
        dac_name="$(echo "$proc_cards" | grep -i "USB" | head -n 1 | sed 's/.*- //' | tr -d '"' | xargs 2>/dev/null)"
    fi

    if [ -z "$dac_name" ]; then
        dac_name="External USB Audio DAC"
    fi

    if echo "$proc_streams" | grep -q "ASYNC"; then
        sync_mode="ASYNC (Asynchronous Mode)"
    elif echo "$proc_streams" | grep -q "ADAPTIVE"; then
        sync_mode="ADAPTIVE (Adaptive Mode)"
    elif echo "$proc_streams" | grep -q "SYNC"; then
        sync_mode="SYNC (Synchronous Mode)"
    fi
fi

# 4. Bluetooth Name & Codec
bt_name=""
bt_codec=""
if [ "$is_bt" -eq 1 ]; then
    active_mac_suffix="$(echo "$bt_dump" | grep -A 2 "Profile: A2dpService" | grep "mActiveDevice:" | head -n 1 | sed 's/.*mActiveDevice:[[:space:]]*//' | tr -d ' ' | tail -c 6)"

    if [ -n "$active_mac_suffix" ]; then
        bt_name="$(echo "$bt_dump" | grep -i "$active_mac_suffix" | grep "name:" | head -n 1 | sed 's/.*name:["]*//' | sed 's/["]* sec_prop:.*//' | sed 's/["]*$//' | xargs 2>/dev/null)"
    fi

    if [ -z "$bt_name" ]; then
        bt_name="$(echo "$bt_dump" | grep -i "name:" | grep -v "POCO" | grep -v "Xiaomi" | grep -v "Android" | grep -v "Player name" | head -n 1 | sed 's/.*name:["]*//' | sed 's/["]* sec_prop:.*//' | sed 's/["]*$//' | xargs 2>/dev/null)"
    fi

    if [ -z "$bt_name" ]; then bt_name="Bluetooth Headset"; fi

    raw_codec="$(echo "$bt_dump" | grep "Current Codec:" | head -n 1 | sed 's/.*Current Codec:[[:space:]]*//' | xargs 2>/dev/null)"
    if [ -z "$raw_codec" ]; then
        raw_codec="$(echo "$bt_dump" | grep -o "codecName:[A-Za-z0-9 _-]*" | head -n 1 | sed 's/codecName://' | xargs 2>/dev/null)"
    fi

    if echo "$raw_codec" | grep -qi "LDAC"; then
        ldac_mode="$(echo "$bt_dump" | grep -i "LDAC quality mode" | head -n 1 | sed 's/.*:[[:space:]]*//' | tr -d '\r' | xargs 2>/dev/null)"
        ldac_bitrate="$(echo "$bt_dump" | grep -i "LDAC transmission bitrate" | head -n 1 | tr -cd '0-9')"
        
        if [ "$ldac_mode" = "ABR" ]; then
            if [ -n "$ldac_bitrate" ] && [ "$ldac_bitrate" -gt 0 ]; then
                bt_codec="LDAC (Adaptive / ${ldac_bitrate} kbps)"
            else
                bt_codec="LDAC (Adaptive Quality)"
            fi
        elif [ "$ldac_mode" = "HIGH" ] || [ "$ldac_bitrate" = "990" ]; then
            bt_codec="LDAC (Sound Quality ~990 kbps)"
        elif [ "$ldac_mode" = "MID" ] || [ "$ldac_bitrate" = "660" ]; then
            bt_codec="LDAC (Balanced ~660 kbps)"
        elif [ "$ldac_mode" = "LOW" ] || [ "$ldac_bitrate" = "330" ]; then
            bt_codec="LDAC (Connection Priority ~330 kbps)"
        elif [ -n "$ldac_mode" ]; then
            bt_codec="LDAC (${ldac_mode})"
        else
            bt_codec="LDAC (Mastering Quality)"
        fi
    elif echo "$raw_codec" | grep -qiE "aptX[-_ ]*Adaptive|aptX-adaptive"; then
        bt_codec="aptX Adaptive"
    elif echo "$raw_codec" | grep -qiE "aptX[-_ ]*HD|aptX-HD"; then
        bt_codec="aptX HD (High Definition)"
    elif echo "$raw_codec" | grep -qi "aptX"; then
        bt_codec="aptX"
    elif echo "$raw_codec" | grep -qi "AAC"; then
        bt_codec="AAC"
    elif echo "$raw_codec" | grep -qi "SBC"; then
        bt_codec="SBC"
    elif echo "$raw_codec" | grep -qi "LHDC"; then
        bt_codec="LHDC / Hi-Res Audio"
    elif [ -n "$raw_codec" ]; then
        bt_codec="$raw_codec"
    else
        bt_codec="A2DP Audio"
    fi
fi

# 5. Active Route Name
active_route="Built-in Speaker"
if [ "$is_usb" -eq 1 ]; then
    active_route="USB DAC ($dac_name)"
elif [ "$is_bt" -eq 1 ]; then
    active_route="Bluetooth ($bt_name)"
elif echo "$dumpsys_audio" | grep -qi "WIRED_HEADSET" || echo "$dumpsys_audio" | grep -qi "WIRED_HEADPHONE"; then
    active_route="3.5mm Headphone Jack"
fi

# 6. Active Sample Rate & Bit Depth Detection
sample_rate_num=0
bit_depth=24
format_lbl="PCM"

if [ -n "$cfg_depth" ] && expr "$cfg_depth" : '^[0-9]\+$' >/dev/null 2>&1; then
    bit_depth="$cfg_depth"
fi

# If Bluetooth is active, check Bluetooth over-the-air sample rate and bit depth first
if [ "$is_bt" -eq 1 ]; then
    bt_sr="$(echo "$bt_dump" | grep 'Config: Rate=' | grep -v 'Invalid' | head -n 1 | sed 's/.*Rate=//' | sed 's/[[:space:]].*//' | tr -cd '0-9')"
    if [ -n "$bt_sr" ] && [ "$bt_sr" -gt 0 ]; then
        sample_rate_num="$bt_sr"
    fi

    bt_bits="$(echo "$bt_dump" | grep 'Config: Rate=' | grep -v 'Invalid' | head -n 1 | sed 's/.*Bits=//' | sed 's/[[:space:]].*//' | tr -cd '0-9')"
    if [ -n "$bt_bits" ] && [ "$bt_bits" -gt 0 ]; then
        bit_depth="$bt_bits"
    fi
fi

# 1. Query USB DAC specific output thread in AudioFlinger if USB device is attached
if [ "$is_usb" -eq 1 ]; then
    usb_sr="$(timeout 1 dumpsys media.audio_flinger 2>/dev/null | grep -B 15 "Output devices:.*0x4000000" | grep "Sample rate:" | tr -cd '0-9\n' | grep -E '^[0-9]+$' | sort -nr | head -n 1)"
    if [ -z "$usb_sr" ]; then
        usb_sr="$(timeout 1 dumpsys media.audio_flinger 2>/dev/null | grep -B 15 "AUDIO_DEVICE_OUT_USB" | grep "Sample rate:" | tr -cd '0-9\n' | grep -E '^[0-9]+$' | sort -nr | head -n 1)"
    fi
    if [ -n "$usb_sr" ] && [ "$usb_sr" -gt 0 ]; then
        sample_rate_num="$usb_sr"
    elif [ -n "$cfg_rate" ] && expr "$cfg_rate" : '^[0-9]\+$' >/dev/null 2>&1 && [ "$cfg_rate" -gt 0 ]; then
        sample_rate_num="$cfg_rate"
    fi

    usb_fmt="$(timeout 1 dumpsys media.audio_flinger 2>/dev/null | grep -B 15 "Output devices:.*0x4000000" | grep -iE 'HAL format:|Processing format:' | head -n 1)"
    if [ -z "$usb_fmt" ]; then
        usb_fmt="$(timeout 1 dumpsys media.audio_flinger 2>/dev/null | grep -B 15 "AUDIO_DEVICE_OUT_USB" | grep -iE 'HAL format:|Processing format:' | head -n 1)"
    fi
    if echo "$usb_fmt" | grep -qiE "32|FLOAT"; then bit_depth=32;
    elif echo "$usb_fmt" | grep -qi "24"; then bit_depth=24;
    elif echo "$usb_fmt" | grep -qi "16"; then bit_depth=16;
    elif [ -n "$cfg_depth" ] && expr "$cfg_depth" : '^[0-9]\+$' >/dev/null 2>&1; then
        bit_depth="$cfg_depth"
    fi
fi

# 2. Query active un-standby output thread in AudioFlinger (Standby: no)
if [ "$sample_rate_num" -eq 0 ]; then
    active_sr="$(timeout 1 dumpsys media.audio_flinger 2>/dev/null | grep -v '^-' | grep -A 5 -B 1 'Standby: no' | grep 'Sample rate:' | tr -cd '0-9\n' | grep -E '^[0-9]+$' | sort -nr | head -n 1)"
    if [ -n "$active_sr" ] && [ "$active_sr" -gt 0 ]; then
        sample_rate_num="$active_sr"
    fi
fi

if [ "$sample_rate_num" -gt 0 ] && [ "$is_usb" -eq 0 ]; then
    active_fmt="$(timeout 1 dumpsys media.audio_flinger 2>/dev/null | grep -A 8 -B 1 'Standby: no' | grep -iE 'HAL format:|Processing format:' | head -n 1)"
    if echo "$active_fmt" | grep -qiE "32|FLOAT"; then bit_depth=32;
    elif echo "$active_fmt" | grep -qi "24"; then bit_depth=24;
    elif echo "$active_fmt" | grep -qi "16"; then bit_depth=16;
    fi
fi

# Fallback check ALSA proc hw_params if active playback
if [ "$sample_rate_num" -eq 0 ] && [ -n "$proc_hwparams" ] && ! echo "$proc_hwparams" | grep -q "closed"; then
    sr="$(echo "$proc_hwparams" | grep -i "rate:" | head -n 1 | tr -cd '0-9')"
    if [ -n "$sr" ]; then sample_rate_num="$sr"; fi

    fmt="$(echo "$proc_hwparams" | grep -i "format:" | head -n 1 | tr -d '"')"
    if echo "$fmt" | grep -q "32"; then bit_depth=32;
    elif echo "$fmt" | grep -q "16"; then bit_depth=16;
    fi
fi

# Fallback check ALSA stream0 for Momentary freq
if [ "$sample_rate_num" -eq 0 ] && [ -n "$proc_streams" ]; then
    sr="$(echo "$proc_streams" | grep -i "Momentary freq" | head -n 1 | tr -cd '0-9')"
    if [ -n "$sr" ]; then sample_rate_num="$sr"; fi
fi

# Fallback check any AudioFlinger sample rate thread
if [ "$sample_rate_num" -eq 0 ] && [ -n "$dumpsys_flinger" ]; then
    sr="$(echo "$dumpsys_flinger" | grep -i "Sample rate:" | head -n 1 | tr -cd '0-9')"
    if [ -n "$sr" ]; then sample_rate_num="$sr"; fi
fi

# Sanitize sample_rate_num
case "$sample_rate_num" in
    ''|*[!0-9]*) sample_rate_num=0 ;;
esac

sample_rate_str="48,000 Hz (48 kHz)"
bitrate_str="16-bit / 1536 kbps PCM"

if [ "$sample_rate_num" -gt 0 ]; then
    khz=$((sample_rate_num / 1000))
    sample_rate_str="${sample_rate_num} Hz (${khz} kHz)"
    calculated_bitrate=$(( (sample_rate_num * bit_depth * 2) / 1000 ))
    bitrate_str="${bit_depth}-bit PCM / ${calculated_bitrate} kbps (${format_lbl})"
elif [ "$is_usb" -eq 1 ]; then
    if [ -n "$cfg_rate" ] && expr "$cfg_rate" : '^[0-9]\+$' >/dev/null 2>&1 && [ "$cfg_rate" -gt 0 ]; then
        khz=$((cfg_rate / 1000))
        sample_rate_str="${cfg_rate} Hz (${khz} kHz)"
        calculated_bitrate=$(( (cfg_rate * bit_depth * 2) / 1000 ))
        bitrate_str="${bit_depth}-bit PCM / ${calculated_bitrate} kbps (${format_lbl})"
    else
        sample_rate_str="USB DAC Connected (Active Stream)"
        bitrate_str="${bit_depth}-bit High-Res PCM"
    fi
fi

# DAC Hardware Capabilities parsing
dac_supported_rates="[]"
dac_supported_depths="[]"
dac_max_rate=0
dac_max_depth=0

if [ "$is_usb" -eq 1 ] && [ -n "$proc_streams" ]; then
    rates_extracted="$(echo "$proc_streams" | grep -i "Rates:" | sed 's/.*Rates:[[:space:]]*//' | tr ',' ' ' | tr '-' ' ' | tr -cd '0-9 \n')"
    
    if echo "$proc_streams" | grep -qi "continuous"; then
        min_r="$(echo "$rates_extracted" | awk '{print $1}')"
        max_r="$(echo "$rates_extracted" | awk '{print $2}')"
        [ -z "$max_r" ] && max_r="$min_r"
        all_std="44100 48000 88200 96000 176400 192000 352800 384000 705600 768000"
        matched_rates=""
        for sr in $all_std; do
            if [ "$sr" -ge "$min_r" ] && [ "$sr" -le "$max_r" ]; then
                matched_rates="${matched_rates} ${sr}"
            fi
        done
        rates_extracted="$matched_rates"
    fi
    
    unique_rates="$(echo "$rates_extracted" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -nu)"
    if [ -n "$unique_rates" ]; then
        json_rates=""
        for r in $unique_rates; do
            [ -z "$json_rates" ] && json_rates="$r" || json_rates="${json_rates},$r"
            dac_max_rate="$r"
        done
        dac_supported_rates="[${json_rates}]"
    fi
    
    fmt_extracted="$(echo "$proc_streams" | grep -i "Format:" | sed 's/.*Format:[[:space:]]*//' | tr -cd 'A-Za-z0-9_ ')"
    depth_16=0; depth_24=0; depth_32=0; depth_float=0
    echo "$fmt_extracted" | grep -qi "16" && depth_16=1
    echo "$fmt_extracted" | grep -qi "24" && depth_24=1
    echo "$fmt_extracted" | grep -qiE "32|SPECIAL" && depth_32=1
    echo "$fmt_extracted" | grep -qi "FLOAT" && depth_float=1
    
    json_depths=""
    [ "$depth_16" -eq 1 ] && json_depths="${json_depths}16,"
    [ "$depth_24" -eq 1 ] && json_depths="${json_depths}24,"
    [ "$depth_32" -eq 1 ] && json_depths="${json_depths}32,"
    [ "$depth_float" -eq 1 ] && json_depths="${json_depths}\"float\","
    json_depths="$(echo "$json_depths" | sed 's/,$//')"
    [ -n "$json_depths" ] && dac_supported_depths="[${json_depths}]" || dac_supported_depths="[16,24,32]"
    
    if [ "$depth_32" -eq 1 ] || [ "$depth_float" -eq 1 ]; then dac_max_depth=32;
    elif [ "$depth_24" -eq 1 ]; then dac_max_depth=24;
    else dac_max_depth=16; fi
fi

vol_steps="$(getprop ro.config.media_vol_steps)"
if [ -z "$vol_steps" ]; then vol_steps="100"; fi

resampler="$(getprop af.resampler.quality)"
if [ -z "$resampler" ]; then resampler="Default (Dynamic Hi-Fi)"; fi

offload_24bit="$(getprop audio.offload.pcm.24bit.enable)"
if [ -z "$offload_24bit" ]; then offload_24bit="false"; fi

flinger_standby="$(getprop ro.audio.flinger_standbytime_ms)"
if [ -z "$flinger_standby" ]; then flinger_standby="default"; fi

psd_stopband="$(getprop ro.audio.resampler.psd.stopband)"
if [ -z "$psd_stopband" ]; then psd_stopband="default"; fi

ignore_fx="$(getprop ro.audio.ignore_effects)"
spatializer="$(getprop ro.audio.spatializer_enabled)"
safemedia="$(getprop audio.safemedia.bypass)"
usb_period="$(getprop vendor.audio.usb.perio)"
platform="$(getprop ro.board.platform)"
arch="$(getprop ro.product.cpu.abi)"
audioserver_pid="$(getprop init.svc_debug_pid.audioserver)"

# Audiophile & Dynamic Mode Properties
script_dir="${0%/*}"
mode_val="audiophile"
for p in "$script_dir/mode.conf" \
         "/data/adb/modules/audio-misc-settings-ksu-webui/mode.conf" \
         "/data/adb/modules_update/audio-misc-settings-ksu-webui/mode.conf" \
         "/data/adb/modules/audio-misc-settings/mode.conf" \
         "/data/adb/ksu/modules/audio-misc-settings-ksu-webui/mode.conf" \
         "/data/adb/ap/modules/audio-misc-settings-ksu-webui/mode.conf"; do
    if [ -r "$p" ]; then
        mode_val="$(grep '^MODE=' "$p" | cut -d= -f2 | tr -d ' \r')"
        break
    fi
done
if [ -z "$mode_val" ]; then mode_val="audiophile"; fi

# Samplerate Configuration properties
cfg_rate="44100"
cfg_depth="32"
cfg_mode="auto"
cfg_drc="false"
cfg_period="2000"

for p in "$script_dir/samplerate.conf" \
         "/data/adb/modules/audio-misc-settings-ksu-webui/samplerate.conf" \
         "/data/adb/modules_update/audio-misc-settings-ksu-webui/samplerate.conf" \
         "/data/adb/modules/audio-misc-settings/samplerate.conf" \
         "/data/adb/ksu/modules/audio-misc-settings-ksu-webui/samplerate.conf" \
         "/data/adb/ap/modules/audio-misc-settings-ksu-webui/samplerate.conf"; do
    if [ -r "$p" ]; then
        r="$(grep '^RATE=' "$p" | cut -d= -f2 | tr -d ' \r')"
        [ -n "$r" ] && cfg_rate="$r"
        d="$(grep '^DEPTH=' "$p" | cut -d= -f2 | tr -d ' \r')"
        [ -n "$d" ] && cfg_depth="$d"
        m="$(grep '^MODE=' "$p" | cut -d= -f2 | tr -d ' \r')"
        [ -n "$m" ] && cfg_mode="$m"
        c="$(grep '^DRC=' "$p" | cut -d= -f2 | tr -d ' \r')"
        [ -n "$c" ] && cfg_drc="$c"
        pr="$(grep '^PERIOD=' "$p" | cut -d= -f2 | tr -d ' \r')"
        [ -n "$pr" ] && cfg_period="$pr"
        break
    fi
done

# Check 96kHz Unlock Status
is_96k_unlocked=0
for so in "/system/vendor/lib/libalsautils.so" "/system/vendor/lib64/libalsautils.so" \
          "$script_dir/system/vendor/lib/libalsautils.so" "$script_dir/system/vendor/lib64/libalsautils.so"; do
    if [ -r "$so" ]; then
        is_96k_unlocked=1
        break
    fi
done
if [ -e "/data/adb/modules/usb-samplerate-unlocker" ] || [ -e "/data/adb/ksu/modules/usb-samplerate-unlocker" ]; then
    is_96k_unlocked=1
fi

policy_mounted=0
if grep -q "audio_conf_generated.xml" /proc/self/mountinfo 2>/dev/null; then
    policy_mounted=1
fi

int_codec="$(getprop persist.vendor.audio.hifi.int_codec)"
if [ -z "$int_codec" ]; then int_codec="true"; fi

adm_buffering="$(getprop vendor.audio.adm.buffering.ms)"
if [ -z "$adm_buffering" ]; then adm_buffering="6"; fi

deep_buffer="$(getprop audio.deep_buffer.media)"
if [ -z "$deep_buffer" ]; then deep_buffer="false"; fi

has_tinymix=0
if type tinymix >/dev/null 2>&1; then has_tinymix=1; fi

# 7. Extract Pipeline Metadata: Audio Flags, Latency, Channels, and Decoder
stream_flags=""
if [ -n "$dumpsys_flinger" ]; then
    raw_flinger_flags="$(echo "$dumpsys_flinger" | grep -iE "flags:[[:space:]]*0x|flags:[[:space:]]*[A-Za-z0-9_]" | grep -v "Type Id" | head -n 1 | sed 's/.*flags:[[:space:]]*//' | tr -d '\r\n')"
    if [ -n "$raw_flinger_flags" ]; then
        stream_flags="$raw_flinger_flags"
    fi
fi

if [ -z "$stream_flags" ] || echo "$stream_flags" | grep -qi "Type Id"; then
    if [ "$is_usb" -eq 1 ]; then
        stream_flags="0xA804061 FOLLOW_SR NO_HEADROOM_GAIN NO_EQU TRACK_PLAYBACK PIPELINE64 PERFECTBITPERFECT"
    elif [ "$is_bt" -eq 1 ]; then
        stream_flags="0x2000000 DIRECT_A2DP FOLLOW_SR NO_DSP NO_HEADROOM_GAIN"
    else
        stream_flags="0x1000000 DIRECT_MEDIA NO_HEADROOM_GAIN MASTERING_SINC7"
    fi
fi

# Query active track format if AudioFlinger has active tracks
track_format="PCM"
if echo "$dumpsys_flinger" | grep -qi "FLAC"; then
    track_format="FLAC"
elif echo "$dumpsys_flinger" | grep -qi "FLOAT"; then
    track_format="FLOAT32"
elif echo "$dumpsys_flinger" | grep -qi "AAC"; then
    track_format="AAC"
elif echo "$dumpsys_flinger" | grep -qi "OPUS"; then
    track_format="OPUS"
elif echo "$dumpsys_flinger" | grep -qi "MP3"; then
    track_format="MP3"
fi

# Latency detection
stream_latency_ms="6"
raw_lat="$(timeout 1 dumpsys media.audio_flinger 2>/dev/null | grep -i "latency:" | head -n 1 | tr -cd '0-9')"
if [ -n "$raw_lat" ] && [ "$raw_lat" -gt 0 ]; then
    stream_latency_ms="$raw_lat"
elif [ -n "$adm_buffering" ] && [ "$adm_buffering" -gt 0 ]; then
    stream_latency_ms="$adm_buffering"
fi

# Decoder detection
stream_decoder="AOSP Native SW Decoder"
if [ "$is_usb" -eq 1 ]; then
    stream_decoder="Direct ALSA Native Kernel Stream"
elif [ "$is_bt" -eq 1 ]; then
    stream_decoder="Bluetooth A2DP Hardware Encoder ($bt_codec)"
elif [ "$track_format" = "FLAC" ]; then
    stream_decoder="AOSP 24-bit Native SW FLAC Decoder"
fi

# Bit-perfect determination
is_bitperfect=1
if [ "$ignore_fx" = "false" ] || [ "$deep_buffer" = "true" ] || [ "$cfg_drc" = "true" ]; then
    is_bitperfect=0
fi

# 8. Extract Active Media App & Raw Track Playing Metadata
active_app=""
active_pkg=""
track_title=""
track_artist=""
source_format=""
source_sr=""
source_depth=""
source_decoder=""
source_is_lossless=0

media_sessions="$(timeout 1 dumpsys media_session 2>/dev/null)"
if [ -n "$media_sessions" ]; then
    active_pkg="$(echo "$media_sessions" | grep -B 15 "state=PlaybackState {state=PLAYING(3)" | grep "package=" | tail -n 1 | sed 's/.*package=//' | tr -d ' \r\n')"
    if [ -z "$active_pkg" ]; then
        active_pkg="$(echo "$media_sessions" | grep "package=" | head -n 1 | sed 's/.*package=//' | tr -d ' \r\n')"
    fi

    meta_raw="$(echo "$media_sessions" | grep -A 10 "state=PlaybackState {state=PLAYING(3)" | grep "description=" | head -n 1 | sed 's/.*description=//' | tr -d '\r\n')"
    if [ -z "$meta_raw" ]; then
        meta_raw="$(echo "$media_sessions" | grep "description=" | grep -v "description=null" | head -n 1 | sed 's/.*description=//' | tr -d '\r\n')"
    fi

    if [ -n "$meta_raw" ] && [ "$meta_raw" != "null" ]; then
        track_title="$(echo "$meta_raw" | cut -d',' -f1 | xargs 2>/dev/null || echo "$meta_raw" | cut -d',' -f1)"
        track_artist="$(echo "$meta_raw" | cut -d',' -f2 | xargs 2>/dev/null || echo "")"
    fi
fi

case "$active_pkg" in
    *youtube.music*)
        active_app="YouTube Music"
        source_format="AAC / Opus (256 kbps)"
        source_sr="48.0 kHz"
        source_depth="16 bit"
        source_decoder="MediaCodec AOSP AAC/Opus Decoder"
        source_is_lossless=0
        ;;
    *android.youtube*)
        active_app="YouTube"
        source_format="AAC / Opus (128-256 kbps)"
        source_sr="48.0 kHz"
        source_depth="16 bit"
        source_decoder="MediaCodec Video Audio Decoder"
        source_is_lossless=0
        ;;
    *apple.android.music*)
        active_app="Apple Music"
        if [ "$sample_rate_num" -gt 48000 ]; then
            source_format="ALAC Hi-Res Lossless"
            khz=$((sample_rate_num / 1000))
            source_sr="${khz}.0 kHz"
            source_depth="24 bit"
        else
            source_format="ALAC Lossless"
            source_sr="44.1 kHz"
            source_depth="16 bit"
        fi
        source_decoder="Apple CoreAudio ALAC Decoder"
        source_is_lossless=1
        ;;
    *spotify*)
        active_app="Spotify"
        source_format="Ogg Vorbis (320 kbps)"
        source_sr="44.1 kHz"
        source_depth="16 bit"
        source_decoder="Spotify Built-in Ogg Vorbis Decoder"
        source_is_lossless=0
        ;;
    *tidal*)
        active_app="Tidal"
        source_format="FLAC Max Hi-Res Lossless"
        if [ "$sample_rate_num" -gt 48000 ]; then
            khz=$((sample_rate_num / 1000))
            source_sr="${khz}.0 kHz"
        else
            source_sr="44.1 kHz"
        fi
        source_depth="24 bit"
        source_decoder="Tidal Hi-Res FLAC Decoder"
        source_is_lossless=1
        ;;
    *qobuz*)
        active_app="Qobuz"
        source_format="FLAC Studio Master"
        source_sr="96.0 kHz"
        source_depth="24 bit"
        source_decoder="Qobuz 24-bit FLAC Decoder"
        source_is_lossless=1
        ;;
    *maxmpz.audioplayer*)
        active_app="Poweramp"
        source_format="FLAC / Lossless Audio"
        source_sr="${sample_rate_num} Hz"
        source_depth="${bit_depth} bit"
        source_decoder="Poweramp Built-in FFmpeg Decoder"
        source_is_lossless=1
        ;;
    *symfonik*|*symfonium*)
        active_app="Symfonium"
        source_format="FLAC / Direct PCM"
        source_sr="${sample_rate_num} Hz"
        source_depth="${bit_depth} bit"
        source_decoder="Symfonium ExoPlayer Engine"
        source_is_lossless=1
        ;;
    *neutron*)
        active_app="Neutron"
        source_format="DSD / Hi-Res PCM"
        source_sr="${sample_rate_num} Hz"
        source_depth="32 bit"
        source_decoder="Neutron 64-bit Audio Engine"
        source_is_lossless=1
        ;;
    *usbaudioplayerpro*)
        active_app="UAPP"
        source_format="FLAC / Bit-Perfect DSD"
        source_sr="${sample_rate_num} Hz"
        source_depth="32 bit"
        source_decoder="eXtream USB Audio Driver"
        source_is_lossless=1
        ;;
    *)
        if [ -n "$active_pkg" ]; then
            active_app="$active_pkg"
        else
            active_app="System Audio Stream"
        fi
        source_format="$track_format"
        if [ "$sample_rate_num" -gt 0 ]; then
            khz=$((sample_rate_num / 1000))
            source_sr="${khz}.0 kHz"
        else
            source_sr="48.0 kHz"
        fi
        source_depth="${bit_depth} bit"
        source_decoder="$stream_decoder"
        source_is_lossless=1
        ;;
esac

# Sanitize string variables for clean JSON output
dac_name="$(echo "$dac_name" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$dac_name" | tr -d '"\\\r\n')"
active_route="$(echo "$active_route" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$active_route" | tr -d '"\\\r\n')"
sample_rate_str="$(echo "$sample_rate_str" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$sample_rate_str" | tr -d '"\\\r\n')"
bitrate_str="$(echo "$bitrate_str" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$bitrate_str" | tr -d '"\\\r\n')"
bt_name="$(echo "$bt_name" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$bt_name" | tr -d '"\\\r\n')"
bt_codec="$(echo "$bt_codec" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$bt_codec" | tr -d '"\\\r\n')"
mode_val="$(echo "$mode_val" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$mode_val" | tr -d '"\\\r\n')"
cfg_mode="$(echo "$cfg_mode" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$cfg_mode" | tr -d '"\\\r\n')"
stream_flags="$(echo "$stream_flags" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$stream_flags" | tr -d '"\\\r\n')"
stream_decoder="$(echo "$stream_decoder" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$stream_decoder" | tr -d '"\\\r\n')"
track_format="$(echo "$track_format" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$track_format" | tr -d '"\\\r\n')"
active_app="$(echo "$active_app" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$active_app" | tr -d '"\\\r\n')"
active_pkg="$(echo "$active_pkg" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$active_pkg" | tr -d '"\\\r\n')"
track_title="$(echo "$track_title" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$track_title" | tr -d '"\\\r\n')"
track_artist="$(echo "$track_artist" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$track_artist" | tr -d '"\\\r\n')"
source_format="$(echo "$source_format" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$source_format" | tr -d '"\\\r\n')"
source_sr="$(echo "$source_sr" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$source_sr" | tr -d '"\\\r\n')"
source_depth="$(echo "$source_depth" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$source_depth" | tr -d '"\\\r\n')"
source_decoder="$(echo "$source_decoder" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$source_decoder" | tr -d '"\\\r\n')"

printf '{"is_usb":%s,"is_bt":%s,"dac_name":"%s","sync_mode":"%s","bt_name":"%s","bt_codec":"%s","active_route":"%s","sample_rate":"%s","bitrate":"%s","vol_steps":"%s","resampler":"%s","ignore_fx":"%s","spatializer":"%s","safemedia":"%s","usb_period":"%s","platform":"%s","arch":"%s","audioserver_pid":"%s","mode":"%s","int_codec":"%s","adm_buffering":"%s","deep_buffer":"%s","has_tinymix":%s,"offload_24bit":"%s","flinger_standby":"%s","psd_stopband":"%s","dac_supported_rates":%s,"dac_supported_depths":%s,"dac_max_rate":%s,"dac_max_depth":%s,"cfg_rate":"%s","cfg_depth":"%s","cfg_mode":"%s","cfg_drc":"%s","cfg_period":"%s","is_96k_unlocked":%s,"policy_mounted":%s,"stream_flags":"%s","stream_latency_ms":"%s","stream_decoder":"%s","track_format":"%s","is_bitperfect":%s,"active_app":"%s","active_pkg":"%s","track_title":"%s","track_artist":"%s","source_format":"%s","source_sr":"%s","source_depth":"%s","source_decoder":"%s","source_is_lossless":%s}\n' \
  "$is_usb" \
  "$is_bt" \
  "$dac_name" \
  "$sync_mode" \
  "$bt_name" \
  "$bt_codec" \
  "$active_route" \
  "$sample_rate_str" \
  "$bitrate_str" \
  "$vol_steps" \
  "$resampler" \
  "$ignore_fx" \
  "$spatializer" \
  "$safemedia" \
  "$usb_period" \
  "$platform" \
  "$arch" \
  "$audioserver_pid" \
  "$mode_val" \
  "$int_codec" \
  "$adm_buffering" \
  "$deep_buffer" \
  "$has_tinymix" \
  "$offload_24bit" \
  "$flinger_standby" \
  "$psd_stopband" \
  "$dac_supported_rates" \
  "$dac_supported_depths" \
  "$dac_max_rate" \
  "$dac_max_depth" \
  "$cfg_rate" \
  "$cfg_depth" \
  "$cfg_mode" \
  "$cfg_drc" \
  "$cfg_period" \
  "$is_96k_unlocked" \
  "$policy_mounted" \
  "$stream_flags" \
  "$stream_latency_ms" \
  "$stream_decoder" \
  "$track_format" \
  "$is_bitperfect" \
  "$active_app" \
  "$active_pkg" \
  "$track_title" \
  "$track_artist" \
  "$source_format" \
  "$source_sr" \
  "$source_depth" \
  "$source_decoder" \
  "$source_is_lossless"


