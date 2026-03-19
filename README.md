# Foxfire

Autonomous RF "rabbit" emitter for spectrum analyzer fox hunting and RF training. Drop it in the field, power it on, and hunt it down with your spectrum analyzer. Runs headless on a Raspberry Pi 4, cycling through realistic signal profiles with randomized timing.

## What It Does

Foxfire generates a rotating mix of RF signal types that look and behave like real-world traffic on a spectrum analyzer:

| Profile | Frequency | Signature |
|---------|-----------|-----------|
| **ICOM-like** | 146.52 MHz (2m) | Narrowband FM, 2.5kHz deviation, CTCSS 88.5Hz subtone, realistic PTT timing with listening gaps |
| **Walkie-talkie** | 462.5625 MHz (UHF) | Wideband FM, compressed audio, roger beep, short punchy bursts |
| **LoRa-like** | 915 MHz (ISM) | Chirp spread spectrum with 8-upchirp preamble, sync downchirps, random data symbols |
| **WiFi** | 2.4/5 GHz | Real 802.11 traffic (ping floods, iperf throughput, HTTP browsing patterns) to a portable router |

Signals are shuffled and cycled with random pauses between them, so the rabbit never looks the same twice.

## Hardware Required

| Part | Role | Approx Cost |
|------|------|-------------|
| Raspberry Pi 4 | Controller | ~$55 |
| HackRF One | RF transmitter (ICOM, walkie, LoRa profiles) | ~$350 |
| RTL-SDR | Optional monitoring/validation | ~$30 |
| GL.iNet Beryl (GL-MT1300) | WiFi traffic target | ~$50 |
| USB power bank | Field power (5V/3A for Pi + peripherals) | ~$30 |

You can skip the RTL-SDR if you don't need self-monitoring. You can skip the Beryl if you don't want the WiFi profile.

## Quick Start

### 1. Flash your Pi

Standard Raspberry Pi OS Lite (64-bit). Enable SSH, configure your user, and connect to the internet for package installation.

### 2. Clone and configure

```bash
git clone https://github.com/samedayhurt/foxfire.git
cd foxfire
cp config.env config.env.local  # optional: keep defaults as reference
```

Edit `config.env` to match your setup:

```bash
# Required: your Beryl WiFi credentials (skip if WIFI_ENABLED=false)
WIFI_SSID=your-beryl-ssid
WIFI_PASSWORD=your-beryl-password
BERYL_IP=192.168.8.1

# Tune frequencies to your licensed bands
ICOM_FREQ=146520000      # 146.52 MHz - 2m calling frequency
WALKIE_FREQ=462562500     # 462.5625 MHz - FRS channel 1
LORA_FREQ=915000000       # 915 MHz ISM band

# TX power (0-47 dB each)
HACKRF_TX_GAIN=47
HACKRF_IF_GAIN=47
```

### 3. Install

```bash
sudo ./install.sh
```

This installs all dependencies (GNU Radio, HackRF tools, RTL-SDR, iperf3, etc.), sets up udev rules for USB device permissions, and creates a systemd service that starts on boot.

### 4. Run

```bash
# Start now
sudo systemctl start rf-rabbit

# Watch logs
journalctl -u rf-rabbit -f

# Stop
sudo systemctl stop rf-rabbit
```

On next boot, it starts automatically. No monitor, keyboard, or SSH needed.

## Configuration Reference

All settings live in `/opt/rf-rabbit/config.env` after install (or `config.env` in the repo before install).

### Global

| Variable | Default | Description |
|----------|---------|-------------|
| `CYCLE_MIN_PAUSE` | 5 | Minimum seconds between signal profiles |
| `CYCLE_MAX_PAUSE` | 30 | Maximum seconds between signal profiles |
| `HACKRF_TX_GAIN` | 47 | HackRF RF gain (0-47 dB) |
| `HACKRF_IF_GAIN` | 47 | HackRF IF gain (0-47 dB) |
| `HACKRF_SAMPLE_RATE` | 2000000 | Sample rate in Hz |

### Per-Profile

Each profile (ICOM, WALKIE, LORA, WIFI) can be individually enabled/disabled and tuned:

- `*_ENABLED` - `true`/`false` to include in rotation
- `*_FREQ` - Center frequency in Hz
- `*_BURSTS` - Number of transmissions per cycle
- `*_TX_DURATION_MIN/MAX` - Randomized burst length range (seconds)

## How the Signals Work

**ICOM / Walkie**: Python generates IQ samples with numpy — FM-modulated noise shaped to voice bandwidth, with profile-specific characteristics (CTCSS subtone for ICOM, roger beep for walkie). Fed to `hackrf_transfer` for transmission.

**LoRa**: Generates proper chirp spread spectrum IQ — linear frequency sweeps with 8 upchirp preamble, 2 downchirp sync word, and randomized cyclic-shifted data symbols. Looks like real LoRa packets on a waterfall.

**WiFi**: Real 802.11 traffic. The Pi connects to the Beryl router and generates actual network traffic (ICMP floods, iperf3 throughput tests, HTTP requests) so the WiFi spectrum signature is authentic.

## Project Structure

```
foxfire/
├── install.sh           # One-shot installer
├── config.env           # All tunable parameters
├── rf-rabbit.service    # Systemd unit file
├── rabbit.sh            # Main orchestrator
├── signals/
│   ├── icom.sh          # NBFM amateur radio profile
│   ├── walkie.sh        # FRS/GMRS walkie-talkie profile
│   └── lora.sh          # LoRa chirp spread spectrum profile
└── wifi/
    └── wifi_traffic.sh  # WiFi traffic generator
```

## Tips

- **Field deployment**: Power everything from a single USB-C power bank (5V/3A). Velcro the Pi, HackRF, and Beryl together in a pelican case with the power bank.
- **Antenna matters**: Attach appropriate antennas to the HackRF for each band. A wideband discone covers all profiles but with reduced efficiency. Band-specific antennas give better range.
- **Reduce detectability**: Lower `HACKRF_TX_GAIN`, increase `CYCLE_MIN_PAUSE`, and reduce `*_BURSTS` to make the rabbit harder to find.
- **Add profiles**: Drop a new `.sh` script in `signals/`, source `config.env`, add corresponding config variables, and enable it in `rabbit.sh`'s `build_playlist()`.
- **Monitor your own output**: The RTL-SDR can be used separately to verify what the HackRF is actually putting out. Use `rtl_power` for a quick spectrum sweep.

## Legal

**You must hold appropriate licenses to transmit on any frequency.** In the US: amateur radio license for 2m/70cm, no license needed for ISM 915MHz at low power, FRS frequencies have specific rules. Check your local regulations. The authors assume no liability for illegal use.

## License

MIT
