#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export YAHOO_FIXTURE="$BATS_TEST_TMPDIR/yahoo.json"
  export TELEGRAM_REQUEST_LOG="$BATS_TEST_TMPDIR/telegram-request.log"
  export CURL_COMMAND="$PROJECT_ROOT/test/helpers/curl"

  mkdir -p "$HOME/.config/investing-monitor"
}

write_config() {
  local threshold="${1:-0}"

  cat > "$HOME/.config/investing-monitor/config" <<EOF
TELEGRAM_BOT_TOKEN="test-token"
TELEGRAM_CHAT_ID="test-chat"
DISTANCE_THRESHOLD="$threshold"
EOF
}

make_fixture() {
  local market_start="$1"
  local market_end="$2"
  local price_pattern="${3:-flat}"

  jq -n \
    --argjson market_start "$market_start" \
    --argjson market_end "$market_end" \
    --arg price_pattern "$price_pattern" '
      (if $price_pattern == "drop"
       then [range(0; 200) | 100] + [90]
       else [range(0; 201) | 100]
       end) as $closes
      | {
          chart: {
            result: [{
              meta: {
                currentTradingPeriod: {
                  regular: {
                    start: $market_start,
                    end: $market_end
                  }
                }
              },
              indicators: {quote: [{close: $closes}]}
            }]
          }
        }
    ' > "$YAHOO_FIXTURE"
}

@test "fails when the config file is missing" {
  run "$PROJECT_ROOT/monitor.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing config file:"* ]]
  [ ! -e "$TELEGRAM_REQUEST_LOG" ]
}

@test "rejects a non-numeric distance threshold" {
  write_config "not-a-number"

  run "$PROJECT_ROOT/monitor.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"DISTANCE_THRESHOLD must be a number."* ]]
  [ ! -e "$TELEGRAM_REQUEST_LOG" ]
}

@test "does not alert while the market is closed" {
  write_config
  make_fixture 0 1

  run "$PROJECT_ROOT/monitor.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Market is closed; no alert sent"* ]]
  [ ! -e "$TELEGRAM_REQUEST_LOG" ]
}

@test "does not alert when the index is not below the threshold" {
  write_config 0
  make_fixture 0 4102444800

  run "$PROJECT_ROOT/monitor.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Distance is not below 0%; no alert sent"* ]]
  [ ! -e "$TELEGRAM_REQUEST_LOG" ]
}

@test "sends the calculated alert when the index drops below the threshold" {
  write_config 0
  make_fixture 0 4102444800 drop

  run "$PROJECT_ROOT/monitor.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *'{"ok":true}'* ]]
  [[ "$output" == *"Done"* ]]
  [ -f "$TELEGRAM_REQUEST_LOG" ]

  request="$(cat "$TELEGRAM_REQUEST_LOG")"
  [[ "$request" == *"https://api.telegram.org/bottest-token/sendMessage"* ]]
  [[ "$request" == *"chat_id=test-chat"* ]]
  [[ "$request" == *"parse_mode=HTML"* ]]
  [[ "$request" == *"<b>S&amp;P 500 Alert</b>"* ]]
  [[ "$request" == *"<b>Price:</b> 90.00"* ]]
  [[ "$request" == *"<b>200-day SMA:</b> 99.95 (-9.95%)"* ]]
  [[ "$request" == *"<b>RSI (14):</b> 0.00 · Oversold"* ]]
}
