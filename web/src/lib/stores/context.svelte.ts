// Context store — manages workspace file tree and attached context files
// Uses Svelte 5 runes ($state)

import type {
  FileNode,
  ContextAddResponseMessage,
  ContextRemoveResponseMessage,
} from '../protocol/messages';
import { toasts } from './toast.svelte';

// ── Context file info ───────────────────────────────────────

export interface ContextFileInfo {
  path: string;
  size: number;
}

// ── Context store ───────────────────────────────────────────

class ContextStore {
  contextFiles = $state<ContextFileInfo[]>([]);
  treeCache = $state<FileNode[]>([]);
  isLoadingTree = $state(false);
  totalContextSize = $state(0);

  // ── Tree response handling ──────────────────────────────

  handleTreeResponse(nodes: FileNode[]): void {
    this.treeCache = nodes;
    this.isLoadingTree = false;
  }

  // ── Context add/remove response handling ────────────────

  handleContextAddResponse(response: ContextAddResponseMessage): void {
    if (response.success) {
      // Add to local list if not already present
      const exists = this.contextFiles.some((f) => f.path === response.path);
      if (!exists) {
        this.contextFiles.push({
          path: response.path,
          size: 0, // We don't know exact size client-side, relay tracks it
        });
      }
      this.totalContextSize = response.totalContextSize;
    } else {
      toasts.error(response.error ?? `Failed to add ${response.path}`);
    }
  }

  handleContextRemoveResponse(response: ContextRemoveResponseMessage): void {
    if (response.success) {
      this.contextFiles = this.contextFiles.filter((f) => f.path !== response.path);
      this.totalContextSize = response.totalContextSize;
    }
  }

  // ── Helpers ─────────────────────────────────────────────

  isFileAttached(path: string): boolean {
    return this.contextFiles.some((f) => f.path === path);
  }

  clear(): void {
    this.contextFiles = [];
    this.treeCache = [];
    this.isLoadingTree = false;
    this.totalContextSize = 0;
  }

  /** Format total context size for display */
  get formattedSize(): string {
    if (this.totalContextSize === 0) return '0 B';
    if (this.totalContextSize < 1024) return `${this.totalContextSize} B`;
    return `${(this.totalContextSize / 1024).toFixed(1)} KB`;
  }

  /** Max context size for display */
  get maxSizeFormatted(): string {
    return '200 KB';
  }
}

// Singleton
export const contextStore = new ContextStore();
