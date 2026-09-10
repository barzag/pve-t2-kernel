#!/usr/bin/env bash

set -euo pipefail

TARGET_MODEL="Macmini8,1"

PVE_DIR="proxmox-pve-kernel"
T2_DIR="linux-t2-patches"
CONFIG_FILE="${PVE_DIR}/debian/rules.d/config-amd64.opts"

SKIPPED_PATCH="2008-i915-4-lane-quirk-for-mbp15-1.patch"

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

echo "Target model: ${TARGET_MODEL}"
echo "Preparing T2 build tree..."

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

if [[ ! -f "${T2_DIR}/extra_config" ]]; then
  echo "ERROR: T2 extra_config is missing" >&2
  exit 1
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "ERROR: Proxmox amd64 configuration file is missing" >&2
  exit 1
fi

rm -f "${PVE_DIR}"/patches/kernel/t2-*.patch

T2_PATCH_COUNT=0

for patchfile in "${T2_DIR}"/*.patch; do
  [[ -e "${patchfile}" ]] || continue

  PATCH_NAME="$(basename "${patchfile}")"

  if [[ "${PATCH_NAME}" == "${SKIPPED_PATCH}" ]]; then
    echo "T2 SKIP -> ${PATCH_NAME}"
    echo "Reason: MacBookPro15,1-specific; not applicable to ${TARGET_MODEL}"
    continue
  fi

  echo "T2 STAGE -> ${PATCH_NAME}"

  cp \
    "${patchfile}" \
    "${PVE_DIR}/patches/kernel/t2-${PATCH_NAME}"

  T2_PATCH_COUNT=$((T2_PATCH_COUNT + 1))
done

if [[ "${T2_PATCH_COUNT}" -ne "${EXPECTED_PATCH_COUNT}" ]]; then
  echo "ERROR: T2 staged patch count mismatch" >&2
  echo "Expected: ${EXPECTED_PATCH_COUNT}"
  echo "Staged:   ${T2_PATCH_COUNT}"
  exit 1
fi

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

T2_CONFIG_OPTS="/tmp/t2-config.opts"
: > "${T2_CONFIG_OPTS}"

T2_CONFIG_COUNT=0

while IFS='=' read -r KEY VALUE || [[ -n "${KEY:-}" ]]; do
  [[ -n "${KEY:-}" ]] || continue
  [[ "${KEY}" == \#* ]] && continue

  if [[ ! "${KEY}" =~ ^CONFIG_[A-Z0-9_]+$ ]]; then
    echo "ERROR: invalid T2 config entry: ${KEY}" >&2
    exit 1
  fi

  SYMBOL="${KEY#CONFIG_}"

  case "${VALUE}" in
    y)
      ACTION="-e"
      ;;
    m)
      ACTION="-m"
      ;;
    n)
      ACTION="-d"
      ;;
    *)
      echo "ERROR: unsupported T2 config value: ${KEY}=${VALUE}" >&2
      exit 1
      ;;
  esac

  printf '%s %s\n' \
    "${ACTION}" \
    "${SYMBOL}" \
    >> "${T2_CONFIG_OPTS}"

  T2_CONFIG_COUNT=$((T2_CONFIG_COUNT + 1))
done < "${T2_DIR}/extra_config"

if [[ "${T2_CONFIG_COUNT}" -eq 0 ]]; then
  echo "ERROR: no T2 kernel configuration found" >&2
  exit 1
fi

{
  echo
  echo "# BEGIN pve-t2-kernel configuration for ${TARGET_MODEL}"
  cat "${T2_CONFIG_OPTS}"
  echo "# END pve-t2-kernel configuration for ${TARGET_MODEL}"
} >> "${CONFIG_FILE}"

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
echo "T2 build integration ready."
echo "Target:             ${TARGET_MODEL}"
echo "T2 patches staged:  ${T2_PATCH_COUNT}"
echo "T2 config options:  ${T2_CONFIG_COUNT}"
echo "Kernel suffix:      -pve-t2"
echo "Excluded patch:     ${SKIPPED_PATCH}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "target=${TARGET_MODEL}" >> "${GITHUB_OUTPUT}"
  echo "patch_count=${T2_PATCH_COUNT}" >> "${GITHUB_OUTPUT}"
  echo "config_count=${T2_CONFIG_COUNT}" >> "${GITHUB_OUTPUT}"
  echo "suffix=pve-t2" >> "${GITHUB_OUTPUT}"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat >> "${GITHUB_STEP_SUMMARY}" <<EOF

## T2 build integration
- Target hardware: \`${TARGET_MODEL}\`
- T2 patches staged: \`${T2_PATCH_COUNT}\`
- T2 configuration directives: \`${T2_CONFIG_COUNT}\`
- Kernel suffix: \`-pve-t2\`
- Excluded patch: \`${SKIPPED_PATCH}\`
- Exclusion reason: MacBookPro15,1-specific, not applicable to \`${TARGET_MODEL}\`
EOF
fi
