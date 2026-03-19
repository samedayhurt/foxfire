#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CONFIG_DIR/config.env"

SIGNALS_DIR="$CONFIG_DIR/signals"
WIFI_DIR="$CONFIG_DIR/wifi"

log() { echo "[$(date '+%H:%M:%S')] [rabbit] $*"; }

# Cleanup on exit
cleanup() {
    log "Shutting down RF Rabbit..."
    # Kill all child processes
    pkill -P $$ 2>/dev/null || true
    # Release HackRF
    hackrf_transfer -R 2>/dev/null || true
    log "Stopped."
}
trap cleanup EXIT INT TERM

# --- Wait for hardware ---
wait_for_hackrf() {
    log "Waiting for HackRF One..."
    for i in $(seq 1 30); do
        if hackrf_info &>/dev/null; then
            log "HackRF One detected."
            return 0
        fi
        sleep 2
    done
    log "ERROR: HackRF not found after 60s"
    return 1
}

wait_for_rtlsdr() {
    log "Waiting for RTL-SDR..."
    for i in $(seq 1 30); do
        if rtl_test -t 2>&1 | grep -q "Found"; then
            log "RTL-SDR detected."
            return 0
        fi
        sleep 2
    done
    log "WARNING: RTL-SDR not found, continuing without monitoring"
}

# --- Build signal profile list ---
build_playlist() {
    PLAYLIST=()
    [[ "${ICOM_ENABLED}" == "true" ]] && PLAYLIST+=("icom")
    [[ "${WALKIE_ENABLED}" == "true" ]] && PLAYLIST+=("walkie")
    [[ "${LORA_ENABLED}" == "true" ]] && PLAYLIST+=("lora")

    if [[ ${#PLAYLIST[@]} -eq 0 ]]; then
        log "ERROR: No signal profiles enabled in config.env"
        exit 1
    fi
    log "Active profiles: ${PLAYLIST[*]}"
}

# --- Random pause between transmissions ---
random_pause() {
    local pause=$(( RANDOM % (CYCLE_MAX_PAUSE - CYCLE_MIN_PAUSE + 1) + CYCLE_MIN_PAUSE ))
    log "Pausing ${pause}s before next transmission..."
    sleep "$pause"
}

# --- Start WiFi traffic in background ---
start_wifi() {
    if [[ "${WIFI_ENABLED}" == "true" ]]; then
        log "Starting WiFi traffic generator..."
        "$WIFI_DIR/wifi_traffic.sh" &
        WIFI_PID=$!
        log "WiFi traffic PID: $WIFI_PID"
    fi
}

# --- Main loop ---
main() {
    log "========================================="
    log "  RF Rabbit Emitter Starting"
    log "========================================="

    wait_for_hackrf
    wait_for_rtlsdr
    build_playlist
    start_wifi

    log "Entering main transmission loop..."

    while true; do
        # Shuffle the playlist each cycle
        local shuffled=($(shuf -e "${PLAYLIST[@]}"))

        for profile in "${shuffled[@]}"; do
            log ">>> Activating profile: $profile"
            "$SIGNALS_DIR/${profile}.sh"
            random_pause
        done

        log "--- Cycle complete, restarting ---"
    done
}

main "$@"
