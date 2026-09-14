#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin"
CURL_COMMAND="${CURL_COMMAND:-curl}"

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

if ! command -v "$CURL_COMMAND" >/dev/null 2>&1; then
  echo "Missing dependency: curl" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Missing dependency: jq" >&2
  exit 1
fi

echo "$(date '+%Y-%m-%dT%H:%M:%S%z'): Running SP500 monitor"

YAHOO_URL="https://query1.finance.yahoo.com/v8/finance/chart/%5EGSPC?interval=1d&range=1y"

DATA=$(
  "$CURL_COMMAND" -fsSL \
    -A "Mozilla/5.0" \
    "$YAHOO_URL"
)

MARKET_STATUS=$(
  echo "$DATA" | jq -r '
    .chart.result[0].meta.currentTradingPeriod.regular as $regular
    | if (($regular.start | type) != "number" or ($regular.end | type) != "number") then
        "unknown"
      elif now >= $regular.start and now < $regular.end then
        "open"
      else
        "closed"
      end
  '
)

if [[ "$MARKET_STATUS" != "open" ]]; then
  if [[ "$MARKET_STATUS" == "closed" ]]; then
    echo "$(date '+%Y-%m-%dT%H:%M:%S%z'): Market is closed; no alert sent"
  else
    echo "$(date '+%Y-%m-%dT%H:%M:%S%z'): Could not determine market status; no alert sent" >&2
  fi
  exit 0
fi

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
    | $c[-2] as $previous_close
    | ((($price / $previous_close) - 1) * 100) as $daily_variation
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
        | (if $daily_variation >= 0 then "+" else "" end) as $variation_sign
        | (if $daily_variation >= 0 then "🟢" else "🔴" end) as $variation_indicator
        | (if $rsi14 >= 70 then "Overbought 🔥"
           elif $rsi14 <= 30 then "Oversold 🧊"
           elif $rsi14 <= 40 then "Near oversold ⚠️"
           else "Neutral ⚖️"
           end) as $rsi_status
        | "<b>S&amp;P 500 Alert</b>\n\n"
          + "💵 <b>Price:</b> \($price | fixed2 | with_commas) \($variation_indicator) \($variation_sign)\($daily_variation | fixed2)%\n"
          + "📈 <b>200-day SMA:</b> \($sma200 | fixed2 | with_commas) (\($distance_sign)\($distance | fixed2)%)\n"
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

"$CURL_COMMAND" -fsSL \
  -X POST \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "parse_mode=HTML" \
  --data-urlencode "text=${RESULT}"

echo "$(date '+%Y-%m-%dT%H:%M:%S%z'): Done"
