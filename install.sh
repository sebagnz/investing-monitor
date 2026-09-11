#!/usr/bin/env bash
set -euo pipefail

REPO_NAME="investing-monitor"
BRANCH="main"

INSTALL_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/investing-monitor"
SCRIPT_NAME="investing-monitor"

BASE_URL="https://raw.githubusercontent.com/sebagnz/${REPO_NAME}/${BRANCH}"

mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"

echo "Installing ${SCRIPT_NAME}..."

curl -fsSL "${BASE_URL}/monitor.sh" \
  -o "${INSTALL_DIR}/${SCRIPT_NAME}"

chmod +x "${INSTALL_DIR}/${SCRIPT_NAME}"

if [[ ! -f "${CONFIG_DIR}/config" ]]; then
  curl -fsSL "${BASE_URL}/config.example" \
    -o "${CONFIG_DIR}/config"

  chmod 600 "${CONFIG_DIR}/config"

  echo
  echo "Created config file:"
  echo "  ${CONFIG_DIR}/config"
  echo
  echo "Edit it before the first run."
fi

CRON_LINE="*/30 * * * * ${INSTALL_DIR}/${SCRIPT_NAME} >> ${CONFIG_DIR}/investing-monitor.log 2>&1"

(
  crontab -l 2>/dev/null | grep -v "${INSTALL_DIR}/${SCRIPT_NAME}" || true
  echo "$CRON_LINE"
) | crontab -

echo
echo "Installed successfully."
echo "Script: ${INSTALL_DIR}/${SCRIPT_NAME}"
echo "Config: ${CONFIG_DIR}/config"
echo "Log:    ${CONFIG_DIR}/investing-monitor.log"
echo "Cron:   every 30 minutes"
