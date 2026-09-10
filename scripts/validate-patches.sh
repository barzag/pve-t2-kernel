#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

PVE_DIR="proxmox-pve-kernel"
T2_DIR="linux-t2-patches"

TARGET_MODEL="Macmini8,1"
SKIPPED_PATCH="2008-i915-4-lane-quirk-for-mbp15-1.patch"

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
echo "Proxmox SHA: ${PVE_SHA}"
echo "T2 SHA:      ${T2_SHA}"

git -C "${PVE_DIR}" checkout --detach "${PVE_SHA}"

git -C "${PVE_DIR}" config \
  submodule.submodules/ubuntu-kernel.url \
  https://git.proxmox.com/git/mirror_ubuntu-kernels.git

git -C "${PVE_DIR}" submodule update \
  --init \
  --depth 1 \
  submodules/ubuntu-kernel

git -C "${T2_DIR}" checkout --detach "${T2_SHA}"

rm -rf kernel-compat

cp -a \
  "${PVE_DIR}/submodules/ubuntu-kernel" \
  kernel-compat

rm -rf \
  kernel-compat/debian \
  kernel-compat/debian.master

cd kernel-compat

echo
echo "Applying official Proxmox patches..."

for patchfile in "../${PVE_DIR}"/patches/kernel/*.patch; do
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

echo
echo "Applying T2 patches..."

T2_COUNT=0
T2_SKIPPED=0

for patchfile in "../${T2_DIR}"/*.patch; do
  [[ -e "${patchfile}" ]] || continue

  PATCH_NAME="$(basename "${patchfile}")"

  if [[ "${PATCH_NAME}" == "${SKIPPED_PATCH}" ]]; then
    echo "T2 SKIP -> ${PATCH_NAME}"
    echo "Reason: MacBookPro15,1-specific; not applicable to ${TARGET_MODEL}"

    T2_SKIPPED=$((T2_SKIPPED + 1))
    continue
  fi

  echo "T2 -> ${PATCH_NAME}"

  if ! patch \
    --batch \
    -p1 \
    < "${patchfile}" \
    > /tmp/t2-patch.log 2>&1
  then
    cat /tmp/t2-patch.log
    echo "ERROR: T2 patch failed: ${PATCH_NAME}" >&2
    exit 1
  fi

  T2_COUNT=$((T2_COUNT + 1))
done

if [[ "${T2_COUNT}" -eq 0 ]]; then
  echo "ERROR: no T2 patches were applied" >&2
  exit 1
fi

echo
echo "Patch compatibility passed."
echo "Applied: ${T2_COUNT}"
echo "Skipped: ${T2_SKIPPED}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "patch_count=${T2_COUNT}" >> "${GITHUB_OUTPUT}"
  echo "skipped_count=${T2_SKIPPED}" >> "${GITHUB_OUTPUT}"
  echo "skipped_patch=${SKIPPED_PATCH}" >> "${GITHUB_OUTPUT}"
fi
