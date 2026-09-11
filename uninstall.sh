#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/investing-monitor"
SCRIPT_NAME="investing-monitor"

echo "Removing cron entry..."

(
  crontab -l 2>/dev/null | grep -v "${INSTALL_DIR}/${SCRIPT_NAME}" || true
) | crontab -

rm -f "${INSTALL_DIR}/${SCRIPT_NAME}"

echo
echo "Removed installed script and cron entry."
echo "Config and logs were left intact at:"
echo "  ${CONFIG_DIR}"
echo
echo "Delete that directory manually if you no longer need it."
