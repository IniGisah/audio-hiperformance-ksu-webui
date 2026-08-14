#!/system/bin/sh

# sleep 31 secs needed for "settings" commands to become effective
# and make volume medial steps to be 100 if a volume steps facility is used

function which_resetprop_command()
{
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

function additionalSettings()
{
    local force_restart_server=0
    local resetprop_command="`which_resetprop_command`"
    local d lname

    # Re-enforce audio effects bypass if PHH toggle is set
    if [ "`getprop persist.sys.phh.disable_audio_effects`" = "0" ]; then
        if [ -n "$resetprop_command" ]; then
            "$resetprop_command" --delete ro.audio.ignore_effects 1>"/dev/null" 2>&1
            "$resetprop_command" ro.audio.ignore_effects true
            force_restart_server=1
        else
            return 1
        fi
    fi

    # Stop Tensor device's AOC daemons for reducing significant jitter
    for svc in aocd aocxd; do
        if [ "`getprop init.svc.${svc}`" = "running" ]; then
            setprop ctl.stop "$svc"
            force_restart_server=1
        fi
    done

    # Nullify volume listeners / Dolby volume compressors via bind-mount
    for d in "lib" "lib64"; do
        for lname in "libvolumelistener.so" "libdlbvol.so"; do
            if [ -s "/vendor/${d}/soundfx/${lname}" ]; then
                mount -o bind "/dev/null" "/vendor/${d}/soundfx/${lname}"
                force_restart_server=1
            fi
        done
    done

    # Force disabling spatializer if OS reverted the setting during boot
    if [ "`getprop ro.audio.spatializer_enabled`" = "true" ]; then
        if [ -n "$resetprop_command" ]; then
            "$resetprop_command" --delete ro.audio.spatializer_enabled 1>"/dev/null" 2>&1
            "$resetprop_command" ro.audio.spatializer_enabled false
            force_restart_server=1
        else
            return 1
        fi
    fi

    if [ "$force_restart_server" = "1" ]; then
        if [ -n "`getprop init.svc.audioserver`" ]; then
            setprop ctl.restart audioserver
            sleep 1.2
            if [ "`getprop init.svc.audioserver`" != "running" ]; then
                local pid="`getprop init.svc_debug_pid.audioserver`"
                if [ -n "$pid" ]; then
                    kill -HUP $pid 1>"/dev/null" 2>&1
                fi
            fi
        fi
    fi

    settings put system volume_steps_music 100

    MODDIR="${0%/*}"
    if [ -f "$MODDIR/set_audio_mode.sh" ]; then
        sh "$MODDIR/set_audio_mode.sh" apply >/dev/null 2>&1
    fi
}

(((sleep 31; additionalSettings)  0<&- &>"/dev/null" &) &)


