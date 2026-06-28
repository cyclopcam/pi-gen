# Cyclops pi-gen changes for trixie

This file records the Cyclops-specific changes applied to the Raspberry Pi OS
trixie `arm64` pi-gen base. It is intended to be the source of truth for this
port, not a blind patch from the older bookworm branch.

## Source branches

The previous Cyclops notes came from the tested bookworm branch:

- Source branch: `arm64-cyclops`
- Source head: `1b39769f2d2574559c88898601628db80001d3cb`
- Source change log: `cyclops-changes.md` on that branch

This trixie port was applied on:

- Base branch: `arm64-cyclops-trixie-v2`
- Trixie base: `ca8aeed0ae300c2a89f55ce9617d5f96a27e99e5`

The `arm64-cyclops-trixie-v1` branch was intentionally not used.

## Intent

Cyclops keeps the useful public lite-image stages, strips out the normal
Raspberry Pi desktop/full-image content, and puts Cyclops-specific installation
into a small custom stage3.

The intended image:

- is named `cyclops`
- enables SSH
- disables cloud-init provisioning
- uses timezone `Africa/Johannesburg`
- uses keyboard layout `English (US)`
- is exported as a gzip-compressed `-lite` image
- avoids desktop, full-image, print, education, and application bundles
- installs `rauc`, `rauc-service`, and `chrony`
- runs the Cyclops installer from `https://files.cyclopcam.org/install.sh`

## Build wrapper

Added executable top-level `build-cyclops`. It writes `config`, skips exporting
the intermediate stage2 image, and prints the normal Docker build and iteration
commands.

```bash
#!/bin/bash

config=$(cat <<EOF
IMG_NAME=cyclops
PI_GEN_RELEASE=v1
ENABLE_SSH=1
ENABLE_CLOUD_INIT=0
TIMEZONE_DEFAULT=Africa/Johannesburg
KEYBOARD_LAYOUT=English (US)
COMPRESSION_LEVEL=3
DEPLOY_COMPRESSION=gz
EOF
)

echo "$config" > config
touch ./stage2/SKIP_IMAGES

echo "Now do:"
echo "./build-docker.sh"

echo "For iteration (see readme 'Skipping stages to speed up development'):"
echo "PRESERVE_CONTAINER=1 CONTINUE=1 CLEAN=1 ./build-docker.sh"

echo "To skip stage0, 'touch ./stage0/SKIP', and etc for the other stages."
echo "We try to keep our custom stuff in stage 3, so that you can just iterate on stage 3,"
echo "without having to go through the previous build steps for every iteration."
echo "So a typical build/iteration workflow involves a full build, and thereafter"
echo "skipping stages 0, 1, and 2."
echo "Example: touch ./stage0/SKIP ./stage1/SKIP ./stage2/SKIP"

echo "To delete stage3 from the docker container:"
echo "sudo docker run --privileged --volumes-from=pigen_work pi-gen rm -rf pi-gen/work/cyclops/stage3"
```

Important behavior:

- `touch ./stage2/SKIP_IMAGES` prevents pi-gen from exporting an intermediate
  stage2 image. The exported Cyclops image should come from stage3.
- The script does not automatically remove `SKIP` markers left from iteration.
  If a full rebuild is needed, clear those markers manually.

## Stage structure

Keep stages 0, 1, and 2 from public pi-gen, then make stage3 the final Cyclops
stage.

Deleted trixie desktop/full-image stage content:

```text
stage3/00-install-packages/00-packages
stage3/00-install-packages/00-packages-nr
stage3/01-print-support/00-run.sh
stage4/00-install-packages/00-packages
stage4/01-disable-wayvnc/00-run.sh
stage4/EXPORT_IMAGE
stage4/prerun.sh
stage5/00-install-extras/00-packages
stage5/00-install-libreoffice/00-packages
stage5/EXPORT_IMAGE
stage5/prerun.sh
```

Final stage3 files:

```text
stage3/prerun.sh
stage3/EXPORT_IMAGE
stage3/01-ownpackages/00-packages
stage3/01-ownpackages/01-run.sh
```

`stage3/prerun.sh` keeps the standard copy-forward behavior:

```bash
#!/bin/bash -e

if [ ! -d "${ROOTFS_DIR}" ]; then
	copy_previous
fi
```

`stage3/EXPORT_IMAGE` exports a lite image:

```bash
IMG_SUFFIX="-lite"
if [ "${USE_QEMU}" = "1" ]; then
	export IMG_SUFFIX="${IMG_SUFFIX}-qemu"
fi
```

## Cyclops packages and installer

Added `stage3/01-ownpackages/00-packages`:

```text
rauc rauc-service chrony
```

