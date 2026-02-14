#!/bin/bash
set -e

echo "[Sirr OS] Configuring dnscrypt-proxy (build-time safe)..."

SYSTEMD_DIR="/etc/systemd/system"
WANTS_DIR="$SYSTEMD_DIR/multi-user.target.wants"

mkdir -p "$WANTS_DIR"

# ---------------------------------------
# Mask systemd-resolved permanently
# ---------------------------------------

if [ -f /lib/systemd/system/systemd-resolved.service ]; then
    echo "[Sirr OS] Masking systemd-resolved..."
    ln -sf /dev/null $SYSTEMD_DIR/systemd-resolved.service
fi

if [ -f /lib/systemd/system/systemd-resolved.socket ]; then
    ln -sf /dev/null $SYSTEMD_DIR/systemd-resolved.socket
fi

# ---------------------------------------
# Enable dnscrypt-proxy permanently
# ---------------------------------------

if [ -f /lib/systemd/system/dnscrypt-proxy.service ]; then
    echo "[Sirr OS] Enabling dnscrypt-proxy..."
    ln -sf /lib/systemd/system/dnscrypt-proxy.service \
           $WANTS_DIR/dnscrypt-proxy.service
fi

echo "[Sirr OS] Build-time DNS configuration complete."
