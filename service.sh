#!/system/bin/sh

# Audio Misc. Settings service runner
# Sets 100 volume steps and safe audiophile parameters after system initialization

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
    
    # Stop Tensor device's AOC daemons on Pixel devices for reducing significant jitter
    for svc in aocd aocxd; do
        if [ "`getprop init.svc.${svc}`" = "running" ]; then
            setprop ctl.stop "$svc"
            force_restart_server=1
        fi
    done
    
    # Apply safe pure-audio properties if resetprop is available
    local resetprop_command="`which_resetprop_command`"
    if [ -n "$resetprop_command" ]; then
        "$resetprop_command" vendor.audio.effect_policy.support false 1>"/dev/null" 2>&1
        "$resetprop_command" ro.vendor.audio.fweffect false 1>"/dev/null" 2>&1
    fi

    # Set 100 volume steps for fine volume control
    local AndroidVersion="`getprop ro.system.build.version.release`"
    local MIUI="`getprop ro.miui.ui.version.code`"
    local Moto="`getprop ro.mot.build.customerid`"
    
    if [ -z "$MIUI" ] && [ -z "$Moto" ]; then
        settings put system volume_steps_music 100 2>/dev/null
    fi

    # Apply active Audio Mode (Audiophile vs Power Saver) & tinymix hardware gain
    MODDIR="${0%/*}"
    if [ -f "$MODDIR/set_audio_mode.sh" ]; then
        sh "$MODDIR/set_audio_mode.sh" apply >/dev/null 2>&1
    fi
}

(((sleep 20; additionalSettings) 0<&- &>"/dev/null" &) &)
