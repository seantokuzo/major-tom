// Office state — Svelte 5 runes-based state management
// Ported from iOS OfficeViewModel.swift

import type { OfficeAgent, CharacterType, Desk, OfficeAreaType, IdleActivity, OfficeView, Point } from './types';
import { ALL_CHARACTER_TYPES } from './types';
import { DESKS, DOOR_POSITION, OFFICE_VIEWS, VIEW_DOOR_POSITIONS, randomPosition, getViewForArea } from './layout';
import { DOG_TYPES, CHARACTER_VIEW_PREFERENCES, CHARACTER_CATALOG } from './characters';
import { OfficeEngine } from './engine';
import type { FacingDirection } from './engine';
import { findPath, findNearestWalkable, pathDuration } from './navigation';
import {
  pickJobComplete, pickDogBark, pickDogBeg, pickGeneralIdle,
  pickSocialInvite, pickSocialAccept, pickSocialDecline,
  pickPingPongRally, pickCasualChat,
} from './speech';
import { ActivityManager } from './activity-manager';

// ── Status colors ────────────────────────────────────────────

export const STATUS_COLORS: Record<string, string> = {
  spawning: 'rgb(153, 153, 153)',
  walking: 'rgb(102, 179, 255)',
  working: 'rgb(77, 217, 115)',
  idle: 'rgb(242, 191, 77)',
  celebrating: 'rgb(242, 166, 64)',
  leaving: 'rgb(179, 77, 77)',
};

// ── Idle Activity Cycling ────────────────────────────────────

/** Initial stagger window — agents start cycling at random offsets so they don't all switch at once */
const IDLE_STAGGER_MAX = 20_000;

/** Activity manager — handles station capacity, room ownership, slot reservations */
const activityManager = new ActivityManager();

// ── Office State ─────────────────────────────────────────────

export interface OfficeState {
  agents: OfficeAgent[];
  desks: Desk[];
  selectedAgentId: string | null;
  engine: OfficeEngine;

  readonly selectedAgent: OfficeAgent | null;
  /** Demo mode active — fake agents populating the office */
  demoMode: boolean;
  /** Session mode active — crew idle during active Claude session */
  sessionMode: boolean;
  /** Whether demo toggle is available (no real agents and no active session) */
  readonly canDemo: boolean;

  toggleDemo(): void;
  /** Auto-start idle demo if no real agents present. Idempotent — safe to call repeatedly. */
  ensureAutoIdle(): void;
  /** Enter session mode — populate all 14 crew members as idle. Idempotent. */
  enterSessionMode(): void;
  /** Exit session mode — dismiss all session-idle agents. */
  exitSessionMode(): void;
  handleSpawn(id: string, role: string, task: string): void;
  handleWorking(id: string, task: string): void;
  handleIdle(id: string): void;
  handleComplete(id: string, result: string): void;
  handleDismissed(id: string): void;
  reset(): void;

  selectAgent(id: string): void;
  dismissInspector(): void;
  renameAgent(id: string, newName: string): void;
}

