<script lang="ts">
  import { analyticsStore, type TimeRange } from '../stores/analytics.svelte';

  // Close on Escape key
  $effect(() => {
    if (!analyticsStore.panelOpen) return;
    function onKeydown(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        analyticsStore.closePanel();
      }
    }
    window.addEventListener('keydown', onKeydown);
    return () => window.removeEventListener('keydown', onKeydown);
  });

  const timeRanges: { label: string; value: TimeRange }[] = [
    { label: '24h', value: '24h' },
    { label: '7d', value: '7d' },
    { label: '30d', value: '30d' },
  ];

  function formatCost(cost: number): string {
    if (cost === 0) return '$0.00';
    if (cost < 0.01) return `$${cost.toFixed(4)}`;
    return `$${cost.toFixed(2)}`;
  }

  function formatTokens(n: number): string {
    if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
    if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
    return String(n);
  }

  // ── Chart helpers ──────────────────────────────────────────

  const chartWidth = 300;
  const chartHeight = 120;
  const barPadding = 2;

  function costBars(data: typeof analyticsStore.data) {
    if (!data || data.timeSeries.length === 0) return [];
    const maxCost = Math.max(...data.timeSeries.map(d => d.cost), 0.001);
    const barWidth = Math.max(
      (chartWidth - barPadding * data.timeSeries.length) / data.timeSeries.length,
      4
    );
    return data.timeSeries.map((d, i) => ({
      x: i * (barWidth + barPadding),
      y: chartHeight - (d.cost / maxCost) * chartHeight,
      width: barWidth,
      height: (d.cost / maxCost) * chartHeight,
      label: d.period,
      cost: d.cost,
    }));
  }

  function tokenBars(data: typeof analyticsStore.data) {
    if (!data || data.timeSeries.length === 0) return [];
    const maxTokens = Math.max(
      ...data.timeSeries.map(d => d.inputTokens + d.outputTokens + d.cacheTokens),
      1
    );
    const barWidth = Math.max(
      (chartWidth - barPadding * data.timeSeries.length) / data.timeSeries.length,
      4
    );
    return data.timeSeries.map((d, i) => {
      const total = d.inputTokens + d.outputTokens + d.cacheTokens;
      const inputH = (d.inputTokens / maxTokens) * chartHeight;
      const outputH = (d.outputTokens / maxTokens) * chartHeight;
      const cacheH = (d.cacheTokens / maxTokens) * chartHeight;
      const x = i * (barWidth + barPadding);
      return {
        x,
        width: barWidth,
        input: { y: chartHeight - inputH, height: inputH },
        output: { y: chartHeight - inputH - outputH, height: outputH },
        cache: { y: chartHeight - inputH - outputH - cacheH, height: cacheH },
        total,
      };
    });
  }

  function modelSlices(data: typeof analyticsStore.data) {
    if (!data || data.byModel.length === 0) return [];
    const totalCost = data.byModel.reduce((s, m) => s + m.cost, 0);
    if (totalCost === 0) return [];

    const colors = ['var(--accent)', '#a78bfa', '#f97316', '#06b6d4', '#84cc16'];
    let startAngle = 0;

    return data.byModel.map((m, i) => {
      const fraction = m.cost / totalCost;
      const angle = fraction * 360;
      const slice = {
        model: m.model,
        cost: m.cost,
        fraction,
        startAngle,
        endAngle: startAngle + angle,
        color: colors[i % colors.length]!,
      };
      startAngle += angle;
      return slice;
    });
  }

  function arcPath(cx: number, cy: number, r: number, startDeg: number, endDeg: number): string {
    const startRad = (startDeg - 90) * Math.PI / 180;
    const endRad = (endDeg - 90) * Math.PI / 180;
    const x1 = cx + r * Math.cos(startRad);
    const y1 = cy + r * Math.sin(startRad);
    const x2 = cx + r * Math.cos(endRad);
    const y2 = cy + r * Math.sin(endRad);
    const largeArc = endDeg - startDeg > 180 ? 1 : 0;
    return `M ${cx} ${cy} L ${x1} ${y1} A ${r} ${r} 0 ${largeArc} 1 ${x2} ${y2} Z`;
  }
