import { homedir } from "node:os";
import { join } from "node:path";

import { configure } from "./configure";
import { loadConfig, runMonitor } from "./monitor";

export async function main(args = process.argv.slice(2)): Promise<number> {
  try {
    const configPath =
      process.env.INVESTING_MONITOR_CONFIG ??
      join(homedir(), ".config", "investing-monitor", "config");
    const command = args[0] ?? "run";

    if (command === "configure") {
      const configDirectory = join(homedir(), ".config", "investing-monitor");
      await configure({
        configPath,
        executablePath:
          process.env.INVESTING_MONITOR_EXECUTABLE ?? process.execPath,
        logPath: join(configDirectory, "investing-monitor.log"),
      });
      return 0;
    }

    if (command !== "run") {
      throw new Error(`Unknown command: ${command}. Expected "run" or "configure".`);
    }

    const config = await loadConfig(configPath);
    return (await runMonitor(config)) ? 0 : 1;
  } catch (error) {
    console.error((error as Error).message);
    return 1;
  }
}

if (import.meta.main) {
  process.exitCode = await main();
}
