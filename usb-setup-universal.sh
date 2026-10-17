#!/bin/sh
# Best-effort USB storage setup for OpenWrt.
# Supports APK-based OpenWrt (25.12+) and opkg-based older releases.
# Kernel modules must match the exact firmware build and kernel.

set -u

say() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

if [ "$(id -u)" -ne 0 ]; then
    say "ERROR: run as root."
    exit 1
fi

if [ -r /etc/openwrt_release ]; then
    . /etc/openwrt_release
    say "==> System: ${DISTRIB_DESCRIPTION:-OpenWrt}"
else
    say "==> System: OpenWrt-compatible system (release info unavailable)"
fi
KERNEL="$(uname -r)"
ARCH="$(uname -m)"
TARGET="$(printf '%s' "${DISTRIB_TARGET:-}" | tr '[:upper:]' '[:lower:]')"
say "==> Kernel: $KERNEL"
say "==> Architecture: $ARCH"
[ -n "$TARGET" ] && say "==> OpenWrt target: $TARGET"

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

is_installed() {
    if [ "$PM" = apk ]; then
        apk info -e "$1" >/dev/null 2>&1
    else
        opkg status "$1" 2>/dev/null | grep -q '^Status: install ok installed$'
    fi
}

INSTALLED=""
FAILED_REQUIRED=""
FAILED_OPTIONAL=""
OPTIONAL_SKIPPED=""

record_result() {
    pkg="$1"
    class="$2"
    say "--- $pkg"
    if install_pkg "$pkg"; then
        INSTALLED="$INSTALLED $pkg"
        say "  result: installed/available"
    else
        if [ "$class" = required ]; then
            FAILED_REQUIRED="$FAILED_REQUIRED $pkg"
            warn "Required package failed: $pkg"
        else
            FAILED_OPTIONAL="$FAILED_OPTIONAL $pkg"
            say "  result: not installed (optional/unavailable for this build)"
        fi
    fi
}

# Core storage support and diagnostics. Filesystem support is attempted
# separately so one unavailable filesystem package does not obscure core setup.
REQUIRED="
kmod-usb-core
kmod-usb-storage
block-mount
usbutils
"
OPTIONAL="
kmod-usb-common
kmod-usb-storage-uas
kmod-fs-vfat
kmod-fs-ext4
kmod-fs-exfat
kmod-fs-ntfs3
kmod-nls-base
kmod-nls-cp437
kmod-nls-iso8859-1
kmod-nls-utf8
libusb-1.0-0
"

say
say "==> Installing core USB storage packages..."
for pkg in $REQUIRED; do
    record_result "$pkg" required
done

say
say "==> Installing optional filesystem and diagnostic support..."
for pkg in $OPTIONAL; do
    record_result "$pkg" optional
done

# Gather hardware identity. Use the OpenWrt target first, then board/device-tree
# strings as hints. Do not install a generic pile of unrelated host drivers.
IDENTITY="$TARGET"
for f in /tmp/sysinfo/board_name /tmp/sysinfo/model /proc/device-tree/compatible; do
    if [ -r "$f" ]; then
        IDENTITY="$IDENTITY $(tr '\000' ' ' < "$f" 2>/dev/null)"
    fi
done
IDENTITY="$(printf '%s' "$IDENTITY" | tr '[:upper:]' '[:lower:]')"

HOST_PKGS=""
HOST_REASON=""
case "$IDENTITY" in
    *mediatek/filogic*|*mt7981*|*mt7986*|*mt7988*)
        HOST_PKGS="kmod-usb-xhci-hcd kmod-usb-xhci-mtk kmod-usb3"
        HOST_REASON="MediaTek Filogic / MT798x: use the MediaTek xHCI controller packages; avoid generic USB2/EHCI packages."
        ;;
    *mediatek/mt7622*|*mt7622*)
        HOST_PKGS="kmod-usb-xhci-hcd kmod-usb-xhci-mtk kmod-usb3"
        HOST_REASON="MediaTek MT7622: MediaTek xHCI controller packages selected."
        ;;
    *x86/64*|*x86/generic*|*x86/legacy*|*amd64*)
        HOST_PKGS="kmod-usb-xhci-hcd kmod-usb-xhci-pci kmod-usb3 kmod-usb2"
        HOST_REASON="x86 target: PCI xHCI and common USB2/USB3 host support selected."
        ;;
    *qualcommax*|*ipq807*|*ipq60*|*ipq50*)
        HOST_PKGS="kmod-usb-xhci-hcd kmod-usb3 kmod-usb-dwc3"
        HOST_REASON="Qualcomm/IPQ target: xHCI and DWC3 candidate packages selected."
        ;;
    *)
        HOST_REASON="Hardware target is not confidently recognized; host-controller packages will not be guessed."
        ;;
