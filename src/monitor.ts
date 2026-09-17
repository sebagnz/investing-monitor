import { readFile } from "node:fs/promises";

export interface MonitorConfig {
  telegramBotToken: string;
  telegramChatId: string;
  distanceThreshold: number;
  symbols: string[];
}

export type MonitorFetch = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

export interface MonitorDependencies {
  fetch: MonitorFetch;
  now: () => Date;
  log: (message: string) => void;
  error: (message: string) => void;
}

interface YahooChart {
  chart?: {
    result?: Array<{
      meta?: {
        currentTradingPeriod?: {
          regular?: { start?: unknown; end?: unknown };
        };
      };
      indicators?: {
        quote?: Array<{ close?: Array<number | null> }>;
      };
    }>;
  };
}

const DEFAULT_SYMBOLS = ["^GSPC", "^NDX"];
const VALID_SYMBOL = /^[A-Za-z0-9._^=-]+$/;

export const defaultDependencies: MonitorDependencies = {
  fetch: globalThis.fetch,
  now: () => new Date(),
  log: console.log,
  error: console.error,
};

function decodeDoubleQuoted(value: string): string {
  return value.replace(/\\([\\"$`])/g, "$1");
}

function decodeUnquoted(value: string): string {
  let decoded = "";

  for (let index = 0; index < value.length; index += 1) {
    const character = value[index];
    if (character === "\\" && index + 1 < value.length) {
      index += 1;
      decoded += value[index];
    } else {
      decoded += character;
    }
  }

  return decoded;
}

function parseConfigValue(rawValue: string): string {
  const value = rawValue.trim();

  if (value.startsWith('"') && value.endsWith('"')) {
    return decodeDoubleQuoted(value.slice(1, -1));
  }

  if (value.startsWith("'") && value.endsWith("'")) {
    return value.slice(1, -1);
  }

  return decodeUnquoted(value);
}

export function parseConfigFile(contents: string): Map<string, string> {
  const values = new Map<string, string>();

  for (const sourceLine of contents.split(/\r?\n/)) {
    const line = sourceLine.trim();
    if (line === "" || line.startsWith("#")) {
      continue;
    }

    const match = /^([A-Z][A-Z0-9_]*)=(.*)$/.exec(line);
    if (!match) {
      throw new Error(`Invalid config line: ${sourceLine}`);
    }

    values.set(match[1]!, parseConfigValue(match[2]!));
  }

  return values;
}

export async function loadConfig(path: string): Promise<MonitorConfig> {
  let contents: string;
  try {
    contents = await readFile(path, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      throw new Error(`Missing config file: ${path}`);
    }
    throw error;
  }

  const values = parseConfigFile(contents);
  const telegramBotToken = values.get("TELEGRAM_BOT_TOKEN") ?? "";
  const telegramChatId = values.get("TELEGRAM_CHAT_ID") ?? "";
  const thresholdText = values.get("DISTANCE_THRESHOLD") ?? "";

  if (telegramBotToken === "") {
    throw new Error("TELEGRAM_BOT_TOKEN is not set");
  }
  if (telegramChatId === "") {
    throw new Error("TELEGRAM_CHAT_ID is not set");
  }
  if (!/^-?[0-9]+(?:\.[0-9]+)?$/.test(thresholdText)) {
    throw new Error("DISTANCE_THRESHOLD must be a number.");
  }

  const symbolsText = values.get("SYMBOLS") ?? DEFAULT_SYMBOLS.join(",");
  const symbols = symbolsText.split(",").map((symbol) => symbol.replace(/\s/g, ""));
  if (symbols.some((symbol) => symbol === "")) {
    throw new Error("SYMBOLS contains an empty symbol.");
  }

  return {
    telegramBotToken,
    telegramChatId,
    distanceThreshold: Number(thresholdText),
    symbols,
  };
}

function timestamp(date: Date): string {
  const pad = (value: number): string => String(value).padStart(2, "0");
  const offsetMinutes = -date.getTimezoneOffset();
  const sign = offsetMinutes >= 0 ? "+" : "-";
  const absoluteOffset = Math.abs(offsetMinutes);

  return (
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` +
    `T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}` +
    `${sign}${pad(Math.floor(absoluteOffset / 60))}${pad(absoluteOffset % 60)}`
  );
}

function displayNameForSymbol(symbol: string): string {
  if (symbol === "^GSPC") return "S&amp;P 500";
  if (symbol === "^NDX") return "Nasdaq-100";
  return symbol;
}

function fixed2(value: number): string {
  return value.toFixed(2);
}

function fixed2WithCommas(value: number): string {
  const [integer, decimals] = fixed2(value).split(".");
  return `${integer!.replace(/\B(?=(\d{3})+(?!\d))/g, ",")}.${decimals}`;
}

function signed(value: number): string {
  return value >= 0 ? `+${fixed2(value)}` : fixed2(value);
}

function calculateAlert(
  displayName: string,
  closes: number[],
  threshold: number,
): string | undefined {
  if (closes.length < 200) {
    throw new Error("Yahoo Finance returned fewer than 200 closing prices");
  }

  const price = closes.at(-1)!;
  const previousClose = closes.at(-2)!;
  const smaCloses = closes.slice(-200);
  const sma200 = smaCloses.reduce((sum, close) => sum + close, 0) / 200;
  const dailyVariation = (price / previousClose - 1) * 100;
  const distance = (price / sma200 - 1) * 100;

  if (distance >= threshold) {
    return undefined;
  }

  const rsiCloses = closes.slice(-15);
  let gains = 0;
  let losses = 0;
  for (let index = 1; index < rsiCloses.length; index += 1) {
    const change = rsiCloses[index]! - rsiCloses[index - 1]!;
    if (change > 0) gains += change;
    if (change < 0) losses -= change;
  }
  const averageGain = gains / 14;
  const averageLoss = losses / 14;
  const rsi14 =
    averageLoss === 0
      ? 100
      : 100 - 100 / (1 + averageGain / averageLoss);
  const variationIndicator = dailyVariation >= 0 ? "🟢" : "🔴";
  const rsiStatus =
    rsi14 >= 70
      ? "Overbought 🔥"
      : rsi14 <= 30
        ? "Oversold 🧊"
        : rsi14 <= 40
          ? "Near oversold ⚠️"
          : "Neutral ⚖️";

  return (
    `<b>${displayName} Alert</b>\n\n` +
    `💵 <b>Price:</b> ${fixed2WithCommas(price)} ${variationIndicator} ${signed(dailyVariation)}%\n` +
    `📈 <b>200-day SMA:</b> ${fixed2WithCommas(sma200)} (${signed(distance)}%)\n` +
    `🌡️ <b>RSI (14):</b> ${fixed2(rsi14)} · ${rsiStatus}`
  );
}

async function monitorSymbol(
  symbol: string,
  config: MonitorConfig,
  dependencies: MonitorDependencies,
): Promise<boolean | string> {
  const time = (): string => timestamp(dependencies.now());

  if (!VALID_SYMBOL.test(symbol)) {
    dependencies.error(`Invalid Yahoo Finance symbol: ${symbol}`);
    return false;
  }

  dependencies.log(`${time()}: Checking ${symbol}`);
  const yahooUrl =
    `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}` +
    "?interval=1d&range=1y";

  let response: Response;
  try {
    response = await dependencies.fetch(yahooUrl, {
      headers: { "User-Agent": "Mozilla/5.0" },
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
  } catch {
    dependencies.error(`${time()}: Failed to fetch ${symbol}`);
    return false;
  }

  let data: YahooChart;
  try {
    data = (await response.json()) as YahooChart;
  } catch {
    dependencies.error(`${time()}: Failed to parse ${symbol} response`);
    return false;
  }

  const result = data.chart?.result?.[0];
  const regular = result?.meta?.currentTradingPeriod?.regular;
  const start = regular?.start;
  const end = regular?.end;

  if (typeof start !== "number" || typeof end !== "number") {
    dependencies.error(
      `${time()}: Could not determine ${symbol} market status; no alert sent`,
    );
    return true;
  }

  const nowSeconds = dependencies.now().getTime() / 1_000;
  if (nowSeconds < start || nowSeconds >= end) {
    dependencies.log(`${time()}: ${symbol} market is closed; no alert sent`);
    return true;
  }

  const closes = (result?.indicators?.quote?.[0]?.close ?? []).filter(
    (close): close is number => typeof close === "number" && Number.isFinite(close),
  );

  let alert: string | undefined;
  try {
    alert = calculateAlert(
      displayNameForSymbol(symbol),
      closes,
      config.distanceThreshold,
    );
  } catch (error) {
    dependencies.error(`${time()}: ${(error as Error).message}`);
    return false;
  }

  if (alert === undefined) {
    dependencies.log(
      `${time()}: ${symbol} distance is not below ${config.distanceThreshold}%; no alert sent`,
    );
    return true;
  }

  dependencies.log(`${time()}: ${symbol} done`);
  return alert;
}

export async function runMonitor(
  config: MonitorConfig,
  dependencies: MonitorDependencies = defaultDependencies,
): Promise<boolean> {
  dependencies.log(`${timestamp(dependencies.now())}: Running investing monitor`);
  let succeeded = true;
  const alerts: string[] = [];

  for (const symbol of config.symbols) {
    const result = await monitorSymbol(symbol, config, dependencies);
    if (result === false) {
      succeeded = false;
    } else if (typeof result === "string") {
      alerts.push(result);
    }
  }

  if (alerts.length > 0) {
    const body = new URLSearchParams({
      chat_id: config.telegramChatId,
      parse_mode: "HTML",
      text: alerts.join("\n\n"),
    });

    try {
      const response = await dependencies.fetch(
        `https://api.telegram.org/bot${config.telegramBotToken}/sendMessage`,
        { method: "POST", body },
      );
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      dependencies.log(await response.text());
    } catch {
      dependencies.error(`${timestamp(dependencies.now())}: Failed to send combined alerts`);
      succeeded = false;
    }
  }

  return succeeded;
}
