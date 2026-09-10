#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${PVE_KERNEL:-}" ]]; then
  echo "ERROR: PVE_KERNEL is not defined" >&2
  exit 1
fi

PVE_SERIES="$(
  printf '%s\n' "${PVE_KERNEL}" |
  sed -E 's/^([0-9]+\.[0-9]+).*/\1/'
)"

echo "Proxmox kernel: ${PVE_KERNEL}"
echo "Required T2 series: ${PVE_SERIES}"

if [[ -e "linux-t2-patches" ]]; then
  echo "ERROR: linux-t2-patches already exists" >&2
  exit 1
fi

git clone \
  --filter=blob:none \
  --no-checkout \
  https://github.com/t2linux/linux-t2-patches.git \
  linux-t2-patches

cd linux-t2-patches

T2_SHA=""
T2_KVER=""

while read -r COMMIT; do
  KVER="$(
    git show "${COMMIT}:version" 2>/dev/null |
    sed -n 's/^KVER=//p' |
    tr -d '\r\n' ||
    true
  )"

  [[ -n "${KVER}" ]] || continue

  T2_SERIES="$(
    printf '%s\n' "${KVER}" |
    sed -E 's/^([0-9]+\.[0-9]+).*/\1/'
  )"

  if [[ "${T2_SERIES}" == "${PVE_SERIES}" ]]; then
    T2_SHA="${COMMIT}"
    T2_KVER="${KVER}"
    break
  fi
done < <(git rev-list origin/main)

if [[ -z "${T2_SHA}" ]]; then
  echo "ERROR: no T2 candidate found for kernel series ${PVE_SERIES}" >&2
  exit 1
fi

T2_SUBJECT="$(
  git show -s --format=%s "${T2_SHA}"
)"

echo
echo "Resolved T2 candidate:"
echo "SHA:    ${T2_SHA}"
echo "KVER:   ${T2_KVER}"
echo "Commit: ${T2_SUBJECT}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "sha=${T2_SHA}" >> "${GITHUB_OUTPUT}"
  echo "kver=${T2_KVER}" >> "${GITHUB_OUTPUT}"
  echo "subject=${T2_SUBJECT}" >> "${GITHUB_OUTPUT}"
fi
