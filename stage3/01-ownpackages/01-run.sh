#!/bin/bash -e

# hailort-pcie-driver builds and installs a kernel module in its postinst. During
# a pi-gen Docker build, uname -r reports the build host kernel, but the module
# must be built against the Raspberry Pi kernel headers in this rootfs. Temporarily
# wrap uname/depmod/modprobe so the package targets the image kernel and does not
# try to load a module into the build host kernel; restore the real tools when
# the install finishes.
target_kernel="$(
	chroot "${ROOTFS_DIR}" /bin/sh -c \
		'for k in /lib/modules/*rpi-2712 /lib/modules/*rpi-v8; do [ -d "$k" ] && basename "$k" && exit 0; done'
)"

restore_build_wrappers() {
	if [ -e "${ROOTFS_DIR}/usr/bin/uname.cyclops-pigen-real" ]; then
		mv "${ROOTFS_DIR}/usr/bin/uname.cyclops-pigen-real" "${ROOTFS_DIR}/usr/bin/uname"
	fi
	if [ -e "${ROOTFS_DIR}/usr/sbin/modprobe.cyclops-pigen-real" ]; then
		mv "${ROOTFS_DIR}/usr/sbin/modprobe.cyclops-pigen-real" "${ROOTFS_DIR}/usr/sbin/modprobe"
	fi
	if [ -e "${ROOTFS_DIR}/usr/sbin/depmod.cyclops-pigen-real" ]; then
		mv "${ROOTFS_DIR}/usr/sbin/depmod.cyclops-pigen-real" "${ROOTFS_DIR}/usr/sbin/depmod"
	fi
	rm -f \
		"${ROOTFS_DIR}/usr/local/lib/cyclops-pigen/depmod" \
		"${ROOTFS_DIR}/usr/local/lib/cyclops-pigen/modprobe"
	rmdir "${ROOTFS_DIR}/usr/local/lib/cyclops-pigen" 2>/dev/null || true
	rm -f "${ROOTFS_DIR}/etc/cyclops-target-kernel"
}
trap restore_build_wrappers EXIT
restore_build_wrappers

printf '%s\n' "${target_kernel}" > "${ROOTFS_DIR}/etc/cyclops-target-kernel"
mkdir -p "${ROOTFS_DIR}/usr/local/lib/cyclops-pigen"
ln -s /usr/bin/kmod "${ROOTFS_DIR}/usr/local/lib/cyclops-pigen/depmod"

mv "${ROOTFS_DIR}/usr/bin/uname" "${ROOTFS_DIR}/usr/bin/uname.cyclops-pigen-real"
cat > "${ROOTFS_DIR}/usr/bin/uname" <<'EOF'
#!/bin/sh
if [ "$1" = "-r" ]; then
	cat /etc/cyclops-target-kernel
else
	exec /usr/bin/uname.cyclops-pigen-real "$@"
fi
EOF
chmod 755 "${ROOTFS_DIR}/usr/bin/uname"

if [ -e "${ROOTFS_DIR}/usr/sbin/modprobe" ]; then
	mv "${ROOTFS_DIR}/usr/sbin/modprobe" "${ROOTFS_DIR}/usr/sbin/modprobe.cyclops-pigen-real"
fi
cat > "${ROOTFS_DIR}/usr/sbin/modprobe" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "${ROOTFS_DIR}/usr/sbin/modprobe"

if [ -e "${ROOTFS_DIR}/usr/sbin/depmod" ]; then
	mv "${ROOTFS_DIR}/usr/sbin/depmod" "${ROOTFS_DIR}/usr/sbin/depmod.cyclops-pigen-real"
fi
cat > "${ROOTFS_DIR}/usr/sbin/depmod" <<'EOF'
#!/bin/sh
exec /usr/local/lib/cyclops-pigen/depmod -a "$(cat /etc/cyclops-target-kernel)"
EOF
chmod 755 "${ROOTFS_DIR}/usr/sbin/depmod"

on_chroot << EOF
apt-get install -y build-essential hailort-pcie-driver
EOF

on_chroot << EOF
curl -fsSL https://files.cyclopcam.org/install.sh | sh
EOF
