#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

PVE_DIR="proxmox-pve-kernel"
T2_DIR="linux-t2-patches"

TARGET_MODEL="Macmini8,1"

# Minimal T2 patchset required for Apple SMC / thermal sensors /
# fan support on Mac mini 2018 (Macmini8,1).
MACMINI_T2_PATCHES=(
  "3001-applesmc-convert-static-structures-to-drvdata.patch"
  "3002-applesmc-make-io-port-base-addr-dynamic.patch"
  "3003-applesmc-switch-to-acpi_device-from-platform.patch"
  "3004-applesmc-key-interface-wrappers.patch"
  "3005-applesmc-basic-mmio-interface-implementation.patch"
  "3006-applesmc-fan-support-on-T2-Macs.patch"
)

if [[ -z "${PVE_SHA:-}" ]]; then
  echo "ERROR: PVE_SHA is not defined" >&2
  exit 1
fi

if [[ -z "${T2_SHA:-}" ]]; then
  echo "ERROR: T2_SHA is not defined" >&2
  exit 1
fi

if [[ ! -d "${PVE_DIR}/.git" ]]; then
  echo "ERROR: ${PVE_DIR} repository is missing" >&2
  exit 1
fi

if [[ ! -d "${T2_DIR}/.git" ]]; then
  echo "ERROR: ${T2_DIR} repository is missing" >&2
  exit 1
fi

echo "Testing compatibility:"
echo "Target:      ${TARGET_MODEL}"
echo "Profile:     AppleSMC / sensors / fan only"
echo "Proxmox SHA: ${PVE_SHA}"
echo "T2 SHA:      ${T2_SHA}"

#
# Lock both source trees to the expected revisions.
#

git -C "${PVE_DIR}" checkout --detach "${PVE_SHA}"

git -C "${PVE_DIR}" config \
  submodule.submodules/ubuntu-kernel.url \
  https://git.proxmox.com/git/mirror_ubuntu-kernels.git

git -C "${PVE_DIR}" submodule update \
  --init \
  --depth 1 \
  submodules/ubuntu-kernel

git -C "${T2_DIR}" checkout --detach "${T2_SHA}"

#
# Verify that every patch required by the Macmini8,1 profile exists.
#

for PATCH_NAME in "${MACMINI_T2_PATCHES[@]}"; do
  if [[ ! -f "${T2_DIR}/${PATCH_NAME}" ]]; then
    echo "ERROR: required T2 patch is missing: ${PATCH_NAME}" >&2
    exit 1
  fi
done

TOTAL_T2_PATCHES="$(
  find "${T2_DIR}" \
    -maxdepth 1 \
    -type f \
    -name '*.patch' |
  wc -l
)"

REQUIRED_PATCH_COUNT="${#MACMINI_T2_PATCHES[@]}"

if [[ "${TOTAL_T2_PATCHES}" -lt "${REQUIRED_PATCH_COUNT}" ]]; then
  echo "ERROR: invalid T2 patch repository state" >&2
  exit 1
fi

T2_SKIPPED=$((TOTAL_T2_PATCHES - REQUIRED_PATCH_COUNT))

#
# Prepare a clean Linux source tree for compatibility testing.
#

rm -rf kernel-compat

cp -a \
  "${PVE_DIR}/submodules/ubuntu-kernel" \
  kernel-compat

rm -rf \
  kernel-compat/debian \
  kernel-compat/debian.master

cd kernel-compat

#
# Apply official Proxmox patches first.
#

echo
echo "Applying official Proxmox patches..."

for patchfile in "../${PVE_DIR}"/patches/kernel/*.patch; do
  [[ -e "${patchfile}" ]] || continue

  PATCH_NAME="$(basename "${patchfile}")"

  echo "PVE -> ${PATCH_NAME}"

  if ! patch \
    --batch \
    -p1 \
    < "${patchfile}" \
    > /tmp/pve-patch.log 2>&1
  then
    cat /tmp/pve-patch.log
    echo "ERROR: official Proxmox patch failed: ${PATCH_NAME}" >&2
    exit 1
  fi
done

#
# Apply only the Macmini8,1 T2 allowlist.
#

echo
echo "Applying Macmini8,1 T2 patches..."

T2_COUNT=0

for PATCH_NAME in "${MACMINI_T2_PATCHES[@]}"; do
  PATCH_FILE="../${T2_DIR}/${PATCH_NAME}"

  echo "T2 -> ${PATCH_NAME}"

  if ! patch \
    --batch \
    -p1 \
    < "${PATCH_FILE}" \
    > /tmp/t2-patch.log 2>&1
  then
    cat /tmp/t2-patch.log

    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
      echo "compatible=false" >> "${GITHUB_OUTPUT}"
      echo "failed_patch=${PATCH_NAME}" >> "${GITHUB_OUTPUT}"
      echo "patch_count=${T2_COUNT}" >> "${GITHUB_OUTPUT}"
      echo "skipped_count=${T2_SKIPPED}" >> "${GITHUB_OUTPUT}"
      echo "skipped_patch=non-Macmini8,1 T2 patches" >> "${GITHUB_OUTPUT}"
    fi

    echo "ERROR: T2 patch failed: ${PATCH_NAME}" >&2
    exit 1
  fi

  T2_COUNT=$((T2_COUNT + 1))
done

if [[ "${T2_COUNT}" -ne "${REQUIRED_PATCH_COUNT}" ]]; then
  echo "ERROR: unexpected applied T2 patch count" >&2
  echo "Expected: ${REQUIRED_PATCH_COUNT}"
  echo "Applied:  ${T2_COUNT}"
  exit 1
fi

echo
echo "Patch compatibility passed."
echo "Target:  ${TARGET_MODEL}"
echo "Applied: ${T2_COUNT}"
echo "Ignored: ${T2_SKIPPED} non-Macmini8,1 T2 patches"
echo "Profile: AppleSMC / sensors / fan only"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "compatible=true" >> "${GITHUB_OUTPUT}"
  echo "failed_patch=" >> "${GITHUB_OUTPUT}"
  echo "patch_count=${T2_COUNT}" >> "${GITHUB_OUTPUT}"
  echo "skipped_count=${T2_SKIPPED}" >> "${GITHUB_OUTPUT}"
  echo "skipped_patch=non-Macmini8,1 T2 patches" >> "${GITHUB_OUTPUT}"
fi