Added executable `stage3/01-ownpackages/01-run.sh`. It installs
`hailort-pcie-driver` before the Cyclops package and temporarily wraps
`uname`, `depmod`, and `modprobe` while the Hailo package configures. This is
needed because `hailort-pcie-driver` builds a kernel module in its postinst;
inside the Docker/chroot build, `uname -r` reports the build host kernel rather
than the Raspberry Pi target kernel. The wrappers make the postinst build
against the target image kernel and avoid trying to load the module into the
build host kernel.

The Cyclops installer is then run with its normal upstream script. The installer
has been adjusted to avoid recommended packages so optional graphics/driver
stacks do not inflate the lite image.

The Debian trixie `arm64` package index contains `rauc`, `rauc-service`, and
`chrony`, so the package names did not need to change.

Added `export-image/05-cyclops-hailo-driver-fix/00-run.sh` and its patch file
to temporarily replace the apt-installed `hailort-pcie-driver` kernel module.
The export step runs after the final apt upgrade and immediately before the
build-only package prune. It downloads the pinned upstream Hailo driver source
for 4.23.0, applies the upstream 4.24.0 `find_vma()` mmap lock fix, rebuilds
`hailo_pci.ko` against the image's Raspberry Pi target kernel, removes any
older `hailo_pci.ko*` copies from that module tree, installs the rebuilt module,
and runs `depmod`. The apt package remains installed so dpkg still believes the
driver is present; this override should be removed once the packaged Hailo
driver has the fix.

Added `export-image/05-cyclops-prune/00-run.sh` to remove Hailo build-only
packages after all apt-based image setup has completed but before final image
compression. Cyclops devices are updated by full RAUC rootfs replacement and do
not run apt in the field, so the exported appliance image does not need to keep
compiler packages or Raspberry Pi kernel headers after the Hailo module has been
built.

## Stage2 package trimming

Removed the same classes of non-essential packages from trixie stage2:
development tools, camera demo tooling, GPIO language bindings, manual-page
tooling, Lua runtimes, venv support, and swap tooling.

Removed from `stage2/01-sys-tweaks/00-packages`:

```text
fbset
ncdu
build-essential
manpages-dev
gdb
python-is-python3
v4l-utils
python3-libgpiod
python3-gpiozero
python3-rpi-lgpio
python3-spidev
python3-smbus2
lua5.1
luajit
rpi-swap
rpi-loop-utils
man-db
kms++-utils
python3-venv
```

Removed from `stage2/01-sys-tweaks/00-packages-nr`:

```text
rpicam-apps-lite
```

Resulting `stage2/01-sys-tweaks/00-packages`:

```text
ssh less sudo psmisc strace ed
console-setup keyboard-configuration debconf-utils parted
bash-completion pkg-config
gpiod
avahi-daemon
ca-certificates curl
usbutils
dosfstools
raspberrypi-sys-mods
apt-listchanges
usb-modeswitch
libpam-chksshpwd
rpi-update
libmtp-runtime
rsync
htop
ssh-import-id
ethtool
ntfs-3g
pciutils
rpi-eeprom
raspi-utils
udisks2
unzip zip p7zip-full
file
bluez bluez-firmware
rpi-keyboard-config
rpi-keyboard-fw-update
rpi-usb-gadget modemmanager-
rpi-connect-lite
rpifwcrypto
```

Resulting `stage2/01-sys-tweaks/00-packages-nr`:

```text
cifs-utils
mkvtoolnix
```

Bookworm packages that were removed in the old branch but are no longer present
in the trixie base:

```text
pigpio
python3-pigpio
raspi-gpio
dphys-swapfile
```

Trixie packages left in place because there was no matching bookworm decision in
the old change log:

```text
bluez bluez-firmware
rpi-keyboard-config
rpi-keyboard-fw-update
rpi-usb-gadget modemmanager-
rpi-connect-lite
rpifwcrypto
```

Cloud-init is new in this trixie base and is explicitly disabled for Cyclops.
`build-cyclops` writes `ENABLE_CLOUD_INIT=0`; `stage2/04-cloud-init/00-packages`
and the example NoCloud seed files were removed; and
`stage2/04-cloud-init/01-run.sh` is a no-op. As a result, `cloud-init`,
`rpi-cloud-init-mods`, and the NoCloud seed files under `/boot/firmware` are not
installed. Cyclops images are appliance images provisioned by the Cyclops
install flow and updated by full RAUC rootfs replacement, so first-boot
user-data execution from the boot partition is not part of the product contract.

## Swap behavior

The bookworm branch removed `dphys-swapfile` and the pi-gen patch that forced
`CONF_SWAPSIZE=512`.

