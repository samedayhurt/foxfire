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

## Speculative Range & Power Analysis

The HackRF One is not a power amplifier — it's an SDR. Understanding its actual output and what that means for detection range is critical for planning your fox hunt area.

### HackRF One TX Power Budget

| Parameter | Value |
|-----------|-------|
| Max TX output (at SMA connector) | ~10-15 dBm (10-30 mW) depending on frequency |
| RF amp enabled (`-a 1`) | Adds ~11 dB, but actual output plateaus around 10-15 dBm total |
| TX VGA gain (`-x 47`) | Sets IF gain, but the analog frontend is the bottleneck |
| Usable TX range | 1 MHz - 6 GHz |
| Output impedance | 50 ohm |

**Reality check**: The HackRF's output power is roughly constant across its range, but efficiency drops significantly above ~2 GHz. At 5.8 GHz you may only see 0-5 dBm at the connector. The numbers below assume ~10 dBm (10 mW) as a conservative baseline.

### Per-Profile Range Estimates

These are **speculative estimates** based on free-space path loss (FSPL), typical receiver sensitivities, and practical field conditions. Real-world range depends heavily on antenna choice, terrain, obstructions, weather, and the sensitivity of the spectrum analyzer being used to hunt.

#### ICOM Profile — 146.52 MHz (2m band)

| Scenario | Estimated Detection Range |
|----------|--------------------------|
| HackRF rubber duck → SA with rubber duck, urban | 200-800 m (650 ft - 0.5 mi) |
| HackRF 1/4-wave whip → SA with directional yagi | 1-4 km (0.6-2.5 mi) |
| HackRF 1/4-wave whip → SA with rubber duck, open field | 0.5-2 km (0.3-1.2 mi) |
| HackRF J-pole → sensitive receiver (-130 dBm), line of sight | 5-15 km (3-9 mi) |

**Why relatively far for 10 mW**: VHF at 146 MHz has low free-space path loss (~31 dB at 1 km). The wavelength is ~2m, so it diffracts well around obstacles. Amateur receivers are extremely sensitive (-120 to -130 dBm). A proper spectrum analyzer in max hold with a narrow RBW can pull signals out of the noise floor at remarkable distances. For context, 10 mW on 2m is roughly equivalent to a handheld turned down to its lowest power setting — and hams routinely make contacts at that level with good antennas.

**FSPL at 146 MHz**: ~31 dB/km. With 10 dBm TX and a -120 dBm receiver, you have a 130 dB link budget — good for ~30 km in theoretical free space. Real-world terrain cuts this dramatically.

#### Walkie-Talkie Profile — 462.5625 MHz (UHF)

| Scenario | Estimated Detection Range |
|----------|--------------------------|
| Rubber duck → SA rubber duck, urban | 100-400 m (300-1300 ft) |
| Rubber duck → SA rubber duck, open field | 300-800 m (1000 ft - 0.5 mi) |
| 1/4-wave whip → SA with directional, open field | 0.5-2 km (0.3-1.2 mi) |
| 1/4-wave whip → sensitive receiver, line of sight | 2-8 km (1.2-5 mi) |

**Why shorter than ICOM**: UHF at 462 MHz has ~10 dB more path loss per km than 2m. The wavelength (~65 cm) doesn't diffract around buildings as well. Real FRS radios run 2W (33 dBm) — we're ~23 dB below that, so expect roughly 1/14th the range of a real walkie-talkie in comparable conditions.

**FSPL at 462 MHz**: ~41 dB/km.

#### LoRa Profile — 915 MHz (ISM band)

| Scenario | Estimated Detection Range |
|----------|--------------------------|
| Rubber duck → SA rubber duck, urban | 200-600 m (650 ft - 0.4 mi) |
| 915 MHz whip → SA with appropriate antenna, open field | 0.5-3 km (0.3-1.9 mi) |
| 915 MHz whip → LoRa receiver (SF12, -137 dBm sensitivity) | 3-10 km (1.9-6.2 mi) |
| With directional antennas both sides, line of sight | 5-20 km (3-12 mi) |

**Why surprisingly far**: LoRa's chirp spread spectrum has ~20 dB of processing gain over conventional modulation. A real LoRa receiver at SF12/125kHz has sensitivity around -137 dBm — that's 10-17 dB better than a typical FM receiver. On a spectrum analyzer, the CSS signal is spread across 125 kHz of bandwidth, so it will appear closer to the noise floor than the narrow FM profiles. You'll see it as a distinctive "chirp" waterfall pattern rather than a clean carrier. A spectrum analyzer in zero-span or waterfall mode with narrow RBW is best for spotting it.

**FSPL at 915 MHz**: ~47 dB/km. But the processing gain effectively gives you free dB at the receiver.

#### WiFi Profile — 2.4 GHz / 5 GHz

| Scenario | Estimated Detection Range |
|----------|--------------------------|
| Beryl 2.4 GHz → SA, indoor | 15-40 m (50-130 ft) |
| Beryl 2.4 GHz → SA with 2.4 GHz yagi, outdoor | 100-500 m (300 ft - 0.3 mi) |
| Beryl 5 GHz → SA, indoor | 5-20 m (15-65 ft) |
| Beryl 5 GHz → SA with directional, outdoor | 30-150 m (100-500 ft) |

