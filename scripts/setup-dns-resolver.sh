#!/bin/bash
set -e

echo "[Sirr OS] Configuring dnscrypt-proxy..."

# Stop and fully disable systemd-resolved
if systemctl list-unit-files | grep -q systemd-resolved; then
    echo "[Sirr OS] Disabling systemd-resolved..."

    systemctl stop systemd-resolved.service 2>/dev/null || true
    systemctl stop systemd-resolved.socket 2>/dev/null || true
    systemctl stop systemd-resolved-varlink.socket 2>/dev/null || true
    systemctl stop systemd-resolved-monitor.socket 2>/dev/null || true

    systemctl disable systemd-resolved.service 2>/dev/null || true
    systemctl mask systemd-resolved.service 2>/dev/null || true
    systemctl mask systemd-resolved.socket 2>/dev/null || true
    systemctl mask systemd-resolved-varlink.socket 2>/dev/null || true
    systemctl mask systemd-resolved-monitor.socket 2>/dev/null || true
fi


# Reload systemd state
systemctl daemon-reexec

# Restart services
systemctl restart dnscrypt-proxy
systemctl restart NetworkManager 2>/dev/null || true

echo "[Sirr OS] dnscrypt-proxy setup complete."
echo "[Sirr OS] All DNS traffic now goes through 127.0.0.1:53"
