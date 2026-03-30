<script lang="ts">
  import { achievementStore, ACHIEVEMENT_CATEGORIES, type AchievementCategory } from '../stores/achievements.svelte';

  // Close on Escape key
  $effect(() => {
    if (!achievementStore.panelOpen) return;
    function onKeydown(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        achievementStore.closePanel();
      }
    }
    window.addEventListener('keydown', onKeydown);
    return () => window.removeEventListener('keydown', onKeydown);
  });

  function formatDate(iso: string | null): string {
    if (!iso) return '';
    const d = new Date(iso);
    return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
  }

  const categoryTabs: { label: string; value: AchievementCategory | 'all' }[] = [
    { label: 'All', value: 'all' },
    ...ACHIEVEMENT_CATEGORIES.map((c) => ({ label: c.label, value: c.id as AchievementCategory })),
  ];
</script>

{#if achievementStore.panelOpen}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="panel-backdrop" onclick={() => achievementStore.closePanel()}>
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="panel" onclick={(e) => e.stopPropagation()}>
      <div class="panel-header">
        <div class="panel-header-left">
          <span class="panel-title">Achievements</span>
        </div>
        <div class="panel-header-right">
          <span class="unlock-summary">{achievementStore.unlockedCount}/{achievementStore.totalCount}</span>
          <button class="panel-close" onclick={() => achievementStore.closePanel()} aria-label="Close">&times;</button>
        </div>
      </div>

      <!-- Category tabs -->
      <div class="category-tabs">
        {#each categoryTabs as tab}
          {@const counts = tab.value === 'all' ? null : achievementStore.categoryCounts[tab.value]}
          <button
            class="category-btn"
            class:active={achievementStore.activeCategory === tab.value}
            onclick={() => achievementStore.setCategory(tab.value)}
          >
            {tab.label}
            {#if counts}
              <span class="category-count">{counts.unlocked}/{counts.total}</span>
            {/if}
          </button>
        {/each}
      </div>

      <div class="panel-body">
        {#if achievementStore.loading && achievementStore.achievements.length === 0}
          <div class="panel-loading">Loading achievements...</div>
        {:else if achievementStore.error}
          <div class="panel-error">{achievementStore.error}</div>
        {:else if achievementStore.filteredAchievements.length > 0}
          <!-- Progress bar -->
          <div class="progress-overview">
            <div class="progress-bar-track">
              <div
                class="progress-bar-fill"
                style:width={achievementStore.totalCount > 0 ? `${(achievementStore.unlockedCount / achievementStore.totalCount) * 100}%` : '0%'}
              ></div>
            </div>
            <span class="progress-label">{Math.round(achievementStore.totalCount > 0 ? (achievementStore.unlockedCount / achievementStore.totalCount) * 100 : 0)}% Complete</span>
          </div>

          <div class="achievement-list">
            {#each achievementStore.filteredAchievements as achievement (achievement.id)}
              <div class="achievement-card" class:unlocked={achievement.unlocked} class:secret={achievement.secret && !achievement.unlocked}>
                <div class="achievement-icon">
                  {#if achievement.secret && !achievement.unlocked}
                    <span class="icon-locked">?</span>
                  {:else}
                    <span class="icon-emoji">{achievement.icon}</span>
                  {/if}
                </div>
                <div class="achievement-info">
                  <div class="achievement-name">
                    {#if achievement.secret && !achievement.unlocked}
                      Secret Achievement
                    {:else}
                      {achievement.name}
                    {/if}
                  </div>
                  <div class="achievement-desc">
                    {#if achievement.secret && !achievement.unlocked}
                      Keep playing to discover this achievement
                    {:else}
                      {achievement.description}
                    {/if}
                  </div>
                  {#if achievement.unlocked}
                    <div class="achievement-date">Unlocked {formatDate(achievement.unlockedAt)}</div>
                  {:else if achievement.target != null && achievement.progress != null && !achievement.secret}
                    <div class="achievement-progress">
                      <div class="progress-track">
                        <div class="progress-fill" style:width={`${achievement.percentage ?? 0}%`}></div>
                      </div>
                      <span class="progress-text">{achievement.progress}/{achievement.target}</span>
                    </div>
                  {/if}
                </div>
                {#if achievement.unlocked}
                  <div class="achievement-check">&#10003;</div>
                {/if}
              </div>
            {/each}
          </div>
        {:else}
          <div class="panel-empty">
            <div class="empty-title">No achievements yet</div>
            <div class="empty-hint">Start a session to begin unlocking achievements</div>
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
    width: min(420px, 92vw);
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

  .unlock-summary {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    font-weight: 700;
    color: var(--accent);
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

  /* Category tabs */
  .category-tabs {
    display: flex;
    gap: 2px;
    padding: var(--sp-xs) var(--sp-sm);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
    overflow-x: auto;
    scrollbar-width: none;
  }
  .category-tabs::-webkit-scrollbar {
    display: none;
  }

  .category-btn {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    font-weight: 600;
    padding: 4px 8px;
    background: transparent;
    border: none;
    color: var(--text-tertiary);
    cursor: pointer;
    border-radius: 3px;
    transition: all 0.15s;
    white-space: nowrap;
    display: flex;
    align-items: center;
    gap: 3px;
  }

  .category-btn:hover {
    color: var(--text-primary);
  }

  .category-btn.active {
    color: var(--bg);
    background: var(--accent);
  }

  .category-count {
    font-size: 0.5rem;
    opacity: 0.7;
  }

  .panel-body {
    flex: 1;
    overflow-y: auto;
    padding: var(--sp-sm) var(--sp-md);
  }

  /* Progress overview */
  .progress-overview {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    padding: var(--sp-sm) 0;
    margin-bottom: var(--sp-sm);
  }

  .progress-bar-track {
    flex: 1;
    height: 6px;
    background: var(--surface);
    border-radius: 3px;
    overflow: hidden;
  }

  .progress-bar-fill {
    height: 100%;
    background: var(--accent);
    border-radius: 3px;
    transition: width 0.3s ease;
  }

  .progress-label {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    font-weight: 600;
    color: var(--text-tertiary);
    flex-shrink: 0;
  }

  /* Achievement list */
  .achievement-list {
    display: flex;
    flex-direction: column;
    gap: var(--sp-xs);
  }

  .achievement-card {
    display: flex;
    align-items: flex-start;
    gap: var(--sp-sm);
    padding: var(--sp-sm) var(--sp-md);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    transition: all 0.15s;
    opacity: 0.5;
  }

  .achievement-card.unlocked {
    opacity: 1;
    border-color: rgba(77, 217, 115, 0.2);
    background: rgba(77, 217, 115, 0.03);
  }

  .achievement-card.secret {
    opacity: 0.35;
    border-style: dashed;
  }

  .achievement-icon {
    flex-shrink: 0;
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: var(--r-sm);
    background: var(--surface);
    font-size: 1.1rem;
    line-height: 1;
  }

  .achievement-card.unlocked .achievement-icon {
    background: rgba(77, 217, 115, 0.1);
  }

  .icon-locked {
    font-family: var(--font-mono);
    font-weight: 700;
    font-size: 0.9rem;
    color: var(--text-tertiary);
  }

  .icon-emoji {
    font-size: 1.1rem;
    line-height: 1;
  }

  .achievement-info {
    flex: 1;
    min-width: 0;
  }

  .achievement-name {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    font-weight: 600;
    color: var(--text-primary);
    line-height: 1.3;
  }

  .achievement-desc {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    color: var(--text-secondary);
    line-height: 1.4;
    margin-top: 1px;
  }

  .achievement-date {
    font-family: var(--font-mono);
    font-size: 0.55rem;
    color: var(--accent);
    margin-top: 3px;
  }

  .achievement-progress {
    display: flex;
    align-items: center;
    gap: var(--sp-xs);
    margin-top: 4px;
  }

  .progress-track {
    flex: 1;
    height: 4px;
    background: var(--surface);
    border-radius: 2px;
    overflow: hidden;
  }

  .progress-fill {
    height: 100%;
    background: var(--accent-dim);
    border-radius: 2px;
    transition: width 0.3s ease;
  }

  .progress-text {
    font-family: var(--font-mono);
    font-size: 0.55rem;
    font-weight: 600;
    color: var(--text-tertiary);
    flex-shrink: 0;
  }

  .achievement-check {
    flex-shrink: 0;
    font-size: 0.75rem;
    color: var(--accent);
    font-weight: 700;
    margin-top: 2px;
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
