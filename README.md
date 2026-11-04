# OpenWrt Port for Tenda W15E v2.0

This directory contains all source files, patches, build scripts, and utilities for building and deploying **OpenWrt** on the **Tenda W15E v2.0** wireless enterprise router.

---

## Hardware Specifications

| Component | Hardware Details |
| :--- | :--- |
| **SoC** | Qualcomm Atheros **QCA9531** (MIPS 24Kc @ 650 MHz) |
| **OpenWrt Target** | `ath79/generic` |
| **Flash** | **16 MB** SPI NOR Flash (`0x1000000` bytes) |
| **RAM** | **128 MB** DDR2 |
| **Ethernet Switch** | Qualcomm `qca_shival` (5x 10/100 Mbps Fast Ethernet: 1-4 WAN, 1-4 LAN configurable) |
| **2.4 GHz Wi-Fi** | Integrated in QCA9531 (2x2 MIMO 802.11b/g/n, driven by `ath9k`) |
| **5 GHz Wi-Fi** | PCIe radio (802.11a/n/ac up to 867 Mbps, driven by `ath10k`) |
| **Calibration** | Stored in 64 KB `art` partition at flash offset `0xff0000` |

---

## Directory Contents

```text
openwrt-port/
├── README.md                      # This documentation
├── dts/
│   └── qca9531_tenda_w15e-v2.dts  # OpenWrt Device Tree source
├── patches/
│   └── 01-add-tenda-w15e-v2.patch # Git patch for target/linux/ath79/image/generic.mk
└── scripts/
    ├── build_openwrt.sh           # Automated build script (clones, configures & compiles)
    ├── wrap_tenda_firmware.py     # Packages OpenWrt with Tenda 64-byte vendor upgrade header
    └── dump_art_extractor.py      # Extracts and validates the 64 KB ART calibration partition
```

---

## Quick Start: Building OpenWrt

### 1. Prerequisites (Ubuntu / Debian / macOS)
* **Debian / Ubuntu**:
  ```bash
  sudo apt-get update
  sudo apt-get install build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
       gettext git libncurses5-dev libssl-dev python3-distutils rsync unzip zlib1g-dev file wget
  ```
* **macOS (Homebrew)**:
  ```bash
  brew install coreutils findutils diffutils gnu-tar gawk gnu-sed grep
  ```

### 2. Run the Build Script
```bash
chmod +x scripts/build_openwrt.sh
./scripts/build_openwrt.sh
```

The script will:
1. Clone the stable `openwrt-23.05` branch into `openwrt/`.
2. Copy the custom `qca9531_tenda_w15e-v2.dts` into `target/linux/ath79/dts/`.
3. Patch `target/linux/ath79/image/generic.mk` to register the `tenda_w15e-v2` profile.
4. Generate the build configuration.
5. Compile both:
   * **RAM-boot test image**: `openwrt-ath79-generic-tenda_w15e-v2-initramfs-kernel.bin`
   * **Production flash image**: `openwrt-ath79-generic-tenda_w15e-v2-squashfs-sysupgrade.bin`

---

## Safe Testing via RAM Boot (Zero Risk)

1. Connect a 3.3V USB-to-UART adapter to the router (GND, TX, RX only; 115200 baud).
2. Set up a TFTP server on your PC (IP `192.168.0.100`) hosting the compiled `initramfs-kernel.bin`.
3. In U-Boot over serial:
   ```text
   setenv ipaddr 192.168.0.1
   setenv serverip 192.168.0.100
   tftpboot 0x80060000 openwrt-ath79-generic-tenda_w15e-v2-initramfs-kernel.bin
   bootm 0x80060000
   ```
4. OpenWrt boots completely inside RAM. Onboard SPI flash remains untouched.
