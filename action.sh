#!/system/bin/sh
# Audio Misc. Settings - Universal Engine Action & Terminal CLI Tool
# Compatible with Magisk Action Button, KernelSU, APatch, and Terminal Shell (Termux/ADB)

export PATH="/system/bin:/system/xbin:/vendor/bin:$PATH"

# Resolve module base directory
MODDIR="${0%/*}"
if [ ! -f "$MODDIR/get_audio_status.sh" ]; then
    for p in "/data/adb/modules/audio-misc-settings-ksu-webui" \
             "/data/adb/modules_update/audio-misc-settings-ksu-webui" \
             "/data/adb/modules/audio-misc-settings" \
             "/data/adb/ksu/modules/audio-misc-settings-ksu-webui" \
             "/data/adb/ap/modules/audio-misc-settings-ksu-webui"; do
        if [ -f "$p/get_audio_status.sh" ]; then
            MODDIR="$p"
            break
        fi
    done
fi

# ANSI Colors
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_CYAN="\033[36m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_MAGENTA="\033[35m"
C_RED="\033[31m"
C_BG_BLUE="\033[44;37m"

print_banner() {
    echo -e "${C_CYAN}${C_BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║     Audio Misc. Settings - Universal Audiophile Engine           ║"
    echo "║        Universal Magisk • KernelSU • APatch • WebUI              ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${C_RESET}"
}

get_diagnostic_summary() {
    local json=""
    if [ -f "$MODDIR/get_audio_status.sh" ]; then
        json="$(sh "$MODDIR/get_audio_status.sh" 2>/dev/null)"
    fi

    # Extract properties
    local route="$(echo "$json" | grep -o '"active_route": *"[^"]*"' | cut -d'"' -f4)"
    local dac="$(echo "$json" | grep -o '"dac_name": *"[^"]*"' | cut -d'"' -f4)"
    local hw_rate="$(echo "$json" | grep -o '"sample_rate": *"[^"]*"' | cut -d'"' -f4)"
    local hw_depth="$(echo "$json" | grep -o '"bitrate": *"[^"]*"' | cut -d'"' -f4)"
    local bt_name="$(echo "$json" | grep -o '"bt_name": *"[^"]*"' | cut -d'"' -f4)"
    local bt_codec="$(echo "$json" | grep -o '"bt_codec": *"[^"]*"' | cut -d'"' -f4)"
    local mode="$(echo "$json" | grep -o '"mode": *"[^"]*"' | cut -d'"' -f4)"
    local cfg_rate="$(echo "$json" | grep -o '"cfg_rate": *"[^"]*"' | cut -d'"' -f4)"
    local cfg_depth="$(echo "$json" | grep -o '"cfg_depth": *"[^"]*"' | cut -d'"' -f4)"
    local cfg_drc="$(echo "$json" | grep -o '"cfg_drc": *"[^"]*"' | cut -d'"' -f4)"
    local cfg_period="$(echo "$json" | grep -o '"cfg_period": *"[^"]*"' | cut -d'"' -f4)"
    local unlock_96k="$(echo "$json" | grep -o '"is_96k_unlocked": *[0-9]*' | grep -o '[0-9]*$')"
    local tinymix_avail="$(echo "$json" | grep -o '"has_tinymix": *[0-9]*' | grep -o '[0-9]*$')"

    [ -z "$route" ] && route="Internal Speaker / System"
    [ -z "$hw_rate" ] && hw_rate="48,000 Hz"
    [ -z "$hw_depth" ] && hw_depth="16-bit PCM"
    [ -z "$mode" ] && mode="audiophile"
    [ -z "$cfg_rate" ] && cfg_rate="44100"
    [ -z "$cfg_depth" ] && cfg_depth="32"
    [ -z "$cfg_drc" ] && cfg_drc="false"
    [ -z "$cfg_period" ] && cfg_period="2000"

    echo -e "${C_BOLD}▶ Audio Pipeline Diagnostics:${C_RESET}"
    echo -e "  • ${C_CYAN}Active Route:${C_RESET}      ${C_BOLD}${route}${C_RESET}"
    if [ -n "$dac" ]; then
        echo -e "  • ${C_CYAN}DAC Hardware:${C_RESET}      ${C_GREEN}${dac}${C_RESET}"
    fi
    if [ -n "$bt_name" ]; then
        echo -e "  • ${C_CYAN}Bluetooth Device:${C_RESET}  ${C_GREEN}${bt_name}${C_RESET} (${bt_codec})"
    fi
    echo -e "  • ${C_CYAN}Active Hardware:${C_RESET}   ${C_GREEN}${hw_rate}${C_RESET} | ${C_GREEN}${hw_depth}${C_RESET}"
    echo -e "  • ${C_CYAN}Engine Profile:${C_RESET}    ${C_YELLOW}${mode}${C_RESET}"
    echo -e "  • ${C_CYAN}Configured Target:${C_RESET} ${cfg_rate} Hz | ${cfg_depth}-bit float | DRC: ${cfg_drc} | USB: ${cfg_period}μs"
    if [ "$unlock_96k" = "1" ]; then
        echo -e "  • ${C_CYAN}96kHz Cap Unlock:${C_RESET} ${C_GREEN}Active (Unlocked up to 768kHz)${C_RESET}"
    else
        echo -e "  • ${C_CYAN}96kHz Cap Unlock:${C_RESET} ${C_YELLOW}Standard${C_RESET}"
    fi
    if [ "$tinymix_avail" = "1" ]; then
        echo -e "  • ${C_CYAN}ALSA Tinymix:${C_RESET}      ${C_GREEN}Available (Hardware Gain Control ready)${C_RESET}"
    fi
    echo ""
}

cli_usage() {
    echo -e "${C_BOLD}Usage:${C_RESET} audiomisc [command] [options]"
    echo ""
    echo -e "${C_BOLD}Commands:${C_RESET}"
    echo "  status               Show live audio pipeline diagnostics"
    echo "  status --json        Output raw diagnostic JSON"
    echo "  mode <mode>          Set mode ('audiophile' or 'power_saver')"
    echo "  rate <hz>            Set sample rate (44100, 48000, 96000, 192000, 384000, 768000, auto)"
    echo "  depth <bits>         Set bit depth (16, 24, 32)"
    echo "  drc <true|false>     Enable/disable Dynamic Range Compression"
    echo "  period <usec>        Set USB buffer period (1000 - 10000)"
    echo "  tinymix              Calibrate ALSA hardware DAC volume to 100%"
    echo "  restart              Restart audioserver"
    echo "  reset                Reset all samplerate & policy overrides to default"
    echo "  webui                Show instructions to open WebUI via KsuWebUIStandalone / MMRL"
    echo ""
}

do_tinymix() {
    echo -e "${C_YELLOW}Running ALSA Hardware DAC Gain Calibration...${C_RESET}"
    if [ -f "$MODDIR/set_audio_mode.sh" ]; then
        sh "$MODDIR/set_audio_mode.sh" tinymix_only
        echo -e "${C_GREEN}✔ Hardware DAC Gain calibrated to 100% (Bit-Perfect output).${C_RESET}"
    else
        echo -e "${C_RED}Error: set_audio_mode.sh not found.${C_RESET}"
    fi
}

do_mode() {
    local target="$1"
    if [ "$target" != "audiophile" ] && [ "$target" != "power_saver" ]; then
        echo -e "${C_RED}Invalid mode. Choose 'audiophile' or 'power_saver'.${C_RESET}"
        return 1
    fi
    echo -e "${C_YELLOW}Switching audio mode to: ${target}...${C_RESET}"
    if [ -f "$MODDIR/set_audio_mode.sh" ]; then
        sh "$MODDIR/set_audio_mode.sh" "$target"
        echo -e "${C_GREEN}✔ Audio mode set to ${target}.${C_RESET}"
    else
        echo -e "${C_RED}Error: set_audio_mode.sh not found.${C_RESET}"
    fi
}

do_samplerate() {
    local rate="$1"
    local depth="$2"
    local drc="$3"
    local period="$4"

    # Read current config if not supplied
    local cur_rate="44100"
    local cur_depth="32"
    local cur_mode="auto"
    local cur_drc="false"
    local cur_period="2000"

    if [ -f "$MODDIR/samplerate.conf" ]; then
        local r="$(grep '^RATE=' "$MODDIR/samplerate.conf" | cut -d= -f2 | tr -d ' \r')"
        [ -n "$r" ] && cur_rate="$r"
        local d="$(grep '^DEPTH=' "$MODDIR/samplerate.conf" | cut -d= -f2 | tr -d ' \r')"
        [ -n "$d" ] && cur_depth="$d"
        local m="$(grep '^MODE=' "$MODDIR/samplerate.conf" | cut -d= -f2 | tr -d ' \r')"
        [ -n "$m" ] && cur_mode="$m"
        local c="$(grep '^DRC=' "$MODDIR/samplerate.conf" | cut -d= -f2 | tr -d ' \r')"
        [ -n "$c" ] && cur_drc="$c"
        local pr="$(grep '^PERIOD=' "$MODDIR/samplerate.conf" | cut -d= -f2 | tr -d ' \r')"
        [ -n "$pr" ] && cur_period="$pr"
    fi

    [ -n "$rate" ] && cur_rate="$rate"
    [ -n "$depth" ] && cur_depth="$depth"
    [ -n "$drc" ] && cur_drc="$drc"
    [ -n "$period" ] && cur_period="$period"

    echo -e "${C_YELLOW}Applying Sample Rate: ${cur_rate} Hz, Bit Depth: ${cur_depth}-bit, DRC: ${cur_drc}, USB Period: ${cur_period}μs...${C_RESET}"
    if [ -f "$MODDIR/set_audio_samplerate.sh" ]; then
        sh "$MODDIR/set_audio_samplerate.sh" --rate "$cur_rate" --depth "$cur_depth" --mode "$cur_mode" --drc "$cur_drc" --period "$cur_period"
        echo -e "${C_GREEN}✔ Applied successfully. Audioserver reloaded.${C_RESET}"
    else
        echo -e "${C_RED}Error: set_audio_samplerate.sh not found.${C_RESET}"
    fi
}

do_reset() {
    echo -e "${C_YELLOW}Resetting audio engine parameters to defaults...${C_RESET}"
    if [ -f "$MODDIR/set_audio_samplerate.sh" ]; then
        sh "$MODDIR/set_audio_samplerate.sh" --reset
        echo -e "${C_GREEN}✔ Reset completed successfully.${C_RESET}"
    else
        echo -e "${C_RED}Error: set_audio_samplerate.sh not found.${C_RESET}"
    fi
}

do_restart() {
    echo -e "${C_YELLOW}Restarting Android audioserver...${C_RESET}"
    setprop ctl.restart audioserver
    sleep 1
    echo -e "${C_GREEN}✔ Audioserver restarted.${C_RESET}"
}

show_webui_info() {
    echo -e "${C_CYAN}${C_BOLD}▶ WebUI Access Options on Magisk:${C_RESET}"
    echo "  1. KsuWebUIStandalone (Recommended, Fast & Simple):"
    echo "     Install the APK from: https://github.com/MeowDump/KsuWebUIStandalone"
    echo "     Open the app and tap 'Audio Misc. Settings' to open the WebUI."
    echo ""
    echo "  2. MMRL (Magisk Module Repo Loader):"
    echo "     Install MMRL from: https://github.com/Googlers-Repo/MMRL"
    echo "     Open MMRL -> Installed Modules -> Audio Misc. Settings -> WebUI."
    echo ""
    echo "  3. Magisk Action Button:"
    echo "     You can configure everything right here in Magisk Manager!"
    echo ""
}

# Check CLI Arguments first
if [ $# -gt 0 ]; then
    case "$1" in
        "status")
            if [ "$2" = "--json" ]; then
                if [ -f "$MODDIR/get_audio_status.sh" ]; then
                    sh "$MODDIR/get_audio_status.sh"
                fi
            else
                print_banner
                get_diagnostic_summary
            fi
            exit 0
            ;;
        "mode")
            do_mode "$2"
            exit $?
            ;;
        "rate")
            do_samplerate "$2" "" "" ""
            exit $?
            ;;
        "depth")
            do_samplerate "" "$2" "" ""
            exit $?
            ;;
        "drc")
            do_samplerate "" "" "$2" ""
            exit $?
            ;;
        "period")
            do_samplerate "" "" "" "$2"
            exit $?
            ;;
        "tinymix")
            do_tinymix
            exit $?
            ;;
        "restart")
            do_restart
            exit $?
            ;;
        "reset")
            do_reset
            exit $?
            ;;
        "webui")
            show_webui_info
            exit 0
            ;;
        "help"|"-h"|"--help")
            print_banner
            cli_usage
            exit 0
            ;;
        *)
            echo -e "${C_RED}Unknown command: $1${C_RESET}"
            cli_usage
            exit 1
            ;;
    esac
fi

# Interactive Loop for Magisk Action Button & Terminal
print_banner
get_diagnostic_summary

# If non-interactive (e.g. triggered in automated non-tty script without args), show summary and exit
if [ ! -t 0 ] && [ -z "$PS1" ]; then
    echo -e "${C_GREEN}✔ Audio Misc. Settings engine is active and running.${C_RESET}"
    echo "Use 'su -c audiomisc help' or KsuWebUIStandalone for full control."
    exit 0
fi

while true; do
    echo -e "${C_BOLD}Select Action:${C_RESET}"
    echo "  1) Toggle Profile Mode (Audiophile ↔ Power Saver)"
    echo "  2) Switch Sample Rate (44.1k / 48k / 96k / 192k / 384k / 768k / Auto)"
    echo "  3) Switch Bit Depth (16-bit / 24-bit / 32-bit Float)"
    echo "  4) Toggle Dynamic Range Compression (DRC)"
    echo "  5) ALSA Hardware DAC Gain Calibration (tinymix 100% fix)"
    echo "  6) Restart Audioserver"
    echo "  7) Reset to Defaults"
    echo "  8) WebUI / KsuWebUIStandalone Info"
    echo "  9) Refresh Diagnostics"
    echo "  0) Exit"
    echo ""
    echo -n "Enter choice [0-9]: "
    read choice
    echo ""

    case "$choice" in
        1)
            cur_m="audiophile"
            [ -f "$MODDIR/mode.conf" ] && cur_m="$(grep '^MODE=' "$MODDIR/mode.conf" | cut -d= -f2 | tr -d ' \r')"
            if [ "$cur_m" = "audiophile" ]; then
                do_mode "power_saver"
            else
                do_mode "audiophile"
            fi
            echo ""
            get_diagnostic_summary
            ;;
        2)
            echo "Select Target Sample Rate:"
            echo "  1) 44,100 Hz (CD Standard)"
            echo "  2) 48,000 Hz (Android Native)"
            echo "  3) 96,000 Hz (Hi-Res)"
            echo "  4) 192,000 Hz (Studio Master)"
            echo "  5) 384,000 Hz (Ultra Hi-Res)"
            echo "  6) 768,000 Hz (Direct DSD-Equivalent PCM)"
            echo "  7) auto (Dynamic matching)"
            echo -n "Choice [1-7]: "
            read r_choice
            case "$r_choice" in
                1) do_samplerate "44100" ;;
                2) do_samplerate "48000" ;;
                3) do_samplerate "96000" ;;
                4) do_samplerate "192000" ;;
                5) do_samplerate "384000" ;;
                6) do_samplerate "768000" ;;
                7) do_samplerate "auto" ;;
                *) echo "Cancelled." ;;
            esac
            echo ""
            get_diagnostic_summary
            ;;
        3)
            echo "Select Target Bit Depth:"
            echo "  1) 16-bit Integer"
            echo "  2) 24-bit Integer / Packed"
            echo "  3) 32-bit Float (Audiophile Recommended)"
            echo -n "Choice [1-3]: "
            read d_choice
            case "$d_choice" in
                1) do_samplerate "" "16" ;;
                2) do_samplerate "" "24" ;;
                3) do_samplerate "" "32" ;;
                *) echo "Cancelled." ;;
            esac
            echo ""
            get_diagnostic_summary
            ;;
        4)
            cur_drc="false"
            [ -f "$MODDIR/samplerate.conf" ] && cur_drc="$(grep '^DRC=' "$MODDIR/samplerate.conf" | cut -d= -f2 | tr -d ' \r')"
            if [ "$cur_drc" = "true" ]; then
                do_samplerate "" "" "false" ""
            else
                do_samplerate "" "" "true" ""
            fi
            echo ""
            get_diagnostic_summary
            ;;
        5)
            do_tinymix
            echo ""
            get_diagnostic_summary
            ;;
        6)
            do_restart
            echo ""
            get_diagnostic_summary
            ;;
        7)
            do_reset
            echo ""
            get_diagnostic_summary
            ;;
        8)
            show_webui_info
            ;;
        9)
            get_diagnostic_summary
            ;;
        0)
            echo "Exiting."
            exit 0
            ;;
        *)
            echo "Invalid choice."
            ;;
    esac
done
