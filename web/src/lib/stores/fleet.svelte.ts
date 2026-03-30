// Fleet store — reactive state for fleet-level visibility across all workers and sessions
// Uses Svelte 5 runes ($state, $derived)

import type {
  FleetStatusResponseMessage,
  FleetWorkerSpawnedMessage,
  FleetWorkerCrashedMessage,
  FleetWorkerRestartedMessage,
  FleetWorkerInfo,
} from '../protocol/messages';

// ── Fleet health summary ────────────────────────────────────

export type FleetHealth = 'healthy' | 'degraded' | 'critical' | 'empty';

// ── Fleet store ─────────────────────────────────────────────

class FleetStore {
  // Core state
  totalWorkers = $state(0);
  totalSessions = $state(0);
  aggregateCost = $state(0);
  aggregateTokens = $state({ input: 0, output: 0 });
  workers = $state<FleetWorkerInfo[]>([]);

  // Panel visibility
  panelOpen = $state(false);

  // Polling
  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private requestFn: (() => void) | null = null;

  // Derived
  health = $derived<FleetHealth>(computeHealth(this.workers, this.totalWorkers));

  // ── Message handlers ──────────────────────────────────────

  handleStatusResponse(msg: FleetStatusResponseMessage): void {
    this.totalWorkers = msg.totalWorkers;
    this.totalSessions = msg.totalSessions;
    this.aggregateCost = msg.aggregateCost;
    this.aggregateTokens = { ...msg.aggregateTokens };
    this.workers = msg.workers;
  }

  handleWorkerSpawned(msg: FleetWorkerSpawnedMessage): void {
    // Dedupe by workerId AND workingDir (restart flow gives new workerId for same dir)
    const existingById = this.workers.find(w => w.workerId === msg.workerId);
    const existingByDir = this.workers.find(w => w.workingDir === msg.workingDir);
    if (!existingById && !existingByDir) {
      // Genuinely new worker
      this.workers = [...this.workers, {
        workerId: msg.workerId,
        workingDir: msg.workingDir,
        dirName: msg.dirName,
        sessionCount: 0,
        uptimeMs: 0,
        restartCount: 0,
        healthy: true,
        sessions: [],
      }];
      this.totalWorkers = this.workers.length;
    } else if (existingByDir && !existingById) {
      // Restart: same dir, new workerId — update in place
      this.workers = this.workers.map(w =>
        w.workingDir === msg.workingDir
          ? { ...w, workerId: msg.workerId, healthy: true }
          : w
      );
    }
  }

  handleWorkerCrashed(msg: FleetWorkerCrashedMessage): void {
    // Mark the worker as unhealthy
    this.workers = this.workers.map(w =>
      w.workerId === msg.workerId
        ? { ...w, healthy: false, restartCount: msg.restartCount }
        : w
    );
  }

  handleWorkerRestarted(msg: FleetWorkerRestartedMessage): void {
    // Update the worker entry with the new workerId and mark healthy
    // The old workerId is gone — find by dirName since the worker was restarted for the same dir
    const idx = this.workers.findIndex(w => w.workingDir === msg.workingDir);
    if (idx >= 0) {
      const updated = [...this.workers];
      updated[idx] = {
        ...updated[idx]!,
        workerId: msg.workerId,
        healthy: true,
        restartCount: msg.restartCount,
        uptimeMs: 0,
      };
      this.workers = updated;
    }
  }

  // ── Panel control ─────────────────────────────────────────

  openPanel(): void {
    this.panelOpen = true;
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

  // ── Polling ───────────────────────────────────────────────

  /** Set the function to call when requesting fleet status */
  setRequestFn(fn: () => void): void {
    this.requestFn = fn;
  }

  requestFleetStatus(): void {
    this.requestFn?.();
  }

  private startPolling(): void {
    this.stopPolling();
    // Immediately request
    this.requestFleetStatus();
    // Then poll every 5 seconds
    this.pollTimer = setInterval(() => {
      if (this.panelOpen) {
        this.requestFleetStatus();
      }
    }, 5000);
  }

  private stopPolling(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
  }
}

// ── Helpers ─────────────────────────────────────────────────

function computeHealth(workers: FleetWorkerInfo[], totalWorkers: number): FleetHealth {
  if (totalWorkers === 0) return 'empty';
  const unhealthyCount = workers.filter(w => !w.healthy).length;
  if (unhealthyCount === 0) return 'healthy';
  if (unhealthyCount === totalWorkers) return 'critical';
  return 'degraded';
}

// Singleton
export const fleetStore = new FleetStore();
