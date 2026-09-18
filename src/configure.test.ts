import { describe, expect, test } from "bun:test";

import {
  configure,
  readConfig,
  saveConfig,
  type ConfigureDependencies,
  type ConfigureOptions,
  type StoredConfig,
} from "./configure";

const options: ConfigureOptions = {
  configPath: "/home/test/.config/investing-monitor/config",
  executablePath: "/home/test/.local/bin/investing-monitor",
  logPath: "/home/test/.config/investing-monitor/investing-monitor.log",
};

function harness(
  answers: string[],
  existing: Partial<StoredConfig> = {},
  crontab = "15 2 * * * /usr/local/bin/backup\n",
) {
  const questions: Array<{ message: string; secret: boolean }> = [];
  const logs: string[] = [];
  let writtenConfig: StoredConfig | undefined;
  let writtenCrontab: string | undefined;

  const dependencies: ConfigureDependencies = {
    readConfig: async () => existing,
    writeConfig: async (_path, config) => {
      writtenConfig = config;
    },
    prompt: async (message, promptOptions) => {
      questions.push({ message, secret: promptOptions.secret });
      const answer = answers.shift();
      if (answer === undefined) throw new Error(`No answer for: ${message}`);
      return answer;
    },
    readCrontab: async () => crontab,
    writeCrontab: async (contents) => {
      writtenCrontab = contents;
    },
    log: (message) => logs.push(message),
  };

  return {
    dependencies,
    get writtenConfig() {
      return writtenConfig;
    },
    get writtenCrontab() {
      return writtenCrontab;
    },
    logs,
    questions,
  };
}

