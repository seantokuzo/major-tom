export type UserRole = 'admin' | 'operator' | 'viewer';

export interface KeybarConfig {
  version: number;
  accessory: string[];
  specialty: string[];
}

export interface UserPreferences {
  keybarConfig?: KeybarConfig;
  fontSize?: number;
}

export interface User {
  id: string;           // Derived from Google sub claim
  email: string;
  name?: string;
  picture?: string;
  role: UserRole;
  createdAt: string;    // ISO 8601
  lastLoginAt: string;  // ISO 8601
  invitedBy?: string;   // userId of who invited them
  allowedPaths?: string[]; // Per-user directory access restrictions (SandboxGuard)
  preferences?: UserPreferences; // Cross-device synced preferences (keybar layout, font size)
}

export interface InviteCode {
  code: string;         // 8-char uppercased base64url (A-Z, 0-9, -, _)
  role: UserRole;
  createdBy: string;    // userId
  createdAt: string;
  expiresAt: string;    // 24h default
  redeemedBy?: string;
  redeemedAt?: string;
}

export interface UserPresenceInfo {
  userId: string;
  email: string;
  name?: string;
  picture?: string;
  role: UserRole;
  connectedAt: string;
  watchingSessionId?: string;
}
