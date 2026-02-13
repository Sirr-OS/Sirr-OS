#!/bin/bash
set -e

echo "[Sirr OS] Configuring dnscrypt-proxy..."

# If systemd is not PID 1 (e.g. chroot), skip runtime actions
if [ "$(ps -p 1 -o comm=)" != "systemd" ]; then
    echo "[Sirr OS] systemd not running (build environment). Skipping runtime service control."
    exit 0
fi

# Disable and mask systemd-resolved permanently
if systemctl list-unit-files | grep -q systemd-resolved; then
    echo "[Sirr OS] Disabling systemd-resolved..."

    systemctl stop systemd-resolved.service 2>/dev/null || true
    systemctl disable systemd-resolved.service 2>/dev/null || true
    systemctl mask systemd-resolved.service 2>/dev/null || true

    systemctl stop systemd-resolved.socket 2>/dev/null || true
    systemctl mask systemd-resolved.socket 2>/dev/null || true
fi

# Enable dnscrypt-proxy permanently
echo "[Sirr OS] Enabling dnscrypt-proxy..."

systemctl enable dnscrypt-proxy.service
systemctl restart dnscrypt-proxy.service

# Restart NetworkManager if present
systemctl restart NetworkManager 2>/dev/null || true

echo "[Sirr OS] dnscrypt-proxy is now permanently enabled."
echo "[Sirr OS] DNS traffic forced to 127.0.0.1:53"
