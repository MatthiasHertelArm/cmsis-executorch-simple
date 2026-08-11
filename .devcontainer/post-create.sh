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

# The ExecuTorch pack, from the copy committed under packs/. Installing it from
# the repository rather than letting `cbuild --packs` fetch it keeps a Codespace
# independent of the public pack index, and pins the bytes: the pack root ends
# up holding exactly the build this branch was tested against.
#
# Guarded, because cpackget arrives with the CMSIS-Toolbox vcpkg artifact, which
# the Arm Environment Manager installs on its first activation -- often after
# this script has run. The install is idempotent either way.
#
# -n (--no-dependencies): the pack declares ARM::CMSIS, and resolving that needs
# the public index, which a pack root created by this script has not fetched
# yet -- cpackget then exits 255 and takes the whole bootstrap with it, despite
# having extracted our pack correctly. The dependencies are public packs that
# `cbuild --packs` installs at build time anyway. Re-running is safe: an
# already-installed pack is reported but exits 0.
PACK="packs/PyTorch.ExecuTorch.1.4.0.pack"
if command -v cpackget >/dev/null 2>&1; then
    cpackget add -n --agree-embedded-license "${PACK}"
else
    echo "cpackget not on PATH yet (the Arm Environment Manager installs it on"
    echo "first activation). Once the toolchain is active, run:"
    echo "    cpackget add -n --agree-embedded-license ${PACK}"
fi

# Model-export venv (executorch + ethos-u-vela). setup_venv.py is idempotent
# and rebuilds the venv by itself if its interpreter no longer runs -- the case
# after a container rebuild, since /workspaces persists but the image's Python
# does not.
./setup_venv.sh

echo
echo "Devcontainer ready. The Arm Environment Manager installs the vcpkg"
echo "artifacts (toolbox, gcc, FVPs) on first activation and prompts for the"
echo "license. Then: ./build.sh, and use the CMSIS Solution panel's buttons."
