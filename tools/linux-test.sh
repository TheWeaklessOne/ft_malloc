#!/usr/bin/env bash
set -euo pipefail

VM_NAME=${VM_NAME:-malloc-test2}
PROJECT_NAME=malloc

if ! command -v multipass >/dev/null 2>&1; then
  echo "[linux-test] multipass not found; skipping" >&2
  exit 0
fi

if ! multipass info "$VM_NAME" >/dev/null 2>&1; then
  echo "[linux-test] VM $VM_NAME not found; run tools/linux-setup.sh first" >&2
  exit 1
fi

TMPDIR_HOST=$(mktemp -d)
rsync -a --delete --exclude '.git' ./ "$TMPDIR_HOST/"

echo "[linux-test] transferring project to VM" >&2
multipass transfer --recursive "$TMPDIR_HOST/" "$VM_NAME:/home/ubuntu/$PROJECT_NAME"

echo "[linux-test] building and testing inside VM" >&2
multipass exec "$VM_NAME" -- bash -lc "cd $PROJECT_NAME && make clean all test | cat"

echo "[linux-test] done."


