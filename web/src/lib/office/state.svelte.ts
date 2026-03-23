// Office state — Svelte 5 runes-based state management
// Ported from iOS OfficeViewModel.swift

import type { OfficeAgent, CharacterType, Desk, OfficeAreaType, BreakDestination, IdleActivity } from './types';
import { ALL_CHARACTER_TYPES, HUMAN_IDLE_ACTIVITIES, DOG_IDLE_ACTIVITIES } from './types';
import { DESKS, DOOR_POSITION, randomPosition, getViewForArea } from './layout';
import { getCharacterConfig, DOG_TYPES } from './characters';
import { OfficeEngine } from './engine';
import { findPath, findNearestWalkable, pathDuration } from './navigation';

// ── Status colors ────────────────────────────────────────────

export const STATUS_COLORS: Record<string, string> = {
  spawning: 'rgb(153, 153, 153)',
  walking: 'rgb(102, 179, 255)',
  working: 'rgb(77, 217, 115)',
  idle: 'rgb(242, 191, 77)',
  celebrating: 'rgb(242, 166, 64)',
  leaving: 'rgb(179, 77, 77)',
};

// ── Break destination → area type mapping ────────────────────

const BREAK_TO_AREA: Record<BreakDestination, OfficeAreaType> = {
  strategyRoom: 'strategyRoom',
  breakRoom: 'breakRoom',
  kitchen: 'kitchen',
};

// ── Idle Activity Cycling ────────────────────────────────────

/** Min/max time (ms) an agent stays on one idle activity before switching */
const IDLE_CYCLE_MIN = 45_000;
const IDLE_CYCLE_MAX = 90_000;

/** Initial stagger window — agents start cycling at random offsets so they don't all switch at once */
const IDLE_STAGGER_MAX = 20_000;

function randomIdleDuration(): number {
  return IDLE_CYCLE_MIN + Math.random() * (IDLE_CYCLE_MAX - IDLE_CYCLE_MIN);
}

/** Pick a random idle activity for a character based on their break destinations */
function pickIdleActivity(characterType: CharacterType): IdleActivity | null {
  const config = getCharacterConfig(characterType);
  const isDog = DOG_TYPES.has(characterType);
  const activityMap = isDog ? DOG_IDLE_ACTIVITIES : HUMAN_IDLE_ACTIVITIES;

  // Collect all available activities from this character's allowed break areas
  const available: IdleActivity[] = [];
  for (const dest of config.breakBehaviors) {
    const areaKey = BREAK_TO_AREA[dest];
    const activities = activityMap[areaKey] ?? activityMap[dest];
    if (activities) available.push(...activities);
  }
  if (available.length === 0) return null;
  return available[Math.floor(Math.random() * available.length)];
}

// ── Office State ─────────────────────────────────────────────

export interface OfficeState {
  agents: OfficeAgent[];
  desks: Desk[];
  selectedAgentId: string | null;
  engine: OfficeEngine;

  readonly selectedAgent: OfficeAgent | null;

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
  let nextCharacterIndex = 0;

  const engine = new OfficeEngine();

  /** Per-agent idle cycling timers (agent id → timeout handle) */
  const idleTimers = new Map<string, ReturnType<typeof setTimeout>>();

  /** Ping pong pairing wait timers (agent id → timeout handle) */
  const pingPongWaitTimers = new Map<string, ReturnType<typeof setTimeout>>();

  const selectedAgent = $derived.by(() => {
    if (!selectedAgentId) return null;
    return agents.find((a) => a.id === selectedAgentId) ?? null;
  });

  // ── Character / Desk Assignment ────────────────────────────

