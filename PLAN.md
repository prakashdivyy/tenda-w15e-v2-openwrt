# Implementation Plan: Porting OpenWrt to Tenda W15E v2.0

This plan outlines the end-to-end steps required to port, compile, and flash **OpenWrt** onto the **Tenda W15E v2.0** (Qualcomm Atheros QCA9531 SoC, 16 MB Flash, 128 MB RAM).

---

## Architecture Overview

```mermaid
flowchart TD
    subgraph Phase 1: Hardware & Flash Backup
        A["Hardware Programmer (CH341A + SOP8 Clip) OR UART"] --> B["Dump 16 MB SPI Flash"]
        B --> C["Extract & Validate 64 KB ART Partition (0xff0000)"]
    end

    subgraph Phase 2: OpenWrt Source & DTS [COMPLETED]
        D["Clone OpenWrt 23.05"] --> E["Write Device Tree .dts (qca9531)"]
        E --> F["Register Board in ath79 Target"]
    end

    subgraph Phase 3: Firmware Image Compilation [COMPLETED]
        G["Compile initramfs-kernel.bin"]
        G --> H["Compile squashfs-sysupgrade.bin"]
        H --> I["Wrap Transition Image (openwrt-tenda_w15e-v2-transition.bin)"]
    end

    subgraph Phase 4: Flashing Paths
        I --> J1["Path A: 2-Stage Web Upgrade (No Soldering)"]
        I --> J2["Path B: Direct UART / TFTP Boot"]
        I --> J3["Path C: Direct Hardware Flash (CH341A)"]
    end

    subgraph Phase 5: Hardware Bring-Up & Validation
        J1 --> K["Verify LAN/WAN Switch Ports (qca_shival)"]
        J2 --> K
        J3 --> K
        K --> L["Verify 2.4GHz (ath9k) & 5GHz (ath10k) Radios"]
        L --> M["Verify Status LEDs & Reset Button GPIOs"]
    end

    Phase 1 --> Phase 2 --> Phase 3 --> Phase 4 --> Phase 5
```

---

## Phase 1: Hardware Setup & Critical Backups

### 1.1 Non-Invasive Hardware Backup (CH341A + SOP8 Clip)
If you have a **CH341A programmer + SOP8 test clip**:
1. Keep the router **powered OFF and unplugged**.
2. Connect the SOP8 test clip to the 16 MB SPI flash chip (Winbond W25Q128 / GD25Q128) on the board (Pin 1 red wire matching the chip dot/notch).
3. Connect the CH341A USB adapter to your PC.
4. Read the flash twice and confirm matching MD5 hashes:
   ```bash
   flashrom -p ch341a_spi -r backup1.bin
   flashrom -p ch341a_spi -r backup2.bin
   diff backup1.bin backup2.bin
   ```
5. Extract the Atheros Radio Test (ART) calibration partition:
   ```bash
   python3 scripts/dump_art_extractor.py backup1.bin art_factory.bin
   ```

### 1.2 Alternative: Connect UART Serial Console
* **Pinout**: Locate the 4-pin unpopulated UART header labeled `J1` on the PCB (`VCC 3.3V`, `GND`, `TX`, `RX`).
  > [!WARNING]
  > **Do NOT connect the 3.3V VCC pin** to your USB-to-UART adapter. Connect only **GND**, **TX**, and **RX** to prevent electrical conflicts.
* **Serial Parameters**: `115200 8N1`, No flow control.

---

## Phase 2: OpenWrt Build Environment & Device Tree [Status: DONE]

### 2.1 Device Tree Specification (`dts/qca9531_tenda_w15e-v2.dts`)
The working Device Tree has been defined and tested:

