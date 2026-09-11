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

: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN is not set}"
: "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID is not set}"
: "${DISTANCE_THRESHOLD:?DISTANCE_THRESHOLD is not set}"

if [[ ! "$DISTANCE_THRESHOLD" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
  echo "DISTANCE_THRESHOLD must be a number." >&2
  exit 1
fi

for dependency in curl jq; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "Missing dependency: $dependency" >&2
    exit 1
  fi
done

echo "$(date '+%Y-%m-%dT%H:%M:%S%z'): Running SP500 monitor"

YAHOO_URL="https://query1.finance.yahoo.com/v8/finance/chart/%5EGSPC?interval=1d&range=1y"

DATA=$(
  curl -fsSL \
    -A "Mozilla/5.0" \
    "$YAHOO_URL"
)

RESULT=$(
  echo "$DATA" | jq -r --argjson threshold "$DISTANCE_THRESHOLD" '
    .chart.result[0] as $r
    | [$r.indicators.quote[0].close[] | select(. != null)] as $c
    | $c[-1] as $price
    | (($c[-200:] | add) / 200) as $sma200
    | $c[-15:] as $rsi_closes
    | [
        range(1; $rsi_closes | length)
        | $rsi_closes[.] - $rsi_closes[.-1]
      ] as $changes
    | ([$changes[] | select(. > 0)] | (add // 0) / 14) as $avg_gain
    | ([$changes[] | select(. < 0) | -.] | (add // 0) / 14) as $avg_loss
    | (
        if $avg_loss == 0 then
          100
        else
          100 - (100 / (1 + ($avg_gain / $avg_loss)))
        end
      ) as $rsi14
    | ((($price / $sma200) - 1) * 100) as $distance
    | if $distance < $threshold then
        "S&P 500\n\nPrice: \($price | tostring)\nSMA 200: \($sma200 | tostring)\nDistance: \($distance | tostring)%\nRSI 14: \($rsi14 | tostring)"
      else
        empty
      end
  '
)

if [[ -z "$RESULT" ]]; then
  echo "$(date '+%Y-%m-%dT%H:%M:%S%z'): Distance is not below ${DISTANCE_THRESHOLD}%; no alert sent"
  exit 0
fi

curl -fsSL \
  -X POST \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=${RESULT}"

echo "$(date '+%Y-%m-%dT%H:%M:%S%z'): Done"
