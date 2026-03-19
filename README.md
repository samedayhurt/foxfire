# RF Rabbit Emitter

Autonomous RF signal emitter for spectrum analyzer training. Runs headless on RPi4 with HackRF One, RTL-SDR, and GL.iNet Beryl.

## Signal Profiles
- **ICOM-like**: Narrowband FM on 2m/70cm amateur frequencies
- **Walkie-talkie (FRS/GMRS-like)**: FM on UHF
- **LoRa-like**: Chirp spread spectrum bursts
- **WiFi traffic**: Continuous data exchange with Beryl router

## Hardware
- Raspberry Pi 4
- HackRF One (TX)
- RTL-SDR (monitoring/validation)
- GL.iNet Beryl (WiFi target)

## Quick Install
```bash
sudo ./install.sh
```
