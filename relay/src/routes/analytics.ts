/**
 * Analytics API route — serves aggregated analytics data from the JSONL log.
 *
 * GET /api/analytics — requires auth (session cookie)
 * Query params:
 *   from     — ISO 8601 start time (default: 24h ago)
 *   to       — ISO 8601 end time (default: now)
 *   groupBy  — hour | day | week | month (default: day)
 *   sessionId — optional filter
 *   workerId  — optional filter
 */

import type { FastifyPluginAsync } from 'fastify';
import { createReadStream } from 'node:fs';
import { existsSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { requireSession } from '../plugins/auth.js';
import type { AnalyticsCollector, AnalyticsEvent, TurnCompleteEvent } from '../analytics/analytics-collector.js';
import type {
  AnalyticsTimeSeriesEntry,
  AnalyticsBySession,
  AnalyticsByModel,
  AnalyticsByTool,
  AnalyticsTotals,
  AnalyticsResponse,
} from '../protocol/messages.js';
import { logger } from '../utils/logger.js';

// ── Query types ────────────────────────────────────────────

type GroupBy = 'hour' | 'day' | 'week' | 'month';

interface AnalyticsQuery {
  from?: string;
  to?: string;
  groupBy?: GroupBy;
  sessionId?: string;
  workerId?: string;
}

// ── Route factory ──────────────────────────────────────────

interface AnalyticsDeps {
  analyticsCollector: AnalyticsCollector;
}

export function createAnalyticsRoutes(deps: AnalyticsDeps): FastifyPluginAsync {
  return async (fastify) => {
    fastify.get<{ Querystring: AnalyticsQuery }>(
      '/api/analytics',
      { preHandler: requireSession },
      async (request, reply) => {
        const {
          from,
          to,
          groupBy = 'day',
          sessionId,
          workerId,
        } = request.query;

        // Validate groupBy
        const validGroupBy: readonly string[] = ['hour', 'day', 'week', 'month'];
        if (!validGroupBy.includes(groupBy)) {
          return reply.status(400).send({ error: `Invalid groupBy: ${groupBy}. Must be one of: ${validGroupBy.join(', ')}` });
        }

        const now = new Date();
        const fromDate = from ? new Date(from) : new Date(now.getTime() - 24 * 60 * 60 * 1000);
        const toDate = to ? new Date(to) : now;

        // Validate date params
        if (!Number.isFinite(fromDate.getTime())) {
          return reply.status(400).send({ error: `Invalid 'from' date: ${from}` });
        }
        if (!Number.isFinite(toDate.getTime())) {
          return reply.status(400).send({ error: `Invalid 'to' date: ${to}` });
        }
        if (fromDate > toDate) {
          return reply.status(400).send({ error: "'from' must be before 'to'" });
        }

        // Read and parse JSONL file (streaming)
        const events = await readAnalyticsFile(deps.analyticsCollector.getFilePath());

        // Filter events by time range + optional filters
        const filtered = events.filter((e) => {
          const ts = new Date(e.timestamp);
          if (ts < fromDate || ts > toDate) return false;
          if (sessionId && 'sessionId' in e && e.sessionId !== sessionId) return false;
          if (workerId && 'workerId' in e && e.workerId !== workerId) return false;
          return true;
        });

        // Only turn_complete events have per-turn metrics
        const turns = filtered.filter(
          (e): e is TurnCompleteEvent => e.event === 'turn_complete',
        );

        // Build aggregations
        const response: AnalyticsResponse = {
          timeSeries: buildTimeSeries(turns, groupBy as GroupBy),
          bySession: buildBySession(turns, filtered),
          byModel: buildByModel(turns),
          byTool: buildByTool(turns),
          totals: buildTotals(turns, filtered),
        };

        return response;
      },
    );
  };
}

// ── JSONL reader ───────────────────────────────────────────

async function readAnalyticsFile(filePath: string): Promise<AnalyticsEvent[]> {
  if (!existsSync(filePath)) return [];

  try {
    const events: AnalyticsEvent[] = [];
    const rl = createInterface({
      input: createReadStream(filePath, { encoding: 'utf-8' }),
      crlfDelay: Infinity,
    });

    for await (const line of rl) {
      if (line.trim().length === 0) continue;
      try {
        events.push(JSON.parse(line) as AnalyticsEvent);
      } catch {
        logger.warn({ line: line.slice(0, 100) }, 'Skipping malformed analytics line');
      }
    }

    return events;
  } catch (err) {
    logger.error({ err }, 'Failed to read analytics file');
    return [];
  }
}

// ── Aggregation helpers ────────────────────────────────────

function periodKey(date: Date, groupBy: GroupBy): string {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, '0');
  const d = String(date.getUTCDate()).padStart(2, '0');
  const h = String(date.getUTCHours()).padStart(2, '0');

  switch (groupBy) {
    case 'hour':
      return `${y}-${m}-${d}T${h}:00:00Z`;
    case 'day':
      return `${y}-${m}-${d}`;
    case 'week': {
      // ISO week start (Monday)
      const dt = new Date(date);
      const day = dt.getUTCDay();
      const diff = dt.getUTCDate() - day + (day === 0 ? -6 : 1);
      dt.setUTCDate(diff);
      const wy = dt.getUTCFullYear();
      const wm = String(dt.getUTCMonth() + 1).padStart(2, '0');
      const wd = String(dt.getUTCDate()).padStart(2, '0');
      return `${wy}-${wm}-${wd}`;
    }
    case 'month':
      return `${y}-${m}`;
  }
}

