# install_USB_owrt

Universal, best-effort USB storage setup script for OpenWrt.

## Run directly on the router

Run as root over SSH:

```sh
sh -c "$(wget -O- https://raw.githubusercontent.com/TMN88/install_USB_owrt/main/usb-setup-universal.sh)"
```

The script supports OpenWrt builds using `apk` and older builds using `opkg`. It installs common USB storage, filesystem, and diagnostic packages; attempts to select likely host-controller packages based on board information; configures storage-module autoload; and prints diagnostic output.

## Important limitations

- USB host-controller drivers depend on the router hardware and firmware.
- Kernel module packages must match the exact kernel/build and configured package feeds.
- The script is best-effort, not guaranteed to work on every OpenWrt device.
- It does not format a drive or mount it automatically. Configure persistent mounting in LuCI under **System → Mount Points**.
- Review the script before running it, especially on routers that are critical to your network.
