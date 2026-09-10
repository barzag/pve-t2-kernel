#!/usr/bin/env bash

set -euo pipefail

PVE_DIR="proxmox-pve-kernel"

TARGET_MODEL="Macmini8,1"

CONFIG_FILE="${PVE_DIR}/debian/rules.d/config-amd64.opts"

#
# Minimal Macmini8,1 T2 kernel configuration.
#
# The selected T2 patch profile only modifies the Apple SMC driver.
# BCE, GMUX, Touch Bar, APFS, audio and other generic T2 options are
# intentionally not enabled for this Proxmox server target.
#

REQUIRED_CONFIG_OPTS=(
  "-m SENSORS_APPLESMC"
)

if [[ ! -d "${PVE_DIR}/.git" ]]; then
  echo "ERROR: ${PVE_DIR} repository is missing" >&2
  exit 1
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "ERROR: Proxmox amd64 configuration file is missing" >&2
  exit 1
fi

if [[ ! -f "${PVE_DIR}/Makefile" ]]; then
  echo "ERROR: Proxmox Makefile is missing" >&2
  exit 1
fi

#
# Ensure that prepare-integration.sh will be able to apply
# the custom kernel suffix to the unmodified Proxmox tree.
#

if ! grep -Fqx \
  'EXTRAVERSION=-$(KREL)$(KREL_EXTRA)-pve' \
  "${PVE_DIR}/Makefile"
then
  echo "ERROR: expected Proxmox EXTRAVERSION was not found" >&2
  exit 1
fi

#
# Validate the minimal configuration directives.
#

CONFIG_COUNT=0

for CONFIG_OPT in "${REQUIRED_CONFIG_OPTS[@]}"; do

  if [[ ! "${CONFIG_OPT}" =~ ^-(e|m|d)[[:space:]][A-Z0-9_]+$ ]]; then
    echo "ERROR: invalid kernel configuration directive: ${CONFIG_OPT}" >&2
    exit 1
  fi

  CONFIG_COUNT=$((CONFIG_COUNT + 1))
done

if [[ "${CONFIG_COUNT}" -ne 1 ]]; then
  echo "ERROR: unexpected Macmini8,1 configuration count" >&2
  echo "Expected: 1"
  echo "Actual:   ${CONFIG_COUNT}"
  exit 1
fi

if [[ "${REQUIRED_CONFIG_OPTS[0]}" != "-m SENSORS_APPLESMC" ]]; then
  echo "ERROR: unexpected Macmini8,1 kernel configuration" >&2
  exit 1
fi

echo
echo "Minimal T2 integration inputs validated."
echo "Target:             ${TARGET_MODEL}"
echo "T2 profile:         AppleSMC / sensors / fan only"
echo "T2 config entries:  ${CONFIG_COUNT}"
echo "Kernel option:       ${REQUIRED_CONFIG_OPTS[0]}"
echo "Kernel suffix input: compatible"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "config_count=${CONFIG_COUNT}" >> "${GITHUB_OUTPUT}"
fi
