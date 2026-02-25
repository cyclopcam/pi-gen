#!/bin/bash -e

on_chroot << EOF2
curl -fsSL https://files.cyclopcam.org/install.sh | sh
EOF2
