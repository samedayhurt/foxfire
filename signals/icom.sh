#!/usr/bin/env bash
# ICOM-like narrowband FM signal profile
# Simulates amateur radio voice comms with realistic timing
set -euo pipefail

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$CONFIG_DIR/config.env"

log() { echo "[$(date '+%H:%M:%S')] [icom] $*"; }

# Generate NBFM-like signal using hackrf_transfer with a generated IQ file
SAMPLE_RATE="${HACKRF_SAMPLE_RATE}"
TMPFILE="/tmp/icom_iq.raw"

generate_nbfm_iq() {
    local duration=$1
    local samples=$((SAMPLE_RATE * duration))

    # Generate narrowband FM IQ data with audio-like modulation
    # Uses Python to create realistic NBFM with sub-audible tone + noise modulation
    python3 -c "
import numpy as np
import sys

sr = ${SAMPLE_RATE}
duration = ${duration}
n = sr * duration

t = np.arange(n) / sr

# Simulate voice-like audio: filtered noise + sub-audible CTCSS tone (88.5 Hz typical ICOM)
ctcss = 0.1 * np.sin(2 * np.pi * 88.5 * t)

# Voice-like: band-limited noise bursts (300-3000 Hz)
voice_raw = np.random.randn(n)
# Simple bandpass via mixing
voice = voice_raw * np.sin(2 * np.pi * 1500 * t) * 0.3

# Combine modulation signal
modulation = ctcss + voice

# FM modulate: deviation ~2.5kHz for narrowband
deviation = 2500
phase = 2 * np.pi * deviation * np.cumsum(modulation) / sr
iq = np.exp(1j * phase).astype(np.complex64)

# Convert to interleaved int8
iq_bytes = np.column_stack([
    (iq.real * 127).astype(np.int8),
    (iq.imag * 127).astype(np.int8)
]).tobytes()

sys.stdout.buffer.write(iq_bytes)
" > "$TMPFILE"
}

# Simulate ICOM-like transmission pattern:
# - Key up (brief carrier)
# - Transmit for variable duration
# - Key down
# - Pause (like waiting for reply)
for burst in $(seq 1 "$ICOM_BURSTS"); do
    duration=$(( RANDOM % (ICOM_TX_DURATION_MAX - ICOM_TX_DURATION_MIN + 1) + ICOM_TX_DURATION_MIN ))
    log "Burst $burst/$ICOM_BURSTS: ${duration}s on $(echo "scale=4; $ICOM_FREQ / 1000000" | bc)MHz"

    generate_nbfm_iq "$duration"

    filesize=$(stat -c%s "$TMPFILE")
    hackrf_transfer \
        -t "$TMPFILE" \
        -f "$ICOM_FREQ" \
        -s "$SAMPLE_RATE" \
        -x "$HACKRF_TX_GAIN" \
        -a 1 \
        -n "$filesize" 2>&1 | tail -3 || log "WARNING: hackrf_transfer exited non-zero"

    # Inter-burst pause (simulates listening/waiting for reply)
    pause=$(( RANDOM % 5 + 2 ))
    log "Listening pause: ${pause}s"
    sleep "$pause"
done

rm -f "$TMPFILE"
log "ICOM profile complete"
