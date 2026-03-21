import { randomInt } from 'node:crypto';

interface ActivePin {
  pin: string;
  expiresAt: Date;
  claimed: boolean;
  claimedByDevice?: string;
}

interface AttemptRecord {
  count: number;
  windowStart: number;
}

const PIN_EXPIRY_MS = 5 * 60 * 1000; // 5 minutes
const RATE_LIMIT_WINDOW_MS = 10 * 60 * 1000; // 10 minutes
const RATE_LIMIT_MAX_ATTEMPTS = 5;

export class PinManager {
  private activePin: ActivePin | null = null;
  private attempts = new Map<string, AttemptRecord>();

  /**
   * Generate a 6-digit PIN. Only one active PIN at a time — previous is invalidated.
   */
  generatePin(): { pin: string; expiresAt: Date } {
    const pin = String(randomInt(0, 1_000_000)).padStart(6, '0');
    const expiresAt = new Date(Date.now() + PIN_EXPIRY_MS);

    this.activePin = { pin, expiresAt, claimed: false };

    return { pin, expiresAt };
  }

  /**
   * Check if a PIN is valid (matches active, not expired, not claimed).
   */
  validatePin(pin: string): boolean {
    if (!this.activePin) return false;
    if (this.activePin.claimed) return false;
    if (Date.now() > this.activePin.expiresAt.getTime()) return false;
    return this.activePin.pin === pin;
  }

  /**
   * Validate and consume (one-time use). Returns true if valid.
   * Optionally records which device claimed it.
   */
  consumePin(pin: string, deviceName?: string): boolean {
    if (!this.validatePin(pin)) return false;
    this.activePin!.claimed = true;
    this.activePin!.claimedByDevice = deviceName;
    return true;
  }

  /**
   * Check if the active PIN has been claimed, and by whom.
   */
  getClaimStatus(): { claimed: boolean; deviceName?: string } {
    if (!this.activePin) return { claimed: false };
    return {
      claimed: this.activePin.claimed,
      deviceName: this.activePin.claimedByDevice,
    };
  }

  /**
   * Check if the active PIN is still valid (not expired, not claimed).
   */
  isActive(): boolean {
    if (!this.activePin) return false;
    if (this.activePin.claimed) return false;
    return Date.now() <= this.activePin.expiresAt.getTime();
  }

  /**
   * Check rate limit for a given IP. Max 5 failed attempts per 10-minute window.
   */
  checkRateLimit(ip: string): { allowed: boolean; retryAfter?: number } {
    const now = Date.now();
    const record = this.attempts.get(ip);

    if (!record || now - record.windowStart > RATE_LIMIT_WINDOW_MS) {
      // Window expired or first attempt — allow
      return { allowed: true };
    }

    if (record.count >= RATE_LIMIT_MAX_ATTEMPTS) {
      const retryAfter = Math.ceil(
        (record.windowStart + RATE_LIMIT_WINDOW_MS - now) / 1000,
      );
      return { allowed: false, retryAfter };
    }

    return { allowed: true };
  }

  /**
   * Record a failed attempt for rate limiting.
   */
  recordFailedAttempt(ip: string): void {
    const now = Date.now();
    const record = this.attempts.get(ip);

    if (!record || now - record.windowStart > RATE_LIMIT_WINDOW_MS) {
      this.attempts.set(ip, { count: 1, windowStart: now });
    } else {
      record.count++;
    }
  }
}

export const pinManager = new PinManager();
