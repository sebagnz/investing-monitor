import { spawnSync } from "node:child_process";
import {
  chmod,
  mkdir,
  readFile,
  rename,
  unlink,
  writeFile,
} from "node:fs/promises";
import { closeSync, openSync } from "node:fs";
import { createReadStream, createWriteStream } from "node:fs";
import { dirname } from "node:path";
import { createInterface } from "node:readline/promises";

import { parseConfigFile } from "./monitor";

export interface StoredConfig {
  telegramBotToken: string;
  telegramChatId: string;
  frequencyMinutes: number;
  distanceThreshold: number;
  symbols: string;
}

export interface ConfigureOptions {
  configPath: string;
  executablePath: string;
  logPath: string;
}

interface PromptOptions {
  secret: boolean;
}

export interface ConfigureDependencies {
  readConfig: (path: string) => Promise<Partial<StoredConfig>>;
  writeConfig: (path: string, config: StoredConfig) => Promise<void>;
  prompt: (message: string, options: PromptOptions) => Promise<string>;
  readCrontab: () => Promise<string>;
  writeCrontab: (contents: string) => Promise<void>;
  log: (message: string) => void;
}

const DEFAULT_FREQUENCY = 30;
const DEFAULT_THRESHOLD = 2;
const DEFAULT_SYMBOLS = "^GSPC,^NDX";
const NUMBER_PATTERN = /^-?[0-9]+(?:\.[0-9]+)?$/;

function isFrequency(value: string): boolean {
  return /^(?:[1-9]|[1-5][0-9])$/.test(value);
}

function isSymbols(value: string): boolean {
  const symbols = value.split(",").map((symbol) => symbol.trim());
  return symbols.length > 0 && symbols.every((symbol) => symbol !== "");
}

function keepCurrent(answer: string): boolean {
  return ["", "y", "yes"].includes(answer.trim().toLowerCase());
}

async function promptForValue(
  dependencies: ConfigureDependencies,
  label: string,
  currentValue: string | undefined,
  secret: boolean,
  validate: (value: string) => boolean,
  validationMessage: string,
): Promise<string> {
  if (currentValue !== undefined && validate(currentValue)) {
    const displayedValue = secret ? "[hidden]" : `"${currentValue}"`;
    const answer = await dependencies.prompt(
      `${label} is currently ${displayedValue}. Keep it? [Y/n] `,
      { secret: false },
    );
    if (keepCurrent(answer)) return currentValue;
  }

  while (true) {
    const value = await dependencies.prompt(`Enter ${label}: `, { secret });
    if (validate(value)) return value;
    dependencies.log(validationMessage);
  }
}

function quoteConfigValue(value: string): string {
  return `"${value.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

export async function readConfig(path: string): Promise<Partial<StoredConfig>> {
  let contents: string;
  try {
    contents = await readFile(path, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return {};
    throw error;
  }

  const values = parseConfigFile(contents);
  const frequency = values.get("FREQUENCY_MINUTES");
  const threshold = values.get("DISTANCE_THRESHOLD");

  return {
    ...(values.has("TELEGRAM_BOT_TOKEN") && {
      telegramBotToken: values.get("TELEGRAM_BOT_TOKEN"),
    }),
    ...(values.has("TELEGRAM_CHAT_ID") && {
      telegramChatId: values.get("TELEGRAM_CHAT_ID"),
    }),
    ...(frequency !== undefined && { frequencyMinutes: Number(frequency) }),
    ...(threshold !== undefined && { distanceThreshold: Number(threshold) }),
    ...(values.has("SYMBOLS") && { symbols: values.get("SYMBOLS") }),
  };
}

export async function saveConfig(
  path: string,
  config: StoredConfig,
): Promise<void> {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const temporaryPath = `${path}.${process.pid}.${crypto.randomUUID()}`;
  const contents = [
    `TELEGRAM_BOT_TOKEN=${quoteConfigValue(config.telegramBotToken)}`,
    `TELEGRAM_CHAT_ID=${quoteConfigValue(config.telegramChatId)}`,
    `FREQUENCY_MINUTES=${config.frequencyMinutes}`,
    `DISTANCE_THRESHOLD=${config.distanceThreshold}`,
    `SYMBOLS=${quoteConfigValue(config.symbols)}`,
    "",
  ].join("\n");

  try {
    await writeFile(temporaryPath, contents, { mode: 0o600, flag: "wx" });
    await chmod(temporaryPath, 0o600);
    await rename(temporaryPath, path);
  } catch (error) {
    await unlink(temporaryPath).catch(() => undefined);
    throw error;
  }
}

function shellQuote(value: string): string {
  if (/^[A-Za-z0-9_./:=+-]+$/.test(value)) return value;
  return `'${value.replace(/'/g, `'"'"'`)}'`;
}

