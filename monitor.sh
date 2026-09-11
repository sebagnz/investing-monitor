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
    def fixed2:
      ((. * 100 | round) / 100 | tostring)
      | if contains(".") then
          . + ("0" * (2 - (split(".")[1] | length)))
        else
          . + ".00"
        end;
    def with_commas:
      split(".") as $parts
      | ($parts[0]
          | explode
          | reverse
          | [range(0; length; 3) as $i
              | .[$i:$i + 3]
              | reverse
              | implode]
          | reverse
          | join(",")) + "." + $parts[1];

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
        (if $distance >= 0 then "+" else "" end) as $distance_sign
        | (if $rsi14 >= 70 then "Overbought 🔥"
           elif $rsi14 <= 30 then "Oversold 🧊"
           else "Neutral ⚖️"
           end) as $rsi_status
        | "<b>⚠️ S&amp;P 500 Alert</b>\n\n"
          + "💵 <b>Price:</b> \($price | fixed2 | with_commas)\n"
          + "📈 <b>200-day SMA:</b> \($sma200 | fixed2 | with_commas)\n"
          + "📏 <b>Distance:</b> \($distance_sign)\($distance | fixed2)%\n"
          + "🌡️ <b>RSI (14):</b> \($rsi14 | fixed2) · \($rsi_status)"
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
  -d "parse_mode=HTML" \
  --data-urlencode "text=${RESULT}"

echo "$(date '+%Y-%m-%dT%H:%M:%S%z'): Done"