esac

say
say "==> Host-controller selection"
say "  $HOST_REASON"
if [ -n "$HOST_PKGS" ]; then
    for pkg in $HOST_PKGS; do
        record_result "$pkg" optional
    done
else
    OPTIONAL_SKIPPED="host-controller packages (unknown target)"
    say "  Skipped automatic host-controller package installation."
    say "  If USB ports are not detected, identify the exact SoC/target before installing host drivers."
fi

say
say "==> Configuring storage-module autoload..."
mkdir -p /etc/modules.d
cat > /etc/modules.d/50-usb-storage <<'EOF'
usb-storage
uas
EOF
say "  Wrote /etc/modules.d/50-usb-storage (usb-storage, uas)."

say
say "==> Attempting to load storage modules..."
for module in usb-storage uas; do
    if [ -d "/sys/module/$module" ]; then
        say "  already loaded/built-in: $module"
    elif command -v modprobe >/dev/null 2>&1; then
        if modprobe "$module" 2>/dev/null; then
            say "  load command succeeded: $module"
        else
            say "  not loaded now: $module (may be unavailable or handled automatically)"
        fi
    else
        say "  modprobe unavailable; skipped immediate load of $module"
    fi
done

say
say "================ FINAL STATUS ================"
say "System: ${DISTRIB_DESCRIPTION:-OpenWrt} | kernel $KERNEL | arch $ARCH"
say "Package manager: $PM"

say
say "Core package status:"
for pkg in $REQUIRED; do
    if is_installed "$pkg"; then
        say "  OK      $pkg"
    else
        say "  MISSING $pkg"
    fi
done

say
say "Optional package status (installed packages only):"
for pkg in $OPTIONAL $HOST_PKGS; do
    [ -n "$pkg" ] || continue
    if is_installed "$pkg"; then
        say "  OK      $pkg"
    fi
done
if [ -n "$FAILED_OPTIONAL" ]; then
    say "Optional packages not installed:$FAILED_OPTIONAL"
fi

say
say "USB-related loaded modules:"
if command -v lsmod >/dev/null 2>&1; then
    lsmod | grep -iE 'xhci|usb|ehci|ohci|dwc|uas|phy' || say "  (no matching modules listed; some drivers may be built-in)"
else
    say "  lsmod unavailable"
fi

say
say "USB devices reported by lsusb:"
if command -v lsusb >/dev/null 2>&1; then
    lsusb || true
else
    say "  lsusb unavailable"
fi

say
say "Detected SCSI/USB disk devices:"
FOUND_DISK=0
for node in /sys/block/sd*; do
    [ -e "$node" ] || continue
    FOUND_DISK=1
    disk="${node##*/}"
    say "  /dev/$disk"
    for part in /dev/"$disk"[0-9]*; do
        [ -e "$part" ] && say "    partition: $part"
    done
done
if [ "$FOUND_DISK" -eq 0 ]; then
    say "  No /dev/sd* disks detected. Connect a drive and run the checks again."
fi

say
say "Block information:"
if command -v block >/dev/null 2>&1; then
    block info || true
else
    say "  block command unavailable"
fi

say
say "Recent USB/storage kernel messages:"
if command -v dmesg >/dev/null 2>&1; then
    dmesg | grep -iE 'xhci|usb-storage|uas|usb [0-9]|dwc|ehci|ohci|scsi|sd[a-z]' | tail -n 25 || true
fi

if [ -n "$FAILED_REQUIRED" ]; then
    say
    warn "One or more core packages failed:$FAILED_REQUIRED"
    warn "Check feed configuration and ensure packages match this firmware/kernel."
fi

say
say "Finished. This script does not format drives or mount them automatically."
say "For persistent mounting use LuCI > System > Mount Points."
say "After connecting a drive, run: dmesg | tail -n 30; lsusb; block info"
