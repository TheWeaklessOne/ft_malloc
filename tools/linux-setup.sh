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
multipass exec "$VM_NAME" -- bash -lc 'sudo apt-get update -y && sudo apt-get install -y build-essential clang make git ca-certificates pkg-config libatomic1 curl'

echo "[linux-setup] checking Swift toolchain" >&2
if ! multipass exec "$VM_NAME" -- bash -lc 'swiftc --version' >/dev/null 2>&1; then
  echo "[linux-setup] Swift not found. Please install Swift toolchain inside VM (Swift 6 recommended)." >&2
  echo "You can follow: https://www.swift.org/install/linux/" >&2
fi

echo "[linux-setup] done."


