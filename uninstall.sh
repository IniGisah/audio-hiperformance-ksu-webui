#!/system/bin/sh
# Audio Misc. Settings Uninstallation & Cleanup Script

MODDIR="${0%/*}"

which_resetprop_command() {
    if type resetprop 1>"/dev/null" 2>&1; then
        echo "resetprop"
    elif [ -x "/data/adb/ksu/bin/resetprop" ]; then
        echo "/data/adb/ksu/bin/resetprop"
    elif [ -x "/data/adb/ap/bin/resetprop" ]; then
        echo "/data/adb/ap/bin/resetprop"
    elif type resetprop_phh 1>"/dev/null" 2>&1; then
        echo "resetprop_phh"
    else
        return 1
    fi
    return 0
}

cleanup_audio_settings() {
    resetprop_cmd="$(which_resetprop_command)"

    # 1. Clean persistent and runtime properties
    if [ -n "$resetprop_cmd" ]; then
        for prop in \
            persist.vendor.audio.hifi \
            persist.vendor.audio.hifi.int_codec \
            persist.vendor.audio.misound.disable \
            persist.vendor.audio.supereffect.enable \
            persist.vendor.audio.fpsop.game.effect \
            persist.vendor.audio.fpsop.game.effect.speaker \
            persist.vendor.audio.fpsop.game.effect.switch \
            persist.vendor.audio.game.mode \
            persist.vendor.audio.game_enhance \
            persist.vendor.audio.bose.effect.enable \
            persist.vendor.audio.effectimplenter \
            persist.audio.dolby.enabled \
            persist.bluetooth.sbc_hd_higher_bitrate \
            vendor.audio.adm.buffering.ms \
            audio.deep_buffer.media \
            vendor.audio.usb.perio \
            vendor.audio.usb.out.period_us \
            vendor.audio.usb.out.period_count \
            vendor.audio.effect_policy.support \
            ro.vendor.audio.fweffect \
            audio.safemedia.bypass \
            audio.safemedia.force \
            audio.safemedia.csd.force \
            vendor.audio.flac.sw.decoder.24bit \
            ro.config.media_vol_steps \
            af.resampler.quality \
            ro.audio.resampler.psd.enable_at_samplerate \
            ro.audio.resampler.psd.stopband \
            ro.audio.resampler.psd.halflength \
            ro.audio.resampler.psd.tbwcheat \
            audio.offload.pcm.24bit.enable \
            ro.audio.flinger_standbytime_ms; do
            "$resetprop_cmd" -p --delete "$prop" 1>/dev/null 2>&1
            "$resetprop_cmd" --delete "$prop" 1>/dev/null 2>&1
        done
    fi

    # 2. Restart Tensor AOC daemons if stopped
    setprop ctl.start aocd 1>/dev/null 2>&1
    setprop ctl.start aocxd 1>/dev/null 2>&1

    # 3. Revert tinymix hardware gain settings
    if type tinymix 1>/dev/null 2>&1; then
        tinymix "RX_HPH_PWR_MODE" "ULP" 1>/dev/null 2>&1
        tinymix "WSA_COMP1 Switch" 1 1>/dev/null 2>&1
        tinymix "WSA_COMP2 Switch" 1 1>/dev/null 2>&1
        tinymix "ADC1 Volume" 4 1>/dev/null 2>&1
        tinymix "MultiMedia1 Mixer PRI_TDM_RX_0" 0 1>/dev/null 2>&1
    fi

    # 4. Re-enable packages if disabled on Motorola
    for pkg in com.motorola.dolby.ds3 com.dolby.daxservice com.dolby.daxui com.motorola.dtv com.google.android.apps.wellbeing; do
        pm enable "$pkg" 1>/dev/null 2>&1
    done

    # 5. Delete system volume steps setting
    settings delete system volume_steps_music 1>/dev/null 2>&1

    # 6. Restart audioserver
    if [ -n "$(getprop init.svc.audioserver)" ]; then
        setprop ctl.restart audioserver
        sleep 1.2
        if [ "$(getprop init.svc.audioserver)" != "running" ]; then
            pid="$(getprop init.svc_debug_pid.audioserver)"
            if [ -n "$pid" ]; then
                kill -HUP "$pid" 1>/dev/null 2>&1
            fi
        fi
    fi
}

cleanup_audio_settings

(((sleep 15; cleanup_audio_settings) 0<&- &>"/dev/null" &) &)
