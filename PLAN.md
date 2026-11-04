# Implementation Plan: Porting OpenWrt to Tenda W15E v2.0

This plan outlines the end-to-end steps required to port, compile, and flash **OpenWrt** onto the **Tenda W15E v2.0** (Qualcomm Atheros QCA9531 SoC, 16 MB Flash, 128 MB RAM).

---

## Architecture Overview

```mermaid
flowchart TD
    subgraph Phase 1: Hardware & Backup
        A[Open Casing & Solder UART] --> B[Capture Boot Log in U-Boot]
        B --> C[Backup Full Flash & ART Partition]
    end

    subgraph Phase 2: OpenWrt Source & DTS
        D[Clone OpenWrt Source] --> E[Write Device Tree .dts]
        E --> F[Register Board in ath79 Target]
    end

    subgraph Phase 3: Zero-Risk RAM Boot
        G[Compile initramfs-kernel.bin] --> H[Setup TFTP Server]
        H --> I[Boot OpenWrt from RAM via U-Boot]
    end

    subgraph Phase 4: Bring-Up & Validation
        I --> J[Verify LAN/WAN Switch Ports]
        J --> K[Verify 2.4GHz & 5GHz Radios]
        K --> L[Map Status LEDs & Reset Button GPIOs]
    end

    subgraph Phase 5: Permanent Flashing
        L --> M[Build Sysupgrade/Factory Image]
        M --> N[Flash to SPI NOR Flash]
    end

    Phase 1 --> Phase 2 --> Phase 3 --> Phase 4 --> Phase 5
```

---

## Phase 1: Hardware Setup & Critical Backups

### 1.1 Connect UART Serial Console
* **Pinout**: Locate the 4-pin unpopulated UART header on the PCB (`VCC (3.3V)`, `GND`, `TX`, `RX`).
  > [!WARNING]
  > **Do NOT connect the 3.3V VCC pin** to your USB-to-UART adapter. Connect only **GND**, **TX**, and **RX** to prevent electrical conflicts.
* **Serial Parameters**:
  * Baud rate: `115200`
  * Data bits: `8`, Parity: `None`, Stop bits: `1`, Flow control: `None`
* Verify you can see U-Boot output and interrupt the autoboot countdown by pressing any key.

### 1.2 Back Up Full Flash & `art` Partition
Before writing anything to the flash, you **must preserve the Atheros Radio Test (ART) partition** located at the end of the 16 MB flash (`0xff0000`–`0x1000000`). If lost, wireless calibration is permanently destroyed.
* In U-Boot:
  ```text
  # Read full 16MB SPI flash into RAM
  sf probe
  sf read 0x81000000 0x0 0x1000000

  # Send to your TFTP server
  tftpput 0x81000000 0x1000000 full_flash_backup.bin
  ```

---

## Phase 2: OpenWrt Build Environment & Device Tree

### 2.1 Clone OpenWrt Source Tree
```bash
git clone -b openwrt-23.05 https://github.com/openwrt/openwrt.git
cd openwrt
./scripts/feeds update -a
./scripts/feeds install -a
```

### 2.2 Define the Device Tree (`.dts`)
Create `target/linux/ath79/dts/qca9531_tenda_w15e-v2.dts`:

