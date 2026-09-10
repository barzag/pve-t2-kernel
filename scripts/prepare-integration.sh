#!/usr/bin/env bash

set -euo pipefail

TARGET_MODEL="Macmini8,1"

PVE_DIR="proxmox-pve-kernel"
T2_DIR="linux-t2-patches"
CONFIG_FILE="${PVE_DIR}/debian/rules.d/config-amd64.opts"

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

if [[ -z "${EXPECTED_PATCH_COUNT:-}" ]]; then
  echo "ERROR: EXPECTED_PATCH_COUNT is not defined" >&2
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

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "ERROR: Proxmox amd64 configuration file is missing" >&2
  exit 1
fi

echo "Target model: ${TARGET_MODEL}"
echo "Preparing minimal T2 build tree..."

ACTUAL_PVE_SHA="$(git -C "${PVE_DIR}" rev-parse HEAD)"
ACTUAL_T2_SHA="$(git -C "${T2_DIR}" rev-parse HEAD)"

if [[ "${ACTUAL_PVE_SHA}" != "${PVE_SHA}" ]]; then
  echo "ERROR: unexpected Proxmox source SHA" >&2
  echo "Expected: ${PVE_SHA}"
  echo "Actual:   ${ACTUAL_PVE_SHA}"
  exit 1
fi

if [[ "${ACTUAL_T2_SHA}" != "${T2_SHA}" ]]; then
  echo "ERROR: unexpected T2 source SHA" >&2
  echo "Expected: ${T2_SHA}"
  echo "Actual:   ${ACTUAL_T2_SHA}"
  exit 1
fi

#
# Stage only the patches required for Macmini8,1.
#

rm -f "${PVE_DIR}"/patches/kernel/t2-*.patch

T2_PATCH_COUNT=0

for PATCH_NAME in "${MACMINI_T2_PATCHES[@]}"; do
  PATCH_SOURCE="${T2_DIR}/${PATCH_NAME}"

  if [[ ! -f "${PATCH_SOURCE}" ]]; then
    echo "ERROR: required T2 patch is missing: ${PATCH_NAME}" >&2
    exit 1
  fi

  echo "T2 STAGE -> ${PATCH_NAME}"

  cp \
    "${PATCH_SOURCE}" \
    "${PVE_DIR}/patches/kernel/t2-${PATCH_NAME}"

  T2_PATCH_COUNT=$((T2_PATCH_COUNT + 1))
done

if [[ "${T2_PATCH_COUNT}" -ne "${EXPECTED_PATCH_COUNT}" ]]; then
  echo "ERROR: T2 staged patch count mismatch" >&2
  echo "Expected: ${EXPECTED_PATCH_COUNT}"
  echo "Staged:   ${T2_PATCH_COUNT}"
  exit 1
fi

#
# Give the custom kernel an explicit suffix.
#

if ! grep -Fqx \
  'EXTRAVERSION=-$(KREL)$(KREL_EXTRA)-pve' \
  "${PVE_DIR}/Makefile"
then
  echo "ERROR: expected Proxmox EXTRAVERSION was not found" >&2
  exit 1
fi

sed -i \
  's|EXTRAVERSION=-$(KREL)$(KREL_EXTRA)-pve|EXTRAVERSION=-$(KREL)$(KREL_EXTRA)-pve-t2|' \
  "${PVE_DIR}/Makefile"

if ! grep -Fqx \
  'EXTRAVERSION=-$(KREL)$(KREL_EXTRA)-pve-t2' \
  "${PVE_DIR}/Makefile"
then
  echo "ERROR: unable to set pve-t2 kernel suffix" >&2
  exit 1
fi

#
# Minimal kernel configuration.
#
# Do NOT import the complete T2Linux extra_config:
# it enables BCE, GMUX, Touch Bar, APFS and other components
# which are not required for this Macmini8,1 Proxmox target.
#

{
  echo
  echo "# BEGIN pve-t2-kernel configuration for ${TARGET_MODEL}"
  echo "-m SENSORS_APPLESMC"
  echo "# END pve-t2-kernel configuration for ${TARGET_MODEL}"
} >> "${CONFIG_FILE}"

T2_CONFIG_COUNT=1

#
# Final consistency checks.
#

STAGED_COUNT="$(
  find "${PVE_DIR}/patches/kernel" \
    -maxdepth 1 \
    -type f \
    -name 't2-*.patch' |
  wc -l
)"

if [[ "${STAGED_COUNT}" -ne "${T2_PATCH_COUNT}" ]]; then
  echo "ERROR: final T2 patch count mismatch" >&2
  exit 1
fi

echo
echo "Minimal T2 build integration ready."
echo "Target:             ${TARGET_MODEL}"
echo "T2 patches staged:  ${T2_PATCH_COUNT}"
echo "T2 config options:  ${T2_CONFIG_COUNT}"
echo "Kernel suffix:      -pve-t2"
echo "Patch profile:      AppleSMC / sensors / fan only"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "target=${TARGET_MODEL}" >> "${GITHUB_OUTPUT}"
  echo "patch_count=${T2_PATCH_COUNT}" >> "${GITHUB_OUTPUT}"
  echo "config_count=${T2_CONFIG_COUNT}" >> "${GITHUB_OUTPUT}"
  echo "suffix=pve-t2" >> "${GITHUB_OUTPUT}"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat >> "${GITHUB_STEP_SUMMARY}" <<EOF

## Minimal T2 build integration
- Target hardware: \`${TARGET_MODEL}\`
- T2 patches staged: \`${T2_PATCH_COUNT}\`
- T2 configuration directives: \`${T2_CONFIG_COUNT}\`
- Kernel suffix: \`-pve-t2\`
- T2 profile: AppleSMC / thermal sensors / fan support only
EOF
fi
