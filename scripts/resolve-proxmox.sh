#!/usr/bin/env bash

set -euo pipefail

if [[ -z "${PUBLISHED_KERNEL:-}" ]]; then
  echo "ERROR: PUBLISHED_KERNEL is not defined" >&2
  exit 1
fi

if [[ -z "${PUBLISHED_VERSION:-}" ]]; then
  echo "ERROR: PUBLISHED_VERSION is not defined" >&2
  exit 1
fi

if [[ -e "proxmox-pve-kernel" ]]; then
  echo "ERROR: proxmox-pve-kernel already exists" >&2
  exit 1
fi

git clone \
  --filter=blob:none \
  --no-checkout \
  https://github.com/proxmox/pve-kernel.git \
  proxmox-pve-kernel

cd proxmox-pve-kernel

EXPECTED_SUBJECT="update ABI file for ${PUBLISHED_KERNEL}-pve (amd64)"

PVE_SHA="$(
  git log origin/master \
    --format='%H%x09%s' |
  awk -F '\t' -v expected="${EXPECTED_SUBJECT}" '
    $2 == expected && !found {
      print $1
      found=1
    }
  '
)"

if [[ -z "${PVE_SHA}" ]]; then
  echo "ERROR: unable to resolve published Proxmox source commit" >&2
  exit 1
fi

PVE_SUBJECT="$(
  git show -s --format=%s "${PVE_SHA}"
)"

PVE_CHANGELOG="$(
  git show "${PVE_SHA}:debian/changelog" |
  sed -n '1p'
)"

if ! grep -Fq "(${PUBLISHED_VERSION}) " <<< "${PVE_CHANGELOG}"; then
  echo "ERROR: resolved source does not match published package version" >&2
  echo "Published version: ${PUBLISHED_VERSION}"
  echo "Changelog:         ${PVE_CHANGELOG}"
  exit 1
fi

echo "Resolved Proxmox source:"
echo "SHA:       ${PVE_SHA}"
echo "Commit:    ${PVE_SUBJECT}"
echo "Changelog: ${PVE_CHANGELOG}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "sha=${PVE_SHA}" >> "${GITHUB_OUTPUT}"
  echo "subject=${PVE_SUBJECT}" >> "${GITHUB_OUTPUT}"
  echo "changelog=${PVE_CHANGELOG}" >> "${GITHUB_OUTPUT}"
fi
