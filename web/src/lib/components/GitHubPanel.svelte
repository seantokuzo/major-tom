<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import type { GitHubPullRequestEntry, GitHubIssueEntry } from '../protocol/messages';

  type Tab = 'prs' | 'issues';
  type StateFilter = 'open' | 'closed' | 'all';
  let activeTab = $state<Tab>('prs');
  let prFilter = $state<StateFilter>('open');
  let issueFilter = $state<StateFilter>('open');
  let expandedPR = $state<number | null>(null);
  let expandedIssue = $state<number | null>(null);

  function close() {
    relay.githubPanelOpen = false;
    activeTab = 'prs';
    prFilter = 'open';
    issueFilter = 'open';
    expandedPR = null;
    expandedIssue = null;
    relay.githubError = null;
  }

  // Fetch data when panel opens, using current filter state
  $effect(() => {
    if (!relay.githubPanelOpen || !relay.sessionId) return;
    relay.requestGitHubPullRequests(prFilter);
    relay.requestGitHubIssues(issueFilter);
  });

  $effect(() => {
    if (!relay.githubPanelOpen) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') close();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  function refresh() {
    if (activeTab === 'prs') {
      relay.requestGitHubPullRequests(prFilter);
    } else {
      relay.requestGitHubIssues(issueFilter);
    }
  }

  function setPRFilter(filter: StateFilter) {
    prFilter = filter;
    expandedPR = null;
    relay.requestGitHubPullRequests(filter);
  }

  function setIssueFilter(filter: StateFilter) {
    issueFilter = filter;
    expandedIssue = null;
    relay.requestGitHubIssues(filter);
  }

  function selectPR(pr: GitHubPullRequestEntry) {
    if (expandedPR === pr.number) {
      expandedPR = null;
      return;
    }
    expandedPR = pr.number;
    relay.requestGitHubPullRequestDetail(pr.number);
  }

  function selectIssue(issue: GitHubIssueEntry) {
    if (expandedIssue === issue.number) {
      expandedIssue = null;
      return;
    }
    expandedIssue = issue.number;
    relay.requestGitHubIssueDetail(issue.number);
  }

  function timeAgo(dateStr: string): string {
    const diff = Date.now() - new Date(dateStr).getTime();
    const mins = Math.floor(diff / 60000);
    if (mins < 1) return 'just now';
    if (mins < 60) return `${mins}m ago`;
    const hrs = Math.floor(mins / 60);
    if (hrs < 24) return `${hrs}h ago`;
    const days = Math.floor(hrs / 24);
    if (days < 30) return `${days}d ago`;
    return new Date(dateStr).toLocaleDateString();
  }

  function prStateClass(pr: GitHubPullRequestEntry): string {
    if (pr.draft) return 'draft';
    return pr.state;
  }

  function prStateLabel(pr: GitHubPullRequestEntry): string {
    if (pr.draft) return 'Draft';
    if (pr.state === 'open') return 'Open';
    if (pr.state === 'merged') return 'Merged';
    return 'Closed';
  }

  function checkIcon(conclusion: string): string {
    if (conclusion === 'success') return '\u2713';
    if (conclusion === 'failure') return '\u2717';
    return '\u25CB';
  }

  function checkClass(conclusion: string): string {
    if (conclusion === 'success') return 'check-pass';
    if (conclusion === 'failure') return 'check-fail';
    return 'check-pending';
  }

  function reviewStateClass(state: string): string {
    const s = state.toLowerCase();
    if (s === 'approved') return 'review-approved';
    if (s === 'changes_requested') return 'review-changes';
    if (s === 'commented') return 'review-commented';
    return 'review-pending';
  }

  function reviewStateLabel(state: string): string {
    const s = state.toLowerCase();
    if (s === 'approved') return 'Approved';
    if (s === 'changes_requested') return 'Changes Requested';
    if (s === 'commented') return 'Commented';
    if (s === 'dismissed') return 'Dismissed';
    return state;
  }
</script>

{#if relay.githubPanelOpen}
  <div class="panel-backdrop" role="button" tabindex="0" aria-label="Close GitHub panel" onclick={close} onkeydown={(e) => { if (e.key === 'Escape' || e.key === 'Enter' || e.key === ' ') { e.preventDefault(); close(); } }}>
    <div class="panel" role="dialog" aria-label="GitHub panel" onclick={(e) => e.stopPropagation()} onkeydown={() => {}}>
      <div class="panel-header">
        <span class="panel-title">
          <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor" class="title-icon">
            <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/>
          </svg>
          GitHub
        </span>
        <div class="header-actions">
          <button class="refresh-btn" onclick={refresh} title="Refresh">&#x21bb;</button>
          <button class="panel-close" onclick={close}>&times;</button>
        </div>
      </div>

      <div class="tabs">
        <button class="tab" class:active={activeTab === 'prs'} onclick={() => activeTab = 'prs'}>
          Pull Requests
          {#if relay.githubPullRequests.length > 0}
            <span class="tab-count">{relay.githubPullRequests.length}</span>
          {/if}
        </button>
        <button class="tab" class:active={activeTab === 'issues'} onclick={() => activeTab = 'issues'}>
          Issues
          {#if relay.githubIssues.length > 0}
            <span class="tab-count">{relay.githubIssues.length}</span>
          {/if}
        </button>
      </div>

      {#if relay.githubError}
        <div class="error-bar">{relay.githubError}</div>
      {/if}

      <div class="panel-body">
        {#if activeTab === 'prs'}
          <div class="filter-bar">
            <button class="filter-btn" class:active={prFilter === 'open'} onclick={() => setPRFilter('open')}>Open</button>
            <button class="filter-btn" class:active={prFilter === 'closed'} onclick={() => setPRFilter('closed')}>Closed</button>
            <button class="filter-btn" class:active={prFilter === 'all'} onclick={() => setPRFilter('all')}>All</button>
          </div>

          {#if relay.githubPullRequests.length === 0}
            <div class="panel-empty">No pull requests</div>
          {:else}
            {#each relay.githubPullRequests as pr (pr.number)}
              <button class="pr-row" onclick={() => selectPR(pr)}>
                <div class="pr-top">
                  <span class="pr-number">#{pr.number}</span>
                  <span class="state-badge {prStateClass(pr)}">{prStateLabel(pr)}</span>
                  <span class="pr-time">{timeAgo(pr.createdAt)}</span>
                </div>
                <div class="pr-title">{pr.title}</div>
                <div class="pr-meta">
                  <span class="pr-author">{pr.author}</span>
                  <span class="pr-branch">{pr.headBranch} &rarr; {pr.baseBranch}</span>
                </div>
                <div class="pr-stats">
                  <span class="additions">+{pr.additions}</span>
                  <span class="deletions">-{pr.deletions}</span>
                  {#if pr.reviewDecision}
                    <span class="review-decision">{pr.reviewDecision}</span>
                  {/if}
                </div>
              </button>
              {#if expandedPR === pr.number && relay.githubPullRequestDetail?.number === pr.number}
                {@const detail = relay.githubPullRequestDetail}
                <div class="detail-block">
                  {#if detail.body}
                    <div class="detail-body">{detail.body}</div>
                  {/if}

                  {#if detail.checks.length > 0}
                    <div class="detail-section-header">CI Checks</div>
                    {#each detail.checks as check (check.name)}
                      <div class="check-row">
                        <span class="check-icon {checkClass(check.conclusion)}">{checkIcon(check.conclusion)}</span>
                        <span class="check-name">{check.name}</span>
                        <span class="check-status">{check.conclusion || check.status}</span>
                      </div>
                    {/each}
                  {/if}

                  {#if detail.reviews.length > 0}
                    <div class="detail-section-header">Reviews</div>
                    {#each detail.reviews as review (review.author + review.submittedAt)}
                      <div class="review-row">
                        <span class="review-badge {reviewStateClass(review.state)}">{reviewStateLabel(review.state)}</span>
                        <span class="review-author">{review.author}</span>
                        <span class="review-time">{timeAgo(review.submittedAt)}</span>
                      </div>
                      {#if review.body}
                        <div class="review-body">{review.body}</div>
                      {/if}
                    {/each}
                  {/if}

                  {#if detail.comments.length > 0}
                    <div class="detail-section-header">Comments ({detail.comments.length})</div>
                    {#each detail.comments as comment (comment.author + comment.createdAt)}
                      <div class="comment-row">
                        <div class="comment-meta">
                          <span class="comment-author">{comment.author}</span>
                          <span class="comment-time">{timeAgo(comment.createdAt)}</span>
                        </div>
                        <div class="comment-body">{comment.body}</div>
                      </div>
                    {/each}
                  {/if}
                </div>
              {/if}
            {/each}
          {/if}

        {:else if activeTab === 'issues'}
          <div class="filter-bar">
            <button class="filter-btn" class:active={issueFilter === 'open'} onclick={() => setIssueFilter('open')}>Open</button>
            <button class="filter-btn" class:active={issueFilter === 'closed'} onclick={() => setIssueFilter('closed')}>Closed</button>
            <button class="filter-btn" class:active={issueFilter === 'all'} onclick={() => setIssueFilter('all')}>All</button>
          </div>

          {#if relay.githubIssues.length === 0}
            <div class="panel-empty">No issues</div>
          {:else}
            {#each relay.githubIssues as issue (issue.number)}
              <button class="issue-row" onclick={() => selectIssue(issue)}>
                <div class="issue-top">
                  <span class="issue-number">#{issue.number}</span>
                  <span class="state-badge {issue.state}">{issue.state === 'open' ? 'Open' : 'Closed'}</span>
                  <span class="issue-time">{timeAgo(issue.createdAt)}</span>
                </div>
                <div class="issue-title">{issue.title}</div>
                <div class="issue-meta">
                  <span class="issue-author">{issue.author}</span>
                  {#if issue.commentCount > 0}
                    <span class="comment-count">{issue.commentCount} comments</span>
                  {/if}
                </div>
                {#if issue.labels.length > 0}
                  <div class="issue-labels">
                    {#each issue.labels as label (label)}
                      <span class="label-pill">{label}</span>
                    {/each}
                  </div>
                {/if}
                {#if issue.assignees.length > 0}
                  <div class="issue-assignees">
                    {#each issue.assignees as assignee (assignee)}
                      <span class="assignee">{assignee}</span>
                    {/each}
                  </div>
                {/if}
              </button>
              {#if expandedIssue === issue.number && relay.githubIssueDetail?.number === issue.number}
                {@const detail = relay.githubIssueDetail}
                <div class="detail-block">
                  {#if detail.body}
                    <div class="detail-body">{detail.body}</div>
                  {/if}

                  {#if detail.comments.length > 0}
                    <div class="detail-section-header">Comments ({detail.comments.length})</div>
                    {#each detail.comments as comment (comment.author + comment.createdAt)}
                      <div class="comment-row">
                        <div class="comment-meta">
                          <span class="comment-author">{comment.author}</span>
                          <span class="comment-time">{timeAgo(comment.createdAt)}</span>
                        </div>
                        <div class="comment-body">{comment.body}</div>
                      </div>
                    {/each}
                  {/if}
                </div>
              {/if}
            {/each}
          {/if}
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .panel-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.45);
    z-index: 200;
  }
  .panel {
    position: fixed;
    top: 0;
    right: 0;
    bottom: 0;
    width: min(480px, 95vw);
    background: var(--bg);
    border-left: 1px solid var(--border);
    box-shadow: -4px 0 24px rgba(0,0,0,0.4);
    animation: slide-in-right 0.2s ease-out;
    display: flex;
    flex-direction: column;
  }
  @keyframes slide-in-right {
    from { transform: translateX(100%); }
    to { transform: translateX(0); }
  }
  .panel-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 16px;
    border-bottom: 1px solid var(--border);
  }
  .panel-title {
    font-weight: 600;
    font-size: 0.9rem;
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .title-icon {
    opacity: 0.8;
  }
  .header-actions {
    display: flex;
    gap: 8px;
    align-items: center;
  }
  .refresh-btn, .panel-close {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    cursor: pointer;
    font-size: 1.1rem;
    padding: 2px 6px;
    border-radius: 4px;
  }
  .refresh-btn:hover, .panel-close:hover {
    color: var(--text-primary);
    background: var(--surface-hover);
  }
  .tabs {
    display: flex;
    border-bottom: 1px solid var(--border);
    padding: 0 16px;
  }
  .tab {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    padding: 8px 12px;
    cursor: pointer;
    font-size: 0.75rem;
    font-family: var(--font-mono, monospace);
    border-bottom: 2px solid transparent;
    display: flex;
    align-items: center;
    gap: 4px;
    transition: all 0.15s;
  }
  .tab:hover { color: var(--text-primary); }
  .tab.active {
    color: var(--accent);
    border-bottom-color: var(--accent);
  }
  .tab-count {
    background: var(--surface-hover);
    padding: 0 5px;
    border-radius: 8px;
    font-size: 0.65rem;
  }
  .error-bar {
    padding: 6px 16px;
    background: rgba(245, 160, 160, 0.15);
    color: #f5a0a0;
    font-size: 0.75rem;
    font-family: var(--font-mono, monospace);
  }
  .filter-bar {
    display: flex;
    gap: 4px;
    padding: 8px 16px;
    border-bottom: 1px solid var(--border);
  }
  .filter-btn {
    background: transparent;
    border: 1px solid var(--border);
    color: var(--text-secondary);
    padding: 3px 10px;
    border-radius: 4px;
    cursor: pointer;
    font-size: 0.7rem;
    font-family: var(--font-mono, monospace);
    transition: all 0.15s;
  }
  .filter-btn:hover {
    color: var(--text-primary);
    border-color: var(--text-secondary);
  }
  .filter-btn.active {
    color: var(--accent);
    border-color: var(--accent);
    background: rgba(77, 217, 115, 0.08);
  }
  .panel-body {
    flex: 1;
    overflow-y: auto;
    padding: 0;
  }
  .panel-empty {
    padding: 32px 16px;
    text-align: center;
    color: var(--text-secondary);
    font-size: 0.8rem;
  }

  /* ── PR rows ─────────────────────────────── */
  .pr-row, .issue-row {
    display: flex;
    flex-direction: column;
    gap: 3px;
    padding: 10px 16px;
    width: 100%;
    text-align: left;
    background: transparent;
    border: none;
    color: var(--text-primary);
    cursor: pointer;
    border-bottom: 1px solid var(--border);
    transition: background 0.1s;
  }
  .pr-row:hover, .issue-row:hover { background: var(--surface-hover); }
  .pr-top, .issue-top {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .pr-number, .issue-number {
    font-family: var(--font-mono, monospace);
    font-size: 0.7rem;
    color: var(--accent);
    font-weight: 600;
  }
  .pr-time, .issue-time {
    font-size: 0.65rem;
    color: var(--text-secondary);
    margin-left: auto;
  }
  .state-badge {
    font-size: 0.6rem;
    font-weight: 700;
    padding: 1px 6px;
    border-radius: 8px;
    text-transform: uppercase;
    letter-spacing: 0.03em;
    line-height: 1.4;
  }
  .state-badge.open { background: rgba(35, 134, 54, 0.2); color: #238636; }
  .state-badge.merged { background: rgba(137, 87, 229, 0.2); color: #8957e5; }
  .state-badge.closed { background: rgba(218, 54, 51, 0.2); color: #da3633; }
  .state-badge.draft { background: rgba(118, 131, 144, 0.2); color: #768390; }
  .pr-title, .issue-title {
    font-size: 0.8rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .pr-meta, .issue-meta {
    display: flex;
    gap: 8px;
    align-items: center;
    font-size: 0.65rem;
    color: var(--text-secondary);
  }
  .pr-author, .issue-author {
    font-weight: 500;
  }
  .pr-branch {
    font-family: var(--font-mono, monospace);
    font-size: 0.6rem;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    max-width: 200px;
  }
  .pr-stats {
    display: flex;
    gap: 8px;
    align-items: center;
    font-size: 0.65rem;
    font-family: var(--font-mono, monospace);
  }
  .additions { color: #a3e6b7; }
  .deletions { color: #f5a0a0; }
  .review-decision {
    color: var(--text-secondary);
    font-size: 0.6rem;
  }
  .comment-count {
    color: var(--text-secondary);
  }

  /* ── Issue labels & assignees ─────────────── */
  .issue-labels {
    display: flex;
    gap: 4px;
    flex-wrap: wrap;
    margin-top: 2px;
  }
  .label-pill {
    font-size: 0.6rem;
    font-weight: 600;
    padding: 1px 6px;
    border-radius: 8px;
    background: rgba(200, 200, 220, 0.15);
    color: var(--text-secondary);
    line-height: 1.4;
  }
  .issue-assignees {
    display: flex;
    gap: 4px;
    font-size: 0.65rem;
    color: var(--text-secondary);
  }
  .assignee::before {
    content: '@';
    opacity: 0.5;
  }

  /* ── Detail block ────────────────────────── */
  .detail-block {
    margin: 0 8px 8px;
    border: 1px solid var(--border);
    border-radius: 4px;
    overflow: hidden;
    background: var(--bg);
  }
  .detail-body {
    padding: 10px 12px;
    font-size: 0.75rem;
    line-height: 1.5;
    color: var(--text-primary);
    white-space: pre-wrap;
    word-break: break-word;
    border-bottom: 1px solid var(--border);
    max-height: 300px;
    overflow-y: auto;
  }
  .detail-section-header {
    padding: 8px 12px 4px;
    font-size: 0.65rem;
    font-weight: 600;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.5px;
    border-top: 1px solid var(--border);
  }

  /* ── Checks ──────────────────────────────── */
  .check-row {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 4px 12px;
    font-size: 0.7rem;
    font-family: var(--font-mono, monospace);
  }
  .check-icon {
    font-size: 0.8rem;
    width: 16px;
    text-align: center;
    flex-shrink: 0;
  }
  .check-icon.check-pass { color: #238636; }
  .check-icon.check-fail { color: #da3633; }
  .check-icon.check-pending { color: #768390; }
  .check-name {
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .check-status {
    font-size: 0.65rem;
    color: var(--text-secondary);
    flex-shrink: 0;
  }

  /* ── Reviews ─────────────────────────────── */
  .review-row {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 12px;
    font-size: 0.7rem;
  }
  .review-badge {
    font-size: 0.6rem;
    font-weight: 700;
    padding: 1px 6px;
    border-radius: 8px;
    line-height: 1.4;
  }
  .review-badge.review-approved { background: rgba(35, 134, 54, 0.2); color: #238636; }
  .review-badge.review-changes { background: rgba(218, 54, 51, 0.2); color: #da3633; }
  .review-badge.review-commented { background: rgba(200, 200, 220, 0.15); color: var(--text-secondary); }
  .review-badge.review-pending { background: rgba(118, 131, 144, 0.2); color: #768390; }
  .review-author {
    font-weight: 500;
  }
  .review-time {
    font-size: 0.65rem;
    color: var(--text-secondary);
    margin-left: auto;
  }
  .review-body {
    padding: 2px 12px 6px 32px;
    font-size: 0.7rem;
    color: var(--text-secondary);
    white-space: pre-wrap;
    word-break: break-word;
  }

  /* ── Comments ────────────────────────────── */
  .comment-row {
    padding: 6px 12px;
    border-top: 1px solid var(--border);
  }
  .comment-row:first-child {
    border-top: none;
  }
  .comment-meta {
    display: flex;
    gap: 8px;
    align-items: center;
    font-size: 0.65rem;
    margin-bottom: 2px;
  }
  .comment-author {
    font-weight: 600;
    color: var(--text-primary);
  }
  .comment-time {
    color: var(--text-secondary);
  }
  .comment-body {
    font-size: 0.7rem;
    line-height: 1.5;
    color: var(--text-secondary);
    white-space: pre-wrap;
    word-break: break-word;
  }
</style>
