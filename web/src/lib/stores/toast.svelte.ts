// Toast notification store — Svelte 5 runes
// Provides a simple queue of auto-dismissing toast notifications

export type ToastType = 'info' | 'success' | 'warning' | 'error';

export interface Toast {
  id: string;
  type: ToastType;
  message: string;
  createdAt: number;
}

const DEFAULT_DURATION_MS = 4000;
const ERROR_DURATION_MS = 6000;

let toastId = 0;

class ToastStore {
  toasts = $state<Toast[]>([]);

  addToast(type: ToastType, message: string, durationMs?: number): void {
    const id = `toast-${++toastId}-${Date.now()}`;
    const toast: Toast = { id, type, message, createdAt: Date.now() };
    this.toasts.push(toast);

    const duration = durationMs ?? (type === 'error' ? ERROR_DURATION_MS : DEFAULT_DURATION_MS);
    setTimeout(() => this.removeToast(id), duration);
  }

  removeToast(id: string): void {
    this.toasts = this.toasts.filter((t) => t.id !== id);
  }

  info(message: string): void {
    this.addToast('info', message);
  }

  success(message: string): void {
    this.addToast('success', message);
  }

  warning(message: string): void {
    this.addToast('warning', message);
  }

  error(message: string, durationMs?: number): void {
    this.addToast('error', message, durationMs);
  }
}

export const toasts = new ToastStore();
