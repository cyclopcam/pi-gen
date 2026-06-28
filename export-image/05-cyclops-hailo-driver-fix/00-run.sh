#!/bin/bash -e

# Keep the apt package installed for dpkg/dependency state, but replace the
# buggy 4.23.0 kernel module with a locally rebuilt 4.23.0 module carrying the
# upstream 4.24.0 find_vma mmap lock fix. This runs after the final apt upgrade
# and before the Cyclops prune step removes build tools and kernel headers.
hailo_drivers_commit="ce1087bfe8132c99b41374e3128fc78612a3f492"
hailo_drivers_url="https://github.com/hailo-ai/hailort-drivers/archive/${hailo_drivers_commit}.tar.gz"
work_dir="${ROOTFS_DIR}/var/lib/cyclops-pigen/hailo-pcie-driver-fix"
source_dir="${work_dir}/src"
archive="${work_dir}/hailort-drivers-${hailo_drivers_commit}.tar.gz"
patch_file="${PWD}/files/hailort-drivers-4.23.0-find-vma-mmap-lock.patch"

target_kernel="$(
	chroot "${ROOTFS_DIR}" /bin/sh -c \
		'for k in /lib/modules/*rpi-2712 /lib/modules/*rpi-v8; do [ -d "$k" ] && basename "$k" && exit 0; done'
)"

if [ -z "${target_kernel}" ]; then
	echo "Failed to find Raspberry Pi target kernel in ${ROOTFS_DIR}/lib/modules"
	exit 1
fi

if [ ! -e "${ROOTFS_DIR}/lib/modules/${target_kernel}/build/Makefile" ]; then
	echo "Missing kernel headers for ${target_kernel}"
	exit 1
fi

if ! chroot "${ROOTFS_DIR}" dpkg-query -W -f '${db:Status-Abbrev}' hailort-pcie-driver 2>/dev/null | grep -q '^i'; then
	echo "hailort-pcie-driver is not installed; refusing to install an unmanaged replacement module"
	exit 1
fi

rm -rf "${work_dir}"
mkdir -p "${source_dir}"

curl -fsSL "${hailo_drivers_url}" -o "${archive}"
tar -xzf "${archive}" -C "${source_dir}" --strip-components=1
patch -d "${source_dir}" -p1 < "${patch_file}"

if ! grep -q 'mmap_read_lock(current->mm);' "${source_dir}/linux/vdma/memory.c"; then
	echo "Hailo PCIe driver mmap lock patch was not applied"
	exit 1
fi

on_chroot << EOF
set -e

make -C /var/lib/cyclops-pigen/hailo-pcie-driver-fix/src/linux/pcie \
	KERNEL_DIR=/lib/modules/${target_kernel}/build \
	kernelver=${target_kernel} \
	ARCH=arm64 \
	UNAME_STR=raspi \
	all

install -d /lib/modules/${target_kernel}/kernel/drivers/misc
find /lib/modules/${target_kernel} -type f \( -name 'hailo_pci.ko' -o -name 'hailo_pci.ko.*' \) -delete
install -m 644 \
	/var/lib/cyclops-pigen/hailo-pcie-driver-fix/src/linux/pcie/build/release/arm64/hailo_pci.ko \
	/lib/modules/${target_kernel}/kernel/drivers/misc/hailo_pci.ko
depmod -a ${target_kernel}
modinfo -F vermagic /lib/modules/${target_kernel}/kernel/drivers/misc/hailo_pci.ko | grep -F ${target_kernel}
EOF

rm -rf "${work_dir}"
