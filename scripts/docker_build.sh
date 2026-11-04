#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_NAME="openwrt-tenda-builder"
USER_ID="$(id -u)"
GROUP_ID="$(id -g)"

echo "=========================================================="
echo " Building Docker Build Container"
echo "=========================================================="

mkdir -p "${PORT_DIR}/bin"

docker build \
    --build-arg USER_ID="${USER_ID}" \
    --build-arg GROUP_ID="${GROUP_ID}" \
    -t "${IMAGE_NAME}" \
    -f "${PORT_DIR}/Dockerfile" \
    "${PORT_DIR}"

echo ""
echo "=========================================================="
echo " Launching OpenWrt Compilation Inside Container"
echo "=========================================================="

docker run --rm -i \
    -v "${PORT_DIR}:/work:ro" \
    -v "${PORT_DIR}/bin:/output" \
    "${IMAGE_NAME}" bash -c '
set -euo pipefail
BRANCH="openwrt-23.05"
NPROC=$(nproc)

echo "[1/6] Cloning OpenWrt ${BRANCH} into container workspace..."
git clone --depth 1 -b "${BRANCH}" https://github.com/openwrt/openwrt.git openwrt
cd openwrt

echo "[2/6] Updating and installing feeds..."
./scripts/feeds update -a
./scripts/feeds install -a

echo "[3/6] Installing Tenda W15E v2.0 Device Tree and profile..."
cp /work/dts/qca9531_tenda_w15e-v2.dts target/linux/ath79/dts/

if ! grep -q "Device/tenda_w15e-v2" target/linux/ath79/image/generic.mk; then
    cat << "EOF" >> target/linux/ath79/image/generic.mk

define Device/tenda_w15e-v2
  SOC := qca9531
  DEVICE_VENDOR := Tenda
  DEVICE_MODEL := W15E
  DEVICE_VARIANT := v2
  DEVICE_PACKAGES := kmod-ath10k ath10k-firmware-qca9887
  IMAGE_SIZE := 16064k
  SUPPORTED_DEVICES += tenda,w15e-v2
endef
TARGET_DEVICES += tenda_w15e-v2
EOF
    echo "       Registered Device/tenda_w15e-v2 in generic.mk"
fi

echo "[4/6] Creating build configuration..."
cat << EOF > .config
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

echo "[5/6] Starting compilation with ${NPROC} parallel jobs..."
make -j"${NPROC}"

echo "[6/6] Copying compiled firmware binaries to output directory..."
cp -v bin/targets/ath79/generic/*tenda_w15e-v2* /output/ || cp -v bin/targets/ath79/generic/*.bin /output/

echo ""
echo "=========================================================="
echo " Build Succeeded! Output firmware binaries:"
ls -lh /output
echo "=========================================================="
'
