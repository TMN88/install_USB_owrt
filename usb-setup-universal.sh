#!/bin/sh
# Best-effort USB storage setup for OpenWrt.
# Supports APK-based OpenWrt (25.12+) and opkg-based OpenWrt (older releases).
# No script can guarantee support on every router: USB host-controller drivers
# and kernel packages vary by target and must match the running kernel exactly.

set -u

say() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

if [ "$(id -u)" -ne 0 ]; then
    say "ERROR: run as root (usually: sh usb-setup-universal.sh)"
    exit 1
fi

if [ -r /etc/openwrt_release ]; then
    . /etc/openwrt_release
    say "==> System: ${DISTRIB_DESCRIPTION:-OpenWrt}"
else
    say "==> System: OpenWrt-compatible system (release info unavailable)"
fi
say "==> Kernel: $(uname -r)"
say "==> Architecture: $(uname -m)"

if command -v apk >/dev/null 2>&1; then
    PM=apk
elif command -v opkg >/dev/null 2>&1; then
    PM=opkg
else
    say "ERROR: neither apk nor opkg was found; cannot install packages."
    exit 1
fi
say "==> Package manager: $PM"

say "==> Updating package indexes..."
if [ "$PM" = apk ]; then
    if ! apk update; then
        say "ERROR: apk update failed. Check network and repository configuration."
        exit 1
    fi
else
    if ! opkg update; then
        say "ERROR: opkg update failed. Check network and repository configuration."
        exit 1
    fi
fi

install_pkg() {
    if [ "$PM" = apk ]; then
        apk add "$1"
    else
        opkg install "$1"
    fi
}

REQUIRED="
kmod-usb-common
kmod-usb-core
kmod-usb-storage
kmod-usb-storage-uas
kmod-fs-vfat
kmod-fs-ext4
kmod-fs-exfat
kmod-fs-ntfs3
kmod-nls-base
kmod-nls-cp437
kmod-nls-iso8859-1
kmod-nls-utf8
block-mount
usbutils
libusb-1.0-0
"

say "==> Installing USB storage, filesystem support and tools..."
FAILED=""
for pkg in $REQUIRED; do
    say "--- $pkg"
    if ! install_pkg "$pkg"; then
        warn "Could not install $pkg (it may be unavailable or named differently in this build)."
        FAILED="$FAILED $pkg"
    fi
done

COMPAT=""
for f in /tmp/sysinfo/board_name /tmp/sysinfo/model /proc/device-tree/compatible; do
    if [ -r "$f" ]; then
        COMPAT="$COMPAT $(tr '\000' ' ' < "$f" 2>/dev/null)"
    fi
done
COMPAT="$(printf '%s' "$COMPAT" | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$COMPAT" in
    *mediatek*|*mt798*|*mt7622*|*mt7623*)
        HOST_PKGS="kmod-usb-xhci-hcd kmod-usb-xhci-mtk kmod-usb3 kmod-usb2"
        ;;
    *x86*|*amd64*)
        HOST_PKGS="kmod-usb-xhci-hcd kmod-usb-xhci-pci kmod-usb3 kmod-usb2 kmod-usb-ehci kmod-usb-ohci"
        ;;
    *bcm*|*broadcom*)
        HOST_PKGS="kmod-usb-xhci-hcd kmod-usb2 kmod-usb3 kmod-usb-ehci kmod-usb-ohci"
        ;;
    *qcom*|*qualcomm*|*ipq*)
        HOST_PKGS="kmod-usb-xhci-hcd kmod-usb3 kmod-usb2 kmod-usb-dwc3 kmod-usb-dwc2"
        ;;
    *)
        # Generic fallback. Package manager/repository will reject unavailable
        # or incompatible packages; host controller drivers are platform-specific.
        HOST_PKGS="kmod-usb-xhci-hcd kmod-usb3 kmod-usb2 kmod-usb-dwc2 kmod-usb-dwc3 kmod-usb-ehci kmod-usb-ohci"
        ;;
esac

say "==> Trying likely USB host-controller packages..."
for pkg in $HOST_PKGS; do
    say "--- $pkg"
    if ! install_pkg "$pkg"; then
        say "  Not installed (may be unnecessary or unavailable for this build)."
    fi
done

say "==> Configuring storage-module autoload..."
mkdir -p /etc/modules.d
cat > /etc/modules.d/50-usb-storage <<'EOF'
usb-storage
uas
EOF

say "==> Attempting to load storage drivers now..."
for module in usb-storage uas; do
    if command -v modprobe >/dev/null 2>&1; then
        if modprobe "$module" 2>/dev/null; then
            say "  loaded/available: $module"
        else
            say "  note: $module did not load now; it may be built-in, already loaded, or unavailable."
        fi
    fi
done

say
say "==> Loaded USB-related modules:"
if command -v lsmod >/dev/null 2>&1; then
    lsmod | grep -iE 'xhci|usb|ehci|ohci|dwc|uas|phy' || true
fi

say
say "==> USB devices:"
if command -v lsusb >/dev/null 2>&1; then
    lsusb || true
else
    say "(lsusb unavailable)"
fi

say
say "==> Block devices:"
if command -v block >/dev/null 2>&1; then
    block info || true
fi

say
say "==> Recent USB messages:"
if command -v dmesg >/dev/null 2>&1; then
    dmesg | grep -iE 'xhci|usb-storage|uas|usb [0-9]|dwc|ehci|ohci' | tail -n 20 || true
fi

if [ -n "$FAILED" ]; then
    say
    warn "Some packages could not be installed:$FAILED"
    warn "Review the output above. Package availability depends on the firmware build."
fi

say
say "==> Finished. Connect a USB drive and check: dmesg | tail -n 30; lsusb; block info"
say "==> This script does not format drives or mount them automatically."
say "==> Configure persistent mounting in LuCI > System > Mount Points."