```dts
/dts-v1/;

#include "qca953x.dtsi"
#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>

/ {
    compatible = "tenda,w15e-v2", "qca,qca9531";
    model = "Tenda W15E v2.0";

    aliases {
        led-boot = &led_sys;
        led-failsafe = &led_sys;
        led-running = &led_sys;
    };

    keys {
        compatible = "gpio-keys";

        reset {
            label = "reset";
            linux,code = <KEY_RESTART>;
            gpios = <&gpio 17 GPIO_ACTIVE_LOW>;
            debounce-interval = <60>;
        };
    };

    leds {
        compatible = "gpio-leds";

        led_sys: sys {
            label = "green:sys";
            gpios = <&gpio 1 GPIO_ACTIVE_LOW>;
            default-state = "on";
        };
    };
};

&spi {
    status = "okay";

    flash@0 {
        compatible = "jedec,spi-nor";
        reg = <0>;
        spi-max-frequency = <25000000>;

        partitions {
            compatible = "fixed-partitions";
            #address-cells = <1>;
            #size-cells = <1>;

            partition@0 {
                label = "u-boot";
                reg = <0x000000 0x040000>; /* 256 KB */
                read-only;
            };

            partition@40000 {
                label = "firmware";
                reg = <0x040000 0xfb0000>; /* ~15.68 MB */
                compatible = "denx,uimage";
            };

            art: partition@ff0000 {
                label = "art";
                reg = <0xff0000 0x010000>; /* 64 KB */
                read-only;
            };
        };
    };
};

&eth0 {
    status = "okay";
    phy-handle = <&phy0>;
    phy-mode = "mii";
};

&wmac {
    status = "okay";
    mtd-cal-data = <&art 0x1000>;
};

&pcie {
    status = "okay";

    wifi@0,0 {
        compatible = "qcom,ath10k";
        reg = <0x0000 0 0 0 0>;
        mtd-cal-data = <&art 0x5000>;
    };
};
```

### 2.3 Register Board in Target Makefile
Edit `target/linux/ath79/image/generic.mk`:

```makefile
define Device/tenda_w15e-v2
  SOC := qca9531
  DEVICE_VENDOR := Tenda
  DEVICE_MODEL := W15E
  DEVICE_VARIANT := v2
  DEVICE_PACKAGES := kmod-ath10k ath10k-firmware-qca9887 kmod-usb-core
  IMAGE_SIZE := 16064k
  SUPPORTED_DEVICES += tenda,w15e-v2
endef
TARGET_DEVICES += tenda_w15e-v2
```

---

## Phase 3: Zero-Risk RAM Boot (`initramfs`)

To verify the build without flashing or risking a brick:

### 3.1 Build `initramfs` Image
```bash
make menuconfig
# Select:
# Target System: Atheros ATH79
# Subtarget: Generic devices with MIPS 24Kc
# Target Profile: Tenda W15E v2
# Target Images -> [*] ramdisk (initramfs)

make -j$(nproc)
```
Output artifact: `bin/targets/ath79/generic/openwrt-ath79-generic-tenda_w15e-v2-initramfs-kernel.bin`

### 3.2 Boot over TFTP in U-Boot
1. Place the `initramfs-kernel.bin` into your local TFTP server directory.
2. In U-Boot over UART:
   ```text
   setenv ipaddr 192.168.0.1
   setenv serverip 192.168.0.100
   tftpboot 0x80060000 openwrt-ath79-generic-tenda_w15e-v2-initramfs-kernel.bin
   bootm 0x80060000
   ```
3. OpenWrt will unpack directly into DDR RAM. The onboard flash remains 100% untouched.

---

## Phase 4: Hardware Validation

Once the system boots into the OpenWrt console over serial:

1. **Verify Network Interfaces & Switch:**
   * Test each physical Ethernet port by plugging in a cable:
     ```bash
     ip link show
     logread -e "link up"
     ```
   * Confirm WAN vs LAN port mapping.
2. **Verify 2.4 GHz & 5 GHz Wi-Fi:**
   * Check wireless interfaces:
     ```bash
     iw dev
     iw phy
     ```
   * Ensure `ath9k` and `ath10k` successfully read calibration data without errors.
3. **Trace GPIOs for LEDs & Buttons:**
   * Read button state via `cat /sys/kernel/debug/gpio`.
   * Toggle GPIOs to find exact pin assignments for the system, Wi-Fi, and WAN LEDs.
   * Update the `.dts` file with confirmed GPIO numbers.

---

## Phase 5: Permanent Flashing

1. Build the production sysupgrade image:
   ```bash
   make -j$(nproc)
   ```
   Artifact: `openwrt-ath79-generic-tenda_w15e-v2-squashfs-sysupgrade.bin`
2. Flash from the running `initramfs` RAM session:
   ```bash
   sysupgrade -n /tmp/openwrt-ath79-generic-tenda_w15e-v2-squashfs-sysupgrade.bin
   ```
3. Reboot and access OpenWrt LuCI web interface at `http://192.168.1.1`.
