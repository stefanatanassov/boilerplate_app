#!/usr/bin/env bash
set -euo pipefail

DOMAIN_BASE="${1:-dev.local.test}"
OUT_DIR="tls/${DOMAIN_BASE}"
mkdir -p "$OUT_DIR"

# Check mkcert
if ! command -v mkcert >/dev/null 2>&1; then
  echo "[error] mkcert not found. On macOS: brew install mkcert nss"
  exit 2
fi

# Install local CA (idempotent)
mkcert -install

# Wildcard + root cert
echo "[info] Generating certs for *.${DOMAIN_BASE} and ${DOMAIN_BASE}"
mkcert -cert-file "${OUT_DIR}/fullchain.pem" -key-file "${OUT_DIR}/privkey.pem" "*.${DOMAIN_BASE}" "${DOMAIN_BASE}"

echo "[success] Certs created at ${OUT_DIR}"
