#!/usr/bin/env bash
set -euo pipefail

REPO_NAME="investing-monitor"

INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="investing-monitor"

RELEASE_BASE_URL="https://github.com/sebagnz/${REPO_NAME}/releases"

SOURCE_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

release_asset_name() {
  local operating_system
  local architecture
  local libc_suffix=""

  case "$(uname -s)" in
    Linux) operating_system="linux" ;;
    Darwin) operating_system="darwin" ;;
    *)
      echo "Unsupported operating system: $(uname -s)" >&2
      return 1
      ;;
  esac

  case "$(uname -m)" in
    x86_64|amd64) architecture="x64" ;;
    arm64|aarch64) architecture="arm64" ;;
    *)
      echo "Unsupported architecture: $(uname -m)" >&2
      return 1
      ;;
  esac

  if [[ "$operating_system" == "linux" ]] && \
     ldd --version 2>&1 | grep -qi musl; then
    libc_suffix="-musl"
  fi

  printf 'investing-monitor-%s-%s%s' \
    "$operating_system" "$architecture" "$libc_suffix"
}

verify_checksum() {
  local binary_path="$1"
  local checksums_path="$2"
  local asset_name="$3"
  local expected_checksum
  local actual_checksum

  expected_checksum="$(awk -v asset="$asset_name" '$2 == asset { print $1 }' "$checksums_path")"
  if [[ -z "$expected_checksum" ]]; then
    echo "No checksum found for ${asset_name}." >&2
    return 1
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    actual_checksum="$(sha256sum "$binary_path" | awk '{ print $1 }')"
  elif command -v shasum >/dev/null 2>&1; then
    actual_checksum="$(shasum -a 256 "$binary_path" | awk '{ print $1 }')"
  else
    echo "Missing dependency: sha256sum or shasum" >&2
    return 1
  fi

  if [[ "$actual_checksum" != "$expected_checksum" ]]; then
    echo "Checksum verification failed for ${asset_name}." >&2
    return 1
  fi
}

mkdir -p "$INSTALL_DIR"

echo "Installing ${SCRIPT_NAME}..."

temporary_script="$(mktemp "${INSTALL_DIR}/${SCRIPT_NAME}.XXXXXX")"

if [[ -n "$SOURCE_DIR" && -x "${SOURCE_DIR}/dist/investing-monitor" ]]; then
  cp "${SOURCE_DIR}/dist/investing-monitor" "$temporary_script"
else
  asset_name="$(release_asset_name)"
  release_version="${INVESTING_MONITOR_VERSION:-latest}"
  temporary_checksums="$(mktemp)"

  if [[ "$release_version" == "latest" ]]; then
    download_url="${RELEASE_BASE_URL}/latest/download"
  else
    download_url="${RELEASE_BASE_URL}/download/${release_version}"
  fi

  if ! curl -fsSL "${download_url}/${asset_name}" -o "$temporary_script"; then
    rm -f "$temporary_script" "$temporary_checksums"
    echo "Failed to download ${asset_name}." >&2
    exit 1
  fi
  if ! curl -fsSL "${download_url}/checksums.txt" -o "$temporary_checksums"; then
    rm -f "$temporary_script" "$temporary_checksums"
    echo "Failed to download release checksums." >&2
    exit 1
  fi
  if ! verify_checksum "$temporary_script" "$temporary_checksums" "$asset_name"; then
    rm -f "$temporary_script" "$temporary_checksums"
    exit 1
  fi
  rm -f "$temporary_checksums"
fi

chmod +x "$temporary_script"
mv "$temporary_script" "${INSTALL_DIR}/${SCRIPT_NAME}"

echo
INVESTING_MONITOR_EXECUTABLE="${INSTALL_DIR}/${SCRIPT_NAME}" \
  "${INSTALL_DIR}/${SCRIPT_NAME}" configure
