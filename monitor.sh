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
SYMBOLS="${SYMBOLS:-^GSPC,^NDX}"

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

display_name_for_symbol() {
  case "$1" in
    "^GSPC") printf 'S&amp;P 500' ;;
    "^NDX") printf 'Nasdaq-100' ;;
    *) printf '%s' "$1" ;;
  esac
}

monitor_symbol() {
  local symbol="$1"
  local display_name
  local encoded_symbol
  local yahoo_url
  local data
  local market_status
  local result
  local telegram_response

  if [[ ! "$symbol" =~ ^[A-Za-z0-9._^=-]+$ ]]; then
    echo "Invalid Yahoo Finance symbol: $symbol" >&2
    return 1
  fi

  display_name="$(display_name_for_symbol "$symbol")"
  encoded_symbol="$(jq -rn --arg symbol "$symbol" '$symbol | @uri')"
  yahoo_url="https://query1.finance.yahoo.com/v8/finance/chart/${encoded_symbol}?interval=1d&range=1y"

  echo "$(date '+%Y-%m-%dT%H:%M:%S%z'): Checking ${symbol}"

  if ! data=$(
    "$CURL_COMMAND" -fsSL \
      -A "Mozilla/5.0" \
      "$yahoo_url"
  ); then
    echo "$(date '+%Y-%m-%dT%H:%M:%S%z'): Failed to fetch ${symbol}" >&2
    return 1
  fi

  market_status=$(
    echo "$data" | jq -r '
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

  if [[ "$market_status" != "open" ]]; then
    if [[ "$market_status" == "closed" ]]; then
      echo "$(date '+%Y-%m-%dT%H:%M:%S%z'): ${symbol} market is closed; no alert sent"
    else
      echo "$(date '+%Y-%m-%dT%H:%M:%S%z'): Could not determine ${symbol} market status; no alert sent" >&2
    fi
    return 0
  fi

  result=$(
    echo "$data" | jq -r \
      --argjson threshold "$DISTANCE_THRESHOLD" \
      --arg display_name "$display_name" '
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
        | "<b>\($display_name) Alert</b>\n\n"
          + "💵 <b>Price:</b> \($price | fixed2 | with_commas) \($variation_indicator) \($variation_sign)\($daily_variation | fixed2)%\n"
          + "📈 <b>200-day SMA:</b> \($sma200 | fixed2 | with_commas) (\($distance_sign)\($distance | fixed2)%)\n"
          + "🌡️ <b>RSI (14):</b> \($rsi14 | fixed2) · \($rsi_status)"
      else
        empty
      end
    '
  )

  if [[ -z "$result" ]]; then
    echo "$(date '+%Y-%m-%dT%H:%M:%S%z'): ${symbol} distance is not below ${DISTANCE_THRESHOLD}%; no alert sent"
    return 0
  fi

  if ! telegram_response=$(
    "$CURL_COMMAND" -fsSL \
      -X POST \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      -d "parse_mode=HTML" \
      --data-urlencode "text=${result}"
  ); then
    echo "$(date '+%Y-%m-%dT%H:%M:%S%z'): Failed to send ${symbol} alert" >&2
    return 1
  fi

  printf '%s\n' "$telegram_response"
  echo "$(date '+%Y-%m-%dT%H:%M:%S%z'): ${symbol} done"
}

echo "$(date '+%Y-%m-%dT%H:%M:%S%z'): Running investing monitor"

IFS=',' read -r -a tracked_symbols <<< "$SYMBOLS"
had_error=false

for symbol in "${tracked_symbols[@]}"; do
  symbol="${symbol//[[:space:]]/}"
  if [[ -z "$symbol" ]]; then
    echo "SYMBOLS contains an empty symbol." >&2
    had_error=true
    continue
  fi

  if ! monitor_symbol "$symbol"; then
    had_error=true
  fi
done

if [[ "$had_error" == true ]]; then
  exit 1
fi