describe("configure", () => {
  test("creates config and cron schedule for a fresh installation", async () => {
    const ctx = harness([
      "test-token",
      "test-chat",
      "",
      "",
      "",
      "",
    ]);

    await configure(options, ctx.dependencies);

    expect(ctx.writtenConfig).toEqual({
      telegramBotToken: "test-token",
      telegramChatId: "test-chat",
      frequencyMinutes: 30,
      maDistanceThreshold: 4,
      rsiDistanceThreshold: 40,
      symbols: "^GSPC,^NDX",
    });
    expect(ctx.questions[0]).toEqual({
      message: "Enter Telegram bot token: ",
      secret: true,
    });
    expect(ctx.writtenCrontab).toContain("15 2 * * * /usr/local/bin/backup");
    expect(ctx.writtenCrontab).toContain(
      "*/30 * * * * /home/test/.local/bin/investing-monitor run >> /home/test/.config/investing-monitor/investing-monitor.log 2>&1 # investing-monitor",
    );
    expect(ctx.logs).toContain("Installed successfully.");
  });

  test("keeps values from an existing config", async () => {
    const existing: StoredConfig = {
      telegramBotToken: "existing-token",
      telegramChatId: "existing-chat",
      frequencyMinutes: 15,
      maDistanceThreshold: -5.5,
      rsiDistanceThreshold: 35,
      symbols: "^GSPC,^NDX",
    };
    const ctx = harness(["", "", "", "", "", ""], existing);

    await configure(options, ctx.dependencies);

    expect(ctx.writtenConfig).toEqual(existing);
    expect(ctx.questions.map(({ message }) => message)).toEqual([
      "Telegram bot token is currently [hidden]. Keep it? [Y/n] ",
      'Telegram chat ID is currently "existing-chat". Keep it? [Y/n] ',
      'frequency in minutes (1-59) is currently "15". Keep it? [Y/n] ',
      'MA distance threshold percentage (for example, 4 or -5.5) is currently "-5.5". Keep it? [Y/n] ',
      'RSI threshold (0-100) is currently "35". Keep it? [Y/n] ',
      'Yahoo Finance symbols (comma-separated) is currently "^GSPC,^NDX". Keep it? [Y/n] ',
    ]);
    expect(ctx.questions[0]?.message).not.toContain(
      existing.telegramBotToken,
    );
  });

  test("re-prompts invalid values and replaces a legacy cron entry", async () => {
    const ctx = harness(
      [
        "token",
        "chat",
        "n",
        "0",
        "60",
        "10",
        "n",
        "not-a-number",
        "-3",
        "n",
        "101",
        "-1",
        "35",
        "n",
        "^GSPC,,^NDX",
        "AAPL,MSFT",
      ],
      {},
      [
        "0 * * * * /home/test/.local/bin/investing-monitor >> old.log 2>&1",
        "30 1 * * * /usr/local/bin/backup",
        "",
      ].join("\n"),
    );

    await configure(options, ctx.dependencies);

    expect(ctx.writtenConfig?.frequencyMinutes).toBe(10);
    expect(ctx.writtenConfig?.maDistanceThreshold).toBe(-3);
    expect(ctx.writtenConfig?.rsiDistanceThreshold).toBe(35);
    expect(ctx.writtenConfig?.symbols).toBe("AAPL,MSFT");
    expect(ctx.writtenCrontab).not.toContain("old.log");
    expect(ctx.writtenCrontab).toContain("30 1 * * * /usr/local/bin/backup");
    expect(ctx.logs).toContain("Frequency must be an integer between 1 and 59.");
    expect(ctx.logs).toContain("Symbols must be a comma-separated list without empty entries.");
  });

  test("migrates the legacy MA threshold during configuration", async () => {
    const file = Bun.file(`${process.env.TMPDIR ?? "/tmp"}/legacy-threshold-${crypto.randomUUID()}`);
    try {
      await Bun.write(file, "TELEGRAM_BOT_TOKEN=test-token\nTELEGRAM_CHAT_ID=test-chat\nDISTANCE_THRESHOLD=-5.5\n");
      const existing = await readConfig(file.name!);
      const ctx = harness(["", "", "", "", "", ""], existing);
      await configure(options, ctx.dependencies);
      expect(ctx.writtenConfig?.maDistanceThreshold).toBe(-5.5);
      expect(ctx.writtenConfig?.rsiDistanceThreshold).toBe(40);
    } finally {
      await file.delete();
    }
  });

  test("does not duplicate its managed cron entry", async () => {
    const managed =
      "*/30 * * * * /home/test/.local/bin/investing-monitor run >> /home/test/.config/investing-monitor/investing-monitor.log 2>&1 # investing-monitor";
    const ctx = harness(["token", "chat", "", "", "", ""], {}, `${managed}\n`);

    await configure(options, ctx.dependencies);

    expect(ctx.writtenCrontab?.match(/# investing-monitor/g)).toHaveLength(1);
  });
});

describe("saveConfig", () => {
  test("writes a canonical config with private permissions", async () => {
    const directory = `${process.env.TMPDIR ?? "/tmp"}/investing-monitor-${crypto.randomUUID()}`;
    const path = `${directory}/config`;

    await saveConfig(path, {
      telegramBotToken: 'token-with-"quotes"',
      telegramChatId: "test-chat",
      frequencyMinutes: 30,
      maDistanceThreshold: 4,
      rsiDistanceThreshold: 40,
      symbols: "^GSPC,^NDX",
    });

    const contents = await Bun.file(path).text();
    const mode = (await Bun.file(path).stat()).mode & 0o777;
    expect(contents).toContain('TELEGRAM_BOT_TOKEN="token-with-\\"quotes\\""');
    expect(contents).toContain("FREQUENCY_MINUTES=30");
    expect(contents).toContain("MA_DISTANCE_THRESHOLD=4");
    expect(contents).toContain("RSI_DISTANCE_THRESHOLD=40");
    expect(contents).not.toMatch(/^DISTANCE_THRESHOLD=/m);
    await expect(readConfig(path)).resolves.toMatchObject({ maDistanceThreshold: 4, rsiDistanceThreshold: 40 });
    expect(mode).toBe(0o600);
  });
});
