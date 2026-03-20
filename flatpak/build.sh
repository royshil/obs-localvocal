#!/usr/bin/env bash
# Build the obs-localvocal Flatpak extension.
#
# Usage:
#   [ACCELERATION=<value>] ./flatpak/build.sh [flatpak-builder options] <build-dir>
#
# ACCELERATION controls the GPU/CPU backend compiled into the plugin.
# Allowed values (default: generic):
#   generic  – portable CPU-only build (OpenBLAS)
#   nvidia   – CUDA-accelerated build
#   amd      – ROCm/HIP-accelerated build
#
# Examples:
#   ./flatpak/build.sh build-dir
#   ACCELERATION=nvidia ./flatpak/build.sh --install build-dir
#   ACCELERATION=amd    ./flatpak/build.sh --repo=repo build-dir

set -euo pipefail

ACCELERATION="${ACCELERATION:-generic}"

case "${ACCELERATION}" in
    generic | nvidia | amd) ;;
    *)
        printf 'Error: ACCELERATION="%s" is invalid. Allowed values: generic, nvidia, amd.\n' \
            "${ACCELERATION}" >&2
        exit 1
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${SCRIPT_DIR}/com.obsproject.Studio.Plugin.LocalVocal.yaml"

# Create a temporary directory and ensure it is removed on exit
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

# Produce a patched copy of the manifest with the requested ACCELERATION value.
# Two substitutions are needed:
#   1. build-options.env entry:  ACCELERATION: generic
#   2. CMake cache variable:     -DACCELERATION=generic
PATCHED="${WORK_DIR}/$(basename "${MANIFEST}")"
sed \
    -e "s/ACCELERATION: generic/ACCELERATION: ${ACCELERATION}/" \
    -e "s/-DACCELERATION=generic/-DACCELERATION=${ACCELERATION}/" \
    "${MANIFEST}" > "${PATCHED}"

# The manifest references the metainfo XML via a relative path; copy it so
# flatpak-builder can find it relative to the patched manifest location.
cp "${SCRIPT_DIR}/com.obsproject.Studio.Plugin.LocalVocal.metainfo.xml" "${WORK_DIR}/"

exec flatpak-builder "$@" "${PATCHED}"
