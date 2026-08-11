#!/usr/bin/env bash
# Copyright 2026 Arm Limited and/or its affiliates.
# SPDX-License-Identifier: Apache-2.0
#
# Devcontainer/Codespaces bootstrap. Deliberately minimal: the Arm Environment
# Manager (part of the Keil Studio extension pack) reads
# vcpkg-configuration.json itself and installs/activates CMSIS-Toolbox,
# arm-none-eabi-gcc, cmake, ninja and the AVH FVPs (incl.
# FVP_Corstone_SSE-320), and it bundles armlm for the license activation.
# This script only covers what the extension does not:
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${HERE}"

# FVP runtime dependencies. libpython3* is only dlopen'd by the VSI/VIO bridges,
# which this example does not use, but without it the model prints a
# five-paragraph error before every run; Ubuntu 22.04's own libpython3.10 is
# enough, so no deadsnakes PPA (its key import is flaky and it has no arm64
# jammy builds for some packages).
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    libatomic1 libpython3.10 libstdc++6 python3-venv python3-pip
sudo rm -rf /var/lib/apt/lists/*

# Nothing to install for Debug. The model is its own GDB server -- the avh-fvp
# artifact pinned in vcpkg-configuration.json ships plugins/GDBServer.so next
# to bin/FVP_Corstone_SSE-320 -- and arm-none-eabi-gdb comes with the
# arm-none-eabi-gcc artifact. .vscode/fvp.sh finds the plugin relative to the
# model on PATH, so it works here without $AVH_FVP_PLUGINS being set, and its
# Docker branch is macOS-only and never taken in a container.

# Model-export venv (executorch + ethos-u-vela). setup_venv.py is idempotent
# and rebuilds the venv by itself if its interpreter no longer runs -- the case
# after a container rebuild, since /workspaces persists but the image's Python
# does not.
./setup_venv.sh

echo
echo "Devcontainer ready. The Arm Environment Manager installs the vcpkg"
echo "artifacts (toolbox, gcc, FVPs) on first activation and prompts for the"
echo "license. Then: ./build.sh, and use the CMSIS Solution panel's buttons."
