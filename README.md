# install_USB_owrt

Best-effort USB storage setup script for OpenWrt. Supports builds using `apk` (OpenWrt 25.12+) and older builds using `opkg`.

## Run directly on the router

Run as root over SSH:

```sh
sh -c "$(wget -O- https://raw.githubusercontent.com/TMN88/install_USB_owrt/main/usb-setup-universal.sh)"
```

## What it does

- Updates package indexes and installs core USB storage packages.
- Separately attempts optional filesystem support (FAT/VFAT, ext4, exFAT, NTFS3), UAS and diagnostic utilities.
- Selects host-controller packages only for recognized targets. For MediaTek Filogic / MT798x it avoids the generic `kmod-usb2` package, which can pull in unrelated legacy EHCI drivers.
- If the hardware target is not confidently recognized, it skips automatic host-controller guessing rather than installing a broad set of unrelated drivers.
- Configures `usb-storage` and `uas` module autoload.
- Prints a final report showing core package status, optional packages, loaded modules, USB devices, detected `/dev/sd*` disks and recent kernel messages.

## Important limitations

- “Universal” means best-effort, not guaranteed compatibility with every router.
- Kernel module packages must match the exact firmware build and kernel. Do not force-install incompatible kmods.
- A listed USB root hub is not proof that a flash drive is detected. Connect a drive and check the final report.
- The script does not format drives or mount them automatically. Configure persistent mounting in LuCI under **System → Mount Points**.
- Review the script before running it, especially on routers that are critical to your network.
