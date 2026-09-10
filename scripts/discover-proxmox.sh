#!/usr/bin/env bash

set -euo pipefail

RESULT="$(
  docker run --rm debian:trixie bash -c '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -qq
    apt-get install -y -qq ca-certificates curl >/dev/null

    curl \
      --fail \
      --location \
      --silent \
      --show-error \
      https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg \
      -o /usr/share/keyrings/proxmox-archive-keyring.gpg

    cat > /etc/apt/sources.list.d/proxmox.sources <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

    apt-get update -qq

    PACKAGE="$(
      apt-cache pkgnames |
      grep -E "^proxmox-kernel-[0-9].*-pve$" |
      sort -V |
      tail -n 1
    )"

    if [[ -z "${PACKAGE}" ]]; then
      echo "ERROR: no Proxmox kernel package found" >&2
      exit 1
    fi

    VERSION="$(
      apt-cache policy "${PACKAGE}" |
      awk "/Candidate:/ {print \$2; exit}"
    )"

    KERNEL="$(
      printf "%s\n" "${PACKAGE}" |
      sed -E "s/^proxmox-kernel-(.*)-pve$/\1/"
    )"

    printf "%s|%s|%s\n" \
      "${PACKAGE}" \
      "${KERNEL}" \
      "${VERSION}"
  '
)"

IFS='|' read -r PACKAGE KERNEL VERSION <<< "${RESULT}"

if [[ -z "${PACKAGE}" || -z "${KERNEL}" || -z "${VERSION}" ]]; then
  echo "ERROR: incomplete Proxmox discovery result" >&2
  exit 1
fi

echo "Published package: ${PACKAGE}"
echo "Published kernel:  ${KERNEL}"
echo "Package version:   ${VERSION}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "package=${PACKAGE}" >> "${GITHUB_OUTPUT}"
  echo "kernel=${KERNEL}" >> "${GITHUB_OUTPUT}"
  echo "version=${VERSION}" >> "${GITHUB_OUTPUT}"
fi
