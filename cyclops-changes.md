# Cyclops pi-gen changes

This file records the Cyclops-specific changes in this fork of `pi-gen` so they
can be re-applied to a future public `pi-gen` base without relying on fragile
git patches.

Use this document as the starting point for future distro ports.

## Source commits

These notes describe the tested `arm64-cyclops` branch only.

- Public base: `9f8fc6ff6e3bfa98629bea3a3f50d0b7fe985d56`
- Cyclops head: `d5de4bd22e1ef9eb1d3b6e572751a2a64b78c487`

Cyclops commits above the public base:

```text
8115d11 Delete stage3,stage4,stage5
8384b46 Remove CONF_SWAPSIZE=512
606cb48 Remove firstboot script from cmdline.txt
d726381 Remove non-essential apt packages
fc0a9b9 Add our own build-cyclops script
d9fd72b Add our own stage3
8000c6a Add rauc and rauc.service to stage3
d5de4bd Add chrony, to speed up NTP sync
```

## Intent

Cyclops keeps the useful public base stages, strips out the normal Raspberry Pi
desktop/full-image content, and puts Cyclops-specific installation into a small
custom stage3.

The intended image:

- is named `cyclops`
- enables SSH
- uses timezone `Africa/Johannesburg`
- uses keyboard layout `English (US)`
- is exported as a gzip-compressed `-lite` image
- avoids desktop, full-image, print, education, and application bundles
- installs `rauc`, `rauc-service`, and `chrony`
- runs the Cyclops installer from `https://files.cyclopcam.org/install.sh`

## Build wrapper

Add an executable top-level `build-cyclops` helper. In the tested branch it
writes `config`, skips exporting the intermediate stage2 image, and prints the
normal Docker build and iteration commands.

```bash
#!/bin/bash

config=$(cat <<EOF
IMG_NAME=cyclops
PI_GEN_RELEASE=v1
ENABLE_SSH=1
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

Keep stages 0, 1, and 2 from public `pi-gen`, then make stage3 the final
Cyclops stage.

The tested branch deleted the public stage3, stage4, and stage5 payloads, then
recreated only the files needed for Cyclops stage3.

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

Add `stage3/01-ownpackages/00-packages`:

```text
rauc rauc-service chrony
```

Add executable `stage3/01-ownpackages/01-run.sh`:

```bash
#!/bin/bash -e

on_chroot << EOF
curl -fsSL https://files.cyclopcam.org/install.sh | sh
EOF
```

Purpose:

- `rauc` and `rauc-service` support the Cyclops update path.
- `chrony` speeds up time synchronisation.
- The installer hook keeps Cyclops-specific setup isolated in stage3.

## Removed desktop and full-image stages

The tested branch removes the public desktop-oriented stage3 content and all of
stage4/stage5. This prevents the image from pulling in the Raspberry Pi desktop,
browsers, print support, beginner material, education apps, LibreOffice, Scratch,
VNC/Wayland desktop extras, and full-image output.

Deleted files:

```text
stage3/00-install-packages/00-packages
stage3/00-install-packages/00-packages-nr
stage3/00-install-packages/01-run.sh
stage3/prerun.sh
stage4/00-install-packages/00-debconf
stage4/00-install-packages/00-packages
stage4/00-install-packages/00-packages-nr
stage4/00-install-packages/02-packages
stage4/01-console-autologin/00-run.sh
stage4/02-extras/00-run.sh
stage4/03-bookshelf/00-run.sh
stage4/03-bookshelf/files/.gitignore
stage4/04-enable-xcompmgr/00-run.sh
stage4/05-print-support/00-packages
stage4/05-print-support/01-run.sh
stage4/06-enable-wayland/00-run.sh
stage4/EXPORT_IMAGE
stage4/prerun.sh
stage5/00-install-extras/00-packages
stage5/00-install-libreoffice/00-packages
stage5/EXPORT_IMAGE
stage5/prerun.sh
```

Later commits add back a minimal `stage3/prerun.sh`, add `stage3/EXPORT_IMAGE`,
and add `stage3/01-ownpackages`.

When porting to a new public base, do not assume these exact paths still exist.
Apply the same rule instead: remove public desktop/full-image steps and make the
custom Cyclops stage3 the final export stage.

## Stage2 package trimming

The tested branch removes non-essential stage2 packages to keep the image small
and avoid pulling in development, camera demo, GPIO language binding, manual-page,
and swap tooling that Cyclops does not need.

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
pigpio
python3-pigpio
raspi-gpio
python3-rpi-lgpio
python3-spidev
python3-smbus2
lua5.1
luajit
dphys-swapfile
man-db
kms++-utils
python3-venv
```