```dts
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
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
		led-upgrade = &led_sys;
		label-mac-device = &eth0;
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

		wlan2g {
			label = "green:wlan2g";
			gpios = <&gpio 12 GPIO_ACTIVE_LOW>;
			linux,default-trigger = "phy0tpt";
		};

		wlan5g {
			label = "green:wlan5g";
			gpios = <&gpio 13 GPIO_ACTIVE_LOW>;
			linux,default-trigger = "phy1tpt";
		};

		wan {
			label = "green:wan";
			gpios = <&gpio 4 GPIO_ACTIVE_LOW>;
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
				reg = <0x000000 0x040000>;
				read-only;
			};

			partition@40000 {
				label = "firmware";
				reg = <0x040000 0xfb0000>;
				compatible = "denx,uimage";
			};

			art: partition@ff0000 {
				label = "art";
				reg = <0xff0000 0x010000>;
				read-only;
			};
		};
	};
};

&eth0 {
	status = "okay";
	phy-handle = <&swphy4>;

	nvmem-cells = <&macaddr_art_0>;
	nvmem-cell-names = "mac-address";
};

&eth1 {
	status = "okay";
	phy-handle = <&swphy0>;

	nvmem-cells = <&macaddr_art_0>;
	nvmem-cell-names = "mac-address";
	mac-address-increment = <1>;
};

&wmac {
	status = "okay";
	mtd-cal-data = <&art 0x1000>;

	nvmem-cells = <&macaddr_art_0>;
	nvmem-cell-names = "mac-address";
};

&pcie0 {
	status = "okay";

	wifi@0,0 {
		compatible = "qcom,ath10k";
		reg = <0 0 0 0 0>;
		mtd-cal-data = <&art 0x5000>;
		device_type = "pci";

		nvmem-cells = <&macaddr_art_0>;
		nvmem-cell-names = "mac-address";
		mac-address-increment = <2>;
	};
};

&art {
	compatible = "nvmem-cells";
	#address-cells = <1>;
	#size-cells = <1>;

	macaddr_art_0: macaddr@0 {
		reg = <0x0 0x6>;
	};
};
```

---

## Phase 3: Firmware Compilation & Output Artifacts [Status: DONE]

The images were built cleanly inside the Docker build container (`scripts/docker_build.sh`):

* `bin/openwrt-tenda_w15e-v2-transition.bin` (5.96 MB) — **Stage 1 Transition Web Image**
* `bin/openwrt-ath79-generic-tenda_w15e-v2-squashfs-sysupgrade.bin` (6.1 MB) — **Stage 2 Final Flash Image**
* `bin/openwrt-ath79-generic-tenda_w15e-v2-initramfs-kernel.bin` (5.7 MB) — **Direct TFTP RAM Test Image**

---

## Phase 4: Flashing Paths

### Option A: The 2-Stage Web Interface Transition (Recommended)
1. **Stage 1**: Navigate to Tenda Web UI (`192.168.0.1`) $\rightarrow$ **Administration / Firmware Upgrade** $\rightarrow$ **Local Upgrade**. Upload `openwrt-tenda_w15e-v2-transition.bin`.
2. Router boots OpenWrt entirely in RAM at `192.168.1.1`.
3. **Stage 2**: Navigate to OpenWrt LuCI (`192.168.1.1`) $\rightarrow$ **System** $\rightarrow$ **Backup / Flash Firmware**. Upload `openwrt-ath79-generic-tenda_w15e-v2-squashfs-sysupgrade.bin` (uncheck "Keep settings").
4. Router writes flash and reboots into permanent OpenWrt!

### Option B: Zero-Flash RAM Boot via U-Boot TFTP
1. Host `openwrt-ath79-generic-tenda_w15e-v2-initramfs-kernel.bin` on a local TFTP server (`192.168.0.100`).
2. In U-Boot serial console:
   ```text
   setenv ipaddr 192.168.0.1
   setenv serverip 192.168.0.100
   tftpboot 0x80060000 openwrt-ath79-generic-tenda_w15e-v2-initramfs-kernel.bin
   bootm 0x80060000
   ```

---

## Phase 5: Hardware Bring-Up & Validation

Once OpenWrt boots:
1. **Ethernet Switch**: Verify all 5 physical ports toggle link up/down (`ip link show`, `logread -e "link"`).
2. **Wi-Fi Radios**: Confirm `ath9k` (2.4 GHz) and `ath10k` (5 GHz) start with proper MAC and calibration (`iw phy`, `iw dev`).
3. **LEDs & Buttons**: Verify the system LED, Wi-Fi LEDs, and reset button behavior.
