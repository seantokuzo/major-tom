/**
 * Achievement API routes — serves achievement state and progress.
 *
 * GET  /api/achievements       — returns all achievements with unlock status + progress
 * POST /api/achievements/reset — resets all achievements (dev/debug)
 *
 * Both routes require authentication (session cookie).
 */

import type { FastifyPluginAsync } from 'fastify';
import { requireSession } from '../plugins/auth.js';
import type { AchievementService } from '../achievements/achievement-service.js';

// ── Route factory ─────────────────────────────────────────────

interface AchievementDeps {
  achievementService: AchievementService;
}

export function createAchievementRoutes(deps: AchievementDeps): FastifyPluginAsync {
  return async (fastify) => {
    // GET /api/achievements — returns all achievements with unlock status + progress
    // Pass ?source=widget to trigger the "Widget Watcher" achievement
    fastify.get<{ Querystring: { source?: string } }>(
      '/api/achievements',
      { preHandler: requireSession },
      async (request) => {
        // Track widget views for achievement
        if (request.query.source === 'widget') {
          deps.achievementService.checkEvent('widget.viewed');
        }
        const achievements = deps.achievementService.getAllStatus();
        return {
          achievements,
          totalCount: deps.achievementService.getTotalCount(),
          unlockedCount: deps.achievementService.getUnlockedCount(),
        };
      },
    );

    // POST /api/achievements/reset — resets all achievements (dev/debug)
    fastify.post(
      '/api/achievements/reset',
      { preHandler: requireSession },
      async () => {
        await deps.achievementService.reset();
        return { success: true, message: 'All achievements have been reset' };
      },
    );
  };
}
