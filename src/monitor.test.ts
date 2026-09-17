import { describe, expect, test } from "bun:test";

import {
  loadConfig,
  runMonitor,
  type MonitorConfig,
  type MonitorDependencies,
} from "./monitor";

const OPEN_START = 0;
const OPEN_END = 4_102_444_800;

function yahooFixture(
  marketStart = OPEN_START,
  marketEnd = OPEN_END,
  pricePattern: "flat" | "drop" = "flat",
): unknown {
  const closes = Array<number>(201).fill(100);
  if (pricePattern === "drop") {
    closes[200] = 90;
  }

  return {
    chart: {
      result: [
        {
          meta: {
            currentTradingPeriod: {
              regular: { start: marketStart, end: marketEnd },
            },
          },
          indicators: { quote: [{ close: closes }] },
        },
      ],
    },
  };
}

function config(overrides: Partial<MonitorConfig> = {}): MonitorConfig {
  return {
    telegramBotToken: "test-token",
    telegramChatId: "test-chat",
    distanceThreshold: 0,
    symbols: ["^GSPC"],
    ...overrides,
  };
}

function harness(fixture: unknown = yahooFixture()) {
  const requests: Array<{ url: string; init?: RequestInit }> = [];
  const output: string[] = [];
  const errors: string[] = [];

  const dependencies: MonitorDependencies = {
    now: () => new Date("2026-01-15T15:00:00Z"),
    log: (message) => output.push(message),
    error: (message) => errors.push(message),
    fetch: async (input, init) => {
      const url = String(input);
      requests.push({ url, init });

      if (url.includes("query1.finance.yahoo.com")) {
        return Response.json(fixture);
      }

      if (url.includes("api.telegram.org")) {
        return Response.json({ ok: true });
      }

      return new Response("not found", { status: 404 });
    },
  };

  return { dependencies, errors, output, requests };
}

describe("configuration", () => {
  test("fails when the config file is missing", async () => {
    await expect(
      loadConfig("/does/not/exist/investing-monitor-config"),
    ).rejects.toThrow("Missing config file:");
  });

  test("rejects a non-numeric distance threshold", async () => {
    const file = Bun.file(`${process.env.TMPDIR ?? "/tmp"}/invalid-config-${crypto.randomUUID()}`);
    await Bun.write(
      file,
      [
        'TELEGRAM_BOT_TOKEN="test-token"',
        'TELEGRAM_CHAT_ID="test-chat"',
        'DISTANCE_THRESHOLD="not-a-number"',
        'SYMBOLS="^GSPC"',
      ].join("\n"),
    );

    try {
      await expect(loadConfig(file.name!)).rejects.toThrow(
        "DISTANCE_THRESHOLD must be a number.",
      );
    } finally {
      await file.delete();
    }
  });

  test("understands values escaped by the existing Bash installer", async () => {
    const file = Bun.file(`${process.env.TMPDIR ?? "/tmp"}/legacy-config-${crypto.randomUUID()}`);
    await Bun.write(
      file,
      [
        "TELEGRAM_BOT_TOKEN=test-token",
        "TELEGRAM_CHAT_ID=-1234",
        "DISTANCE_THRESHOLD=-5.5",
        "SYMBOLS=\\^GSPC\\,\\^NDX",
      ].join("\n"),
    );

    try {
      await expect(loadConfig(file.name!)).resolves.toEqual(
        config({
          telegramChatId: "-1234",
          distanceThreshold: -5.5,
          symbols: ["^GSPC", "^NDX"],
        }),
      );
    } finally {
      await file.delete();
    }
  });
});

