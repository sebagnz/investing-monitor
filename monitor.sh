#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin"

CONFIG_FILE="$HOME/.config/investing-monitor/config"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing config file: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

for dependency in curl jq; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "Missing dependency: $dependency" >&2
    exit 1
  fi
done

echo "$(date -Is): Running SP500 monitor"

# -------------------------------------------------------------------
# Put your monitoring logic here.
#
# Example:
#
# response="$(curl -fsSL 'https://example.com/api')"
# price="$(jq -r '.price' <<< "$response")"
#
# message="S&P 500 price: $price"
#
# curl -fsSL \
#   -X POST \
#   "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
#   -d "chat_id=${TELEGRAM_CHAT_ID}" \
#   --data-urlencode "text=${message}" \
#   >/dev/null
# -------------------------------------------------------------------

echo "$(date -Is): Done"
