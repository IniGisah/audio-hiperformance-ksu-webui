#!/system/bin/sh

# Locate system vendor directory
function getVendorDir()
{
    if [ -d "/vendor" ]; then
        echo "/vendor"
    elif [ -d "/system/vendor" ]; then
        echo "/system/vendor"
    else
        return 1
    fi
}

function isMountCompatible()
{
    local vdir
    vdir="$(getVendorDir)"
    if [ -n "$vdir" -a -d "$vdir" ]; then
        return 0
    else
        return 1
    fi
}

function isMagiskMountCompatible()
{
    isMountCompatible
}

function find_module()
{
    local modname="$1"
    [ -e "${MODPATH%/*}/${modname}" ] && return 0
    [ -e "/data/adb/ksu/modules/${modname}" ] && return 0
    [ -e "/data/adb/ap/modules/${modname}" ] && return 0
    [ -e "/data/adb/modules/${modname}" ] && return 0
    return 1
}

# Get the active audio policy configuration fille from the audioserever
function getActivePolicyFile()
{
    dumpsys media.audio_policy | awk ' 
        /^ Config source: / {
            print $3
        }' 
}

# Extract the file name of an audio_policy_volumes.xml
function getVolumeFile()
{
    if [ $# -gt 0  -a  -r "$1" ]; then
        grep -m 1 -e '<xi:include[[:space:]]*href[[:space:]]*=[[:space:]]*".*audio_policy_volumes.*\.xml"' "$1" | awk -F '"' '{ print $2 }'
    else
        return 1
    fi
}

# Extract the file name of a default_volume_tables.xml
function getDefaultVolumeFile()
{
    if [ $# -gt 0  -a  -r "$1" ]; then
        grep -m 1 -e '<xi:include[[:space:]]*href[[:space:]]*=[[:space:]]*".*default_volume_tables.*\.xml"' "$1" | awk -F '"' '{ print $2 }'
    else
        return 1
    fi
}

function stopDRC()
{
    # stopDRC has two args specifying a main audio policy configuration XML file (eg. audio_policy_configuration.xml) and its dummy one to be overridden

     if [ $# -eq 2  -a  -r "$1"  -a  -w "$2" ]; then
        # Copy and override an original audio_policy_configuration.xml to its dummy file
        cp -f "$1" "$2"
        # Change audio_policy_configuration.xml file to remove DRC
        sed -i 's/speaker_drc_enabled[[:space:]]*=[[:space:]]*"true"/speaker_drc_enabled="false"/' "$2"
    fi
}

# Get the actual audio configuration XML file name, even for Xiaomi, OnePlus, etc.  stock devices
#    that may overlay another file on the dummy mount point file

function getActualConfigXML()
{
    if [ $# -eq 1 ]; then
        local dir=${1%/*}
        local fname=${1##*/}
        local sname=${fname%.*}
        
        if [ -r "${dir}/${sname}_sec.xml" ]; then
            echo "${dir}/${sname}_sec.xml"
        elif [ -e "${dir}_qssi"  -a  -r "${dir}_qssi/${fname}" ]; then
            # OnePlus stock pattern
            echo "${dir}_qssi/${fname}"
        elif [ "${dir##*/}"  = "sku_`getprop ro.board.platform`"  -a  -r "${dir%/*}/${fname}" ]; then
            # OnePlus stock pattern2
            echo "${dir%/*}/${fname}"
        elif [ -r "${dir}/audio/${fname}" ]; then
            # Xiaomi stock pattern
            echo "${dir}/audio/${fname}"
        elif [ -r "${dir}/${sname}_base.xml" ]; then
            echo "${dir}/${sname}_base.xml"
        else
            echo "$1"
        fi
    fi
}

function toHexLE()
{
    if [ $# -eq 1  -a  $1 -gt 0 ]; then
        printf "%2.2x%2.2x%2.2x%2.2x" $(( $1 % 256 ))  $(( $1 / 256 % 256 ))  $(( $1 / 256 / 256 % 256 ))  $(( $1 / 256 / 256 / 256 % 256 ))
        return 0
    else
        return 1
    fi
}

function toHexLineLE()
{
    if [ $# -eq 1 ]; then
        local i
        for i in $1; do
            toHexLE $i
        done
        return 0
    else
        return 1
    fi
}

function toHexString()
{
    if [ $# -ge 1 ]; then
        local tmp
        tmp=`echo -n "$1" | xxd -p | tr -d ' \n'`
        if [ $# -eq 2 ]; then
            if [ ${#tmp} -ge $2 ]; then
                echo -n ${tmp:0:$2}
            else
                local strt=`expr ${#tmp} + 1`
                echo -n "$tmp"
                for i in `seq $strt $2` ; do
                    echo -n "0"
                done
            fi
        else
            echo -n "$tmp"
        fi
    else
      return 1
    fi
}

# Patch libalsautils.so and audio_usb_aoc.so (Tensor's offload USB driver) to map a property string to another
#   arg1: original libalsautils.so file;  arg2: patched libalsautils.so file; 
function patchMapProperty()
{
    local orig_prop='ro.audio.usb.period_us'
    local new_prop='vendor.audio.usb.perio'
    
    if [ $# -eq 2  -a  -r "$1" ]; then
      local pat1=`toHexString "$orig_prop"`
      local pat2=`toHexString "$new_prop" ${#pat1}`
      
      xxd -p <"$1" | tr -d ' \n' | sed -e "s/$pat1/$pat2/" \
          | awk 'BEGIN {
                 foldWidth=60
                 getline buf
                 len=length(buf)
                 for (i=1; i <= len; i+=foldWidth) {
                     if (i + foldWidth - 1 <= len)
                         print substr(buf, i, foldWidth)
                     else
                         print substr(buf, i, len)
                 }
                 exit
             }'  \
         | xxd -r -p >"$2"
      return $?
    else
      return 1
    fi
}

# Patch libalsautils.so to clear the 96kHz lock of USB audio class drivers
#   arg1: original libalsautils.so file;  arg2: patched libalsautils.so file; 
#     optional arg3: "max" (clearing upto 768kHz), "full" (clearing upto 386kHz), "default" or others (clearing upto 192kHz)
function patchClearLock()
{
    local orig_rates='96000  88200  192000  176400  48000  44100  32000  24000  22050  16000  12000  11025  8000'
    local new_rates='192000  176400  96000  88200  48000  44100  32000  24000  22050  16000  12000  11025  8000'
    
    if [ $# -ge 2  -a  -r "$1" ]; then
        if [ $# -gt 2 ]; then
            case "$3" in
                "max" )
                    new_rates='768000  705600  384000  352800  192000  176400  96000  88200  48000  44100  24000  16000  8000'
                    ;;
                "full" )
                    new_rates='384000  352800  192000  176400  96000  88200  48000  44100  32000  24000  16000  12000  8000'
                    ;;
                "default" | * )
                    ;;
          esac
      fi

        local pat1=`toHexLineLE "$orig_rates"`
        local pat2=`toHexLineLE "$new_rates"`
      
        # A workaroud for a SELinux permission bug on Android 12
        local prop1=`toHexString "ro.audio.usb.period_us"`
        local prop2=`toHexString "vendor.audio.usb.perio"`
      
        xxd -p <"$1" | tr -d ' \n' | sed -e "s/$prop1/$prop2/" -e "s/$pat1/$pat2/" \
            | awk 'BEGIN {
                foldWidth=60
                getline buf
                len=length(buf)
                for (i=1; i <= len; i+=foldWidth) {
                    if (i + foldWidth - 1 <= len)
                        print substr(buf, i, foldWidth)
                    else
                        print substr(buf, i, len)
                }
                exit
              }'  \
            | xxd -r -p >"$2"
            
        return $?
        
    else
        
        return 1
    fi
}

# Patch audio_usb_aoc.so file to clear the 192kHz lock of USB audio class Tensor offload drivers
#   arg1: original audio_usb_aoc.so file;  arg2: patched audio_usb_aoc.so file; 
function patchClearTensorOffloadLock()
{
    local orig_rates='192000  96000  48000  44100  32000  24000  22050  16000  12000  11025  8000'
    local new_rates='768000  705600  384000  352800  192000  176400  96000  88200  48000  44100  8000'

    if [ $# -ge 2  -a  -r "$1" ]; then
        local pat1=`toHexLineLE "$orig_rates"`
        local pat2=`toHexLineLE "$new_rates"`

        # A workaroud for a SELinux permission bug on Android 12
        local prop1=`toHexString "ro.audio.usb.period_us"`
        local prop2=`toHexString "vendor.audio.usb.perio"`

        # sample rate limiter at 192kHz
        local ul1=`toHexLineLE "192000"`
        local ul2=`toHexLineLE "768000"`
          
#        Don't work yet. Need more inviestigations
#        xxd -p <"$1" | tr -d ' \n' | sed -e "s/$prop1/$prop2/" -e "s/$ul1/$ul2/" -e "s/$pat1/$pat2/" \
        xxd -p <"$1" | tr -d ' \n' | sed -e "s/$prop1/$prop2/" \
            | awk 'BEGIN {
                 foldWidth=60
                 getline buf
                 len=length(buf)
                 for (i=1; i <= len; i+=foldWidth) {
                     if (i + foldWidth - 1 <= len)
                         print substr(buf, i, foldWidth)
                     else
                         print substr(buf, i, len)
                 }
                 exit
               }'  \
             | xxd -r -p >"$2"
             
        return $?
        
    else
        return 1
    fi
}

# Helper: Install a patched/generated file into the module overlay with correct permissions
#   arg1: source or "null" (to create empty file); arg2: destination file path; arg3: SELinux context
function install_mod_file()
{
    local src="$1" dst="$2" secon="${3:-u:object_r:vendor_file:s0}"
    mkdir -p "${dst%/*}"
    if [ "$src" = "null" ]; then
        cp /dev/null "$dst"
    else
        # Source is already written by the patching function
        :
    fi
    chmod 644 "$dst"
    chcon "$secon" "$dst"
    chown root:root "$dst"
    chmod -R a+rX "${dst%/*}"
}

# Helper: Append a file path to the REPLACEFILES list
function append_replacefile()
{
    if [ -z "${REPLACEFILES}" ]; then
        REPLACEFILES="$1"
    else
        REPLACEFILES="${REPLACEFILES} $1"
    fi
}

function makeLibraries()
{
    local VENDORDIR="$(getVendorDir)"
    local d lname dst
    
    if [ -z "$VENDORDIR" ]; then
        return 1
    fi
    
    for d in "lib" "lib64"; do
        for lname in "libalsautils.so" "libalsautilsv2.so" "audio_usb_aoc.so"; do
            if [ -r "${VENDORDIR}/${d}/${lname}" ]; then
                dst="${MODPATH}/system/vendor/${d}/${lname}"
                mkdir -p "${dst%/*}"
                patchMapProperty "${VENDORDIR}/${d}/${lname}" "$dst"
                install_mod_file "patched" "$dst"
                append_replacefile "/system/vendor/${d}/${lname}"
            fi
        done        
    done
}

function nullifySoundFx()
{
    local VENDORDIR="$(getVendorDir)"
    local d lname dst
    
    if [ -z "$VENDORDIR" ]; then
        return 1
    fi
    
    for d in "lib" "lib64"; do
        for lname in "libvolumelistener.so" "libdlbvol.so"; do
            if [ -r "${VENDORDIR}/${d}/soundfx/${lname}" ]; then
                dst="${MODPATH}/system/vendor/${d}/soundfx/${lname}"
                install_mod_file "null" "$dst"
                append_replacefile "/system/vendor/${d}/soundfx/${lname}"
            fi
        done
    done
}

function makeUnlockedLibraries()
{
    local VENDORDIR="$(getVendorDir)"
    local d lname dst
    
    if [ -z "$VENDORDIR" ]; then
        return 1
    fi

    for d in "lib" "lib64"; do
        for lname in "libalsautils.so" "libalsautilsv2.so"; do
            if [ -r "${VENDORDIR}/${d}/${lname}" ]; then
                dst="${MODPATH}/system/vendor/${d}/${lname}"
                mkdir -p "${dst%/*}"
                patchClearLock "${VENDORDIR}/${d}/${lname}" "$dst" "max"
                install_mod_file "patched" "$dst"
                append_replacefile "/system/vendor/${d}/${lname}"
            fi
        done        
        for lname in "audio_usb_aoc.so"; do
            if [ -r "${VENDORDIR}/${d}/${lname}" ]; then
                dst="${MODPATH}/system/vendor/${d}/${lname}"
                mkdir -p "${dst%/*}"
                patchClearTensorOffloadLock "${VENDORDIR}/${d}/${lname}" "$dst"
                install_mod_file "patched" "$dst"
                append_replacefile "/system/vendor/${d}/${lname}"
            fi
        done        
    done
}

# Replace system property values for old Androids and some low performance SoC's

function loosenedMessage()
{
    local freq="96kHz"
    if [ $# -gt 0 ]; then
        freq="$1"
    fi
    
    ui_print ""
    ui_print "****************************************************************"
    ui_print " Loosened the USB jitter level for more than $freq USB outputs! "
    ui_print "   (\"USB Samplerate Unlocker\" was detected) "
    ui_print "****************************************************************"
    ui_print ""
}

# Helper: Apply sed replacements to both system.prop and system.prop-workaround
#   All arguments are passed directly to sed -i as -e expressions
function sed_system_props()
{
    sed -i "$@" "$MODPATH/system.prop"
    sed -i "$@" "$MODPATH/system.prop-workaround"
}

# Helper: Set USB period values in both system.prop files
#   arg1: period value in microseconds
function set_usb_period()
{
    local val="$1"
    sed_system_props \
        -e "s/vendor\.audio\.usb\.perio=.*$/vendor\.audio\.usb\.perio=${val}/" \
        -e "s/vendor\.audio\.usb\.out\.period_us=.*$/vendor\.audio\.usb\.out\.period_us=${val}/"
}

# VHPerf / SDM845 / MTK Dimensity / Tensor — all use 2000μs period
function replaceSystemProps_VHPerf()
{
    set_usb_period 2000
}

function replaceSystemProps_Old()
{
    if find_module "usb-samplerate-unlocker"; then
        set_usb_period 2250
        loosenedMessage
    else
        set_usb_period 2250
    fi
}

function replaceSystemProps_S4()
{
    if find_module "usb-samplerate-unlocker"; then
        set_usb_period 5000
        loosenedMessage
    else
        set_usb_period 3875
    fi
}

function replaceSystemProps_Kona()
{
    set_usb_period 4000
}

# SDM845 / MTK Dimensity / Tensor all use same 2000μs period as VHPerf
function replaceSystemProps_SDM845()
{
    set_usb_period 2000
}

function replaceSystemProps_SDM()
{
    # Do nothing even if "usb-samplerate-unlocker" exists
    :
}

function replaceSystemProps_MTK_Dimensity()
{
    set_usb_period 2000
}

function replaceSystemProps_Tensor()
{
    set_usb_period 2000
}

function replaceSystemProps_Others()
{
    if find_module "usb-samplerate-unlocker"; then
        set_usb_period 2000
        loosenedMessage
    fi
}

# HyperOS v2.0 and Motorola stock OS v15.0 cannot increase the number of volume steps

function deleteSystemProps_for_some_Stocks()
{
    local Moto="`getprop ro.mot.build.customerid`"
    local MIUI="`getprop ro.miui.ui.version.code`"
    local AndroidVersion="`getprop ro.system.build.version.release`"

    if [  -n "$MIUI"  -a  "$MIUI" -ge 14 ] || [ -n "$Moto"  -a  "$AndroidVersion" -ge 15 ]; then
        sed_system_props -e '/^ro\.config\.media_vol_steps=/d'
    fi
}

function stopSpatializer()
{
    # stopSpatializer has two args specifying an audio policy configuration XML file (eg. bluetooth_audio_policy_configuration_7_0.xml) 
    #   and its dummy one to be overridden

    if [ $# -eq 2  -a  -r "$1"  -a  -w "$2" ]; then
        # Copy and override an original audio_policy_configuration.xml to its dummy file
        cp -f "$1" "$2"
        # Change an audio_policy_configuration.xml file to remove Spatializer
        sed -i 's/flags[[:space:]]*=[[:space:]]*"AUDIO_OUTPUT_FLAG_SPATIALIZER"//' "$2"
    fi
}

function deSpatializeAudioPolicyConfig()
{
    if [ $# -ne 1  -o  -z "$1"  -o  ! -r "$1" ]; then
        return 1
    fi
    local configXML="$1"

    if [ -n "$configXML"  -a  -r "$configXML" ]; then
        if grep -q "flags[[:space:]]*=[[:space:]]*\"AUDIO_OUTPUT_FLAG_SPATIALIZER\"" "$configXML" 2>/dev/null; then
            local modConfigXML="$MODPATH/system${configXML}"
            mkdir -p "${modConfigXML%/*}"
            touch "$modConfigXML"
            stopSpatializer "$configXML" "$modConfigXML"
            install_mod_file "patched" "$modConfigXML" "u:object_r:vendor_configs_file:s0"
            append_replacefile "/system${configXML}"
        fi
    fi
}

function disablePrivApps()
{
    if [ $# -ne 1  -o  -z "$1" ]; then
        return 1
    fi

    local dir mdir target_dir
    local PrivApps="$1"
    
    for dir in $PrivApps; do
        if [ -d "${dir}" ] || [ -d "/system${dir}" ]; then
            target_dir="${dir}"
            case "${target_dir}" in
                /system/* )
                    target_dir="${target_dir#/system}"
                ;;
            esac
            mdir="${MODPATH}/system${target_dir}"
            mkdir -p "${mdir%/*}"
            rm -rf "$mdir" 2>/dev/null
            mknod "$mdir" c 0 0 2>/dev/null || mkdir -p "$mdir"
            touch "$mdir/.replace" 2>/dev/null
            chmod a+rx "$mdir" 2>/dev/null
            if [ -z "$REPLACE" ]; then
                REPLACE="/system${target_dir}"
            else
                REPLACE="${REPLACE} /system${target_dir}"
            fi
        fi
    done
}

function ui_print_replacelist()
{
    local f
    for f in $1; do
        ui_print "- Replace target file: $f"
    done
}

function disableDrcAudioPolicyConfig()
{
    if [ $# -ne 1  -o  -z "$1"  -o  ! -r "$1" ]; then
        return 1
    fi
    local configXML="$1"

    if [ -n "$configXML"  -a  -r "$configXML" ]; then
        local modConfigXML="$MODPATH/system${configXML}"
        mkdir -p "${modConfigXML%/*}"
        cp -f "$configXML" "$modConfigXML"
        sed -i 's/speaker_drc_enabled[[:space:]]*=[[:space:]]*"true"/speaker_drc_enabled="false"/g' "$modConfigXML"
        install_mod_file "patched" "$modConfigXML" "u:object_r:vendor_configs_file:s0"
        append_replacefile "/system${configXML}"
    fi
}

function patchBitPerfectAudioPolicyConfig()
{
    if [ $# -ne 1  -o  -z "$1"  -o  ! -r "$1" ]; then
        return 1
    fi
    local configXML="$1"

    if [ -n "$configXML"  -a  -r "$configXML" ]; then
        local modConfigXML="$MODPATH/system${configXML}"
        mkdir -p "${modConfigXML%/*}"
        cp -f "$configXML" "$modConfigXML"
        if grep -q "AUDIO_OUTPUT_FLAG_DIRECT" "$modConfigXML" && ! grep -q "AUDIO_OUTPUT_FLAG_BIT_PERFECT" "$modConfigXML"; then
            sed -i 's/AUDIO_OUTPUT_FLAG_DIRECT/AUDIO_OUTPUT_FLAG_DIRECT|AUDIO_OUTPUT_FLAG_BIT_PERFECT/g' "$modConfigXML"
        fi
        install_mod_file "patched" "$modConfigXML" "u:object_r:vendor_configs_file:s0"
        append_replacefile "/system${configXML}"
    fi
}

