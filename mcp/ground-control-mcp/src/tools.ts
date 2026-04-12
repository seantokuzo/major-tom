import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

// ---------------------------------------------------------------------------
// Control API client — thin HTTP wrapper for Ground Control's ControlServer
// ---------------------------------------------------------------------------

const DEFAULT_BASE_URL = "http://127.0.0.1:9092";

function getBaseUrl(): string {
  return process.env.GROUND_CONTROL_URL || DEFAULT_BASE_URL;
}

interface ControlResponse {
  status: number;
  body: Record<string, unknown>;
}

async function controlRequest(
  method: string,
  path: string,
  body?: Record<string, unknown>
): Promise<ControlResponse> {
  const url = `${getBaseUrl()}${path}`;

  const opts: RequestInit = {
    method,
    headers: { "Content-Type": "application/json" },
  };

  if (body) {
    opts.body = JSON.stringify(body);
  }

  const res = await fetch(url, opts);
  const text = await res.text();

  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = { raw: text };
  }

  return { status: res.status, body: parsed };
}

// ---------------------------------------------------------------------------
// Tool registration — each tool maps 1:1 to a ControlServer endpoint
// ---------------------------------------------------------------------------

export function registerTools(server: McpServer): void {
  // ── get_relay_status ────────────────────────────────────────
  server.tool(
    "get_relay_status",
    "Get relay state, tunnel state, restart count, and uptime",
    {},
    async () => {
      try {
        const res = await controlRequest("GET", "/control/status");
        return {
          content: [
            { type: "text" as const, text: JSON.stringify(res.body, null, 2) },
          ],
          isError: res.status !== 200,
        };
      } catch (error) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Failed to reach Ground Control: ${error instanceof Error ? error.message : String(error)}`,
            },
          ],
          isError: true,
        };
      }
    }
  );

  // ── start_relay ─────────────────────────────────────────────
  server.tool(
    "start_relay",
    "Start the relay server",
    {},
    async () => {
      try {
        const res = await controlRequest("POST", "/control/relay/start");
        return {
          content: [
            { type: "text" as const, text: JSON.stringify(res.body, null, 2) },
          ],
          isError: res.status !== 200,
        };
      } catch (error) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Failed to start relay: ${error instanceof Error ? error.message : String(error)}`,
            },
          ],
          isError: true,
        };
      }
    }
  );

  // ── stop_relay ──────────────────────────────────────────────
  server.tool(
    "stop_relay",
    "Stop the relay server",
    {},
    async () => {
      try {
        const res = await controlRequest("POST", "/control/relay/stop");
        return {
          content: [
            { type: "text" as const, text: JSON.stringify(res.body, null, 2) },
          ],
          isError: res.status !== 200,
        };
      } catch (error) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Failed to stop relay: ${error instanceof Error ? error.message : String(error)}`,
            },
          ],
          isError: true,
        };
      }
    }
  );

  // ── restart_relay ───────────────────────────────────────────
  server.tool(
    "restart_relay",
    "Restart the relay server (stop then start)",
    {},
    async () => {
      try {
        const res = await controlRequest("POST", "/control/relay/restart");
        return {
          content: [
            { type: "text" as const, text: JSON.stringify(res.body, null, 2) },
          ],
          isError: res.status !== 200,
        };
      } catch (error) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Failed to restart relay: ${error instanceof Error ? error.message : String(error)}`,
            },
          ],
          isError: true,
        };
      }
    }
  );

  // ── start_tunnel ────────────────────────────────────────────
  server.tool(
    "start_tunnel",
    "Start the Cloudflare tunnel (must be configured in Ground Control)",
    {},
    async () => {
      try {
        const res = await controlRequest("POST", "/control/tunnel/start");
        return {
          content: [
            { type: "text" as const, text: JSON.stringify(res.body, null, 2) },
          ],
          isError: res.status !== 200,
        };
      } catch (error) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Failed to start tunnel: ${error instanceof Error ? error.message : String(error)}`,
            },
          ],
          isError: true,
        };
      }
    }
  );

  // ── stop_tunnel ─────────────────────────────────────────────
  server.tool(
    "stop_tunnel",
    "Stop the Cloudflare tunnel",
    {},
    async () => {
      try {
        const res = await controlRequest("POST", "/control/tunnel/stop");
        return {
          content: [
            { type: "text" as const, text: JSON.stringify(res.body, null, 2) },
          ],
          isError: res.status !== 200,
        };
      } catch (error) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Failed to stop tunnel: ${error instanceof Error ? error.message : String(error)}`,
            },
          ],
          isError: true,
        };
      }
    }
  );

  // ── get_logs ────────────────────────────────────────────────
  server.tool(
    "get_logs",
    "Get recent log entries from Ground Control, optionally filtered by level and count",
    {
      count: z
        .number()
        .int()
        .min(1)
        .max(1000)
        .optional()
        .describe("Number of recent log entries to return (default 100, max 1000)"),
      level: z
        .enum(["trace", "debug", "info", "warn", "error", "fatal"])
        .optional()
        .describe("Minimum log level to include (default: all levels)"),
      since: z
        .number()
        .optional()
        .describe("Unix timestamp — only return entries after this time"),
    },
    async ({ count, level, since }) => {
      try {
        const params = new URLSearchParams();
        if (count !== undefined) params.set("count", String(count));
        if (level) params.set("level", level);
        if (since !== undefined) params.set("since", String(since));

        const query = params.toString();
        const path = `/control/logs${query ? `?${query}` : ""}`;
        const res = await controlRequest("GET", path);

        return {
          content: [
            { type: "text" as const, text: JSON.stringify(res.body, null, 2) },
          ],
          isError: res.status !== 200,
        };
      } catch (error) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Failed to get logs: ${error instanceof Error ? error.message : String(error)}`,
            },
          ],
          isError: true,
        };
      }
    }
  );

  // ── get_config ──────────────────────────────────────────────
  server.tool(
    "get_config",
    "Get current Ground Control configuration (non-secret fields only)",
    {},
    async () => {
      try {
        const res = await controlRequest("GET", "/control/config");
        return {
          content: [
            { type: "text" as const, text: JSON.stringify(res.body, null, 2) },
          ],
          isError: res.status !== 200,
        };
      } catch (error) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Failed to get config: ${error instanceof Error ? error.message : String(error)}`,
            },
          ],
          isError: true,
        };
      }
    }
  );

  // ── update_config ───────────────────────────────────────────
  server.tool(
    "update_config",
    "Update Ground Control config fields. Restart the relay to apply changes.",
    {
      port: z
        .number()
        .int()
        .min(1024)
        .max(65535)
        .optional()
        .describe("Relay WebSocket port"),
      hookPort: z
        .number()
        .int()
        .min(1024)
        .max(65535)
        .optional()
        .describe("Hook listener port"),
      authMode: z
        .enum(["none", "pin", "google"])
        .optional()
        .describe("Authentication mode"),
      multiUserEnabled: z
        .boolean()
        .optional()
        .describe("Enable multi-user mode"),
      claudeWorkDir: z
        .string()
        .optional()
        .describe("Claude working directory (supports ~ expansion)"),
      logLevel: z
        .enum(["trace", "debug", "info", "warn", "error"])
        .optional()
        .describe("Log level for the relay process"),
      cloudflareEnabled: z
        .boolean()
        .optional()
        .describe("Enable Cloudflare tunnel"),
      cloudflareTunnelName: z
        .string()
        .optional()
        .describe("Display name for the Cloudflare tunnel"),
      autoStart: z
        .boolean()
        .optional()
        .describe("Auto-start relay on app launch"),
      controlPort: z
        .number()
        .int()
        .min(1024)
        .max(65535)
        .optional()
        .describe("Control API port (requires Ground Control restart to take effect)"),
    },
    async (params) => {
      try {
        // Only send fields that were actually provided
        const updates: Record<string, unknown> = {};
        for (const [key, value] of Object.entries(params)) {
          if (value !== undefined) {
            updates[key] = value;
          }
        }

        if (Object.keys(updates).length === 0) {
          return {
            content: [
              { type: "text" as const, text: "No config fields provided to update" },
            ],
            isError: true,
          };
        }

        const res = await controlRequest("PATCH", "/control/config", updates);
        return {
          content: [
            { type: "text" as const, text: JSON.stringify(res.body, null, 2) },
          ],
          isError: res.status !== 200,
        };
      } catch (error) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Failed to update config: ${error instanceof Error ? error.message : String(error)}`,
            },
          ],
          isError: true,
        };
      }
    }
  );
}
