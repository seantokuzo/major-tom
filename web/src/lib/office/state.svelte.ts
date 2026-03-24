// Office state — Svelte 5 runes-based state management
// Ported from iOS OfficeViewModel.swift

import type { OfficeAgent, CharacterType, Desk, OfficeAreaType, IdleActivity, OfficeView } from './types';
import {
  ALL_CHARACTER_TYPES,
  HUMAN_IDLE_ACTIVITIES, DOG_IDLE_ACTIVITIES,
  DOG_PARK_HUMAN_ACTIVITIES, DOG_PARK_DOG_ACTIVITIES,
  GYM_HUMAN_ACTIVITIES, GYM_DOG_ACTIVITIES,
  SPRITE_ST_HUMAN_ACTIVITIES, SPRITE_ST_DOG_ACTIVITIES,
} from './types';
import { DESKS, DOOR_POSITION, OFFICE_VIEWS, VIEW_DOOR_POSITIONS, randomPosition, getViewForArea } from './layout';
import { DOG_TYPES, CHARACTER_VIEW_PREFERENCES } from './characters';
import { OfficeEngine } from './engine';
import { findPath, findNearestWalkable, pathDuration } from './navigation';
import { pickJobComplete, pickDogBark, pickDogBeg, pickGeneralIdle } from './speech';

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

/** Get the area types belonging to a given view */
function getViewAreaTypes(view: OfficeView): OfficeAreaType[] {
  const viewConfig = OFFICE_VIEWS.find((v) => v.id === view);
  return viewConfig?.areas ?? [];
}

/** Pick a random idle activity for a character, biased toward preferred views */
function pickIdleActivity(characterType: CharacterType, currentView?: OfficeView): IdleActivity | null {
  const isDog = DOG_TYPES.has(characterType);

  // Get view preferences for this character
  const viewPrefs = CHARACTER_VIEW_PREFERENCES[characterType] ?? ['office'];

  // Weighted random: 60% chance stay in current view (or office), 40% chance other view
  const baseView = currentView ?? 'office';
  const useOtherView = Math.random() < 0.4 && viewPrefs.length > 1;

  let targetView: OfficeView;
  if (useOtherView) {
    // Pick a random different view from preferences
    const otherViews = viewPrefs.filter((v) => v !== baseView);
    if (otherViews.length > 0) {
      targetView = otherViews[Math.floor(Math.random() * otherViews.length)];
    } else {
      targetView = baseView;
    }
  } else {
    targetView = baseView;
  }

  // Gate: dogs cannot visit the gym
  if (isDog && targetView === 'gym') {
    targetView = 'office';
  }

  // Merge all activity maps
  const allActivities: Record<string, IdleActivity[]> = isDog
    ? { ...DOG_IDLE_ACTIVITIES, ...DOG_PARK_DOG_ACTIVITIES, ...GYM_DOG_ACTIVITIES, ...SPRITE_ST_DOG_ACTIVITIES }
    : { ...HUMAN_IDLE_ACTIVITIES, ...DOG_PARK_HUMAN_ACTIVITIES, ...GYM_HUMAN_ACTIVITIES, ...SPRITE_ST_HUMAN_ACTIVITIES };

  // Filter to only activities in the target view's areas
  const viewAreas = getViewAreaTypes(targetView);
  const available: IdleActivity[] = [];
  for (const areaType of viewAreas) {
    const activities = allActivities[areaType];
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
  /** Demo mode active — fake agents populating the office */
  demoMode: boolean;
  /** Whether demo toggle is available (no real agents present) */
  readonly canDemo: boolean;

  toggleDemo(): void;
  /** Auto-start idle demo if no real agents present. Idempotent — safe to call repeatedly. */
  ensureAutoIdle(): void;
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
  let nextCharacterIndex = 0;

  const engine = new OfficeEngine();

  /** Demo agent ID prefix — used to distinguish fake agents from real ones */
  const DEMO_PREFIX = 'demo-';

  /** Check if an agent is a demo agent */
  function isDemoAgent(id: string): boolean {
    return id.startsWith(DEMO_PREFIX);
  }

  /** Whether demo toggle is available (no real agents present) */
  const canDemo = $derived.by(() => {
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
    // Ping pong table center is at approximately {x: 480, y: 579}
    // (table position {x: 420, y: 545} + {w: 120, h: 68} / 2)
    const tableCenter = { x: 480, y: 579 };
    const leftPos = { x: 410, y: tableCenter.y };
    const rightPos = { x: 550, y: tableCenter.y };

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
    const activity = pickIdleActivity(agent.characterType, agentCurrentView);
    if (!activity) {
      // No activities available, just schedule next check
      startIdleCycle(id);
      return;
    }

    // Set activity label on both state agent and engine agent
    agent.idleActivity = activity.label;
    engine.setIdleActivity(id, activity.label);
    agents = [...agents];

    const targetView = getViewForArea(activity.area);
    const rawPos = activity.target ?? randomPosition(activity.area);
    const pos = findNearestWalkable(rawPos, targetView);
    const walkSpeed = 100; // casual walking pace

    if (targetView !== agentCurrentView) {
      // ── Cross-view transition ────────────────────────
      // 1. Walk to exit of current view
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

      // 2. After reaching exit, fade out
      setTimeout(() => {
        const current = agents.find((a) => a.id === id);
        if (!current || current.status !== 'idle') return;

        engine.setAnimation(id, 'fade-out');

        // 3. After fade-out, teleport to entrance of new view
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

          // 4. Fade in
          engine.setAnimation(id, 'fade-in');

          // 5. After fade-in, walk to activity destination
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

            // 6. After arriving, settle into idle
            setTimeout(() => {
              arriveAtActivity(id, activity);
            }, entryWalkDuration + 200);
          }, 350); // fade-in duration + small buffer
        }, 550); // fade-out duration + small buffer
      }, exitWalkDuration + 100);
    } else {
      // ── Same-view transition (original logic) ────────
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
        arriveAtActivity(id, activity);
      }, walkDuration + 200);
    }

    // Schedule next activity switch
    startIdleCycle(id);
  }

  /** Common arrival logic after walking to an activity destination */
  function arriveAtActivity(id: string, activity: IdleActivity): void {
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
        releaseDesk(id);
        engine.removeAgent(id);
      }
      agents = agents.filter((a) => !demoIds.has(a.id));
      if (selectedAgentId && demoIds.has(selectedAgentId)) selectedAgentId = null;
      nextCharacterIndex = 0;
    }, 600);
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
    // Keep previous status during the walk so the inspector badge stays accurate.
    agent.currentTask = null;
    agents = [...agents];

    const engineAgent = engine.agents.get(id);
    const agentCurrentView: OfficeView = engineAgent?.currentView ?? 'office';

    // Pick an initial idle activity (view-aware)
    const activity = pickIdleActivity(agent.characterType, agentCurrentView);
    const areaType = activity?.area ?? 'breakRoom';
    const targetView = getViewForArea(areaType);
    const rawPos = activity?.target ?? randomPosition(areaType);
    const pos = findNearestWalkable(rawPos, targetView);
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
          arriveAtActivity(id, activity);
        } else {
          engine.setStatusColor(id, STATUS_COLORS.idle);
          engine.setAnimation(id, 'idle');
        }

        // Start cycling with a staggered initial delay so agents don't all switch together
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
    get canDemo() { return canDemo; },
    engine,

    toggleDemo,
    ensureAutoIdle() {
      if (!demoMode && canDemo) toggleDemo();
    },
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