describe("monitor", () => {
  test("combines S&P 500 and Nasdaq-100 alerts into one message", async () => {
    const ctx = harness(yahooFixture(OPEN_START, OPEN_END, "drop"));

    await expect(
      runMonitor(config({ symbols: ["^GSPC", "^NDX"] }), ctx.dependencies),
    ).resolves.toBe(true);

    const yahooRequests = ctx.requests.filter(({ url }) =>
      url.includes("query1.finance.yahoo.com"),
    );
    const telegramRequests = ctx.requests.filter(({ url }) =>
      url.includes("api.telegram.org"),
    );

    expect(yahooRequests).toHaveLength(2);
    expect(yahooRequests[0]?.url).toContain("%5EGSPC");
    expect(yahooRequests[1]?.url).toContain("%5ENDX");
    expect(telegramRequests).toHaveLength(1);
    expect(
      new URLSearchParams(String(telegramRequests[0]?.init?.body)).get("text"),
    ).toContain("<b>S&amp;P 500 Alert</b>");
    expect(
      new URLSearchParams(String(telegramRequests[0]?.init?.body)).get("text"),
    ).toContain("<b>Nasdaq-100 Alert</b>");
  });

  test("reports a failed combined message delivery", async () => {
    const ctx = harness(yahooFixture(OPEN_START, OPEN_END, "drop"));
    const successfulFetch = ctx.dependencies.fetch;
    ctx.dependencies.fetch = async (input, init) => {
      if (String(input).includes("api.telegram.org")) {
        return new Response("upstream error", { status: 500 });
      }
      return successfulFetch(input, init);
    };

    await expect(
      runMonitor(config({ symbols: ["^GSPC", "^NDX"] }), ctx.dependencies),
    ).resolves.toBe(false);
    expect(ctx.errors.join("\n")).toContain("Failed to send combined alerts");
  });

  test("does not alert while the market is closed", async () => {
    const ctx = harness(yahooFixture(0, 1));

    await expect(runMonitor(config(), ctx.dependencies)).resolves.toBe(true);

    expect(ctx.requests).toHaveLength(1);
    expect(ctx.output.join("\n")).toContain("market is closed; no alert sent");
  });

  test("does not alert when the index is not below the threshold", async () => {
    const ctx = harness();

    await expect(runMonitor(config(), ctx.dependencies)).resolves.toBe(true);

    expect(ctx.requests).toHaveLength(1);
    expect(ctx.output.join("\n")).toContain(
      "distance is not below 0%; no alert sent",
    );
  });

  test("sends the calculated alert when the index drops below the threshold", async () => {
    const ctx = harness(yahooFixture(OPEN_START, OPEN_END, "drop"));

    await expect(runMonitor(config(), ctx.dependencies)).resolves.toBe(true);

    const telegram = ctx.requests[1];
    expect(telegram?.url).toBe(
      "https://api.telegram.org/bottest-token/sendMessage",
    );
    expect(telegram?.init?.method).toBe("POST");

    const body = new URLSearchParams(String(telegram?.init?.body));
    expect(body.get("chat_id")).toBe("test-chat");
    expect(body.get("parse_mode")).toBe("HTML");
    expect(body.get("text")).toContain("<b>S&amp;P 500 Alert</b>");
    expect(body.get("text")).toContain("<b>Price:</b> 90.00");
    expect(body.get("text")).toContain(
      "<b>200-day SMA:</b> 99.95 (-9.95%)",
    );
    expect(body.get("text")).toContain(
      "<b>RSI (14):</b> 0.00 · Oversold",
    );
    expect(ctx.output.join("\n")).toContain("^GSPC done");
  });

  test("continues monitoring other symbols and reports a failed fetch", async () => {
    const ctx = harness(yahooFixture(OPEN_START, OPEN_END, "drop"));
    let yahooCalls = 0;
    const successfulFetch = ctx.dependencies.fetch;
    ctx.dependencies.fetch = async (input, init) => {
      if (String(input).includes("query1.finance.yahoo.com")) {
        yahooCalls += 1;
        if (yahooCalls === 1) {
          return new Response("upstream error", { status: 500 });
        }
      }
      return successfulFetch(input, init);
    };

    await expect(
      runMonitor(config({ symbols: ["^GSPC", "^NDX"] }), ctx.dependencies),
    ).resolves.toBe(false);

    expect(yahooCalls).toBe(2);
    expect(ctx.errors.join("\n")).toContain("Failed to fetch ^GSPC");
    expect(ctx.requests.some(({ url }) => url.includes("api.telegram.org"))).toBe(
      true,
    );
  });
});
