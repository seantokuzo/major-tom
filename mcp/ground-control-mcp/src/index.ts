#!/usr/bin/env node

/**
 * Ground Control MCP Server
 *
 * Bridges Claude Code agents to the Ground Control macOS app via MCP tools.
 * Each tool is a thin wrapper around the ControlServer HTTP API running on
 * 127.0.0.1:<controlPort> (default 9092).
 *
 * Usage:
 *   npx ground-control-mcp
 *   GROUND_CONTROL_URL=http://127.0.0.1:9092 npx ground-control-mcp
 *
 * Claude Code config (~/.claude.json or project .mcp.json):
 *   {
 *     "mcpServers": {
 *       "ground-control": {
 *         "command": "node",
 *         "args": ["<path>/mcp/ground-control-mcp/dist/index.js"]
 *       }
 *     }
 *   }
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { registerTools } from "./tools.js";

async function main() {
  const server = new McpServer(
    {
      name: "ground-control",
      version: "1.0.0",
    },
    {
      capabilities: { logging: {} },
      instructions: [
        "Ground Control MCP server — manages the Major Tom relay server and Cloudflare tunnel.",
        "The relay is a Node.js WebSocket server that bridges Claude Code to the Major Tom PWA/iOS app.",
        "The tunnel is an optional Cloudflare tunnel for remote access.",
        "",
        "Available tools:",
        "  get_relay_status  — Check relay + tunnel state, uptime, restart count",
        "  start_relay       — Start the relay server",
        "  stop_relay        — Stop the relay server",
        "  restart_relay     — Restart the relay (stop then start)",
        "  start_tunnel      — Start the Cloudflare tunnel",
        "  stop_tunnel       — Stop the Cloudflare tunnel",
        "  get_logs          — Fetch recent log entries (filterable by level/count)",
        "  get_config        — Read current configuration",
        "  update_config     — Update config fields (restart relay to apply)",
        "",
        "Always check get_relay_status before starting/stopping to avoid redundant operations.",
      ].join("\n"),
    }
  );

  registerTools(server);

  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("[ground-control-mcp] Server running on stdio");
}

main().catch((error) => {
  console.error("[ground-control-mcp] Fatal error:", error);
  process.exit(1);
});
