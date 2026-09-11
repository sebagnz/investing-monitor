# SP500 Monitor

Small shell-script monitor that fetches S&P 500 data from Yahoo Finance,
calculates the 200-day simple moving average and 14-day RSI, and sends the
results to Telegram at a configurable interval using cron.

## Repository structure

```text
investing-monitor/
├── install.sh
├── uninstall.sh
├── monitor.sh
├── config.example
├── .gitignore
└── README.md
```

## Requirements

- Linux
- `bash`
- `curl`
- `jq`
- `cron` / `crontab`

## Install

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/sebagnz/investing-monitor/main/install.sh | bash
```

The installer will:

1. Download the latest `monitor.sh`
2. Install it as `~/.local/bin/investing-monitor`
3. Create `~/.config/investing-monitor/config` if it does not already exist
4. Prompt for the Telegram bot token, chat ID, and monitoring frequency
5. Add a cron entry that runs at the configured frequency
6. Write output to `~/.config/investing-monitor/investing-monitor.log`

When `install.sh` is run from a local checkout, it installs the sibling
`monitor.sh` directly. When piped from GitHub, it downloads `monitor.sh` from
the repository.

The bot token is entered without being displayed. If a Telegram value or the
monitoring frequency is already configured, the installer offers to keep its
current value.

## Configure

The installer configures these values interactively. To change them manually,
edit:

```bash
nano ~/.config/investing-monitor/config
```

For example:

```bash
TELEGRAM_BOT_TOKEN="your-token"
TELEGRAM_CHAT_ID="your-chat-id"
FREQUENCY_MINUTES=1
```

The config file is created with permissions `600`.

`FREQUENCY_MINUTES` must be an integer from 1 to 59. The installer updates the
cron entry after you confirm or change the frequency.

## Run manually

```bash
~/.local/bin/investing-monitor
```

## Check cron

```bash
crontab -l
```

You should see:

```cron
*/1 * * * * ~/.local/bin/investing-monitor
```

The actual installed entry uses the configured frequency and expanded home
directory path.

## Logs

```bash
tail -f ~/.config/investing-monitor/investing-monitor.log
```

## Update

Run the same installation command again:

```bash
curl -fsSL https://raw.githubusercontent.com/sebagnz/investing-monitor/main/install.sh | bash
```

The current script will be replaced with the latest version from GitHub.

The existing config file will not be overwritten.

## Uninstall

From the cloned repository:

```bash
./uninstall.sh
```

Or run the remote version:

```bash
curl -fsSL https://raw.githubusercontent.com/sebagnz/investing-monitor/main/uninstall.sh | bash
```

The config directory is intentionally preserved during uninstall.
