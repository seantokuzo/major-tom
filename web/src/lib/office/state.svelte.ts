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
import { ThemeEngine } from './theme-engine';
import { MoodEngine, pickMoodSpeech } from './mood-engine';
import type { AgentMood } from './mood-engine';
import { pickEventReaction } from './interactions';
import type { OfficeEvent } from './interactions';

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
  /** Theme engine — day/night cycle + seasonal themes */
  themeEngine: ThemeEngine;
  /** Mood engine — per-agent mood tracking */
  moodEngine: MoodEngine;

  readonly selectedAgent: OfficeAgent | null;

  handleSpawn(id: string, role: string, task: string): void;
  handleWorking(id: string, task: string): void;
  /** Record a tool error or denial for frustrated mood */
  handleError(id: string): void;
  handleIdle(id: string): void;
  handleComplete(id: string, result: string): void;
  handleDismissed(id: string): void;
  /** Broadcast an office event — triggers reactions from nearby agents */
  broadcastEvent(event: OfficeEvent, sourceAgentId?: string): void;
  /** Get the current mood for an agent */
  getAgentMood(agentId: string): AgentMood;
  reset(): void;

  selectAgent(id: string): void;
  dismissInspector(): void;
  renameAgent(id: string, newName: string): void;
}

export function createOfficeState(): OfficeState {
  let agents = $state<OfficeAgent[]>([]);
  let desks = $state<Desk[]>(DESKS.map((d) => ({ ...d, occupantId: null })));
  let selectedAgentId = $state<string | null>(null);
  const engine = new OfficeEngine();
  const themeEngine = new ThemeEngine();
  const moodEngine = new MoodEngine();

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

  // ── Sprite Pool ─────────────────────────────────────────────
  /** Idle sprite ID prefix — permanent office residents not bound to any agent */
  const IDLE_PREFIX = 'idle-';

  /** Available sprite types not currently bound to an agent */
  const spritePool = new Set<CharacterType>(ALL_CHARACTER_TYPES);

  function isIdleSprite(id: string): boolean {
    return id.startsWith(IDLE_PREFIX);
  }

  function claimRandomSprite(): CharacterType | null {
    if (spritePool.size === 0) return null;
    const available = Array.from(spritePool);
    const picked = available[Math.floor(Math.random() * available.length)];
    spritePool.delete(picked);
    return picked;
  }

  function releaseSprite(type: CharacterType): void {
    spritePool.add(type);
  }

  // ── Character / Desk Assignment ────────────────────────────

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
    clearIdleTimer(id);
    clearPingPongTimer(id);
    clearPairing(id);
    socialNegotiating.delete(id);
    activityManager.release(id);
    releaseDesk(id);
    // Drop mood-engine state too — without this, completed agents kept
    // their mood records indefinitely (Copilot review on PR #89).
    moodEngine.removeAgent(id);
    engine.removeAgent(id);
    agents = agents.filter((a) => a.id !== id);
    if (selectedAgentId === id) selectedAgentId = null;
  }

  // ── Lifecycle Handlers ─────────────────────────────────────

  function handleSpawn(id: string, role: string, task: string): void {
    if (agents.some((a) => a.id === id)) return;

    const spriteType = claimRandomSprite();

    // Grab position from idle sprite before removing it
    let startPos = DOOR_POSITION;
    let startView: OfficeView = 'office';

    if (spriteType) {
      const idleSpriteId = `${IDLE_PREFIX}${spriteType}`;
      const engineAgent = engine.agents.get(idleSpriteId);
      if (engineAgent) {
        startPos = { ...engineAgent.position };
        startView = engineAgent.currentView ?? 'office';
      }

      // Remove idle sprite
      clearIdleTimer(idleSpriteId);
      clearPingPongTimer(idleSpriteId);
      clearPairing(idleSpriteId);
      activityManager.release(idleSpriteId);
      engine.removeAgent(idleSpriteId);
      agents = agents.filter((a) => a.id !== idleSpriteId);
    }

    const characterType = spriteType ?? ALL_CHARACTER_TYPES[agents.length % ALL_CHARACTER_TYPES.length];
    const deskIndex = assignNextAvailableDesk(id);
    const displayName = role.charAt(0).toUpperCase() + role.slice(1);

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
    agents = [...agents];

    // If sprite was in another view, start from office door instead
    if (startView !== 'office') {
      startPos = VIEW_DOOR_POSITIONS['office'] ?? DOOR_POSITION;
    }

    engine.addAgent(id, characterType, displayName, startPos);
    engine.setStatusColor(id, STATUS_COLORS.spawning);

    if (deskIndex !== null) {
      const desk = desks[deskIndex];
      if (desk) {
        // Walk to desk
        const seatPos = { x: desk.position.x, y: desk.position.y + 20 };
        agent.status = 'walking';
        agents = [...agents];
        engine.setAnimation(id, 'none');
        const path = findPath(startPos, seatPos);
        const walkSpeed = 120;

        if (path.length > 0) {
          engine.moveAgentAlongPath(id, path, walkSpeed);
        } else {
          engine.moveAgent(id, seatPos, 1500);
        }

        const walkDuration = path.length > 0 ? pathDuration(path, walkSpeed) : 1500;
        setTimeout(() => {
          const a = agents.find((x) => x.id === id);
          if (a) {
            a.status = 'working';
            agents = [...agents];
          }
          engine.setAnimation(id, 'work-shake');
          engine.setStatusColor(id, STATUS_COLORS.working);
          engine.setFacing(id, 'up');
          moodEngine.recordActivity(id);
        }, walkDuration + 200);
      }
    } else {
      engine.setAnimation(id, 'idle');
      engine.setStatusColor(id, STATUS_COLORS.idle);
      handleIdle(id);
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

      // Fade out and return sprite to idle pool
      setTimeout(() => {
        engine.setAnimation(id, 'fade-out');
        setTimeout(() => {
          const charType = a!.characterType;
          removeAgent(id);
          returnToIdlePool(charType);
        }, 600);
      }, walkDuration + 200);
    }, 2000);
  }

  /** Return a character type to the idle sprite pool after agent removal */
  function returnToIdlePool(charType: CharacterType): void {
    releaseSprite(charType);

    const config = CHARACTER_CATALOG.find((c) => c.type === charType);
    const idleId = `${IDLE_PREFIX}${charType}`;

    // Don't re-create if already exists (edge case)
    if (agents.some((a) => a.id === idleId)) return;

    const idleAgent: OfficeAgent = {
      id: idleId,
      name: config?.displayName ?? charType,
      role: charType,
      characterType: charType,
      status: 'idle',
      currentTask: null,
      deskIndex: null,
      spawnedAt: new Date(),
      idleActivity: null,
    };

    agents.push(idleAgent);
    agents = [...agents];

    const startPos = randomPosition('mainOffice');
    engine.addAgent(idleId, charType, idleAgent.name, startPos);
    engine.setStatusColor(idleId, STATUS_COLORS.idle);
    engine.setAnimation(idleId, 'fade-in');

    setTimeout(() => {
      engine.setAnimation(idleId, 'idle');
      handleIdle(idleId);
    }, 400);
  }

  function handleDismissed(id: string): void {
    const agent = agents.find((a) => a.id === id);
    if (!agent) return;

    // Skip idle sprites
    if (isIdleSprite(id)) return;

    const charType = agent.characterType;

    // Mark the agent as leaving so the UI (AgentInspector etc.) can
    // render its terminal state during the fade-out window. Caught by
    // Copilot review on PR #89 — without this, AgentInspector's new
    // `isTerminal = agent.status === 'leaving'` check never fires.
    agent.status = 'leaving';
    agents = [...agents];

    // Fade out animation, then delegate the rest of the cleanup to
    // removeAgent() so all per-agent bookkeeping (socialNegotiating,
    // pairings, activity manager, desks, timers, moodEngine) is cleared
    // in exactly one place. Skipping that path previously left stale ids
    // in `socialNegotiating` (Copilot review).
    engine.setAnimation(id, 'fade-out');
    setTimeout(() => {
      removeAgent(id);

      // Return sprite to idle pool
      returnToIdlePool(charType);
    }, 600);
  }

  // ── Office Event Broadcasting ──────────────────────────────────
  // When a significant session event happens, nearby agents react.

  function broadcastEvent(event: OfficeEvent, sourceAgentId?: string): void {
    // Get source position for proximity check
    const sourceEa = sourceAgentId ? engine.agents.get(sourceAgentId) : null;
    const sourcePos = sourceEa?.position ?? null;
    const MAX_REACTION_DISTANCE = 200;

    for (const agent of agents) {
      if (agent.id === sourceAgentId) continue;
      if (agent.status !== 'idle') continue;
      const ea = engine.agents.get(agent.id);
      if (!ea || ea.speechBubble) continue;

      // Proximity check — only agents within MAX_REACTION_DISTANCE react
      if (sourcePos) {
        const dx = ea.position.x - sourcePos.x;
        const dy = ea.position.y - sourcePos.y;
        if (Math.sqrt(dx * dx + dy * dy) > MAX_REACTION_DISTANCE) continue;
      }

      // 30% chance for each nearby idle agent to react
      if (Math.random() > 0.3) continue;
      const reaction = pickEventReaction(event);
      engine.setSpeechBubble(agent.id, reaction, 2000);
    }
  }

  function getAgentMood(agentId: string): AgentMood {
    return moodEngine.getMood(agentId);
  }

  // ── Mood-Driven Speech Integration ────────────────────────────
  // On mood update ticks, occasionally show mood-based speech bubbles.

  function moodSpeechCheck(): void {
    for (const agent of agents) {
      if (agent.status !== 'idle') continue;
      const ea = engine.agents.get(agent.id);
      if (!ea || ea.speechBubble) continue;

      const mood = moodEngine.getMood(agent.id);
      // Only moody agents speak: bored 8%, frustrated 10%, excited 12%
      let chance = 0;
      if (mood === 'bored') chance = 0.08;
      else if (mood === 'frustrated') chance = 0.10;
      else if (mood === 'excited') chance = 0.12;
      else continue;

      if (Math.random() > chance) continue;
      const text = pickMoodSpeech(mood);
      if (text) engine.setSpeechBubble(agent.id, text, 2500);
    }
  }

  // Run mood speech check every 30 seconds alongside mood updates
  let moodSpeechInterval: ReturnType<typeof setInterval> | null = null;

  function startMoodSpeechScanner(): void {
    if (moodSpeechInterval) return;
    moodSpeechInterval = setInterval(() => {
      moodEngine.updateAllMoods();
      moodSpeechCheck();
    }, 30_000);
  }

  function stopMoodSpeechScanner(): void {
    if (moodSpeechInterval) {
      clearInterval(moodSpeechInterval);
      moodSpeechInterval = null;
    }
  }

  // ── Populate Idle Sprites ──────────────────────────────────
  // Create all 14 character types as permanent idle residents on startup.

  function populateIdleSprites(): void {
    ALL_CHARACTER_TYPES.forEach((charType, i) => {
      const idleId = `${IDLE_PREFIX}${charType}`;
      if (agents.some((a) => a.id === idleId)) return;

      const config = CHARACTER_CATALOG.find((c) => c.type === charType);
      const name = config?.displayName ?? charType;

      const idleAgent: OfficeAgent = {
        id: idleId,
        name,
        role: charType,
        characterType: charType,
        status: 'idle',
        currentTask: null,
        deskIndex: null,
        spawnedAt: new Date(),
        idleActivity: null,
      };

      agents.push(idleAgent);

      const startPos = randomPosition('mainOffice');
      engine.addAgent(idleId, charType, name, startPos);
      engine.setStatusColor(idleId, STATUS_COLORS.idle);

      // Stagger idle activity start
      setTimeout(() => {
        const current = agents.find((a) => a.id === idleId);
        if (!current) return;
        engine.setAnimation(idleId, 'idle');
        handleIdle(idleId);
      }, i * 150 + 400);
    });

    agents = [...agents];
    startSocialScanner();
  }

  // Populate on creation
  populateIdleSprites();

  return {
    get agents() { return agents; },
    get desks() { return desks; },
    get selectedAgentId() { return selectedAgentId; },
    set selectedAgentId(v) { selectedAgentId = v; },
    get selectedAgent() { return selectedAgent; },
    engine,
    themeEngine,
    moodEngine,

    handleSpawn(id: string, role: string, task: string) {
      handleSpawn(id, role, task);
      moodEngine.addAgent(id);
      startMoodSpeechScanner();
    },
    handleWorking(id: string, task: string) {
      handleWorking(id, task);
      moodEngine.recordActivity(id);
    },
    /** Record a tool error or denial for frustrated mood */
    handleError(id: string) {
      moodEngine.recordError(id);
    },
    handleIdle(id: string) {
      handleIdle(id);
      moodEngine.recordIdle(id);
    },
    handleComplete(id: string, result: string) {
      handleComplete(id, result);
      moodEngine.recordCompletion(id);
      broadcastEvent('task_complete', id);
    },
    handleDismissed(id: string) {
      handleDismissed(id);
    },
    broadcastEvent,
    getAgentMood,
    reset() {
      for (const id of idleTimers.keys()) clearIdleTimer(id);
      for (const id of pingPongWaitTimers.keys()) clearPingPongTimer(id);
      stopSocialScanner();
      stopMoodSpeechScanner();
      agents = [];
      desks = DESKS.map((d) => ({ ...d, occupantId: null }));
      selectedAgentId = null;
      activityManager.reset();
      moodEngine.reset();
      engine.clear();
      spritePool.clear();
      ALL_CHARACTER_TYPES.forEach((t) => spritePool.add(t));
      populateIdleSprites();
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
