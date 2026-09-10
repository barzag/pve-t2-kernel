#!/usr/bin/env bash

set -euo pipefail

PVE_DIR="${PVE_DIR:-proxmox-pve-kernel}"

if [[ -z "${KERNEL_VERSION:-}" ]]; then
  echo "ERROR: KERNEL_VERSION is not defined" >&2
  exit 1
fi

TEMP_DIR="${RUNNER_TEMP:-/tmp}"

echo
echo "Build completed. Validating packages..."

KERNEL_DEB="$(
  find "${PVE_DIR}" \
    -maxdepth 1 \
    -type f \
    -name "proxmox-kernel-*-pve-t2_*.deb" \
    -print |
  sed -n "1p"
)"

HEADER_DEB="$(
  find "${PVE_DIR}" \
    -maxdepth 1 \
    -type f \
    -name "proxmox-headers-*-pve-t2_*.deb" \
    -print |
  sed -n "1p"
)"

if [[ -z "${KERNEL_DEB}" ]]; then
  echo "ERROR: T2 kernel package was not generated" >&2
  exit 1
fi

if [[ -z "${HEADER_DEB}" ]]; then
  echo "ERROR: T2 headers package was not generated" >&2
  exit 1
fi

echo
echo "Kernel package:"

dpkg-deb \
  --show \
  --showformat='Package: ${Package}\nVersion: ${Version}\nArchitecture: ${Architecture}\n' \
  "${KERNEL_DEB}"

echo
echo "Headers package:"

dpkg-deb \
  --show \
  --showformat='Package: ${Package}\nVersion: ${Version}\nArchitecture: ${Architecture}\n' \
  "${HEADER_DEB}"

KERNEL_CONTENTS="${TEMP_DIR}/kernel-package.list"
EXPECTED_VMLINUZ="/boot/vmlinuz-${KERNEL_VERSION}-pve-t2"

if ! dpkg-deb -c "${KERNEL_DEB}" > "${KERNEL_CONTENTS}"; then
  echo "ERROR: unable to inspect generated kernel package" >&2
  exit 1
fi

if ! grep -Fq "${EXPECTED_VMLINUZ}" "${KERNEL_CONTENTS}"; then
  echo "ERROR: expected T2 vmlinuz was not found in the package" >&2
  echo "Expected: ${EXPECTED_VMLINUZ}"

  echo
  echo "Files found under /boot:"

  grep -F "/boot/" "${KERNEL_CONTENTS}" || true

  exit 1
fi

echo
echo "Validated T2 kernel image:"

grep -F "${EXPECTED_VMLINUZ}" "${KERNEL_CONTENTS}"

echo
echo "Generating SHA256 checksums..."

sha256sum \
  "${KERNEL_DEB}" \
  "${HEADER_DEB}" \
  | tee "${PVE_DIR}/SHA256SUMS"

echo
echo "T2 KERNEL BUILD SUCCESSFUL"
echo "Kernel: ${KERNEL_VERSION}-pve-t2"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "kernel_deb=${KERNEL_DEB}" >> "${GITHUB_OUTPUT}"
  echo "header_deb=${HEADER_DEB}" >> "${GITHUB_OUTPUT}"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat >> "${GITHUB_STEP_SUMMARY}" <<EOF

## T2 kernel build
- Target: \`Macmini8,1\`
- Kernel: \`${KERNEL_VERSION}-pve-t2\`
- Build result: **SUCCESS**
- Kernel package: \`$(basename "${KERNEL_DEB}")\`
- Headers package: \`$(basename "${HEADER_DEB}")\`
EOF
fi
