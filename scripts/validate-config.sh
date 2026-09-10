#!/usr/bin/env bash

set -euo pipefail

PVE_DIR="proxmox-pve-kernel"
T2_DIR="linux-t2-patches"

TARGET_MODEL="Macmini8,1"

CONFIG_FILE="${PVE_DIR}/debian/rules.d/config-amd64.opts"

if [[ ! -f "${T2_DIR}/extra_config" ]]; then
  echo "ERROR: T2 extra_config is missing" >&2
  exit 1
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "ERROR: Proxmox amd64 configuration file is missing" >&2
  exit 1
fi

if ! grep -Fqx \
  'EXTRAVERSION=-$(KREL)$(KREL_EXTRA)-pve' \
  "${PVE_DIR}/Makefile"
then
  echo "ERROR: expected Proxmox EXTRAVERSION was not found" >&2
  exit 1
fi

CONFIG_COUNT=0

while IFS='=' read -r KEY VALUE || [[ -n "${KEY:-}" ]]; do
  [[ -n "${KEY:-}" ]] || continue
  [[ "${KEY}" == \#* ]] && continue

  if [[ ! "${KEY}" =~ ^CONFIG_[A-Z0-9_]+$ ]]; then
    echo "ERROR: invalid T2 config entry: ${KEY}" >&2
    exit 1
  fi

  case "${VALUE}" in
    y|m|n)
      ;;
    *)
      echo "ERROR: unsupported T2 config value: ${KEY}=${VALUE}" >&2
      exit 1
      ;;
  esac

  CONFIG_COUNT=$((CONFIG_COUNT + 1))
done < "${T2_DIR}/extra_config"

if [[ "${CONFIG_COUNT}" -eq 0 ]]; then
  echo "ERROR: no T2 kernel configuration found" >&2
  exit 1
fi

echo
echo "T2 integration inputs validated."
echo "Target:             ${TARGET_MODEL}"
echo "T2 config entries:  ${CONFIG_COUNT}"
echo "Kernel suffix input: compatible"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "config_count=${CONFIG_COUNT}" >> "${GITHUB_OUTPUT}"
fi
