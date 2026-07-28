#!/usr/bin/env bash
set -Eeuo pipefail

IFACE="wlan0"
OUT_PREFIX=""
BSSID=""
ESSID=""
CHANNEL=""

usage() {
    echo "Usage:"
    echo "  sudo $0"
    echo "  sudo $0 wlan1"
    echo "  sudo $0 wlan1 capture_output"
    echo "  sudo $0 -i wlan1 -w capture_output"
    echo "  sudo $0 -i wlan1 --bssid AA:BB:CC:DD:EE:FF -c 6"
    echo "  sudo $0 -i wlan1 --ssid HomeLab -c 6 -w captures/homelab"
    echo
    echo "Options:"
    echo "  -i, --interface   Wireless interface, default wlan0"
    echo "  -w, --write       Output file prefix"
    echo "  -b, --bssid       Target AP BSSID"
    echo "  -e, --essid       Target AP ESSID/SSID"
    echo "      --ssid        Alias for --essid"
    echo "  -c, --channel     Lock to channel"
}

require_value() {
    local flag="$1"
    local remaining="$2"

    if [[ "$remaining" -lt 2 ]]; then
        echo "/!\ Option $flag requires a value."
        echo
        usage
        exit 1
    fi
}

get_monitor_iface_for_phy() {
    local phy="$1"

    iw dev | awk -v target_phy="$phy" '
        $1 ~ /^phy#/ {
            current_phy = $1
            sub(/^phy#/, "phy", current_phy)
            iface = ""
        }

        $1 == "Interface" {
            iface = $2
        }

        $1 == "type" && $2 == "monitor" && current_phy == target_phy && iface != "" {
            print iface
            exit
        }
    '
}

check_dependencies() {
    local missing=()
    local cmd

    for cmd in airmon-ng airodump-ng iw ip rfkill systemctl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ "${#missing[@]}" -gt 0 ]]; then
        echo "/!\ Missing required tool(s): ${missing[*]}"
        echo
        echo "Install with: sudo apt install aircrack-ng iw iproute2 rfkill"
        exit 1
    fi
}

cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM

    echo
    echo "/!\ Cleaning up..."

    if [[ -n "${MON_IFACE:-}" ]]; then
        sudo airmon-ng stop "$MON_IFACE" >/dev/null 2>&1 || true
    fi

    sudo systemctl restart NetworkManager >/dev/null 2>&1 || true
    sudo systemctl restart wpa_supplicant >/dev/null 2>&1 || true

    echo "/!\ Network services restored."
    exit "$exit_code"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--interface)
            require_value "$1" "$#"
            IFACE="$2"
            shift 2
            ;;
        -w|--write|--output)
            require_value "$1" "$#"
            OUT_PREFIX="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -b|--bssid)
            require_value "$1" "$#"
            BSSID="$2"
            shift 2
            ;;
        -e|--essid|--ssid)
            require_value "$1" "$#"
            ESSID="$2"
            shift 2
            ;;
        -c|--channel)
            require_value "$1" "$#"
            CHANNEL="$2"
            shift 2
            ;;
        -*)
            echo "/!\ Unknown option: $1"
            echo
            usage
            exit 1
            ;;
        *)
            if [[ "$IFACE" == "wlan0" ]]; then
                IFACE="$1"
            elif [[ -z "$OUT_PREFIX" ]]; then
                OUT_PREFIX="$1"
            else
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ "$EUID" -ne 0 ]]; then
    echo "/!\ Run this with sudo."
    exit 1
fi

check_dependencies

if ! ip link show "$IFACE" >/dev/null 2>&1; then
    echo "/!\ Interface '$IFACE' not found."
    echo
    echo "Available interfaces:"
    ip -br link
    exit 1
fi

PHY="phy$(iw dev "$IFACE" info | awk '/wiphy/ {print $2}')"

if [[ -z "$PHY" || "$PHY" == "phy" ]]; then
    echo "/!\ Could not determine PHY for interface '$IFACE'."
    exit 1
fi

trap cleanup EXIT INT TERM

echo "Using interface: $IFACE"
echo "Using PHY:       $PHY"

echo "Unblocking Wi-Fi..."
rfkill unblock wifi || true
rfkill unblock all || true

echo "Bringing interface down..."
ip link set "$IFACE" down || true

echo "Killing monitor-mode conflicts..."
airmon-ng check kill

echo "Starting monitor mode..."
if ! airmon-ng start "$IFACE"; then
    echo "/!\ airmon-ng failed to start monitor mode on '$IFACE' (see output above)."
    exit 1
fi

MON_IFACE="$(get_monitor_iface_for_phy "$PHY")"

if [[ -z "$MON_IFACE" ]]; then
    echo "/!\ Could not identify monitor interface."
    echo
    echo "Current wireless interfaces:"
    iw dev
    exit 1
fi

echo "Monitor interface: $MON_IFACE"

AIRODUMP_ARGS=()

if [[ -n "$BSSID" ]]; then
    AIRODUMP_ARGS+=(--bssid "$BSSID")
fi

if [[ -n "$ESSID" ]]; then
    AIRODUMP_ARGS+=(--essid "$ESSID")
fi

if [[ -n "$CHANNEL" ]]; then
    AIRODUMP_ARGS+=(-c "$CHANNEL")
fi

if [[ -n "$OUT_PREFIX" ]]; then
    OUT_DIR="$(dirname "$OUT_PREFIX")"

    if [[ "$OUT_DIR" != "." ]]; then
        mkdir -p "$OUT_DIR"
    fi

    echo "Starting airodump-ng with file output prefix: $OUT_PREFIX"
    echo "Press Ctrl+C to stop and restore networking."
    echo

    airodump-ng \
        "${AIRODUMP_ARGS[@]}" \
        --write "$OUT_PREFIX" \
        --output-format pcap,csv,netxml \
        "$MON_IFACE"
else
    echo "Starting airodump-ng screen-only."
    echo "Press Ctrl+C to stop and restore networking."
    echo

    airodump-ng \
        "${AIRODUMP_ARGS[@]}" \
        "$MON_IFACE"
fi
