#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== RF Rabbit Emitter - Installer ==="

# --- Package dependencies ---
echo "[1/5] Installing system packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
  gnuradio \
  hackrf \
  gr-osmosdr \
  rtl-sdr \
  python3-numpy \
  python3-scipy \
  iperf3 \
  wavemon \
  nmap \
  curl \
  jq \
  python3-pip \
  screen

# --- Python deps ---
echo "[2/5] Installing Python packages..."
pip3 install --break-system-packages 2>/dev/null || true
pip3 install numpy scipy 2>/dev/null || true

# --- Permissions for HackRF/RTL-SDR ---
echo "[3/5] Setting up udev rules..."
sudo tee /etc/udev/rules.d/99-hackrf.rules > /dev/null <<'UDEV'
SUBSYSTEM=="usb", ATTR{idVendor}=="1d50", ATTR{idProduct}=="6089", MODE="0666", GROUP="plugdev"
UDEV
sudo tee /etc/udev/rules.d/99-rtlsdr.rules > /dev/null <<'UDEV'
SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="2838", MODE="0666", GROUP="plugdev"
UDEV
sudo udevadm control --reload-rules
sudo udevadm trigger

# --- Install project files ---
echo "[4/5] Installing rf-rabbit files..."
sudo mkdir -p /opt/rf-rabbit
sudo cp -r "$SCRIPT_DIR"/signals /opt/rf-rabbit/
sudo cp -r "$SCRIPT_DIR"/wifi /opt/rf-rabbit/
sudo cp "$SCRIPT_DIR"/rabbit.sh /opt/rf-rabbit/
sudo cp "$SCRIPT_DIR"/config.env /opt/rf-rabbit/
sudo chmod +x /opt/rf-rabbit/rabbit.sh
sudo chmod +x /opt/rf-rabbit/signals/*.sh
sudo chmod +x /opt/rf-rabbit/wifi/*.sh

# --- Systemd service ---
echo "[5/5] Installing systemd service..."
sudo cp "$SCRIPT_DIR"/rf-rabbit.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable rf-rabbit.service

echo ""
echo "=== Installation complete ==="
echo "Start now:  sudo systemctl start rf-rabbit"
echo "Check logs: journalctl -u rf-rabbit -f"
echo "Stop:       sudo systemctl stop rf-rabbit"
echo ""
echo "Edit /opt/rf-rabbit/config.env to tune frequencies/timing."
