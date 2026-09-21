#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR=${INSTALL_DIR:-$HOME/.local/bin}
DOWNLOAD_URL=${GRAPHIFY_INIT_DOWNLOAD_URL:-https://raw.githubusercontent.com/wrallee/graphify-init/main/graphify-init}
TARGET="$INSTALL_DIR/graphify-init"

mkdir -p "$INSTALL_DIR"
TMP=$(mktemp "$INSTALL_DIR/.graphify-init.tmp.XXXXXX")
trap 'rm -f "$TMP"' EXIT

if ! curl -fsSL -o "$TMP" "$DOWNLOAD_URL"; then
  printf 'ERROR: failed to download graphify-init\n' >&2
  exit 1
fi

if ! bash -n "$TMP"; then
  printf 'ERROR: downloaded graphify-init failed shell syntax validation\n' >&2
  exit 1
fi

chmod +x "$TMP"
mv "$TMP" "$TARGET"
trap - EXIT

printf 'Installed graphify-init to %s\n' "$TARGET"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) printf 'Add %s to PATH, then run: graphify-init\n' "$INSTALL_DIR" ;;
esac
