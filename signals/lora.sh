#!/usr/bin/env bash
# LoRa-like chirp spread spectrum signal profile
# Generates CSS (chirp spread spectrum) bursts on 915MHz ISM band
set -euo pipefail

CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$CONFIG_DIR/config.env"

log() { echo "[$(date '+%H:%M:%S')] [lora] $*"; }

SAMPLE_RATE="${HACKRF_SAMPLE_RATE}"
TMPFILE="/tmp/lora_iq.raw"

generate_lora_iq() {
    local num_chirps=$1

    python3 -c "
import numpy as np
import sys

sr = ${SAMPLE_RATE}
bw = ${LORA_BANDWIDTH}
chirp_dur = ${LORA_CHIRP_DURATION}
num_chirps = ${num_chirps}

samples_per_chirp = int(sr * chirp_dur)

all_iq = []

# LoRa preamble: 8 upchirps
for _ in range(8):
    t = np.arange(samples_per_chirp) / sr
    # Linear frequency sweep from -bw/2 to +bw/2
    freq = -bw/2 + (bw / chirp_dur) * t
    phase = 2 * np.pi * np.cumsum(freq) / sr
    all_iq.append(np.exp(1j * phase))

# Sync word: 2 downchirps
for _ in range(2):
    t = np.arange(samples_per_chirp) / sr
    freq = bw/2 - (bw / chirp_dur) * t
    phase = 2 * np.pi * np.cumsum(freq) / sr
    all_iq.append(np.exp(1j * phase))

# Data symbols: chirps with random cyclic shifts (simulates encoded data)
for _ in range(num_chirps):
    t = np.arange(samples_per_chirp) / sr
    # Random starting frequency offset simulates different symbols
    offset = np.random.uniform(-bw/2, bw/2)
    freq = offset + (bw / chirp_dur) * t
    # Wrap around bandwidth (cyclic shift)
    freq = ((freq + bw/2) % bw) - bw/2
    phase = 2 * np.pi * np.cumsum(freq) / sr
    all_iq.append(np.exp(1j * phase))

# Small gap between packets
gap = np.zeros(int(sr * 0.1), dtype=np.complex64)
all_iq.append(gap)

iq = np.concatenate(all_iq).astype(np.complex64)

iq_bytes = np.column_stack([
    (iq.real * 127).astype(np.int8),
    (iq.imag * 127).astype(np.int8)
]).tobytes()

sys.stdout.buffer.write(iq_bytes)
" > "$TMPFILE"
}

for burst in $(seq 1 "$LORA_BURSTS"); do
    # Random number of data symbols per packet (4-20)
    num_symbols=$(( RANDOM % 17 + 4 ))
    log "Packet $burst/$LORA_BURSTS: ${num_symbols} symbols on $(echo "scale=1; $LORA_FREQ / 1000000" | bc)MHz"

    generate_lora_iq "$num_symbols"

    hackrf_transfer \
        -t "$TMPFILE" \
        -f "$LORA_FREQ" \
        -s "$SAMPLE_RATE" \
        -x "$HACKRF_TX_GAIN" \
        -R 2>/dev/null || log "WARNING: hackrf_transfer exited non-zero"

    # LoRa devices have variable duty cycles
    pause=$(( RANDOM % 8 + 2 ))
    log "Duty cycle pause: ${pause}s"
    sleep "$pause"
done

rm -f "$TMPFILE"
log "LoRa profile complete"
