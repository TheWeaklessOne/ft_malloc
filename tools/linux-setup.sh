#!/usr/bin/env bash
set -euo pipefail

VM_NAME=${VM_NAME:-malloc-test2}

if ! command -v multipass >/dev/null 2>&1; then
  echo "[linux-setup] multipass not found; install from https://multipass.run" >&2
  exit 0
fi

if ! multipass info "$VM_NAME" >/dev/null 2>&1; then
  echo "[linux-setup] launching VM $VM_NAME" >&2
  multipass launch --name "$VM_NAME" --mem 4G --disk 10G --cpus 2 || true
fi

echo "[linux-setup] ensuring build tools inside $VM_NAME" >&2
multipass exec "$VM_NAME" -- bash -lc 'sudo apt-get update -y && sudo apt-get install -y build-essential clang make git ca-certificates pkg-config libatomic1 curl libicu-dev libbsd0 libedit2 libsqlite3-0 libxml2 tzdata zlib1g libcurl4-openssl-dev'

echo "[linux-setup] checking Swift toolchain" >&2
if ! multipass exec "$VM_NAME" -- bash -lc 'swiftc --version' >/dev/null 2>&1; then
  echo "[linux-setup] Installing Swift 6.0.1 for Ubuntu 24.04 aarch64..." >&2
  multipass exec "$VM_NAME" -- bash -lc '
    set -euo pipefail
    SWIFT_VER=6.0.1-RELEASE
    SWIFT_BASE=https://download.swift.org/swift-6.0.1-release/ubuntu2404-aarch64/swift-$SWIFT_VER
    SWIFT_TAR=swift-$SWIFT_VER-ubuntu24.04-aarch64.tar.xz
    cd /tmp && curl -fL "$SWIFT_BASE/$SWIFT_TAR" -o "$SWIFT_TAR"
    sudo mkdir -p /opt/swift && sudo tar -xJf "$SWIFT_TAR" -C /opt/swift
    echo "export PATH=/opt/swift/swift-$SWIFT_VER-ubuntu24.04-aarch64/usr/bin:\$PATH" >> ~/.profile
    echo "export PATH=/opt/swift/swift-$SWIFT_VER-ubuntu24.04-aarch64/usr/bin:\$PATH" >> ~/.bashrc
  '
fi

echo "[linux-setup] done."