</script>

{#if analyticsStore.panelOpen}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="panel-backdrop" onclick={() => analyticsStore.closePanel()}>
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="panel" onclick={(e) => e.stopPropagation()}>
      <div class="panel-header">
        <div class="panel-header-left">
          <span class="panel-title">Analytics</span>
        </div>
        <div class="panel-header-right">
          <div class="time-range-picker">
            {#each timeRanges as tr}
              <button
                class="time-btn"
                class:active={analyticsStore.timeRange === tr.value}
                onclick={() => analyticsStore.setTimeRange(tr.value)}
              >
                {tr.label}
              </button>
            {/each}
          </div>
          <button class="panel-close" onclick={() => analyticsStore.closePanel()} aria-label="Close">&times;</button>
        </div>
      </div>

      <div class="panel-body">
        {#if analyticsStore.loading && !analyticsStore.data}
          <div class="panel-loading">Loading analytics...</div>
        {:else if analyticsStore.error}
          <div class="panel-error">{analyticsStore.error}</div>
        {:else if analyticsStore.data}
          <!-- Totals row -->
          <div class="stats-row">
            <div class="stat">
              <span class="stat-value">{formatCost(analyticsStore.data.totals.cost)}</span>
              <span class="stat-label">total cost</span>
            </div>
            <div class="stat">
              <span class="stat-value">{formatTokens(analyticsStore.data.totals.inputTokens + analyticsStore.data.totals.outputTokens)}</span>
              <span class="stat-label">tokens</span>
            </div>
            <div class="stat">
              <span class="stat-value">{analyticsStore.data.totals.turnCount}</span>
              <span class="stat-label">turns</span>
            </div>
            <div class="stat">
              <span class="stat-value">{analyticsStore.data.totals.sessionCount}</span>
              <span class="stat-label">sessions</span>
            </div>
          </div>

          <!-- Cost over time chart -->
          {#if analyticsStore.data.timeSeries.length > 0}
            <div class="chart-section">
              <div class="chart-title">Cost Over Time</div>
              <svg viewBox="0 0 {chartWidth} {chartHeight}" class="chart-svg">
                {#each costBars(analyticsStore.data) as bar}
                  <rect
                    x={bar.x}
                    y={bar.y}
                    width={bar.width}
                    height={Math.max(bar.height, 1)}
                    fill="var(--accent)"
                    rx="1"
                  >
                    <title>{bar.label}: {formatCost(bar.cost)}</title>
                  </rect>
                {/each}
              </svg>
            </div>
          {/if}

          <!-- Token usage stacked bar -->
          {#if analyticsStore.data.timeSeries.length > 0}
            <div class="chart-section">
              <div class="chart-title">Token Usage</div>
              <div class="chart-legend">
                <span class="legend-item"><span class="legend-dot" style:background="var(--accent)"></span> Input</span>
                <span class="legend-item"><span class="legend-dot" style:background="#a78bfa"></span> Output</span>
                <span class="legend-item"><span class="legend-dot" style:background="var(--text-tertiary)"></span> Cache</span>
              </div>
              <svg viewBox="0 0 {chartWidth} {chartHeight}" class="chart-svg">
                {#each tokenBars(analyticsStore.data) as bar}
                  <rect x={bar.x} y={bar.input.y} width={bar.width} height={Math.max(bar.input.height, 0)} fill="var(--accent)" rx="1">
                    <title>Input: {formatTokens(bar.input.height > 0 ? bar.input.height : 0)}</title>
                  </rect>
                  <rect x={bar.x} y={bar.output.y} width={bar.width} height={Math.max(bar.output.height, 0)} fill="#a78bfa" rx="1">
                    <title>Output</title>
                  </rect>
                  <rect x={bar.x} y={bar.cache.y} width={bar.width} height={Math.max(bar.cache.height, 0)} fill="var(--text-tertiary)" rx="1">
                    <title>Cache</title>
                  </rect>
                {/each}
              </svg>
            </div>
          {/if}

          <!-- Model distribution donut -->
          {#if analyticsStore.data.byModel.length > 0}
            <div class="chart-section">
              <div class="chart-title">Model Distribution</div>
              <div class="donut-row">
                <svg viewBox="0 0 100 100" class="donut-svg">
                  {#each modelSlices(analyticsStore.data) as slice}
                    {#if slice.endAngle - slice.startAngle >= 359.9}
                      <circle cx="50" cy="50" r="40" fill={slice.color}>
                        <title>{slice.model}: {formatCost(slice.cost)} ({(slice.fraction * 100).toFixed(1)}%)</title>
                      </circle>
                    {:else}
                      <path
                        d={arcPath(50, 50, 40, slice.startAngle, slice.endAngle)}
                        fill={slice.color}
                      >
                        <title>{slice.model}: {formatCost(slice.cost)} ({(slice.fraction * 100).toFixed(1)}%)</title>
                      </path>
                    {/if}
                  {/each}
                  <circle cx="50" cy="50" r="22" fill="var(--bg)" />
                </svg>
                <div class="donut-legend">
                  {#each modelSlices(analyticsStore.data) as slice}
                    <div class="donut-legend-item">
                      <span class="legend-dot" style:background={slice.color}></span>
                      <span class="donut-model">{slice.model.split('-').slice(-2).join('-')}</span>
                      <span class="donut-cost">{formatCost(slice.cost)}</span>
                    </div>
                  {/each}
                </div>
              </div>
            </div>
          {/if}

          <!-- Per-session cost ranking -->
          {#if analyticsStore.data.bySession.length > 0}
            <div class="chart-section">
              <div class="chart-title">Session Costs</div>
              <div class="session-list">
                {#each analyticsStore.data.bySession.slice(0, 10) as session}
                  <div class="session-row">
                    <span class="session-dir" title={session.workingDir}>{session.workingDir.split('/').pop() ?? session.sessionId.slice(0, 8)}</span>
                    <span class="session-cost">{formatCost(session.totalCost)}</span>
                    <span class="session-tokens">{formatTokens(session.totalTokens)}</span>
                    <span class="session-turns">{session.turnCount}t</span>
                  </div>
                {/each}
              </div>
            </div>
          {/if}

          <!-- Top tools -->
          {#if analyticsStore.data.byTool.length > 0}
            <div class="chart-section">
              <div class="chart-title">Top Tools</div>
              <div class="tool-list">
                {#each analyticsStore.data.byTool.slice(0, 10) as tool}
                  <div class="tool-row">
                    <span class="tool-name">{tool.tool}</span>
                    <span class="tool-count">{tool.count}x</span>
                  </div>
                {/each}
              </div>
            </div>
          {/if}
        {:else}
          <div class="panel-empty">
            <div class="empty-title">No analytics data</div>
            <div class="empty-hint">Data will appear after your first session</div>
          </div>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .panel-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.45);
    z-index: 200;
  }

  .panel {
    position: fixed;
    top: 0;
    right: 0;
    bottom: 0;
    width: min(400px, 92vw);
    background: var(--bg);
    border-left: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    box-shadow: -4px 0 24px rgba(0, 0, 0, 0.4);
    animation: slide-in-right 0.2s ease-out;
  }

  @keyframes slide-in-right {
    from { transform: translateX(100%); }
    to { transform: translateX(0); }
  }

  .panel-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--sp-md) var(--sp-lg);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  .panel-header-left {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
  }

  .panel-header-right {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
  }

  .panel-title {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--text-primary);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .time-range-picker {
    display: flex;
    gap: 2px;
    background: var(--surface);
    border-radius: var(--r-sm);
    padding: 2px;
  }

  .time-btn {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    font-weight: 600;
    padding: 3px 8px;
    background: transparent;
    border: none;
    color: var(--text-tertiary);
    cursor: pointer;
    border-radius: 3px;
    transition: all 0.15s;
  }

  .time-btn:hover {
    color: var(--text-primary);
  }

  .time-btn.active {
    color: var(--bg);
    background: var(--accent);
  }

  .panel-close {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    font-size: 1.3rem;
    cursor: pointer;
    padding: 0 var(--sp-xs);
    line-height: 1;
  }
  .panel-close:hover {
    color: var(--text-primary);
  }

  .panel-body {
    flex: 1;
    overflow-y: auto;
    padding: var(--sp-sm) var(--sp-md);
  }

  /* Stats row */
  .stats-row {
    display: flex;
    align-items: center;
    gap: var(--sp-md);
    padding: var(--sp-sm) 0;
    border-bottom: 1px solid var(--border);
    margin-bottom: var(--sp-sm);
    flex-wrap: wrap;
  }

  .stat {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 1px;
  }

  .stat-value {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    font-weight: 700;
    color: var(--text-primary);
  }

  .stat-label {
    font-family: var(--font-mono);
    font-size: 0.55rem;
    font-weight: 500;
    color: var(--text-tertiary);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  /* Chart sections */
  .chart-section {
    margin-bottom: var(--sp-md);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    padding: var(--sp-sm) var(--sp-md);
  }

  .chart-title {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    font-weight: 600;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    margin-bottom: var(--sp-sm);
  }

  .chart-svg {
    width: 100%;
    height: auto;
  }

  .chart-legend {
    display: flex;
    gap: var(--sp-sm);
    margin-bottom: var(--sp-xs);
    font-family: var(--font-mono);
    font-size: 0.55rem;
    color: var(--text-tertiary);
  }

  .legend-item {
    display: flex;
    align-items: center;
    gap: 3px;
  }

  .legend-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  /* Donut chart */
  .donut-row {
    display: flex;
    align-items: center;
    gap: var(--sp-md);
  }

  .donut-svg {
    width: 100px;
    height: 100px;
    flex-shrink: 0;
  }

  .donut-legend {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .donut-legend-item {
    display: flex;
    align-items: center;
    gap: var(--sp-xs);
    font-family: var(--font-mono);
    font-size: 0.6rem;
  }

  .donut-model {
    color: var(--text-secondary);
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .donut-cost {
    color: var(--text-primary);
    font-weight: 600;
    flex-shrink: 0;
  }

  /* Session list */
  .session-list, .tool-list {
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .session-row {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    font-family: var(--font-mono);
    font-size: 0.65rem;
    padding: 4px var(--sp-xs);
    border-radius: 3px;
  }

  .session-row:hover {
    background: var(--surface-hover);
  }

  .session-dir {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    color: var(--text-primary);
    font-weight: 600;
  }

  .session-cost {
    color: var(--accent);
    font-weight: 600;
    flex-shrink: 0;
  }

  .session-tokens {
    color: var(--text-tertiary);
    flex-shrink: 0;
  }

  .session-turns {
    color: var(--text-tertiary);
    flex-shrink: 0;
    min-width: 20px;
    text-align: right;
  }

  .tool-row {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    font-family: var(--font-mono);
    font-size: 0.65rem;
    padding: 3px var(--sp-xs);
    border-radius: 3px;
  }

  .tool-row:hover {
    background: var(--surface-hover);
  }

  .tool-name {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    color: var(--text-primary);
  }

  .tool-count {
    color: var(--accent);
    font-weight: 600;
    flex-shrink: 0;
  }

  /* Empty / loading / error states */
  .panel-loading, .panel-error, .panel-empty {
    padding: var(--sp-xl);
    text-align: center;
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--text-tertiary);
  }

  .panel-error {
    color: var(--deny);
  }

  .empty-title {
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--text-secondary);
    margin-bottom: var(--sp-xs);
  }

  .empty-hint {
    font-size: 0.7rem;
    color: var(--text-tertiary);
  }
</style>
