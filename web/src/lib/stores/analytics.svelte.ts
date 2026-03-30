// Analytics store — reactive state for cost/token analytics dashboard
// Uses Svelte 5 runes ($state, $derived)

import type { AnalyticsResponse } from '../protocol/messages';

// ── Time range presets ─────────────────────────────────────

export type TimeRange = '24h' | '7d' | '30d' | 'custom';

function getFromDate(range: TimeRange): string {
  const now = new Date();
  switch (range) {
    case '24h':
      return new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();
    case '7d':
      return new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();
    case '30d':
      return new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString();
    case 'custom':
      return new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();
  }
}

function getGroupBy(range: TimeRange): string {
  switch (range) {
    case '24h': return 'hour';
    case '7d': return 'day';
    case '30d': return 'day';
    case 'custom': return 'day';
  }
}

// ── Analytics store ────────────────────────────────────────

class AnalyticsStore {
  // Panel state
  panelOpen = $state(false);

  // Time range
  timeRange = $state<TimeRange>('24h');

  // Data
  data = $state<AnalyticsResponse | null>(null);
  loading = $state(false);
  error = $state<string | null>(null);

  // Polling
  private pollTimer: ReturnType<typeof setInterval> | null = null;

  // Derived
  todayCost = $derived(this.data?.totals.cost ?? 0);

  // ── Panel control ─────────────────────────────────────────

  openPanel(): void {
    this.panelOpen = true;
    void this.fetchAnalytics();
    this.startPolling();
  }

  closePanel(): void {
    this.panelOpen = false;
    this.stopPolling();
  }

  togglePanel(): void {
    if (this.panelOpen) {
      this.closePanel();
    } else {
      this.openPanel();
    }
  }

  setTimeRange(range: TimeRange): void {
    this.timeRange = range;
    void this.fetchAnalytics();
  }

  // ── Data fetching ─────────────────────────────────────────

  async fetchAnalytics(): Promise<void> {
    this.loading = true;
    this.error = null;

    try {
      const from = getFromDate(this.timeRange);
      const to = new Date().toISOString();
      const groupBy = getGroupBy(this.timeRange);

      const params = new URLSearchParams({ from, to, groupBy });
      const res = await fetch(`/api/analytics?${params}`, {
        credentials: 'include',
      });

      if (!res.ok) {
        throw new Error(`HTTP ${res.status}: ${res.statusText}`);
      }

      this.data = await res.json() as AnalyticsResponse;
    } catch (err) {
      this.error = err instanceof Error ? err.message : 'Failed to fetch analytics';
    } finally {
      this.loading = false;
    }
  }

  // ── Polling ───────────────────────────────────────────────

  private startPolling(): void {
    this.stopPolling();
    this.pollTimer = setInterval(() => {
      if (this.panelOpen) {
        void this.fetchAnalytics();
      }
    }, 30_000);
  }

  private stopPolling(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
  }
}

// Singleton
export const analyticsStore = new AnalyticsStore();
