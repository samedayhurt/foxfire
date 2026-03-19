#!/usr/bin/env bash
# WiFi traffic generator - continuous data exchange with GL.iNet Beryl
# Runs in background, creates realistic WiFi spectrum activity
set -euo pipefail

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$CONFIG_DIR/config.env"

log() { echo "[$(date '+%H:%M:%S')] [wifi] $*"; }

# --- Connect to Beryl WiFi ---
connect_wifi() {
    log "Connecting to ${WIFI_SSID}..."

    # Check if already connected
    if nmcli -t -f active,ssid dev wifi | grep -q "^yes:${WIFI_SSID}$"; then
        log "Already connected to ${WIFI_SSID}"
        return 0
    fi

    # Try to connect
    for attempt in $(seq 1 5); do
        if nmcli dev wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" ifname "$WIFI_INTERFACE" 2>/dev/null; then
            log "Connected to ${WIFI_SSID}"
            return 0
        fi
        log "Connection attempt $attempt failed, retrying..."
        sleep 5
    done

    log "ERROR: Could not connect to ${WIFI_SSID}"
    return 1
}

# --- Traffic patterns ---

# Steady ping flood - creates consistent small packets
traffic_ping() {
    local duration=$1
    log "Pattern: ping flood (${duration}s)"
    timeout "$duration" ping -i 0.1 -s 1400 "$BERYL_IP" >/dev/null 2>&1 || true
}

# iperf3 - heavy throughput, big wide WiFi signal
traffic_iperf() {
    local duration=$1
    log "Pattern: iperf3 throughput test (${duration}s)"

    # Try to use Beryl as iperf server, fall back to self-hosted traffic
    if timeout 3 bash -c "echo >/dev/tcp/${BERYL_IP}/5201" 2>/dev/null; then
        timeout "$duration" iperf3 -c "$BERYL_IP" -t "$duration" -P 4 >/dev/null 2>&1 || true
    else
        # Generate traffic by downloading from Beryl's web interface repeatedly
        local end=$((SECONDS + duration))
        while [[ $SECONDS -lt $end ]]; do
            curl -s -o /dev/null "http://${BERYL_IP}/" 2>/dev/null || true
            # Upload some data via POST
            dd if=/dev/urandom bs=4096 count=100 2>/dev/null | \
                curl -s -o /dev/null -X POST -d @- "http://${BERYL_IP}/" 2>/dev/null || true
            sleep 0.5
        done
    fi
}

# HTTP-like browsing - bursty, variable packet sizes
traffic_curl() {
    local duration=$1
    log "Pattern: HTTP browsing simulation (${duration}s)"

    local end=$((SECONDS + duration))
    while [[ $SECONDS -lt $end ]]; do
        # Simulate page load: multiple rapid requests
        for _ in $(seq 1 $(( RANDOM % 8 + 3 ))); do
            curl -s -o /dev/null "http://${BERYL_IP}/" 2>/dev/null &
        done
        wait
        # Think time between pages
        sleep $(( RANDOM % 3 + 1 ))
    done
}

# DNS-like small queries mixed with larger transfers
traffic_mixed() {
    local duration=$1
    log "Pattern: mixed traffic (${duration}s)"

    local segment=$(( duration / 4 ))

    # Interleave different patterns
    traffic_ping "$segment"
    sleep 1
    traffic_curl "$segment"
    sleep 1
    traffic_iperf "$segment"
    sleep 1
    traffic_ping "$segment"
}

# --- Main WiFi loop ---
connect_wifi || exit 1

log "Starting WiFi traffic generation loop..."

while true; do
    case "${WIFI_PATTERN}" in
        ping)   traffic_ping "$WIFI_DURATION" ;;
        iperf)  traffic_iperf "$WIFI_DURATION" ;;
        curl)   traffic_curl "$WIFI_DURATION" ;;
        mixed)
            # Randomly pick a pattern each cycle
            patterns=(ping iperf curl mixed)
            pick=${patterns[$((RANDOM % ${#patterns[@]}))]}
            case "$pick" in
                ping)  traffic_ping "$WIFI_DURATION" ;;
                iperf) traffic_iperf "$WIFI_DURATION" ;;
                curl)  traffic_curl "$WIFI_DURATION" ;;
                mixed) traffic_mixed "$WIFI_DURATION" ;;
            esac
            ;;
    esac

    # Brief pause between traffic bursts
    pause=$(( RANDOM % 10 + 5 ))
    log "Traffic pause: ${pause}s"
    sleep "$pause"
done
