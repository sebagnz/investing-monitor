# Investing Monitor

Small TypeScript monitor that fetches S&P 500 and Nasdaq-100 data from Yahoo
Finance, calculates the 200-day simple moving average and 14-day RSI, and sends
the results to Telegram at a configurable interval using cron. Alerts are only
evaluated while the regular market session is open.

Release builds are standalone executables compiled with Bun. Bun, Node.js, and
third-party runtime packages are not required on the machine running the
monitor.

## Repository structure

```text
investing-monitor/
├── .github/workflows/
├── bun.lock
├── install.sh
├── uninstall.sh
├── package.json
├── src/
├── tsconfig.json
├── .gitignore
└── README.md
```

## Requirements

- Linux or macOS on x64 or ARM64
- `bash`
- `curl`
- `cron` / `crontab`
- `sha256sum` or `shasum`

## Install

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/sebagnz/investing-monitor/main/install.sh | bash
```

The bootstrap installer will:

1. Detect the operating system, CPU architecture, and Linux libc
2. Download and verify the matching executable from the latest GitHub release
3. Install it as `~/.local/bin/investing-monitor`
4. Run `investing-monitor configure`

The TypeScript configuration command then prompts for the Telegram bot token,
chat ID, frequency, MA and RSI thresholds, and Yahoo Finance symbols; writes the
private config file; and installs or updates the cron entry.

Set `INVESTING_MONITOR_VERSION` to install a specific release tag:

```bash
curl -fsSL https://raw.githubusercontent.com/sebagnz/investing-monitor/main/install.sh \
  | INVESTING_MONITOR_VERSION=v1.0.0 bash
```

When `install.sh` is run from a local checkout after `bun run build`, it
installs `dist/investing-monitor` directly. Otherwise, it downloads a release.

The bot token is entered without being displayed. If a Telegram value,
monitoring frequency, thresholds, or symbol list is already configured,
the installer offers to keep its current value.

## Configure

Run the configuration command again at any time to change settings or repair
the cron entry:

```bash
~/.local/bin/investing-monitor configure
```

You can also edit the configuration manually:

```bash
nano ~/.config/investing-monitor/config
```

For example:

```bash
TELEGRAM_BOT_TOKEN="your-token"
TELEGRAM_CHAT_ID="your-chat-id"
FREQUENCY_MINUTES=30
MA_DISTANCE_THRESHOLD=4
RSI_DISTANCE_THRESHOLD=40
SYMBOLS="^GSPC,^NDX"
```

The config file is created with permissions `600`.

`FREQUENCY_MINUTES` must be an integer from 1 to 59. The configuration command
updates the cron entry after you confirm or change the frequency.

An asset qualifies when its 14-day RSI is strictly below `RSI_DISTANCE_THRESHOLD`
**or** its signed price distance from the 200-day SMA is strictly below
`MA_DISTANCE_THRESHOLD`. Defaults are 40 and 4%, respectively. RSI thresholds
must be between 0 and 100. MA distance is calculated as
`(price / SMA200 - 1) * 100`; negative thresholds select prices below the SMA.

`MA_DISTANCE_THRESHOLD` replaces `DISTANCE_THRESHOLD`. Existing configs still
use the old key as a fallback when the new key is absent. Running `configure`
preserves that value and saves it under the new name, and lets you set the RSI
threshold too.

`SYMBOLS` is a comma-separated list of Yahoo Finance symbols. It defaults to
`^GSPC,^NDX`, which tracks the S&P 500 and Nasdaq-100 indexes. All qualifying alerts from a
monitoring run are combined into one Telegram message, with a section for each
symbol. If no symbols qualify, no message is sent.

## Run manually

```bash
~/.local/bin/investing-monitor run
```

Running the executable without a command remains equivalent to `run`.

## Test

Development requires [Bun](https://bun.com). Install dependencies and run the
test suite with:

```bash
bun install --frozen-lockfile
bun test
```

The tests use temporary configuration and mocked HTTP requests. They do not
contact Yahoo Finance or Telegram. Run strict TypeScript and Bash syntax checks
with:

```bash
bun run typecheck
bash -n install.sh uninstall.sh
```

Build a standalone executable for the current platform with:

```bash
bun run build
```

## Release a version

After committing your changes, run `bun run release:minor` to bump the minor
version, create a release commit and annotated `v` tag, and push the current
branch and tag to `origin`. This command requires npm and Node.js and refuses
to run with uncommitted changes. Pushing the tag triggers the release workflow.

Track the current version in `package.json` using semantic versioning. Update
that version in the release commit, then create a matching annotated Git tag
with a `v` prefix (for example, `1.1.0` in `package.json` and `v1.1.0` in Git).
GitHub Releases identify the published versions.

After merging the version update and changes into `main`, update your local
checkout and push the matching annotated version tag:

```bash
git switch main
git pull --ff-only origin main
git tag -a v1.1.0 -m "Release v1.1.0"
git push origin v1.1.0
```

Pushing a tag matching `v*` triggers the **Release** workflow. Pushing changes
to `main` alone does not create a release. The workflow runs tests and
type-checking, cross-compiles glibc and musl Linux executables plus macOS
executables for x64 and ARM64, and creates a GitHub Release with generated
release notes and SHA-256 checksums.

Check the repository's **Actions** tab for the workflow result, then verify
that all six executables and `checksums.txt` appear under **Releases**. The
curl installer can then download the new release.

Use a new version tag for subsequent releases, such as `v1.0.1`. Do not move or
reuse a tag after its release has been published.

## Check cron

```bash
crontab -l
```

You should see:

```cron
*/30 * * * * ~/.local/bin/investing-monitor run
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

The current executable will be replaced with the latest GitHub release.

Existing configuration values are offered as defaults and preserved when you
choose to keep them.

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
