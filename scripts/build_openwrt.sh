#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PORT_DIR}/openwrt-build"
BRANCH="openwrt-23.05"

echo "=========================================================="
echo " OpenWrt Build Setup for Tenda W15E v2.0"
echo "=========================================================="

# 1. Clone OpenWrt
if [ ! -d "${BUILD_DIR}/.git" ]; then
    echo "[1/5] Cloning OpenWrt ${BRANCH}..."
    git clone --depth 1 -b "${BRANCH}" https://github.com/openwrt/openwrt.git "${BUILD_DIR}"
else
    echo "[1/5] OpenWrt source tree already exists in ${BUILD_DIR}."
fi

cd "${BUILD_DIR}"

# 2. Update Feeds
echo "[2/5] Updating and installing OpenWrt feeds..."
./scripts/feeds update -a
./scripts/feeds install -a

# 3. Install Device Tree
echo "[3/5] Installing Device Tree (qca9531_tenda_w15e-v2.dts)..."
cp "${PORT_DIR}/dts/qca9531_tenda_w15e-v2.dts" "${BUILD_DIR}/target/linux/ath79/dts/"

# 4. Patch Target Makefile
echo "[4/5] Patching target/linux/ath79/image/generic.mk..."
if git apply --check "${PORT_DIR}/patches/01-add-tenda-w15e-v2.patch" >/dev/null 2>&1; then
    git apply "${PORT_DIR}/patches/01-add-tenda-w15e-v2.patch"
    echo "       Patch applied cleanly."
else
    if grep -q "tenda_w15e-v2" "${BUILD_DIR}/target/linux/ath79/image/generic.mk"; then
        echo "       Patch already applied."
    else
        echo "       [WARN] Could not automatically apply patch. Please inspect generic.mk."
    fi
fi

# 5. Generate Target Configuration
echo "[5/5] Generating .config..."
cat << 'EOF' > "${BUILD_DIR}/.config"
CONFIG_TARGET_ath79=y
CONFIG_TARGET_ath79_generic=y
CONFIG_TARGET_ath79_generic_DEVICE_tenda_w15e-v2=y
CONFIG_TARGET_ROOTFS_INITRAMFS=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_kmod-ath10k=y
CONFIG_PACKAGE_ath10k-firmware-qca9887=y
CONFIG_PACKAGE_kmod-ath9k=y
EOF

make defconfig

echo ""
echo "=========================================================="
echo " Setup Complete!"
echo "=========================================================="
echo " To build the firmware images, run:"
echo "   cd ${BUILD_DIR}"
echo "   make -j\$(nproc || sysctl -n hw.ncpu)"
echo ""
echo " Output images will be located in:"
echo "   ${BUILD_DIR}/bin/targets/ath79/generic/"
echo "   - openwrt-ath79-generic-tenda_w15e-v2-initramfs-kernel.bin (RAM boot test)"
echo "   - openwrt-ath79-generic-tenda_w15e-v2-squashfs-sysupgrade.bin (Production flash)"
echo "=========================================================="