  function assignNextCharacterType(): CharacterType {
    const type = ALL_CHARACTER_TYPES[nextCharacterIndex % ALL_CHARACTER_TYPES.length];
    nextCharacterIndex++;
    return type;
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

  /** Set up ping pong pairing for an agent arriving at the table */
  function setupPingPong(agentId: string): void {
    // Ping pong table center is at approximately {x: 370, y: 468}
    // (table position {x: 320, y: 440} + {w: 100, h: 56} / 2)
    const tableCenter = { x: 370, y: 468 };
    const leftPos = { x: 310, y: tableCenter.y };
    const rightPos = { x: 430, y: tableCenter.y };

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
        // Partner goes left, new agent goes right
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
        // No partner arrived, switch to a different activity
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

  /** Switch an idle agent to a new activity + position */
  function cycleIdleActivity(id: string): void {
    const agent = agents.find((a) => a.id === id);
    if (!agent) return;
    // Only cycle if still idle
    if (agent.status !== 'idle') {
      clearIdleTimer(id);
      return;
    }

    const activity = pickIdleActivity(agent.characterType);
    if (!activity) {
      // No activities available, just schedule next check
      startIdleCycle(id);
      return;
    }

    // Set activity label on both state agent and engine agent
    agent.idleActivity = activity.label;
    engine.setIdleActivity(id, activity.label);
    agents = [...agents];

    // Walk to new position in the activity's area via pathfinding
    const pos = findNearestWalkable(randomPosition(activity.area));
    const currentPos = engine.agents.get(id)?.position ?? DOOR_POSITION;
    const path = findPath(currentPos, pos);
    const walkSpeed = 100; // casual walking pace

    engine.setStatusColor(id, STATUS_COLORS.walking);
    engine.setAnimation(id, 'none');
    engine.setCurrentView(id, getViewForArea(activity.area));

    if (path.length > 0) {
      engine.moveAgentAlongPath(id, path, walkSpeed);
    } else {
      engine.moveAgent(id, pos, 2000);
    }

    // After arriving, resume idle animation and set facing
    const walkDuration = path.length > 0 ? pathDuration(path, walkSpeed) : 2000;
    setTimeout(() => {
      const current = agents.find((a) => a.id === id);
      if (!current || current.status !== 'idle') return;

      engine.setStatusColor(id, STATUS_COLORS.idle);
      engine.setAnimation(id, 'idle');

      // Set facing direction based on activity
      setFacingForActivity(id, activity.label);

      // Set up ping pong pairing if applicable
      if (activity.label === 'Playing ping pong') {
        setupPingPong(id);
      }
    }, walkDuration + 200);

    // Schedule next activity switch
    startIdleCycle(id);
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
    releaseDesk(id);
    engine.removeAgent(id);
    agents = agents.filter((a) => a.id !== id);
    if (selectedAgentId === id) selectedAgentId = null;
  }

  // ── Lifecycle Handlers ─────────────────────────────────────

  function handleSpawn(id: string, role: string, task: string): void {
    if (agents.some((a) => a.id === id)) return;

    const characterType = assignNextCharacterType();
    const deskIndex = assignNextAvailableDesk(id);

    const agent: OfficeAgent = {
      id,
      name: role.charAt(0).toUpperCase() + role.slice(1),
      role,
      characterType,
      status: 'spawning',
      currentTask: task,
      deskIndex,
      spawnedAt: new Date(),
      idleActivity: null,
    };

    agents.push(agent);

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
    agent.status = 'working';
    agent.currentTask = task;
    agent.idleActivity = null;
    engine.setIdleActivity(id, null);
    engine.setCurrentView(id, 'office');
    agents = [...agents];

    engine.setStatusColor(id, STATUS_COLORS.working);
    engine.setAnimation(id, 'work-shake');
    engine.setFacing(id, 'up'); // face their monitor
  }

  function handleIdle(id: string): void {
    const agent = agents.find((a) => a.id === id);
    if (!agent) return;
    // Don't set status to 'idle' yet — agent needs to walk to break spot first.
    // Keep previous status during the walk so the inspector badge stays accurate.
    agent.currentTask = null;
    agents = [...agents];

    // Pick an initial idle activity
    const activity = pickIdleActivity(agent.characterType);
    const areaType = activity?.area ?? 'breakRoom';
    const pos = findNearestWalkable(randomPosition(areaType));
    const currentPos = engine.agents.get(id)?.position ?? DOOR_POSITION;
    const path = findPath(currentPos, pos);
    const walkSpeed = 100;

    engine.setStatusColor(id, STATUS_COLORS.walking);
    engine.setAnimation(id, 'none');
    engine.setCurrentView(id, getViewForArea(areaType));

    if (path.length > 0) {
      engine.moveAgentAlongPath(id, path, walkSpeed);
    } else {
      engine.moveAgent(id, pos, 2000);
    }

    const walkDuration = path.length > 0 ? pathDuration(path, walkSpeed) : 2000;

    // After arrival, set idle status and start idle animation + cycling.
    // Guard: if the agent transitioned to another state before timeout fires, bail out.
    setTimeout(() => {
      const current = agents.find((a) => a.id === id);
      if (!current) return;
      if (current.status === 'working' || current.status === 'celebrating' || current.status === 'leaving') return;

      current.status = 'idle';
      current.idleActivity = activity?.label ?? null;
      engine.setIdleActivity(id, current.idleActivity);
      agents = [...agents];
      engine.setStatusColor(id, STATUS_COLORS.idle);
      engine.setAnimation(id, 'idle');

      // Set facing direction based on activity
      if (activity) {
        setFacingForActivity(id, activity.label);
        if (activity.label === 'Playing ping pong') {
          setupPingPong(id);
        }
      }

      // Start cycling with a staggered initial delay so agents don't all switch together
      const stagger = Math.random() * IDLE_STAGGER_MAX;
      startIdleCycle(id, randomIdleDuration() + stagger);
    }, walkDuration + 200);
  }

  function handleComplete(id: string, result: string): void {
    const agent = agents.find((a) => a.id === id);
    if (!agent) return;
    clearIdleTimer(id);
    clearPingPongTimer(id);
    clearPairing(id);
    agent.idleActivity = null;
    agent.status = 'celebrating';
    agent.currentTask = result;
    agents = [...agents];

    engine.setStatusColor(id, STATUS_COLORS.celebrating);
    engine.setAnimation(id, 'celebrate');
    engine.setFacing(id, 'down'); // face camera for celebration

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

      // Fade out and remove
      setTimeout(() => {
        engine.setAnimation(id, 'fade-out');
        setTimeout(() => removeAgent(id), 600);
      }, walkDuration + 200);
    }, 2000);
  }

  function handleDismissed(id: string): void {
    const agent = agents.find((a) => a.id === id);
    if (!agent) return;
    clearIdleTimer(id);
    clearPingPongTimer(id);
    clearPairing(id);
    agent.status = 'leaving';
    agent.currentTask = null;
    agent.idleActivity = null;
    agents = [...agents];
    releaseDesk(id);
    engine.setFacing(id, 'down'); // face camera when leaving

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
    engine,

    handleSpawn,
    handleWorking,
    handleIdle,
    handleComplete,
    handleDismissed,
    reset() {
      for (const id of idleTimers.keys()) clearIdleTimer(id);
      for (const id of pingPongWaitTimers.keys()) clearPingPongTimer(id);
      agents = [];
      desks = DESKS.map((d) => ({ ...d, occupantId: null }));
      selectedAgentId = null;
      nextCharacterIndex = 0;
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
