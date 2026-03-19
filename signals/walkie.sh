#!/usr/bin/env bash
# Walkie-talkie (FRS/GMRS-like) FM signal profile
# Short, punchy transmissions with roger beep
set -euo pipefail

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$CONFIG_DIR/config.env"

log() { echo "[$(date '+%H:%M:%S')] [walkie] $*"; }

SAMPLE_RATE="${HACKRF_SAMPLE_RATE}"
TMPFILE="/tmp/walkie_iq.raw"

generate_walkie_iq() {
    local duration=$1

    python3 -c "
import numpy as np
import sys

sr = ${SAMPLE_RATE}
duration = ${duration}
n = sr * duration

t = np.arange(n) / sr

# FRS/GMRS style: wider deviation, no CTCSS or simple DCS
# Voice-like modulation
voice_raw = np.random.randn(n)
voice = voice_raw * np.sin(2 * np.pi * 1200 * t) * 0.4

# Add characteristic walkie-talkie compression (clipping)
voice = np.clip(voice, -0.6, 0.6)

# Roger beep at end: 1000Hz tone, last 0.3s
beep_start = max(0, n - int(0.3 * sr))
beep = np.zeros(n)
beep[beep_start:] = 0.5 * np.sin(2 * np.pi * 1000 * t[beep_start:])

modulation = voice + beep

# FM modulate: deviation ~5kHz (wider than ICOM for consumer feel)
deviation = 5000
phase = 2 * np.pi * deviation * np.cumsum(modulation) / sr
iq = np.exp(1j * phase).astype(np.complex64)

iq_bytes = np.column_stack([
    (iq.real * 127).astype(np.int8),
    (iq.imag * 127).astype(np.int8)
]).tobytes()

sys.stdout.buffer.write(iq_bytes)
" > "$TMPFILE"
}

# Walkie pattern: short bursts, quick back-and-forth feel
for burst in $(seq 1 "$WALKIE_BURSTS"); do
    duration=$(( RANDOM % (WALKIE_TX_DURATION_MAX - WALKIE_TX_DURATION_MIN + 1) + WALKIE_TX_DURATION_MIN ))
    log "Burst $burst/$WALKIE_BURSTS: ${duration}s on $(echo "scale=4; $WALKIE_FREQ / 1000000" | bc)MHz"

    generate_walkie_iq "$duration"

    filesize=$(stat -c%s "$TMPFILE")
    hackrf_transfer \
        -t "$TMPFILE" \
        -f "$WALKIE_FREQ" \
        -s "$SAMPLE_RATE" \
        -x "$HACKRF_TX_GAIN" \
        -a 1 \
        -n "$filesize" 2>&1 | tail -3 || log "WARNING: hackrf_transfer exited non-zero"

    # Short pause (walkie-talkie conversations are snappy)
    pause=$(( RANDOM % 3 + 1 ))
    sleep "$pause"
done

rm -f "$TMPFILE"
log "Walkie profile complete"
