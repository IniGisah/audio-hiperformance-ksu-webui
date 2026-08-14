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

# Direct query active un-standby output thread in AudioFlinger (Standby: no)
if [ "$sample_rate_num" -eq 0 ]; then
    active_sr="$(timeout 1 dumpsys media.audio_flinger 2>/dev/null | grep -v '^-' | grep -A 5 -B 1 'Standby: no' | grep 'Sample rate:' | tr -cd '0-9\n' | grep -E '^[0-9]+$' | sort -nr | head -n 1)"
    if [ -n "$active_sr" ] && [ "$active_sr" -gt 0 ]; then
        sample_rate_num="$active_sr"
    fi
fi

active_fmt="$(timeout 1 dumpsys media.audio_flinger 2>/dev/null | grep -A 8 -B 1 'Standby: no' | grep -iE 'HAL format:|Processing format:' | head -n 1)"
if echo "$active_fmt" | grep -qiE "32|FLOAT"; then bit_depth=32;
elif echo "$active_fmt" | grep -qi "24"; then bit_depth=24;
elif echo "$active_fmt" | grep -qi "16"; then bit_depth=16;
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
    sample_rate_str="USB DAC Connected (Active Stream)"
    bitrate_str="24-bit / 4608 kbps High-Res PCM"
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
         "/data/adb/modules/audio-misc-settings/mode.conf"; do
    if [ -r "$p" ]; then
        mode_val="$(grep '^MODE=' "$p" | cut -d= -f2 | tr -d ' \r')"
        break
    fi
done
if [ -z "$mode_val" ]; then mode_val="audiophile"; fi

int_codec="$(getprop persist.vendor.audio.hifi.int_codec)"
if [ -z "$int_codec" ]; then int_codec="true"; fi

adm_buffering="$(getprop vendor.audio.adm.buffering.ms)"
if [ -z "$adm_buffering" ]; then adm_buffering="6"; fi

deep_buffer="$(getprop audio.deep_buffer.media)"
if [ -z "$deep_buffer" ]; then deep_buffer="false"; fi

has_tinymix=0
if type tinymix >/dev/null 2>&1; then has_tinymix=1; fi

# Sanitize string variables for clean JSON output
dac_name="$(echo "$dac_name" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$dac_name" | tr -d '"\\\r\n')"
active_route="$(echo "$active_route" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$active_route" | tr -d '"\\\r\n')"
sample_rate_str="$(echo "$sample_rate_str" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$sample_rate_str" | tr -d '"\\\r\n')"
bitrate_str="$(echo "$bitrate_str" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$bitrate_str" | tr -d '"\\\r\n')"
bt_name="$(echo "$bt_name" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$bt_name" | tr -d '"\\\r\n')"
bt_codec="$(echo "$bt_codec" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$bt_codec" | tr -d '"\\\r\n')"
mode_val="$(echo "$mode_val" | tr -d '"\\\r\n' | xargs 2>/dev/null || echo "$mode_val" | tr -d '"\\\r\n')"

printf '{"is_usb":%s,"is_bt":%s,"dac_name":"%s","sync_mode":"%s","bt_name":"%s","bt_codec":"%s","active_route":"%s","sample_rate":"%s","bitrate":"%s","vol_steps":"%s","resampler":"%s","ignore_fx":"%s","spatializer":"%s","safemedia":"%s","usb_period":"%s","platform":"%s","arch":"%s","audioserver_pid":"%s","mode":"%s","int_codec":"%s","adm_buffering":"%s","deep_buffer":"%s","has_tinymix":%s,"offload_24bit":"%s","flinger_standby":"%s","psd_stopband":"%s"}\n' \
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
  "$psd_stopband"

