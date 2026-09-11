#!/usr/bin/env bash
set -euo pipefail

REPO_NAME="investing-monitor"
BRANCH="main"

INSTALL_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/investing-monitor"
SCRIPT_NAME="investing-monitor"

BASE_URL="https://raw.githubusercontent.com/sebagnz/${REPO_NAME}/${BRANCH}"

SOURCE_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

set_config_value() {
  local key="$1"
  local value="$2"
  local quoted_value
  local temporary_file
  local found=false

  printf -v quoted_value '%q' "$value"
  temporary_file="$(mktemp "${CONFIG_DIR}/config.XXXXXX")"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "${key}="* ]]; then
      printf '%s=%s\n' "$key" "$quoted_value" >> "$temporary_file"
      found=true
    else
      printf '%s\n' "$line" >> "$temporary_file"
    fi
  done < "${CONFIG_DIR}/config"

  if [[ "$found" == false ]]; then
    printf '\n%s=%s\n' "$key" "$quoted_value" >> "$temporary_file"
  fi

  chmod 600 "$temporary_file"
  mv "$temporary_file" "${CONFIG_DIR}/config"
}

prompt_for_value() {
  local key="$1"
  local label="$2"
  local current_value="$3"
  local secret="$4"
  local answer
  local new_value

  if [[ -n "$current_value" ]]; then
    printf '%s is already configured. Keep the current value? [Y/n] ' "$label" >&3
    IFS= read -r answer <&3 || exit 1

    case "$answer" in
      ""|y|Y|yes|YES|Yes)
        return
        ;;
    esac
  fi

  while true; do
    printf 'Enter %s: ' "$label" >&3
    if [[ "$secret" == true ]]; then
      IFS= read -r -s new_value <&3 || exit 1
      printf '\n' >&3
    else
      IFS= read -r new_value <&3 || exit 1
    fi

    if [[ -n "$new_value" ]]; then
      set_config_value "$key" "$new_value"
      return
    fi

    printf '%s cannot be empty.\n' "$label" >&3
  done
}

prompt_for_frequency() {
  local current_value="$1"
  local answer
  local new_value

  if [[ "$current_value" =~ ^([1-9]|[1-5][0-9])$ ]]; then
    printf 'The monitor currently runs every %s minutes. Keep this frequency? [Y/n] ' \
      "$current_value" >&3
    IFS= read -r answer <&3 || exit 1

    case "$answer" in
      ""|y|Y|yes|YES|Yes)
        return
        ;;
    esac
  elif [[ -n "$current_value" ]]; then
    printf 'The configured frequency "%s" is invalid.\n' "$current_value" >&3
  fi

  while true; do
    printf 'Enter frequency in minutes (1-59): ' >&3
    IFS= read -r new_value <&3 || exit 1

    if [[ "$new_value" =~ ^([1-9]|[1-5][0-9])$ ]]; then
      set_config_value "FREQUENCY_MINUTES" "$new_value"
      FREQUENCY_MINUTES="$new_value"
      return
    fi

    printf 'Frequency must be an integer between 1 and 59.\n' >&3
  done
}

prompt_for_distance_threshold() {
  local current_value="$1"
  local answer
  local new_value
  local number_pattern='^-?[0-9]+([.][0-9]+)?$'

  if [[ "$current_value" =~ $number_pattern ]]; then
    printf 'The distance threshold is currently %s%%. Keep this value? [Y/n] ' \
      "$current_value" >&3
    IFS= read -r answer <&3 || exit 1

    case "$answer" in
      ""|y|Y|yes|YES|Yes)
        return
        ;;
    esac
  elif [[ -n "$current_value" ]]; then
    printf 'The configured distance threshold "%s" is invalid.\n' \
      "$current_value" >&3
  fi

  while true; do
    printf 'Enter distance threshold percentage (for example, 0 or -5.5): ' >&3
    IFS= read -r new_value <&3 || exit 1

    if [[ "$new_value" =~ $number_pattern ]]; then
      set_config_value "DISTANCE_THRESHOLD" "$new_value"
      DISTANCE_THRESHOLD="$new_value"
      return
    fi

    printf 'Distance threshold must be a number.\n' >&3
  done
}

mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"

echo "Installing ${SCRIPT_NAME}..."

temporary_script="$(mktemp "${INSTALL_DIR}/${SCRIPT_NAME}.XXXXXX")"

if [[ -n "$SOURCE_DIR" && -f "${SOURCE_DIR}/monitor.sh" ]]; then
  cp "${SOURCE_DIR}/monitor.sh" "$temporary_script"
elif ! curl -fsSL "${BASE_URL}/monitor.sh" -o "$temporary_script"; then
  rm -f "$temporary_script"
  echo "Failed to download the latest monitor script." >&2
  exit 1
fi

if ! bash -n "$temporary_script"; then
  rm -f "$temporary_script"
  echo "The monitor script is not valid Bash; the installed version was not changed." >&2
  exit 1
fi

chmod +x "$temporary_script"
mv "$temporary_script" "${INSTALL_DIR}/${SCRIPT_NAME}"

if [[ ! -f "${CONFIG_DIR}/config" ]]; then
  if [[ -n "$SOURCE_DIR" && -f "${SOURCE_DIR}/config.example" ]]; then
    cp "${SOURCE_DIR}/config.example" "${CONFIG_DIR}/config"
  else
    curl -fsSL "${BASE_URL}/config.example" \
      -o "${CONFIG_DIR}/config"
  fi

  chmod 600 "${CONFIG_DIR}/config"
fi

if ! exec 3<>/dev/tty; then
  echo "Installation requires an interactive terminal for configuration." >&2
  exit 1
fi

# shellcheck disable=SC1090,SC1091
source "${CONFIG_DIR}/config"

echo
echo "Configure the monitor:"
prompt_for_value \
  "TELEGRAM_BOT_TOKEN" \
  "Telegram bot token" \
  "${TELEGRAM_BOT_TOKEN:-}" \
  true
prompt_for_value \
  "TELEGRAM_CHAT_ID" \
  "Telegram chat ID" \
  "${TELEGRAM_CHAT_ID:-}" \
  false
prompt_for_frequency "${FREQUENCY_MINUTES:-}"
prompt_for_distance_threshold "${DISTANCE_THRESHOLD:-}"

exec 3>&-

CRON_LINE="*/${FREQUENCY_MINUTES} * * * * ${INSTALL_DIR}/${SCRIPT_NAME} >> ${CONFIG_DIR}/investing-monitor.log 2>&1"

(
  crontab -l 2>/dev/null | grep -v "${INSTALL_DIR}/${SCRIPT_NAME}" || true
  echo "$CRON_LINE"
) | crontab -

echo
echo "Installed successfully."
echo "Script: ${INSTALL_DIR}/${SCRIPT_NAME}"
echo "Config: ${CONFIG_DIR}/config"
echo "Log:    ${CONFIG_DIR}/investing-monitor.log"
echo "Cron:   every ${FREQUENCY_MINUTES} minutes"
