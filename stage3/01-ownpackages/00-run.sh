#!/bin/bash -e

on_chroot << EOF
curl -fsSL https://files.cyclopcam.org/install.sh | sh
EOF

