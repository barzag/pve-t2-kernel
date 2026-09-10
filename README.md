# Proxmox Mac mini T2 Kernel

Personal kernel builds for **Mac mini 2018 (Macmini8,1)** running Proxmox on Debian Trixie.

- **Patches:** T2 Linux AppleSMC 3001–3006 + 3008, for sensors and fan support.
- **Builds:** upstream checks every 6 hours; automatic prereleases after successful compilation.

## Install
Download both `.deb` files and `SHA256SUMS` from [Releases](https://github.com/barzag/proxmox-macmini-t2-kernel/releases). In their folder, as root:

    sha256sum -c SHA256SUMS
    apt install ./*.deb

Reboot and check `uname -r`. Keep a working kernel and local console access: builds are not hardware-validated or Secure Boot signed.

## Recovery
If boot fails, select the previous kernel from the boot menu.

Thanks to [Proxmox](https://www.proxmox.com/) and [T2 Linux](https://github.com/t2linux/linux-t2-patches).