That exact patch does not exist in the trixie base. The Raspberry Pi trixie
package metadata shows `rpi-swap` as the replacement: it conflicts with,
replaces, and provides `dphys-swapfile`. It depends on `rpi-loop-utils` as
supporting tooling. To preserve the Cyclops "no swap manager from stage2"
behavior, both explicit packages were removed from
`stage2/01-sys-tweaks/00-packages`.

No `CONF_SWAPSIZE=512` equivalent remains in this pi-gen tree.

## First-boot resize behavior

The bookworm branch disabled the first-boot resize path by making
`stage2/01-sys-tweaks/00-patches/07-resize-init.diff` a no-op. That patch does
not exist in the trixie base.

Trixie has two active pieces instead:

- `stage1/00-boot-files/files/cmdline.txt` includes the `resize` kernel command
  line token.
- `stage2/01-sys-tweaks/01-run.sh` enables `rpi-resize`.

This port removes both:

- `resize` was removed from `stage1/00-boot-files/files/cmdline.txt`.
- `systemctl enable rpi-resize` was removed from
  `stage2/01-sys-tweaks/01-run.sh`.

This is the closest trixie equivalent to the old bookworm "remove firstboot
script from cmdline.txt" change.

## Changes that did not port one-for-one

- The old desktop/full-image stage package names changed substantially in
  trixie. Instead of trying to map every old package name, this port removed the
  current public desktop/full-image stage directories that serve the same role.
- The old `dphys-swapfile` package and `02-swap.diff` patch are gone. Trixie's
  replacement is `rpi-swap`, so this port removed `rpi-swap` and
  `rpi-loop-utils`.
- The old `07-resize-init.diff` patch is gone. Trixie's resize path is now the
  `resize` cmdline token plus the `rpi-resize` service, so this port removed
  both.
- `pigpio`, `python3-pigpio`, and `raspi-gpio` were removed in bookworm but are
  not present in this trixie base, so there was nothing to remove.
- Cloud-init is new in the trixie base. It was not removed because the old
  Cyclops change log did not make a decision about it.

## Trixie build-host fix

The trixie `build-docker.sh` expects the host to have `qemu-user-binfmt` and the
non-static `qemu-aarch64` binary. On Ubuntu, installing `qemu-user-binfmt`
removes `qemu-user-static`, and that is expected.

One extra wrapper issue was fixed in this port: `build-docker.sh` previously
registered a custom `qemu-aarch64-rpi` binfmt entry on the host whenever the
existing host entry did not point at exactly `/usr/bin/qemu-aarch64`. On Ubuntu,
the normal entry points at `/usr/libexec/qemu-binfmt/aarch64-binfmt-P`, which is
a valid wrapper. The custom host registration used the `F` flag with the host's
dynamically linked QEMU binary, and that can fail inside the Debian trixie
container with a missing `libglib-2.0.so.0`.

The wrapper now avoids custom host-side registration. Instead, after the
privileged Debian trixie build container starts, it registers a
`qemu-aarch64-rpi` entry with the container's static `/usr/bin/qemu-aarch64` and
the `F` flag. That is needed because debootstrap verifies the second stage with
`arch-test -c <target> arm64`; without an `F` entry, the QEMU interpreter path
is resolved inside the not-yet-bootstrapped target rootfs and the check fails
with `Unable to execute target architecture`.

`Dockerfile` was also changed to install `qemu-user-binfmt` directly instead of
the stale `qemu-user-static` package name.

## Validation performed

Lightweight checks run after the port:

```text
bash -n build-cyclops stage2/01-sys-tweaks/01-run.sh stage3/01-ownpackages/01-run.sh stage3/prerun.sh
bash -n build-docker.sh
git diff --check
```

The syntax and whitespace checks passed.

Package metadata checked:

- Debian trixie `arm64` package index contains `rauc`, `rauc-service`, and
  `chrony`.
- Raspberry Pi trixie `arm64` package index contains `rpi-swap` and
  `rpi-loop-utils`; `rpi-swap` provides/replaces/conflicts with
  `dphys-swapfile`.
- `raspberrypi-sys-mods` does not recommend `rpi-swap`, so removing the explicit
  stage2 package entries should not immediately pull it back in.

The actual image build has not been run yet.

## Fresh porting checklist

1. Run `./build-cyclops`.
2. Confirm it writes `config` and creates `stage2/SKIP_IMAGES`.
3. Build with `./build-docker.sh`.
4. Boot the image and verify SSH, timezone, keyboard layout, `rauc`,
   `rauc-service`, `chrony`, Cyclops installer effects, lack of desktop extras,
   absence of cloud-init, and expected swap/resize behavior.
