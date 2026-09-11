# SP500 Monitor

Small shell-script boilerplate for running an S&P 500 monitoring task every 30 minutes using cron.

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
4. Add a cron entry that runs every 30 minutes
5. Write output to `~/.config/investing-monitor/investing-monitor.log`

## Configure

Edit:

```bash
nano ~/.config/investing-monitor/config
```

For example:

```bash
TELEGRAM_BOT_TOKEN="your-token"
TELEGRAM_CHAT_ID="your-chat-id"
```

The config file is created with permissions `600`.

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
*/30 * * * * ~/.local/bin/investing-monitor
```

The actual installed entry uses the expanded home directory path.

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
