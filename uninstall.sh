#!/system/bin/sh
# Do NOT assume where your module will be located. ALWAYS use $MODDIR if you need to know where this script and module is placed.

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

    # 1. Re-enable Audio Effects framework and Dolby
    if [ -n "$resetprop_cmd" ]; then
        "$resetprop_cmd" --delete ro.audio.ignore_effects 1>/dev/null 2>&1
        "$resetprop_cmd" ro.audio.ignore_effects false 1>/dev/null 2>&1
        "$resetprop_cmd" --delete ro.audio.spatializer_enabled 1>/dev/null 2>&1
        "$resetprop_cmd" ro.audio.spatializer_enabled true 1>/dev/null 2>&1
        "$resetprop_cmd" --delete ro.vendor.audio.dolby.dax.support 1>/dev/null 2>&1
        "$resetprop_cmd" --delete vendor.audio.dolby.control.support 1>/dev/null 2>&1
        "$resetprop_cmd" --delete persist.audio.dolby.enabled 1>/dev/null 2>&1
        "$resetprop_cmd" persist.audio.dolby.enabled true 1>/dev/null 2>&1
    else
        setprop ro.audio.ignore_effects false 1>/dev/null 2>&1
        setprop ro.audio.spatializer_enabled true 1>/dev/null 2>&1
        setprop persist.audio.dolby.enabled true 1>/dev/null 2>&1
    fi

    # 2. Revert module persistent properties stored on device
    if [ -n "$resetprop_cmd" ]; then
        for prop in \
            persist.vendor.audio.hifi \
            persist.vendor.audio.hifi.int_codec \
            persist.bluetooth.sbc_hd_higher_bitrate \
            vendor.audio.adm.buffering.ms \
            audio.deep_buffer.media \
            vendor.audio.usb.perio \
            vendor.audio.usb.out.period_us \
            vendor.audio.usb.out.period_count \
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
            "$resetprop_cmd" --delete "$prop" 1>/dev/null 2>&1
        done
    fi

    # 3. Unmount soundfx live bind mounts
    local d lname
    for d in "lib" "lib64"; do
        for lname in "libvolumelistener.so" "libdlbvol.so"; do
            umount -l "/vendor/${d}/soundfx/${lname}" 1>/dev/null 2>&1
        done
    done

    # 4. Restart Tensor AOC daemons if stopped
    setprop ctl.start aocd 1>/dev/null 2>&1
    setprop ctl.start aocxd 1>/dev/null 2>&1

    # 5. Revert tinymix hardware gain settings
    if type tinymix 1>/dev/null 2>&1; then
        tinymix "RX_HPH_PWR_MODE" "ULP" 1>/dev/null 2>&1
        tinymix "WSA_COMP1 Switch" 1 1>/dev/null 2>&1
        tinymix "WSA_COMP2 Switch" 1 1>/dev/null 2>&1
        tinymix "ADC1 Volume" 4 1>/dev/null 2>&1
        tinymix "MultiMedia1 Mixer PRI_TDM_RX_0" 0 1>/dev/null 2>&1
    fi

    # 6. Re-enable packages if disabled
    for pkg in com.motorola.dolby.ds3 com.dolby.daxservice com.dolby.daxui com.motorola.dtv com.google.android.apps.wellbeing; do
        pm enable "$pkg" 1>/dev/null 2>&1
    done

    # 7. Delete system volume steps setting
    settings delete system volume_steps_music 1>/dev/null 2>&1

    # 8. Restart audioserver to apply restored audio effect framework
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

# Run immediate cleanup
cleanup_audio_settings

# Run delayed cleanup in an orphan background process to ensure settings service & property changes take effect after manager uninstalls
(((sleep 15; cleanup_audio_settings) 0<&- &>"/dev/null" &) &)

