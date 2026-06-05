#!/usr/bin/env bash
# Patchfly CLI installer for macOS and Linux.
#
# One-liner (no setup required):
#   curl --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/fatmuh/patchfly-install/main/install.sh -sSf | bash
#
# Environment variables (all optional):
#   PATCHFLY_BINARY_URL   Override default binary CDN URL
#                         default: https://is3.cloudhost.id/moccilabs/patchfly
#   PATCHFLY_VERSION      Version to install (default: latest)
#   PATCHFLY_INSTALL      Install location (default: ~/.patchfly/bin)

set -euo pipefail

BINARY_NAME="patchfly"
INSTALL_DIR="${PATCHFLY_INSTALL:-$HOME/.patchfly/bin}"
VERSION="${PATCHFLY_VERSION:-latest}"
# Default binary CDN (IDCloudHost S3 hosting Patchfly releases).
# Override with PATCHFLY_BINARY_URL=... to self-host or use a different bucket.
BINARY_URL="${PATCHFLY_BINARY_URL:-https://is3.cloudhost.id/moccilabs/patchfly}"
BINARY_URL="${BINARY_URL%/}"  # strip trailing slash

# ---------------------------------------------------------------------------
# Pretty output
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  BOLD="\033[1m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"
else
  BOLD=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi
info()    { printf "${BOLD}==>${RESET} %s\n" "$*"; }
success() { printf "${GREEN}\xe2\x9c\x93${RESET} %s\n" "$*"; }
warn()    { printf "${YELLOW}!${RESET} %s\n" "$*" >&2; }
error()   { printf "${RED}\xe2\x9c\x97${RESET} %s\n" "$*" >&2; }

# ---------------------------------------------------------------------------
# Detect OS and arch
# ---------------------------------------------------------------------------
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
  linux)  OS="linux" ;;
  darwin) OS="macos" ;;
  *) error "Unsupported OS: $OS. Patchfly CLI supports macOS and Linux."; exit 1 ;;
esac

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)  ARCH="x64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) error "Unsupported arch: $ARCH. Supported: x86_64, aarch64 (arm64)."; exit 1 ;;
esac

ASSET="${BINARY_NAME}-${OS}-${ARCH}"
info "Detected platform: ${OS}/${ARCH}"

# ---------------------------------------------------------------------------
# Resolve version (default: latest)
# ---------------------------------------------------------------------------
if [ "$VERSION" = "latest" ]; then
  VERSION_PATH="latest"
else
  VERSION_PATH="v$VERSION"
fi
info "Version: $VERSION_PATH"

# ---------------------------------------------------------------------------
# Set up temp dir
# ---------------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BINARY_PATH="$INSTALL_DIR/$BINARY_NAME"

# ---------------------------------------------------------------------------
# Download binary
# ---------------------------------------------------------------------------
DOWNLOAD_URL="${BINARY_URL}/cli/${VERSION_PATH}/${ASSET}"
info "Downloading from: $BINARY_URL/cli/${VERSION_PATH}/${ASSET}"

HTTP_CODE="000"
if command -v curl >/dev/null 2>&1; then
  HTTP_CODE=$(curl -sSL -w "%{http_code}" -o "$TMP/$BINARY_NAME" "$DOWNLOAD_URL" 2>/dev/null || echo "000")
elif command -v wget >/dev/null 2>&1; then
  if wget -q -O "$TMP/$BINARY_NAME" "$DOWNLOAD_URL" 2>/dev/null; then
    HTTP_CODE="200"
  fi
else
  error "Need curl or wget installed"
  exit 1
fi

if [ "$HTTP_CODE" != "200" ] || [ ! -s "$TMP/$BINARY_NAME" ]; then
  error "Download failed (HTTP $HTTP_CODE) for: $DOWNLOAD_URL"
  echo ""
  echo "  Troubleshooting:"
  echo "    - Check your internet connection"
  echo "    - Verify the release exists at: ${BINARY_URL}/cli/${VERSION_PATH}/"
  echo "    - Try a specific version: PATCHFLY_VERSION=0.1.0 ..."
  echo "    - Self-host? Set PATCHFLY_BINARY_URL=... to your own bucket"
  exit 1
fi

# ---------------------------------------------------------------------------
# Verify SHA-256 (if sidecar exists)
# ---------------------------------------------------------------------------
SHA_URL="${BINARY_URL}/cli/${VERSION_PATH}/${ASSET}.sha256"
SHA_FILE="$TMP/${ASSET}.sha256"
SHA_OK=false
if command -v curl >/dev/null 2>&1 && curl -sSL -o "$SHA_FILE" "$SHA_URL" 2>/dev/null && [ -s "$SHA_FILE" ]; then
  EXPECTED=$(awk '{print $1}' "$SHA_FILE")
  if command -v shasum >/dev/null 2>&1; then
    ACTUAL=$(shasum -a 256 "$TMP/$BINARY_NAME" | awk '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    ACTUAL=$(sha256sum "$TMP/$BINARY_NAME" | awk '{print $1}')
  fi
  if [ -n "${ACTUAL:-}" ] && [ "$EXPECTED" = "$ACTUAL" ]; then
    success "SHA-256 verified"
    SHA_OK=true
  else
    warn "SHA-256 mismatch (continuing anyway)"
  fi
fi

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
FILE_SIZE=$(du -h "$TMP/$BINARY_NAME" | cut -f1)
mkdir -p "$INSTALL_DIR"
chmod +x "$TMP/$BINARY_NAME"
mv -f "$TMP/$BINARY_NAME" "$BINARY_PATH"
success "Installed $FILE_SIZE to: $BINARY_PATH"

# ---------------------------------------------------------------------------
# PATH setup
# ---------------------------------------------------------------------------
PATH_LINE="export PATH=\"\$PATH:$INSTALL_DIR\""
SHELL_RC=""
case "${SHELL:-/bin/bash}" in
  */zsh)  SHELL_RC="$HOME/.zshrc" ;;
  */bash) SHELL_RC="$HOME/.bashrc" ;;
  */fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
esac

case ":$PATH:" in
  *":$INSTALL_DIR:"*) in_path=true ;;
  *) in_path=false ;;
esac

echo ""
if [ "$in_path" = true ]; then
  success "Already in PATH - run: $BINARY_NAME --version"
else
  warn "Not in PATH yet. Add to your shell rc:"
  echo ""
  printf "  ${BOLD}%s${RESET}\n" "$PATH_LINE"
  echo ""
  if [ -n "$SHELL_RC" ] && [ -w "$SHELL_RC" ] && ! grep -qF "$INSTALL_DIR" "$SHELL_RC" 2>/dev/null; then
    printf "  Auto-add to %s? [y/N] " "$SHELL_RC"
    read -r REPLY
    if [ "${REPLY:-n}" = "y" ] || [ "${REPLY:-n}" = "Y" ]; then
      echo "" >> "$SHELL_RC"
      echo "# Patchfly CLI" >> "$SHELL_RC"
      echo "$PATH_LINE" >> "$SHELL_RC"
      success "Added to $SHELL_RC - restart shell or: source $SHELL_RC"
    fi
  fi
fi

echo ""
info "Verify installation:"
echo "  $BINARY_PATH --version"
echo ""
info "Quick start:"
echo "  $BINARY_NAME register --email you@example.com --password yourpass"
echo "  $BINARY_NAME apps create --slug com.example.app --name \"My App\""
echo "  $BINARY_NAME patch"