function cronLine(options: ConfigureOptions, frequency: number): string {
  return (
    `*/${frequency} * * * * ${shellQuote(options.executablePath)} run` +
    ` >> ${shellQuote(options.logPath)} 2>&1 # investing-monitor`
  );
}

async function promptFromTerminal(
  message: string,
  options: PromptOptions,
): Promise<string> {
  const input = createReadStream("/dev/tty");
  const output = createWriteStream("/dev/tty");
  const terminal = createInterface({ input, output, terminal: true });
  let terminalFd: number | undefined;

  try {
    if (options.secret) {
      terminalFd = openSync("/dev/tty", "r+");
      const result = spawnSync("stty", ["-echo"], {
        stdio: [terminalFd, "ignore", "ignore"],
      });
      if (result.status !== 0) {
        throw new Error("Could not disable terminal echo for secret input.");
      }
    }

    const answer = await terminal.question(message);
    if (options.secret) output.write("\n");
    return answer;
  } finally {
    if (terminalFd !== undefined) {
      spawnSync("stty", ["echo"], {
        stdio: [terminalFd, "ignore", "ignore"],
      });
      closeSync(terminalFd);
    }
    terminal.close();
    input.destroy();
    output.end();
  }
}

async function readCrontab(): Promise<string> {
  const result = spawnSync("crontab", ["-l"], { encoding: "utf8" });
  if (result.status === 0) return result.stdout;
  if (result.status === 1) return "";
  throw new Error(result.stderr.trim() || "Failed to read crontab.");
}

async function writeCrontab(contents: string): Promise<void> {
  const result = spawnSync("crontab", ["-"], {
    encoding: "utf8",
    input: contents,
  });
  if (result.status !== 0) {
    throw new Error(result.stderr.trim() || "Failed to update crontab.");
  }
}

export const defaultConfigureDependencies: ConfigureDependencies = {
  readConfig,
  writeConfig: saveConfig,
  prompt: promptFromTerminal,
  readCrontab,
  writeCrontab,
  log: console.log,
};

export async function configure(
  options: ConfigureOptions,
  dependencies: ConfigureDependencies = defaultConfigureDependencies,
): Promise<void> {
  const existing = await dependencies.readConfig(options.configPath);
  dependencies.log("Configure the monitor:");

  const telegramBotToken = await promptForValue(
    dependencies,
    "Telegram bot token",
    existing.telegramBotToken || undefined,
    true,
    (value) => value !== "",
    "Telegram bot token cannot be empty.",
  );
  const telegramChatId = await promptForValue(
    dependencies,
    "Telegram chat ID",
    existing.telegramChatId || undefined,
    false,
    (value) => value !== "",
    "Telegram chat ID cannot be empty.",
  );
  const frequencyText = await promptForValue(
    dependencies,
    "frequency in minutes (1-59)",
    String(existing.frequencyMinutes ?? DEFAULT_FREQUENCY),
    false,
    isFrequency,
    "Frequency must be an integer between 1 and 59.",
  );
  const thresholdText = await promptForValue(
    dependencies,
    "distance threshold percentage (for example, 0 or -5.5)",
    String(existing.distanceThreshold ?? DEFAULT_THRESHOLD),
    false,
    (value) => NUMBER_PATTERN.test(value),
    "Distance threshold must be a number.",
  );
  const symbols = await promptForValue(
    dependencies,
    "Yahoo Finance symbols (comma-separated)",
    existing.symbols || DEFAULT_SYMBOLS,
    false,
    isSymbols,
    "Symbols must be a comma-separated list without empty entries.",
  );

  const config: StoredConfig = {
    telegramBotToken,
    telegramChatId,
    frequencyMinutes: Number(frequencyText),
    distanceThreshold: Number(thresholdText),
    symbols: symbols
      .split(",")
      .map((symbol) => symbol.trim())
      .join(","),
  };
  await dependencies.writeConfig(options.configPath, config);

  const existingCrontab = await dependencies.readCrontab();
  const retainedLines = existingCrontab
    .split(/\r?\n/)
    .filter(
      (line) =>
        line !== "" &&
        !line.includes("# investing-monitor") &&
        !line.includes(options.executablePath),
    );
  retainedLines.push(cronLine(options, config.frequencyMinutes));
  await dependencies.writeCrontab(`${retainedLines.join("\n")}\n`);

  dependencies.log("Installed successfully.");
  dependencies.log(`Executable: ${options.executablePath}`);
  dependencies.log(`Config:     ${options.configPath}`);
  dependencies.log(`Log:        ${options.logPath}`);
  dependencies.log(`Cron:       every ${config.frequencyMinutes} minutes`);
}