export function createOfficeState(): OfficeState {
  let agents = $state<OfficeAgent[]>([]);
  let desks = $state<Desk[]>(DESKS.map((d) => ({ ...d, occupantId: null })));
  let selectedAgentId = $state<string | null>(null);
  let demoMode = $state(false);
  let sessionMode = $state(false);
  let nextCharacterIndex = 0;

  const engine = new OfficeEngine();

  // ── Stuck Detection Handler ──────────────────────────────────
  // Wired up after engine creation — reroutes or bails stuck agents.
  engine.onStuck = (agentId: string, position: Point, target: Point, stuckCount: number): boolean => {
    const agent = agents.find((a) => a.id === agentId);
    if (!agent || agent.status !== 'idle') {
      // Non-idle agents (walking, leaving, etc.) need their movement to complete.
      // Return false so the engine keeps trying — they'll reach their target eventually.
      return false;
    }

    const ea = engine.agents.get(agentId);
    const currentView: OfficeView = ea?.currentView ?? 'office';

    if (stuckCount <= 2) {
      // Reroute — recompute A* path from current position to same target
      const newPath = findPath(position, target, currentView);
      if (newPath.length > 0) {
        engine.moveAgentAlongPath(agentId, newPath, 100);
      } else {
        // Can't pathfind — bail immediately
        activityManager.release(agentId);
        cycleIdleActivity(agentId);
      }
      return true;
    }

    // stuckCount > 2 — bail: cancel movement, pick a new activity entirely
    if (ea) ea.move = null;
    activityManager.release(agentId);
    cycleIdleActivity(agentId);
    return true;
  };

  /** Demo agent ID prefix — used to distinguish fake agents from real ones */
  const DEMO_PREFIX = 'demo-';
  /** Session-idle agent ID prefix — crew members during active sessions */
  const SESSION_PREFIX = 'session-';

  /** Check if an agent is a demo agent */
  function isDemoAgent(id: string): boolean {
    return id.startsWith(DEMO_PREFIX);
  }

  /** Check if an agent is a session-idle agent */
  function isSessionAgent(id: string): boolean {
    return id.startsWith(SESSION_PREFIX);
  }

  /** Whether demo toggle is available (no real agents and no active session) */
  const canDemo = $derived.by(() => {
    if (sessionMode) return false;
    return agents.every((a) => isDemoAgent(a.id));
  });

  /** Idle cycle duration */
  function randomIdleDuration(): number {
    return 45_000 + Math.random() * 45_000;
  }

  /** Per-agent idle cycling timers (agent id → timeout handle) */
  const idleTimers = new Map<string, ReturnType<typeof setTimeout>>();

  /** Ping pong pairing wait timers (agent id → timeout handle) */
  const pingPongWaitTimers = new Map<string, ReturnType<typeof setTimeout>>();

  const selectedAgent = $derived.by(() => {
    if (!selectedAgentId) return null;
    return agents.find((a) => a.id === selectedAgentId) ?? null;
  });

  // ── Character / Desk Assignment ────────────────────────────

  /** Direct role → character type mapping */
  const ROLE_TO_CHARACTER: Record<string, CharacterType> = {
    researcher: 'databaseGuru',
    architect: 'architect',
    qa: 'engManager',
    devops: 'devops',
    frontend: 'frontendEngineer',
    backend: 'backendEngineer',
    lead: 'leadEngineer',
  };

  /** Pool for 'engineer' role — human types not directly mapped */
  const ENGINEER_POOL: CharacterType[] = [
    'uxDesigner', 'projectManager', 'productManager',
  ];
  let engineerPoolIndex = 0;

  /** Non-reactive counter — tracks active (non-demo, non-session) agents per CharacterType.
   *  Using a plain Map avoids reading the reactive `agents` array inside $effect call chains,
   *  which would cause effect_update_depth_exceeded (read+write on same $state). */
  const charTypeCounter = new Map<CharacterType, number>();

  function incrementCharTypeCount(type: CharacterType): void {
    charTypeCounter.set(type, (charTypeCounter.get(type) ?? 0) + 1);
  }

  function decrementCharTypeCount(type: CharacterType): void {
    const current = charTypeCounter.get(type) ?? 0;
    if (current > 1) charTypeCounter.set(type, current - 1);
    else charTypeCounter.delete(type);
  }

  function getCharTypeCount(type: CharacterType): number {
    return charTypeCounter.get(type) ?? 0;
  }

  function assignNextCharacterType(): CharacterType {
    const type = ALL_CHARACTER_TYPES[nextCharacterIndex % ALL_CHARACTER_TYPES.length];
    nextCharacterIndex++;
    return type;
  }

  /** Role-aware character assignment */
  function assignCharacterForRole(role: string): CharacterType {
    // Direct mapping for known roles
    const mapped = ROLE_TO_CHARACTER[role];
    if (mapped) return mapped;

    // Engineer pool rotation
    if (role === 'engineer') {
      const type = ENGINEER_POOL[engineerPoolIndex % ENGINEER_POOL.length];
      engineerPoolIndex++;
      return type;
    }

    // Fallback: round-robin (legacy 'subagent' or unknown)
    return assignNextCharacterType();
  }

  function assignNextAvailableDesk(agentId: string): number | null {
    const idx = desks.findIndex((d) => d.occupantId === null);
    if (idx === -1) return null;
    desks[idx].occupantId = agentId;
    return idx;
  }

  function releaseDesk(agentId: string): void {
    const idx = desks.findIndex((d) => d.occupantId === agentId);
    if (idx !== -1) desks[idx].occupantId = null;
  }

  function clearIdleTimer(id: string): void {
    const timer = idleTimers.get(id);
    if (timer) {
      clearTimeout(timer);
      idleTimers.delete(id);
    }
  }

  function clearPingPongTimer(id: string): void {
    const timer = pingPongWaitTimers.get(id);
    if (timer) {
      clearTimeout(timer);
      pingPongWaitTimers.delete(id);
    }
  }

  /** Clear pairing for an agent and notify the partner */
  function clearPairing(id: string): void {
    const engineAgent = engine.agents.get(id);
    if (!engineAgent?.pairedWith) return;
    const partnerId = engineAgent.pairedWith;
    engine.setPairedWith(partnerId, null);
    engine.setPairedWith(id, null);
    // Partner picks a new activity after a short delay
    setTimeout(() => cycleIdleActivity(partnerId), 1000);
  }

  // ── Social Interactions ─────────────────────────────────────
  // Proximity-triggered spontaneous interactions between idle sprites.

  /** Agents currently mid-negotiation (invite pending response) */
  const socialNegotiating = new Set<string>();
  /** Interval handles for the social scanner and rally chatter */
  let proximityScanInterval: ReturnType<typeof setInterval> | null = null;
  let rallyInterval: ReturnType<typeof setInterval> | null = null;

  function startSocialScanner(): void {
    if (proximityScanInterval) return;
    proximityScanInterval = setInterval(scanForSocialInteractions, 8_000);
    rallyInterval = setInterval(pingPongRallyChatter, 5_000);
  }

  function stopSocialScanner(): void {
    if (proximityScanInterval) { clearInterval(proximityScanInterval); proximityScanInterval = null; }
    if (rallyInterval) { clearInterval(rallyInterval); rallyInterval = null; }
    socialNegotiating.clear();
  }

  /** Scan all idle agents for nearby pairs and maybe trigger a social interaction */
  function scanForSocialInteractions(): void {
    const idleAgents: { id: string; position: Point; view: OfficeView }[] = [];
    for (const agent of agents) {
      if (agent.status !== 'idle') continue;
      if (socialNegotiating.has(agent.id)) continue;
      const ea = engine.agents.get(agent.id);
      if (!ea || ea.pairedWith || ea.isMoving) continue;
      idleAgents.push({ id: agent.id, position: { ...ea.position }, view: ea.currentView ?? 'office' });
    }

    if (idleAgents.length < 2) return;

    const SOCIAL_DIST = 80;
    const TRIGGER_CHANCE = 0.08;

    for (let i = 0; i < idleAgents.length; i++) {
      for (let j = i + 1; j < idleAgents.length; j++) {
        const a = idleAgents[i];
        const b = idleAgents[j];
        if (a.view !== b.view) continue;

        const dx = a.position.x - b.position.x;
        const dy = a.position.y - b.position.y;
        if (Math.sqrt(dx * dx + dy * dy) > SOCIAL_DIST) continue;
        if (Math.random() > TRIGGER_CHANCE) continue;

        // 40% ping pong invite (only in office view), 60% casual chat
        if (Math.random() < 0.4 && a.view === 'office') {
          initiatePingPongInvite(a.id, b.id);
        } else {
          initiateCasualChat(a.id, b.id);
        }
        return; // one interaction per scan
      }
    }
  }

  /** Initiate a ping pong invite: speech bubbles → accept/decline → coordinated walk */
  function initiatePingPongInvite(initiatorId: string, targetId: string): void {
    socialNegotiating.add(initiatorId);
    socialNegotiating.add(targetId);

    engine.setSpeechBubble(initiatorId, pickSocialInvite(), 3000);

    // Face each other during negotiation
    const iPos = engine.agents.get(initiatorId)?.position;
    const tPos = engine.agents.get(targetId)?.position;
    if (iPos && tPos) {
      const ddx = tPos.x - iPos.x;
      if (Math.abs(ddx) > 1) {
        engine.setFacing(initiatorId, ddx > 0 ? 'right' : 'left');
        engine.setFacing(targetId, ddx > 0 ? 'left' : 'right');
      }
    }

    setTimeout(() => {
      socialNegotiating.delete(initiatorId);
      socialNegotiating.delete(targetId);

      const init = agents.find(a => a.id === initiatorId);
      const tgt = agents.find(a => a.id === targetId);
      if (!init || !tgt || init.status !== 'idle' || tgt.status !== 'idle') return;

      if (Math.random() < 0.7) {
        // Accepted
        engine.setSpeechBubble(targetId, pickSocialAccept(), 2000);

        // Try to reserve both ping pong slots
        const station = activityManager.getStation('break-pingPong');
        if (!station || station.slots[0].occupantId !== null || station.slots[1].occupantId !== null) return;

        activityManager.release(initiatorId);
        activityManager.release(targetId);
        const reserved0 = activityManager.reserveSpecific(initiatorId, 'break-pingPong', 0);
        const reserved1 = activityManager.reserveSpecific(targetId, 'break-pingPong', 1);
        if (!reserved0 || !reserved1) {
          // Roll back partial reservations to avoid blocking the station
          activityManager.release(initiatorId);
          activityManager.release(targetId);
          return;
        }

        // Update activity labels
        init.idleActivity = 'Playing ping pong';
        tgt.idleActivity = 'Playing ping pong';
        engine.setIdleActivity(initiatorId, 'Playing ping pong');
        engine.setIdleActivity(targetId, 'Playing ping pong');
        agents = [...agents];

        // Walk both to ping pong table
        const walkSpeed = 100;
        for (const [id, slotIdx] of [[initiatorId, 0], [targetId, 1]] as [string, number][]) {
          const ea = engine.agents.get(id);
          const pos = station.slots[slotIdx].position;
          const from = ea?.position ?? DOOR_POSITION;
          const path = findPath(from, pos, 'office');

          clearIdleTimer(id);
          engine.setStatusColor(id, STATUS_COLORS.walking);
          engine.setAnimation(id, 'none');
          engine.setCurrentView(id, 'office');

          if (path.length > 0) {
            engine.moveAgentAlongPath(id, path, walkSpeed);
          } else {
            engine.moveAgent(id, pos, 2000);
          }

          const walkDuration = path.length > 0 ? pathDuration(path, walkSpeed) : 2000;
          setTimeout(() => {
            const current = agents.find(a => a.id === id);
            if (!current || current.status !== 'idle') return;
            engine.setStatusColor(id, STATUS_COLORS.idle);
            engine.setAnimation(id, 'idle');
            engine.setFacing(id, station.slots[slotIdx].facing);
            engine.setPairedWith(initiatorId, targetId);
            engine.setPairedWith(targetId, initiatorId);
          }, walkDuration + 200);
        }

        // Restart idle cycle timers (they'll eventually break up and move on)
        startIdleCycle(initiatorId);
        startIdleCycle(targetId);
      } else {
        // Declined
        engine.setSpeechBubble(targetId, pickSocialDecline(), 2000);
      }
    }, 2000);
  }

  /** Casual chat: two nearby idle sprites exchange speech bubbles */
  function initiateCasualChat(agentAId: string, agentBId: string): void {
    socialNegotiating.add(agentAId);
    socialNegotiating.add(agentBId);

    // Face each other
    const aPos = engine.agents.get(agentAId)?.position;
    const bPos = engine.agents.get(agentBId)?.position;
    if (aPos && bPos) {
      const ddx = bPos.x - aPos.x;
      if (Math.abs(ddx) > 1) {
        engine.setFacing(agentAId, ddx > 0 ? 'right' : 'left');
        engine.setFacing(agentBId, ddx > 0 ? 'left' : 'right');
      }
    }

    engine.setSpeechBubble(agentAId, pickCasualChat(), 2500);

    setTimeout(() => {
      const b = agents.find(a => a.id === agentBId);
      if (b && b.status === 'idle') {
        engine.setSpeechBubble(agentBId, pickCasualChat(), 2500);
      }
      socialNegotiating.delete(agentAId);
      socialNegotiating.delete(agentBId);
    }, 2000);
  }

  /** Periodic rally chatter for paired ping pong agents */
  function pingPongRallyChatter(): void {
    for (const agent of agents) {
      if (agent.status !== 'idle' || agent.idleActivity !== 'Playing ping pong') continue;
      const ea = engine.agents.get(agent.id);
      if (!ea?.pairedWith) continue;
      // 30% chance per pair per tick (only fire for one of the pair to avoid double)
      if (ea.id > ea.pairedWith) continue; // deterministic: lower ID drives the rally
      if (Math.random() > 0.3) continue;
      // Pick which player speaks
      const speaker = Math.random() < 0.5 ? ea.id : ea.pairedWith;
      engine.setSpeechBubble(speaker, pickPingPongRally(), 2000);
    }
  }

  /** Set up ping pong pairing for an agent arriving at the table */
  function setupPingPong(agentId: string): void {
    // Get positions from station definition
    const station = activityManager.getStation('break-pingPong');
    if (!station) return;
    const leftPos = station.slots[0].position;
    const rightPos = station.slots[1].position;

    // Find another agent already at ping pong without a partner
    const partner = agents.find((a) =>
      a.id !== agentId &&
      a.status === 'idle' &&
      a.idleActivity === 'Playing ping pong' &&
      !engine.agents.get(a.id)?.pairedWith
    );

    if (partner) {
      // Pair them
      clearPingPongTimer(partner.id);
      engine.setPairedWith(agentId, partner.id);
      engine.setPairedWith(partner.id, agentId);

      // Position on opposite sides of ping pong table
      const partnerEngine = engine.agents.get(partner.id);
      if (partnerEngine) {
        engine.moveAgent(partner.id, leftPos, 500);
        engine.moveAgent(agentId, rightPos, 500);
        setTimeout(() => {
          engine.setFacing(partner.id, 'right');
          engine.setFacing(agentId, 'left');
        }, 600);
      }
    } else {
      // Wait for a partner — if no one joins in 15s, switch activity
      const timer = setTimeout(() => {
        pingPongWaitTimers.delete(agentId);
        const agent = agents.find((a) => a.id === agentId);
        if (!agent || agent.status !== 'idle') return;
        const ea = engine.agents.get(agentId);
        if (ea?.pairedWith) return; // already paired
        cycleIdleActivity(agentId);
      }, 15_000);
      pingPongWaitTimers.set(agentId, timer);
    }
  }

  /** Start cycling idle activities for an agent */
  function startIdleCycle(id: string, initialDelay?: number): void {
    clearIdleTimer(id);

    const delay = initialDelay ?? randomIdleDuration();
    const timer = setTimeout(() => {
      cycleIdleActivity(id);
    }, delay);
    idleTimers.set(id, timer);
  }

  /** Switch an idle agent to a new activity + position, with cross-view transitions */
  function cycleIdleActivity(id: string): void {
    const agent = agents.find((a) => a.id === id);
    if (!agent) return;
    // Only cycle if still idle
    if (agent.status !== 'idle') {
      clearIdleTimer(id);
      return;
    }

    const engineAgent = engine.agents.get(id);
    const agentCurrentView: OfficeView = engineAgent?.currentView ?? 'office';

    // Pick activity via manager (handles capacity + room ownership)
    const assignment = activityManager.pickAndReserve(id, agent.characterType, agentCurrentView);
    if (!assignment) {
      startIdleCycle(id);
      return;
    }

    const { activity } = assignment;

    // Set activity label on both state agent and engine agent
    agent.idleActivity = activity.label;
    engine.setIdleActivity(id, activity.label);
    agents = [...agents];

    const targetView = getViewForArea(activity.area);
    const pos = findNearestWalkable(assignment.walkTarget, targetView);
    const walkSpeed = 100;

    if (targetView !== agentCurrentView) {
      // ── Cross-view transition ────────────────────────
      const exitPos = findNearestWalkable(VIEW_DOOR_POSITIONS[agentCurrentView], agentCurrentView);
      const currentPos = engineAgent?.position ?? DOOR_POSITION;
      const exitPath = findPath(currentPos, exitPos, agentCurrentView);

      engine.setStatusColor(id, STATUS_COLORS.walking);
      engine.setAnimation(id, 'none');

      if (exitPath.length > 0) {
        engine.moveAgentAlongPath(id, exitPath, walkSpeed);
      } else {
        engine.moveAgent(id, exitPos, 1500);
      }

      const exitWalkDuration = exitPath.length > 0 ? pathDuration(exitPath, walkSpeed) : 1500;

      setTimeout(() => {
        const current = agents.find((a) => a.id === id);
        if (!current || current.status !== 'idle') return;

        engine.setAnimation(id, 'fade-out');

        setTimeout(() => {
          const still = agents.find((a) => a.id === id);
          if (!still || still.status !== 'idle') return;

          const entrancePos = findNearestWalkable(VIEW_DOOR_POSITIONS[targetView], targetView);
          const ea = engine.agents.get(id);
          if (ea) {
            ea.position.x = entrancePos.x;
            ea.position.y = entrancePos.y;
          }
          engine.setCurrentView(id, targetView);
          engine.setAnimation(id, 'fade-in');

          setTimeout(() => {
            const alive = agents.find((a) => a.id === id);
            if (!alive || alive.status !== 'idle') return;

            const entryPath = findPath(entrancePos, pos, targetView);
            engine.setAnimation(id, 'none');

            if (entryPath.length > 0) {
              engine.moveAgentAlongPath(id, entryPath, walkSpeed);
            } else {
              engine.moveAgent(id, pos, 2000);
            }

            const entryWalkDuration = entryPath.length > 0 ? pathDuration(entryPath, walkSpeed) : 2000;

            setTimeout(() => {
              arriveAtActivity(id, activity, assignment.facing);
            }, entryWalkDuration + 200);
          }, 350);
        }, 550);
      }, exitWalkDuration + 100);
    } else {
      // ── Same-view transition ─────────────────────────
      const currentPos = engineAgent?.position ?? DOOR_POSITION;
      const path = findPath(currentPos, pos, targetView);

      engine.setStatusColor(id, STATUS_COLORS.walking);
      engine.setAnimation(id, 'none');
      engine.setCurrentView(id, targetView);

      if (path.length > 0) {
        engine.moveAgentAlongPath(id, path, walkSpeed);
      } else {
        engine.moveAgent(id, pos, 2000);
      }

      const walkDuration = path.length > 0 ? pathDuration(path, walkSpeed) : 2000;
      setTimeout(() => {
        arriveAtActivity(id, activity, assignment.facing);
      }, walkDuration + 200);
    }

    // Schedule next activity switch
    startIdleCycle(id);
  }

  /** Common arrival logic after walking to an activity destination */
  function arriveAtActivity(id: string, activity: IdleActivity, stationFacing?: FacingDirection): void {
    const current = agents.find((a) => a.id === id);
    if (!current || current.status !== 'idle') return;

    engine.setStatusColor(id, STATUS_COLORS.idle);
    engine.setAnimation(id, 'idle');

    // Use station-provided facing if available, otherwise infer from activity
    if (stationFacing) {
      engine.setFacing(id, stationFacing);
    } else {
      setFacingForActivity(id, activity.label);
    }

    // Set up ping pong pairing if applicable
    if (activity.label === 'Playing ping pong') {
      setupPingPong(id);
    }

    // Speech bubble triggers
    const isDog = DOG_TYPES.has(current.characterType);
    if (isDog) {
      if (activity.label === 'Begging for scraps') {
        engine.setSpeechBubble(id, pickDogBeg());
      } else if (Math.random() < 0.15) {
        engine.setSpeechBubble(id, pickDogBark());
      }
    } else {
      if (Math.random() < 0.05) {
        engine.setSpeechBubble(id, pickGeneralIdle());
      }
    }
  }

  /** Set facing direction based on the idle activity */
  function setFacingForActivity(id: string, label: string): void {
    if (
      label.includes('whiteboard') ||
      label.includes('Planning') ||
      label.includes('Reviewing') ||
      label.includes('Brainstorming')
    ) {
      engine.setFacing(id, 'up'); // face the whiteboard (on wall)
    } else if (
      label.includes('TV') ||
      label.includes('video games') ||
      label.includes('arcade') ||
      label.includes('Watching')
    ) {
      engine.setFacing(id, 'up'); // face the screen
    } else if (
      label.includes('fridge') ||
      label.includes('Staring')
    ) {
      engine.setFacing(id, 'up'); // face the fridge
    } else if (label.includes('ping pong')) {
      // facing set by setupPingPong when paired
      engine.setFacing(id, 'down'); // default until paired
    } else {
      engine.setFacing(id, 'down'); // face camera for eating, chatting, etc.
    }
  }

  function removeAgent(id: string): void {
    // Decrement char type counter for real agents only
    if (!isDemoAgent(id) && !isSessionAgent(id)) {
      const agent = agents.find(a => a.id === id);
      if (agent) decrementCharTypeCount(agent.characterType);
    }
    clearIdleTimer(id);
    clearPingPongTimer(id);
    clearPairing(id);
    socialNegotiating.delete(id);
    activityManager.release(id);
    releaseDesk(id);
    engine.removeAgent(id);
    agents = agents.filter((a) => a.id !== id);
    if (selectedAgentId === id) selectedAgentId = null;
  }

  // ── Demo Mode ──────────────────────────────────────────────

  /** Demo agent roster — mix of desk workers and break room wanderers */
  const DEMO_ROSTER: { role: string; behavior: 'desk' | 'idle'; char: CharacterType }[] = [
    { role: 'Architect', behavior: 'desk', char: 'architect' },
    { role: 'Backend', behavior: 'desk', char: 'backendEngineer' },
    { role: 'Frontend', behavior: 'desk', char: 'frontendEngineer' },
    { role: 'DevOps', behavior: 'desk', char: 'devops' },
    { role: 'Designer', behavior: 'idle', char: 'uxDesigner' },
    { role: 'PM', behavior: 'idle', char: 'productManager' },
    { role: 'Elvito', behavior: 'idle', char: 'dachshund' },
    { role: 'Kai', behavior: 'idle', char: 'schnauzerPepper' },
  ];

  function dismissAllDemoAgents(): void {
    stopSocialScanner();
    const demoAgents = agents.filter((a) => isDemoAgent(a.id));
    for (const agent of demoAgents) {
      engine.setAnimation(agent.id, 'fade-out');
    }
    // Remove after fade-out completes
    setTimeout(() => {
      const demoIds = new Set(demoAgents.map((a) => a.id));
      for (const id of demoIds) {
        clearIdleTimer(id);
        clearPingPongTimer(id);
        clearPairing(id);
        activityManager.release(id);
        releaseDesk(id);
        engine.removeAgent(id);
      }
      agents = agents.filter((a) => !demoIds.has(a.id));
      if (selectedAgentId && demoIds.has(selectedAgentId)) selectedAgentId = null;
      nextCharacterIndex = 0;
    }, 600);
  }

  // ── Session Mode ─────────────────────────────────────────────
  // When a Claude session is active, all 14 crew members are spawned as idle.
  // Real agent.spawn events reuse existing session-idle characters.
  // Agent dismiss returns characters to idle rather than removing them.

  /** Map session agent ID → character type for reuse lookups */
  const sessionCharMap = new Map<string, CharacterType>();

  function enterSessionMode(): void {
    if (sessionMode) return; // idempotent

    // Kill demo if active
    if (demoMode) {
      demoMode = false;
      dismissAllDemoAgents();
    }

    sessionMode = true;
    startSocialScanner();

    // Spawn all 14 characters with stagger
    ALL_CHARACTER_TYPES.forEach((charType, i) => {
      const id = `${SESSION_PREFIX}${charType}`;
      const config = CHARACTER_CATALOG.find(c => c.type === charType);
      const name = config?.displayName ?? charType;

      sessionCharMap.set(id, charType);

      setTimeout(() => {
        if (!sessionMode) return;
        if (agents.some(a => a.id === id)) return; // already exists

        const agent: OfficeAgent = {
          id,
          name,
          role: charType,
          characterType: charType,
          status: 'idle',
          currentTask: null,
          deskIndex: null,
          spawnedAt: new Date(),
          idleActivity: null,
        };

        agents.push(agent);
        agents = [...agents];

        // Add to engine at a random position in the office
        const startPos = randomPosition('mainOffice');
        engine.addAgent(id, charType, name, startPos);
        engine.setStatusColor(id, STATUS_COLORS.idle);
        engine.setAnimation(id, 'fade-in');

        // After fade-in, start idle cycling
        setTimeout(() => {
          if (!sessionMode) return;
          const current = agents.find(a => a.id === id);
          if (!current) return;
          engine.setAnimation(id, 'idle');
          handleIdle(id);
        }, 400);
      }, i * 150); // stagger 150ms each
    });
  }

  function exitSessionMode(): void {
    if (!sessionMode) return;
    sessionMode = false;
    stopSocialScanner();

    // Fade out and remove all session agents
    const sessionAgents = agents.filter(a => isSessionAgent(a.id));
    for (const agent of sessionAgents) {
      engine.setAnimation(agent.id, 'fade-out');
    }

    setTimeout(() => {
      const sessionIds = new Set(sessionAgents.map(a => a.id));
      for (const id of sessionIds) {
        clearIdleTimer(id);
        clearPingPongTimer(id);
        clearPairing(id);
        activityManager.release(id);
        releaseDesk(id);
        engine.removeAgent(id);
      }
      agents = agents.filter(a => !sessionIds.has(a.id));
      if (selectedAgentId && sessionIds.has(selectedAgentId)) selectedAgentId = null;
      sessionCharMap.clear();
    }, 600);
  }

  /** Find a session-idle agent by character type and promote it to a real agent */
  function promoteSessionAgent(characterType: CharacterType, realId: string, role: string, task: string): boolean {
    const sessionId = `${SESSION_PREFIX}${characterType}`;
    const sessionAgent = agents.find(a => a.id === sessionId);
    if (!sessionAgent || !isSessionAgent(sessionId)) return false;

    // Get engine state before removing
    const engineAgent = engine.agents.get(sessionId);
    const currentPos = engineAgent ? { ...engineAgent.position } : DOOR_POSITION;
    const currentView = engineAgent?.currentView ?? 'office';

    // Remove the session agent
    clearIdleTimer(sessionId);
    clearPingPongTimer(sessionId);
    clearPairing(sessionId);
    engine.removeAgent(sessionId);
    agents = agents.filter(a => a.id !== sessionId);
    sessionCharMap.delete(sessionId);

    // Create the real agent at the same position
    const deskIndex = assignNextAvailableDesk(realId);
    const dupCount = getCharTypeCount(characterType);
    const baseName = role.charAt(0).toUpperCase() + role.slice(1);
    const displayName = dupCount > 0 ? `${baseName} ${dupCount + 1}` : baseName;
    const agent: OfficeAgent = {
      id: realId,
      name: displayName,
      role,
      characterType,
      status: 'spawning',
      currentTask: task,
      deskIndex,
      spawnedAt: new Date(),
      idleActivity: null,
    };

    agents.push(agent);
    incrementCharTypeCount(characterType);
    engine.addAgent(realId, characterType, agent.name, currentPos);
    engine.setCurrentView(realId, currentView);
    engine.setStatusColor(realId, STATUS_COLORS.spawning);

    if (deskIndex !== null) {
      // Walk to desk
      const deskPos = desks[deskIndex].position;
      const seatPos = { x: deskPos.x, y: deskPos.y + 20 };

      // Bring to office view if in another view
      if (currentView !== 'office') {
        const ea = engine.agents.get(realId);
        if (ea) {
          ea.position.x = DOOR_POSITION.x;
          ea.position.y = DOOR_POSITION.y;
        }
        engine.setCurrentView(realId, 'office');
      }

      const startPos = currentView === 'office' ? currentPos : DOOR_POSITION;
      const path = findPath(startPos, seatPos);
      agent.status = 'walking';
      engine.setStatusColor(realId, STATUS_COLORS.walking);
      agents = [...agents];

      if (path.length > 0) {
        engine.moveAgentAlongPath(realId, path, 120);
      } else {
        engine.moveAgent(realId, seatPos, 1500);
      }
    } else {
      agent.status = 'idle';
      engine.setStatusColor(realId, STATUS_COLORS.idle);
      engine.setAnimation(realId, 'idle');
      agents = [...agents];
    }

    return true;
  }

  function toggleDemo(): void {
    if (demoMode) {
      // Deactivate demo — dismiss all demo agents
      demoMode = false;
      dismissAllDemoAgents();
      return;
    }

    // Can't activate demo if real agents are present
    if (!canDemo) return;

    demoMode = true;
    startSocialScanner();

    // Spawn demo agents with staggered entrance
    DEMO_ROSTER.forEach((entry, i) => {
      const id = `${DEMO_PREFIX}${i}`;
      const characterType = entry.char;
      const deskIndex = entry.behavior === 'desk' ? assignNextAvailableDesk(id) : null;

      const agent: OfficeAgent = {
        id,
        name: entry.role,
        role: entry.role.toLowerCase(),
        characterType,
        status: 'spawning',
        currentTask: entry.behavior === 'desk' ? 'Working on tasks' : null,
        deskIndex,
        spawnedAt: new Date(),
        idleActivity: null,
      };

      // Stagger spawns by 300ms each
      setTimeout(() => {
        if (!demoMode) return; // bail if demo was cancelled during stagger

        agents.push(agent);
        engine.addAgent(id, characterType, agent.name, DOOR_POSITION);
        engine.setStatusColor(id, STATUS_COLORS.spawning);

        if (entry.behavior === 'desk' && deskIndex !== null) {
          // Walk to desk, then work
          const deskPos = desks[deskIndex].position;
          const seatPos = { x: deskPos.x, y: deskPos.y + 20 };
          const path = findPath(DOOR_POSITION, seatPos);
          const walkSpeed = 120;

          agent.status = 'walking';
          engine.setStatusColor(id, STATUS_COLORS.walking);
          agents = [...agents];

          if (path.length > 0) {
            engine.moveAgentAlongPath(id, path, walkSpeed);
          } else {
            engine.moveAgent(id, seatPos, 1500);
          }

          const walkDuration = path.length > 0 ? pathDuration(path, walkSpeed) : 1500;
          setTimeout(() => {
            if (!demoMode) return;
            const current = agents.find((a) => a.id === id);
            if (!current) return;
            current.status = 'working';
            current.idleActivity = null;
            agents = [...agents];
            engine.setStatusColor(id, STATUS_COLORS.working);
            engine.setAnimation(id, 'work-shake');
            engine.setFacing(id, 'up');
          }, walkDuration + 200);
        } else {
          // Idle agent — send to break room / kitchen activity
          agent.status = 'walking';
          agents = [...agents];
          handleIdle(id);
        }
      }, i * 300);
    });
  }

  // ── Lifecycle Handlers ─────────────────────────────────────

  function handleSpawn(id: string, role: string, task: string): void {
    if (agents.some((a) => a.id === id)) return;

    // Auto-dismiss demo agents when a real session starts
    if (demoMode) {
      demoMode = false;
      dismissAllDemoAgents();
    }

    // In session mode, try to promote an existing idle crew member
    if (sessionMode) {
      const charType = assignCharacterForRole(role);
      if (promoteSessionAgent(charType, id, role, task)) {
        return;
      }
    }

    const characterType = assignCharacterForRole(role);
    const deskIndex = assignNextAvailableDesk(id);

    // Deduplicate name when same CharacterType already active
    const dupCount = getCharTypeCount(characterType);
    const baseName = role.charAt(0).toUpperCase() + role.slice(1);
    const displayName = dupCount > 0 ? `${baseName} ${dupCount + 1}` : baseName;

    const agent: OfficeAgent = {
      id,
      name: displayName,
      role,
      characterType,
      status: 'spawning',
      currentTask: task,
      deskIndex,
      spawnedAt: new Date(),
      idleActivity: null,
    };

    agents.push(agent);
    incrementCharTypeCount(characterType);

    // Add to engine at door position
    engine.addAgent(id, characterType, agent.name, DOOR_POSITION);
    engine.setStatusColor(id, STATUS_COLORS.spawning);

    // No desk available — park near the door in idle state
    if (deskIndex === null) {
      agent.status = 'idle';
      engine.setStatusColor(id, STATUS_COLORS.idle);
      engine.setAnimation(id, 'idle');
      agents = [...agents];
      return;
    }

    // Desk assigned, walk to desk via pathfinding
    {
      const deskPos = desks[deskIndex].position;
      // Sit slightly below the desk
      const seatPos = { x: deskPos.x, y: deskPos.y + 20 };
      const path = findPath(DOOR_POSITION, seatPos);
      if (path.length > 0) {
        engine.moveAgentAlongPath(id, path, 120);
      } else {
        engine.moveAgent(id, seatPos, 1500);
      }

      // Set walking status immediately
      agent.status = 'walking';
      engine.setStatusColor(id, STATUS_COLORS.walking);
      agents = [...agents];
    }
  }

  function handleWorking(id: string, task: string): void {
    const agent = agents.find((a) => a.id === id);
    if (!agent) return;
    clearIdleTimer(id);
    clearPingPongTimer(id);
    clearPairing(id);
    activityManager.release(id);
    agent.status = 'working';
    agent.currentTask = task;
    agent.idleActivity = null;
    engine.setIdleActivity(id, null);
    agents = [...agents];

    const engineAgent = engine.agents.get(id);
    const agentView = engineAgent?.currentView ?? 'office';

    if (agentView !== 'office') {
      // Agent is in another view — teleport back to office at desk or door
      const deskPos = agent.deskIndex !== null
        ? { x: desks[agent.deskIndex].position.x, y: desks[agent.deskIndex].position.y + 20 }
        : DOOR_POSITION;
      if (engineAgent) {
        engineAgent.position.x = deskPos.x;
        engineAgent.position.y = deskPos.y;
      }
      engine.setCurrentView(id, 'office');
    }

    engine.setCurrentView(id, 'office');
    engine.setStatusColor(id, STATUS_COLORS.working);
    engine.setAnimation(id, 'work-shake');
    engine.setFacing(id, 'up'); // face their monitor
  }

  function handleIdle(id: string): void {
    const agent = agents.find((a) => a.id === id);
    if (!agent) return;
    // Don't set status to 'idle' yet — agent needs to walk to break spot first.
    agent.currentTask = null;
    agents = [...agents];

    const engineAgent = engine.agents.get(id);
    const agentCurrentView: OfficeView = engineAgent?.currentView ?? 'office';

    // Pick activity via manager (handles capacity + room ownership)
    const assignment = activityManager.pickAndReserve(id, agent.characterType, agentCurrentView);
    const activity = assignment?.activity ?? null;
    const areaType = activity?.area ?? 'breakRoom';
    const targetView = getViewForArea(areaType);
    const rawPos = assignment?.walkTarget ?? randomPosition(areaType);
    const pos = findNearestWalkable(rawPos, targetView);
    const assignmentFacing = assignment?.facing;
    const walkSpeed = 100;

    engine.setStatusColor(id, STATUS_COLORS.walking);
    engine.setAnimation(id, 'none');

    // Schedule arrival handler that sets idle status
    const scheduleArrival = (totalDelay: number) => {
      setTimeout(() => {
        const current = agents.find((a) => a.id === id);
        if (!current) return;
        if (current.status === 'working' || current.status === 'celebrating' || current.status === 'leaving') return;

        current.status = 'idle';
        current.idleActivity = activity?.label ?? null;
        engine.setIdleActivity(id, current.idleActivity);
        agents = [...agents];

        if (activity) {
          arriveAtActivity(id, activity, assignmentFacing);
        } else {
          engine.setStatusColor(id, STATUS_COLORS.idle);
          engine.setAnimation(id, 'idle');
        }

        const stagger = Math.random() * IDLE_STAGGER_MAX;
        startIdleCycle(id, randomIdleDuration() + stagger);
      }, totalDelay);
    };

    if (targetView !== agentCurrentView) {
      // Cross-view: walk to exit, fade, teleport, fade in, walk to destination
      const exitPos = findNearestWalkable(VIEW_DOOR_POSITIONS[agentCurrentView], agentCurrentView);
      const currentPos = engineAgent?.position ?? DOOR_POSITION;
      const exitPath = findPath(currentPos, exitPos, agentCurrentView);

      if (exitPath.length > 0) {
        engine.moveAgentAlongPath(id, exitPath, walkSpeed);
      } else {
        engine.moveAgent(id, exitPos, 1500);
      }
      const exitDuration = exitPath.length > 0 ? pathDuration(exitPath, walkSpeed) : 1500;

      setTimeout(() => {
        const current = agents.find((a) => a.id === id);
        if (!current) return;
        if (current.status === 'working' || current.status === 'celebrating' || current.status === 'leaving') return;

        engine.setAnimation(id, 'fade-out');

        setTimeout(() => {
          const still = agents.find((a) => a.id === id);
          if (!still) return;
          if (still.status === 'working' || still.status === 'celebrating' || still.status === 'leaving') return;

          const entrancePos = findNearestWalkable(VIEW_DOOR_POSITIONS[targetView], targetView);
          const ea = engine.agents.get(id);
          if (ea) {
            ea.position.x = entrancePos.x;
            ea.position.y = entrancePos.y;
          }
          engine.setCurrentView(id, targetView);
          engine.setAnimation(id, 'fade-in');

          setTimeout(() => {
            const alive = agents.find((a) => a.id === id);
            if (!alive) return;
            if (alive.status === 'working' || alive.status === 'celebrating' || alive.status === 'leaving') return;

            const entryPath = findPath(entrancePos, pos, targetView);
            engine.setAnimation(id, 'none');

            if (entryPath.length > 0) {
              engine.moveAgentAlongPath(id, entryPath, walkSpeed);
            } else {
              engine.moveAgent(id, pos, 2000);
            }

            const entryDuration = entryPath.length > 0 ? pathDuration(entryPath, walkSpeed) : 2000;
            scheduleArrival(entryDuration + 200);
          }, 350);
        }, 550);
      }, exitDuration + 100);
    } else {
      // Same view — walk directly
      const currentPos = engineAgent?.position ?? DOOR_POSITION;
      const path = findPath(currentPos, pos, targetView);
      engine.setCurrentView(id, targetView);

      if (path.length > 0) {
        engine.moveAgentAlongPath(id, path, walkSpeed);
      } else {
        engine.moveAgent(id, pos, 2000);
      }

      const walkDuration = path.length > 0 ? pathDuration(path, walkSpeed) : 2000;
      scheduleArrival(walkDuration + 200);
    }
  }

  function handleComplete(id: string, result: string): void {
    const agent = agents.find((a) => a.id === id);
    if (!agent) return;
    clearIdleTimer(id);
    clearPingPongTimer(id);
    clearPairing(id);
    activityManager.release(id);
    agent.idleActivity = null;
    agent.status = 'celebrating';
    agent.currentTask = result;
    agents = [...agents];

    // Bring back to office if in another view
    const engineAgent = engine.agents.get(id);
    if (engineAgent && engineAgent.currentView !== 'office') {
      engineAgent.position.x = DOOR_POSITION.x;
      engineAgent.position.y = DOOR_POSITION.y;
      engine.setCurrentView(id, 'office');
    }

    engine.setStatusColor(id, STATUS_COLORS.celebrating);
    engine.setAnimation(id, 'celebrate');
    engine.setFacing(id, 'down'); // face camera for celebration
    engine.setSpeechBubble(id, pickJobComplete());

    // After celebration, walk to door and leave
    setTimeout(() => {
      const a = agents.find((a) => a.id === id);
      if (!a) return;
      a.status = 'leaving';
      agents = [...agents];
      releaseDesk(id);

      const currentPos = engine.agents.get(id)?.position ?? DOOR_POSITION;
      const path = findPath(currentPos, DOOR_POSITION);
      const walkSpeed = 140; // faster, purposeful walk

      engine.setStatusColor(id, STATUS_COLORS.leaving);
      engine.setAnimation(id, 'none');

      if (path.length > 0) {
        engine.moveAgentAlongPath(id, path, walkSpeed);
      } else {
        engine.moveAgent(id, DOOR_POSITION, 1500);
      }

      const walkDuration = path.length > 0 ? pathDuration(path, walkSpeed) : 1500;

      // Fade out and either return to session idle or remove
      setTimeout(() => {
        engine.setAnimation(id, 'fade-out');
        setTimeout(() => {
          if (sessionMode && !isSessionAgent(id) && !isDemoAgent(id)) {
            // Return to session idle
            const charType = a!.characterType;
            returnToSessionIdle(id, charType);
          } else {
            removeAgent(id);
          }
        }, 600);
      }, walkDuration + 200);
    }, 2000);
  }

  /** Helper: remove a real agent and re-create as session-idle */
  function returnToSessionIdle(realId: string, charType: CharacterType): void {
    const config = CHARACTER_CATALOG.find(c => c.type === charType);
    const sessionId = `${SESSION_PREFIX}${charType}`;

    // Remove real agent
    decrementCharTypeCount(charType);
    releaseDesk(realId);
    clearIdleTimer(realId);
    clearPingPongTimer(realId);
    clearPairing(realId);
    activityManager.release(realId);
    engine.removeAgent(realId);
    agents = agents.filter(a => a.id !== realId);
    if (selectedAgentId === realId) selectedAgentId = null;

    // Re-create as session idle
    const sessionAgent: OfficeAgent = {
      id: sessionId,
      name: config?.displayName ?? charType,
      role: charType,
      characterType: charType,
      status: 'idle',
      currentTask: null,
      deskIndex: null,
      spawnedAt: new Date(),
      idleActivity: null,
    };

    agents.push(sessionAgent);
    agents = [...agents];
    sessionCharMap.set(sessionId, charType);

    const startPos = randomPosition('mainOffice');
    engine.addAgent(sessionId, charType, sessionAgent.name, startPos);
    engine.setCurrentView(sessionId, 'office');
    engine.setStatusColor(sessionId, STATUS_COLORS.idle);
    engine.setAnimation(sessionId, 'fade-in');

    setTimeout(() => {
      if (!sessionMode) return;
      engine.setAnimation(sessionId, 'idle');
      handleIdle(sessionId);
    }, 400);
  }

  function handleDismissed(id: string): void {
    const agent = agents.find((a) => a.id === id);
    if (!agent) return;
    clearIdleTimer(id);
    clearPingPongTimer(id);
    clearPairing(id);
    activityManager.release(id);

    // In session mode, return the character to idle as a session agent
    if (sessionMode && !isSessionAgent(id) && !isDemoAgent(id)) {
      returnToSessionIdle(id, agent.characterType);
      return;
    }

    agent.status = 'leaving';
    agent.currentTask = null;
    agent.idleActivity = null;
    agents = [...agents];
    releaseDesk(id);
    engine.setFacing(id, 'down'); // face camera when leaving

    // Bring back to office if in another view
    const engineAgent = engine.agents.get(id);
    if (engineAgent && engineAgent.currentView !== 'office') {
      engineAgent.position.x = DOOR_POSITION.x;
      engineAgent.position.y = DOOR_POSITION.y;
      engine.setCurrentView(id, 'office');
    }

    const currentPos = engine.agents.get(id)?.position ?? DOOR_POSITION;
    const path = findPath(currentPos, DOOR_POSITION);
    const walkSpeed = 140;

    engine.setStatusColor(id, STATUS_COLORS.leaving);
    engine.setAnimation(id, 'none');

    if (path.length > 0) {
      engine.moveAgentAlongPath(id, path, walkSpeed);
    } else {
      engine.moveAgent(id, DOOR_POSITION, 1500);
    }

    const walkDuration = path.length > 0 ? pathDuration(path, walkSpeed) : 1500;

    setTimeout(() => {
      engine.setAnimation(id, 'fade-out');
      setTimeout(() => removeAgent(id), 600);
    }, walkDuration + 200);
  }

  return {
    get agents() { return agents; },
    get desks() { return desks; },
    get selectedAgentId() { return selectedAgentId; },
    set selectedAgentId(v) { selectedAgentId = v; },
    get selectedAgent() { return selectedAgent; },
    get demoMode() { return demoMode; },
    get sessionMode() { return sessionMode; },
    get canDemo() { return canDemo; },
    engine,

    toggleDemo,
    enterSessionMode,
    exitSessionMode,
    ensureAutoIdle() {
      if (!demoMode && !sessionMode && canDemo) toggleDemo();
    },
    handleSpawn,
    handleWorking,
    handleIdle,
    handleComplete,
    handleDismissed,
    reset() {
      for (const id of idleTimers.keys()) clearIdleTimer(id);
      for (const id of pingPongWaitTimers.keys()) clearPingPongTimer(id);
      stopSocialScanner();
      agents = [];
      desks = DESKS.map((d) => ({ ...d, occupantId: null }));
      selectedAgentId = null;
      nextCharacterIndex = 0;
      demoMode = false;
      sessionMode = false;
      sessionCharMap.clear();
      activityManager.reset();
      engine.clear();
    },

    selectAgent(id: string) { selectedAgentId = id; },
    dismissInspector() { selectedAgentId = null; },
    renameAgent(id: string, newName: string) {
      const agent = agents.find((a) => a.id === id);
      if (agent) {
        agent.name = newName;
        agents = [...agents];
        engine.updateName(id, newName);
      }
    },
  };
}
