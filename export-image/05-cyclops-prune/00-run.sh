#!/bin/bash -e

# Cyclops boxes are updated by replacing the full rootfs with RAUC, not by
# running apt on the device. hailort-pcie-driver needs compiler tools and kernel
# headers only while pi-gen builds its module, so prune them from the exported
# image after all apt-based pi-gen stages have finished. This intentionally
# leaves hailort-pcie-driver's build-essential dependency unsatisfied; do not run
# apt in the deployed image.
packages="
build-essential
cpp
cpp-14
cpp-aarch64-linux-gnu
gcc
gcc-14
gcc-14-aarch64-linux-gnu
gcc-14-for-host
gcc-aarch64-linux-gnu
g++
g++-14
g++-14-aarch64-linux-gnu
g++-aarch64-linux-gnu
dpkg-dev
fakeroot
libalgorithm-diff-perl
libalgorithm-diff-xs-perl
libalgorithm-merge-perl
libdpkg-perl
libfakeroot
libfile-fcntllock-perl
libgcc-14-dev
libstdc++-14-dev
linux-headers-6.18.34+rpt-common-rpi
linux-headers-6.18.34+rpt-rpi-2712
linux-headers-6.18.34+rpt-rpi-v8
linux-headers-rpi-2712
linux-headers-rpi-v8
make
patch
"

installed_packages="$(
	for package in ${packages}; do
		if chroot "${ROOTFS_DIR}" dpkg-query -W -f '${db:Status-Abbrev}' "${package}" 2>/dev/null | grep -q '^i'; then
			printf '%s\n' "${package}"
		fi
	done
)"

if [ -n "${installed_packages}" ]; then
	chroot "${ROOTFS_DIR}" dpkg --purge --force-depends ${installed_packages}
fi

on_chroot << EOF
apt-get clean
EOF

rm -rf "${ROOTFS_DIR}/var/lib/apt/lists/"*
rm -f "${ROOTFS_DIR}/var/cache/apt/archives/"*.deb
rm -f "${ROOTFS_DIR}/var/cache/apt/pkgcache.bin"
rm -f "${ROOTFS_DIR}/var/cache/apt/srcpkgcache.bin"
