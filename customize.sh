#!/system/bin/sh

. "$MODPATH/customize-functions.sh"

if ! isMountCompatible; then
    abort '  ***
  Aborted: Unable to locate system /vendor partition directory.
  Ensure MetaModule (OverlayFS / Magic Mount) is properly initialized.
  ***'
fi

REPLACE=""
REPLACEFILES=""

# Ensure system directory, marker file, and mode.conf exist
mkdir -p "$MODPATH/system/etc"
echo "# Audio Misc. Settings ZeroMount Target Marker" > "$MODPATH/system/etc/audio_misc_settings.conf"
chmod 644 "$MODPATH/system/etc/audio_misc_settings.conf"

if [ ! -f "$MODPATH/mode.conf" ]; then
    echo "MODE=audiophile" > "$MODPATH/mode.conf"
fi
chmod 644 "$MODPATH/mode.conf"

if [ ! -f "$MODPATH/samplerate.conf" ]; then
    cat <<'EOF' > "$MODPATH/samplerate.conf"
RATE=44100
DEPTH=32
MODE=auto
DRC=false
PERIOD=2000
EOF
fi
chmod 644 "$MODPATH/samplerate.conf"

# Make patched ALSA utility and Tensor's offload libraries (96kHz lock cleared up to 768kHz)
makeUnlockedLibraries
patchPlatformConfig

# Remove spatial audio flags, disable DRC, and inject bit-perfect profiles into audio policy configs
deSpatializeAudioPolicyConfig "/vendor/etc/bluetooth_audio_policy_configuration_7_0.xml"
disableDrcAudioPolicyConfig "/vendor/etc/audio_policy_configuration.xml"
patchBitPerfectAudioPolicyConfig "/vendor/etc/usb_audio_policy_configuration.xml"

# Install CLI command wrapper 'audiomisc' for Termux and terminal emulator users
mkdir -p "$MODPATH/system/bin"
cat <<'EOF' > "$MODPATH/system/bin/audiomisc"
#!/system/bin/sh
MODDIR="${0%/*}/../.."
if [ -f "$MODDIR/action.sh" ]; then
    exec sh "$MODDIR/action.sh" "$@"
fi
for p in "/data/adb/modules/audio-misc-settings-ksu-webui" \
         "/data/adb/modules/audio-misc-settings" \
         "/data/adb/ksu/modules/audio-misc-settings-ksu-webui" \
         "/data/adb/ap/modules/audio-misc-settings-ksu-webui"; do
    if [ -f "$p/action.sh" ]; then
        exec sh "$p/action.sh" "$@"
    fi
done
echo "Error: Audio Misc. Settings module not found."
exit 1
EOF
chmod 755 "$MODPATH/system/bin/audiomisc"

chmod 755 "$MODPATH/action.sh" 2>/dev/null
chmod 755 "$MODPATH/set_audio_mode.sh" 2>/dev/null
chmod 755 "$MODPATH/set_audio_samplerate.sh" 2>/dev/null
chmod 755 "$MODPATH/get_audio_status.sh" 2>/dev/null
chmod 755 "$MODPATH/service.sh" 2>/dev/null
chmod 755 "$MODPATH/post-fs-data.sh" 2>/dev/null
chmod 755 "$MODPATH/uninstall.sh" 2>/dev/null

# Disable pre-installed Moto Dolby features and Wellbeing on Motorola devices only
if [ "`getprop ro.product.manufacturer`" = "motorola" ]; then
    disablePrivApps "
/system_ext/priv-app/MotoDolbyDax3
/system_ext/priv-app/daxService
/system_ext/priv-app/DaxUI
/system_ext/app/MotoSignatureApp
/product/priv-app/WellbeingPrebuilt
/product/priv-app/Wellbeing
/system_ext/priv-app/WellbeingPrebuilt
/system_ext/priv-app/Wellbeing
"
fi

if "$IS64BIT"; then
    board="`getprop ro.board.platform`"
    case "$board" in
        sun* | "pineapple" | zuma* | mt69* )
            replaceSystemProps_VHPerf
            ;;
        "kona" | "kalama" | "shima" | "yupik" )
            replaceSystemProps_Kona
            ;;
        "sdm845" )
            replaceSystemProps_SDM845
            ;;
        gs* )
            replaceSystemProps_Tensor
            ;;
        "sdm660" | "bengal" | "holi" )
            replaceSystemProps_SDM
            ;;
        mt68* )
            replaceSystemProps_MTK_Dimensity
            ;;
        mt67[56]? )
            replaceSystemProps_Others
            ;;
        * )
            replaceSystemProps_VHPerf
            ;;
    esac
    
    deleteSystemProps_for_some_Stocks

else
    if [ "`getprop ro.build.product`" = "jfltexx" ]; then
        replaceSystemProps_S4
    else
        replaceSystemProps_Old
    fi

fi

# AudioFlinger's resampler has a bug on an Android OS of which version is less than 12.
# This bug makes the resampler to distort audible audio output by wrong aliasing processing
#   when specifying a transition band around or higher than the Nyquist frequency

if [ "`getprop ro.system.build.version.release`" -lt "12"  -a  "`getprop ro.system.build.date.utc`" -lt "1648632000" ]; then
    mv -f "$MODPATH/system.prop-workaround" "$MODPATH/system.prop"
else
    rm -f "$MODPATH/system.prop-workaround"
fi

rm -f "$MODPATH/customize-functions.sh" "$MODPATH/LICENSE" "$MODPATH/README.md" "$MODPATH/changelog.md"
ui_print_replacelist "$REPLACEFILES"