function buildTimeSeries(turns: TurnCompleteEvent[], groupBy: GroupBy): AnalyticsTimeSeriesEntry[] {
  const buckets = new Map<string, AnalyticsTimeSeriesEntry>();

  for (const turn of turns) {
    const key = periodKey(new Date(turn.timestamp), groupBy);
    const existing = buckets.get(key) ?? {
      period: key,
      cost: 0,
      inputTokens: 0,
      outputTokens: 0,
      cacheTokens: 0,
      turnCount: 0,
    };
    existing.cost += turn.cost;
    existing.inputTokens += turn.inputTokens;
    existing.outputTokens += turn.outputTokens;
    existing.cacheTokens += (turn.cacheCreationTokens ?? 0) + (turn.cacheReadTokens ?? 0);
    existing.turnCount += 1;
    buckets.set(key, existing);
  }

  return [...buckets.values()].sort((a, b) => a.period.localeCompare(b.period));
}

function buildBySession(turns: TurnCompleteEvent[], allEvents: AnalyticsEvent[]): AnalyticsBySession[] {
  // Get working dirs from session_start events
  const sessionDirs = new Map<string, string>();
  for (const e of allEvents) {
    if (e.event === 'session_start') {
      sessionDirs.set(e.sessionId, e.workingDir);
    }
  }

  const sessions = new Map<string, AnalyticsBySession>();
  for (const turn of turns) {
    const existing = sessions.get(turn.sessionId) ?? {
      sessionId: turn.sessionId,
      workingDir: sessionDirs.get(turn.sessionId) ?? 'unknown',
      totalCost: 0,
      totalTokens: 0,
      turnCount: 0,
    };
    existing.totalCost += turn.cost;
    existing.totalTokens += turn.inputTokens + turn.outputTokens;
    existing.turnCount += 1;
    sessions.set(turn.sessionId, existing);
  }

  return [...sessions.values()].sort((a, b) => b.totalCost - a.totalCost);
}

function buildByModel(turns: TurnCompleteEvent[]): AnalyticsByModel[] {
  const models = new Map<string, AnalyticsByModel>();

  for (const turn of turns) {
    const model = turn.model ?? 'unknown';
    const existing = models.get(model) ?? {
      model,
      cost: 0,
      tokens: 0,
      turnCount: 0,
    };
    existing.cost += turn.cost;
    existing.tokens += turn.inputTokens + turn.outputTokens;
    existing.turnCount += 1;
    models.set(model, existing);
  }

  return [...models.values()].sort((a, b) => b.cost - a.cost);
}

function buildByTool(turns: TurnCompleteEvent[]): AnalyticsByTool[] {
  const tools = new Map<string, { count: number; totalDurationMs: number }>();

  for (const turn of turns) {
    for (const tool of turn.toolsUsed) {
      const existing = tools.get(tool) ?? { count: 0, totalDurationMs: 0 };
      existing.count += 1;
      // Distribute turn duration across tools as a rough estimate
      existing.totalDurationMs += turn.durationMs / Math.max(turn.toolsUsed.length, 1);
      tools.set(tool, existing);
    }
  }

  return [...tools.entries()]
    .map(([tool, data]) => ({
      tool,
      count: data.count,
      avgDurationMs: Math.round(data.totalDurationMs / Math.max(data.count, 1)),
    }))
    .sort((a, b) => b.count - a.count);
}

function buildTotals(turns: TurnCompleteEvent[], allEvents: AnalyticsEvent[]): AnalyticsTotals {
  const sessionIds = new Set<string>();
  let cost = 0;
  let inputTokens = 0;
  let outputTokens = 0;

  for (const turn of turns) {
    cost += turn.cost;
    inputTokens += turn.inputTokens;
    outputTokens += turn.outputTokens;
    sessionIds.add(turn.sessionId);
  }

  // Also count sessions from session_start events that may not have turns yet
  for (const e of allEvents) {
    if (e.event === 'session_start') {
      sessionIds.add(e.sessionId);
    }
  }

  return {
    cost,
    inputTokens,
    outputTokens,
    turnCount: turns.length,
    sessionCount: sessionIds.size,
  };
}