Removed from `stage2/01-sys-tweaks/00-packages-nr`:

```text
rpicam-apps-lite
```

Resulting `stage2/01-sys-tweaks/00-packages` in the tested branch:

```text
ssh less sudo psmisc strace ed
console-setup keyboard-configuration debconf-utils parted
bash-completion
pkg-config
gpiod
avahi-daemon
ca-certificates curl
fake-hwclock nfs-common usbutils
dosfstools
raspberrypi-sys-mods
pi-bluetooth
apt-listchanges
usb-modeswitch
libpam-chksshpwd
rpi-update
libmtp-runtime
rsync
htop
policykit-1
ssh-import-id
ethtool
ntfs-3g
pciutils
rpi-eeprom
raspi-utils
udisks2
unzip zip p7zip-full
file
```

Resulting `stage2/01-sys-tweaks/00-packages-nr`:

```text
cifs-utils
mkvtoolnix
```

When porting, inspect the new public package lists and remove the same classes
of packages if they are still present.

## Swap behavior

The tested branch removes the public patch that forced a 512 MB dphys-swapfile:

- delete `stage2/01-sys-tweaks/00-patches/02-swap.diff`
- remove `02-swap.diff` from `stage2/01-sys-tweaks/00-patches/series`
- remove `dphys-swapfile` from `stage2/01-sys-tweaks/00-packages`

Effect: the image does not install `dphys-swapfile`, and pi-gen does not patch
`/etc/dphys-swapfile` to force `CONF_SWAPSIZE=512`.

When porting, verify the new base does not introduce an equivalent fixed swap
setup elsewhere.

## First-boot resize behavior

The public base patched `/boot/firmware/cmdline.txt` to append:

```text
quiet init=/usr/lib/raspberrypi-sys-mods/firstboot
```

The Cyclops branch changes
`stage2/01-sys-tweaks/00-patches/07-resize-init.diff` so the generated command
line remains:

```text
console=serial0,115200 console=tty1 root=ROOTDEV rootfstype=ext4 fsck.repair=yes rootwait
```

Effect: the image does not boot through the
`/usr/lib/raspberrypi-sys-mods/firstboot` init hook from this public base.

When porting, inspect the target base's current first-boot resize mechanism and
decide whether Cyclops still needs to disable the equivalent behavior.

## Fresh porting checklist

1. Start from the public pi-gen branch for the target distro and architecture.
2. Add executable `build-cyclops` from this document.
3. Run `./build-cyclops` and confirm it writes `config` and creates
   `stage2/SKIP_IMAGES`.
4. Remove public desktop, print, stage4, and stage5 package/image export steps
   that would produce non-Cyclops images or pull in GUI bundles.
5. Make stage3 the final export stage with `stage3/prerun.sh` and
   `stage3/EXPORT_IMAGE`.
6. Add `stage3/01-ownpackages/00-packages` with `rauc rauc-service chrony`.
7. Add the Cyclops installer hook in `stage3/01-ownpackages/01-run.sh`.
8. Inspect stage2 packages and remove the same non-essential package classes if
   they still exist in the new base.
9. Verify no fixed `CONF_SWAPSIZE=512` or equivalent forced swap setup remains.
10. Verify the target distro's first-boot resize behavior and disable it only if
    Cyclops still requires that behavior.
11. Build with `./build-docker.sh`.
12. Boot the image and verify SSH, timezone, keyboard layout, `rauc`,
    `rauc-service`, `chrony`, Cyclops installer effects, lack of desktop extras,
    and expected swap/resize behavior.