**Note**: WiFi range here is from the **Beryl router**, not the HackRF. The Beryl runs ~20 dBm (100 mW) on 2.4 GHz and ~17 dBm (50 mW) on 5 GHz — significantly more power than the HackRF profiles. However, WiFi uses much higher frequencies with correspondingly higher path loss. 5 GHz is especially short-range and heavily attenuated by walls and foliage.

On a spectrum analyzer, the WiFi signal will be the widest and most obvious — 20 MHz or 40 MHz channel bandwidth with distinctive OFDM humps. Easy to spot, hard to miss.

### Antenna Impact Summary

The single biggest variable in detection range is antenna choice. These are rough gain figures:

| Antenna | Gain | Best For |
|---------|------|----------|
| HackRF rubber duck (stock) | -2 to 2 dBi | Omnidirectional, all profiles, short range |
| 1/4-wave ground plane (DIY) | 2-3 dBi | Specific band, good omnidirectional baseline |
| J-pole / slim jim | 3-6 dBi | VHF/UHF, good omnidirectional gain |
| Wideband discone | 0-3 dBi | Covers all HackRF profiles with one antenna |
| Yagi (on SA side) | 8-15 dBi | Directional hunting, dramatically extends detection range |
| Helical (915 MHz) | 10-14 dBi | LoRa profile, circular polarization |

**Rule of thumb**: Every 6 dB of antenna gain doubles your detection range. Swapping the stock rubber duck for a band-matched whip on the HackRF and a yagi on the spectrum analyzer can increase range by 4-10x.

### Planning Your Fox Hunt Area

| Difficulty | Setup | Approximate Radius |
|------------|-------|--------------------|
| Beginner | All profiles on, stock antennas, open park | 200-500 m |
| Intermediate | Reduced TX gain (20 dB), mixed terrain, band-matched antennas | 500 m - 2 km |
| Advanced | Single profile enabled, long cycle pauses, minimal TX gain, concealed in urban area | 1-5 km |
| Expert | LoRa only, low gain, directional antenna pointing away from start, heavy foliage | 2-10+ km |

## Troubleshooting

### HackRF not detected / `hackrf_info` fails

| Symptom | Cause | Fix |
|---------|-------|-----|
| `No HackRF boards found` | Not plugged in, or USB hub issue | Plug HackRF directly into a Pi USB port, not through a hub |
| `Input/Output Error (-1000)` | USB power insufficient or flaky connection | Use a powered USB hub or plug directly into Pi USB 3.0 (blue) port. Try a different cable. |
| `Resource busy (-1000)` | Another process (like rf-rabbit service) already has the device open | `sudo systemctl stop rf-rabbit` before running manual commands |
| HackRF disappears after USB reset | Known Pi 4 USB controller quirk | Physically unplug and replug the HackRF |

### Service crashes / restart loop

| Symptom | Cause | Fix |
|---------|-------|-----|
| `hackrf_transfer` dumps usage help and exits | Bad arguments to hackrf_transfer | Check that IQ file was generated (look for `/tmp/*_iq.raw`). Ensure config.env values are valid numbers. |
| Pi becomes unresponsive | Service restart loop (10s intervals) with RTL-SDR wait (60s each) saturating resources | Power cycle Pi, then `sudo systemctl stop rf-rabbit` immediately on boot. Disable RTL-SDR wait or set `RTLSDR_ENABLED=false` if no RTL-SDR is connected. |
| `set -e` kills the script unexpectedly | Any command returning non-zero exits the whole script | Check `journalctl -u rf-rabbit` for the exact failing line |

### WiFi traffic not working

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Could not connect to <SSID>` | Wrong SSID/password, or Beryl not powered on | Verify `WIFI_SSID` and `WIFI_PASSWORD` in config.env. Ensure Beryl is on and broadcasting. |
| `nmcli` not found | NetworkManager not installed | `sudo apt install network-manager` and ensure it manages wlan0 |
| iperf3 shows no throughput | No iperf3 server on Beryl | The script falls back to HTTP requests automatically. For full throughput testing, install iperf3 on the Beryl via its package manager. |

### USB Power Budget

The Pi 4 supplies limited current over USB. Running HackRF + RTL-SDR + Ubertooth simultaneously through a passive hub will cause brownouts. Solutions:
- Use a **powered** USB hub (5V/2A+ per port)
- Plug the HackRF directly into the Pi (it draws the most current during TX)
- If devices keep disconnecting, reduce `HACKRF_TX_GAIN` — higher gain = higher current draw

### Verifying Transmissions

If you're unsure whether the HackRF is actually transmitting:
```bash
# Quick manual test (transmit 1s of silence on 915MHz)
dd if=/dev/zero bs=2000000 count=2 > /tmp/test.raw
sudo hackrf_transfer -t /tmp/test.raw -f 915000000 -s 2000000 -x 47 -a 1 -n 4000000
```
You should see `MiB/second` throughput in the output and a carrier on your spectrum analyzer at 915MHz.

## Legal

**You must hold appropriate licenses to transmit on any frequency.** In the US: amateur radio license for 2m/70cm, no license needed for ISM 915MHz at low power, FRS frequencies have specific rules. Check your local regulations. The authors assume no liability for illegal use.

## License

MIT
