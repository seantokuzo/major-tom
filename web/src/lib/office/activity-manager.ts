// Activity Manager — Station capacity, room ownership, and smart activity selection
// Tracks which furniture/objects are occupied, enforces capacity limits,
// and gates Sprite St. bedrooms by character ownership.

import type { CharacterType, IdleActivity, OfficeAreaType, OfficeView, Point } from './types';
import type { FacingDirection } from './engine';
import {
  HUMAN_IDLE_ACTIVITIES, DOG_IDLE_ACTIVITIES,
  DOG_PARK_HUMAN_ACTIVITIES, DOG_PARK_DOG_ACTIVITIES,
  GYM_HUMAN_ACTIVITIES, GYM_DOG_ACTIVITIES,
  SPRITE_ST_HUMAN_ACTIVITIES, SPRITE_ST_DOG_ACTIVITIES,
  CHARACTER_BEDROOM,
} from './types';
import { DOG_TYPES, CHARACTER_VIEW_PREFERENCES } from './characters';
import { OFFICE_VIEWS, randomPosition } from './layout';

// ── Types ─────────────────────────────────────────────────

export interface StationSlot {
  position: Point;
  facing: FacingDirection;
  occupantId: string | null;
}

export interface Station {
  id: string;
  view: OfficeView;
  area: OfficeAreaType;
  /** Activity labels managed by this station */
  activities: string[];
  type: 'single' | 'multi' | 'paired';
  slots: StationSlot[];
}

export interface ActivityAssignment {
  activity: IdleActivity;
  /** Resolved walk target (from station slot or activity.target) */
  walkTarget: Point;
  /** Facing direction at destination */
  facing: FacingDirection;
  /** Station ID if capacity-managed, null if open area */
  stationId: string | null;
  /** Slot index within station */
  slotIndex: number;
}

// ── Station Definitions ───────────────────────────────────

function createStations(): Station[] {
  const stations: Station[] = [
    // ── Kitchen (office view) ──────────────────
    {
      id: 'kitchen-coffee', view: 'office', area: 'kitchen',
      activities: ['Making coffee'], type: 'single',
      slots: [{ position: { x: 137, y: 290 }, facing: 'up', occupantId: null }],
    },
    {
      id: 'kitchen-toaster', view: 'office', area: 'kitchen',
      activities: ['Toasting bread'], type: 'single',
      slots: [{ position: { x: 25, y: 316 }, facing: 'up', occupantId: null }],
    },
    {
      id: 'kitchen-fridge', view: 'office', area: 'kitchen',
      activities: ['Raiding the fridge', 'Staring at the fridge'], type: 'single',
      slots: [{ position: { x: 252, y: 310 }, facing: 'up', occupantId: null }],
    },
    {
      id: 'kitchen-sink', view: 'office', area: 'kitchen',
      activities: ['Doing dishes'], type: 'single',
      slots: [{ position: { x: 76, y: 290 }, facing: 'up', occupantId: null }],
    },
    {
      id: 'kitchen-microwave', view: 'office', area: 'kitchen',
      activities: ['Microwaving lunch'], type: 'single',
      slots: [{ position: { x: 188, y: 290 }, facing: 'up', occupantId: null }],
    },
    {
      id: 'kitchen-table', view: 'office', area: 'kitchen',
      activities: ['Begging for scraps'], type: 'multi',
      slots: [
        { position: { x: 120, y: 462 }, facing: 'up', occupantId: null },
        { position: { x: 165, y: 462 }, facing: 'up', occupantId: null },
      ],
    },

    // ── Strategy Room (office view) ────────────
    {
      id: 'strategy-whiteboard', view: 'office', area: 'strategyRoom',
      activities: ['Planning at whiteboard', 'Brainstorming'], type: 'multi',
      slots: [
        { position: { x: 112, y: 62 }, facing: 'up', occupantId: null },
        { position: { x: 160, y: 62 }, facing: 'up', occupantId: null },
      ],
    },
    {
      id: 'strategy-table', view: 'office', area: 'strategyRoom',
      activities: ['Discussing strategy', 'Reviewing architecture'], type: 'multi',
      slots: [
        { position: { x: 97, y: 152 }, facing: 'up', occupantId: null },
        { position: { x: 147, y: 152 }, facing: 'up', occupantId: null },
        { position: { x: 197, y: 152 }, facing: 'up', occupantId: null },
        { position: { x: 147, y: 72 }, facing: 'down', occupantId: null },
      ],
    },

    // ── Break Room (office view) — corrected positions ──
    {
      id: 'break-tvCouch', view: 'office', area: 'breakRoom',
      activities: ['Watching TV', 'Playing video games', 'Watching TV (confused)'], type: 'multi',
      slots: [
        { position: { x: 755, y: 100 }, facing: 'up', occupantId: null },
        { position: { x: 800, y: 100 }, facing: 'up', occupantId: null },
        { position: { x: 840, y: 100 }, facing: 'up', occupantId: null },
      ],
    },
    {
      id: 'break-napCouch', view: 'office', area: 'breakRoom',
      activities: ['Napping on couch'], type: 'multi',
      slots: [
        { position: { x: 870, y: 418 }, facing: 'up', occupantId: null },
        { position: { x: 910, y: 418 }, facing: 'up', occupantId: null },
      ],
    },
    {
      id: 'break-beanBag', view: 'office', area: 'breakRoom',
      activities: ['Chilling in bean bag'], type: 'multi',
      slots: [
        { position: { x: 875, y: 78 }, facing: 'up', occupantId: null },
        { position: { x: 920, y: 100 }, facing: 'up', occupantId: null },
      ],
    },
    {
      id: 'break-pingPong', view: 'office', area: 'breakRoom',
      activities: ['Playing ping pong', 'Chasing ping pong ball'], type: 'paired',
      slots: [
        { position: { x: 748, y: 280 }, facing: 'right', occupantId: null },
        { position: { x: 882, y: 280 }, facing: 'left', occupantId: null },
      ],
    },

    // ── Dog Park ───────────────────────────────
    {
      id: 'park-hydrant', view: 'dogPark', area: 'dogParkField',
      activities: ['Sniffing fire hydrant'], type: 'single',
      slots: [{ position: { x: 159, y: 125 }, facing: 'up', occupantId: null }],
    },
    {
      id: 'park-bench1', view: 'dogPark', area: 'dogParkField',
      activities: ['Reading on bench'], type: 'multi',
      slots: [
        { position: { x: 90, y: 348 }, facing: 'down', occupantId: null },
        { position: { x: 122, y: 348 }, facing: 'down', occupantId: null },
      ],
    },
    {
      id: 'park-bench2', view: 'dogPark', area: 'dogParkField',
      activities: ['Sitting on bench'], type: 'multi',
      slots: [
        { position: { x: 390, y: 440 }, facing: 'down', occupantId: null },
        { position: { x: 422, y: 440 }, facing: 'down', occupantId: null },
      ],
    },
    {
      id: 'pond-bench', view: 'dogPark', area: 'dogPondArea',
      activities: ['Sitting by the pond', 'Watching dogs swim'], type: 'multi',
      slots: [
        { position: { x: 690, y: 234 }, facing: 'down', occupantId: null },
        { position: { x: 722, y: 234 }, facing: 'down', occupantId: null },
      ],
    },

    // ── Gym Floor ──────────────────────────────
    {
      id: 'gym-treadmill', view: 'gym', area: 'gymFloor',
      activities: ['Running on treadmill', 'Running on treadmill (slowly)'], type: 'multi',
      slots: [
        { position: { x: 148, y: 98 }, facing: 'up', occupantId: null },
        { position: { x: 223, y: 98 }, facing: 'up', occupantId: null },
        { position: { x: 298, y: 98 }, facing: 'up', occupantId: null },
      ],
    },
    {
      id: 'gym-weights', view: 'gym', area: 'gymFloor',
      activities: ['Lifting weights', 'Spotting a friend', 'Napping on weight bench'], type: 'multi',
      slots: [
        { position: { x: 470, y: 185 }, facing: 'up', occupantId: null },
        { position: { x: 510, y: 185 }, facing: 'up', occupantId: null },
      ],
    },
    {
      id: 'gym-punchingBag', view: 'gym', area: 'gymFloor',
      activities: ['Boxing punching bag', 'Barking at punching bag'], type: 'single',
      slots: [{ position: { x: 263, y: 322 }, facing: 'up', occupantId: null }],
    },
    {
      id: 'gym-mirror', view: 'gym', area: 'gymFloor',
      activities: ['Checking mirror form'], type: 'single',
      slots: [{ position: { x: 35, y: 195 }, facing: 'left', occupantId: null }],
    },

    // ── Yoga Studio ────────────────────────────
    {
      id: 'yoga-mat1', view: 'gym', area: 'yogaStudio',
      activities: ['Doing yoga', 'Downward dog (for real)'], type: 'single',
      slots: [{ position: { x: 675, y: 400 }, facing: 'up', occupantId: null }],
    },
    {
      id: 'yoga-mat2', view: 'gym', area: 'yogaStudio',
      activities: ['Stretching', 'Rolling on yoga mat'], type: 'single',
      slots: [{ position: { x: 763, y: 400 }, facing: 'up', occupantId: null }],
    },
    {
      id: 'yoga-mat3', view: 'gym', area: 'yogaStudio',
      activities: ['Meditating'], type: 'single',
      slots: [{ position: { x: 850, y: 400 }, facing: 'down', occupantId: null }],
    },
    {
      id: 'yoga-ball', view: 'gym', area: 'yogaStudio',
      activities: ['Balancing on exercise ball', 'Chewing exercise ball'], type: 'single',
      slots: [{ position: { x: 941, y: 385 }, facing: 'down', occupantId: null }],
    },

    // ── Locker Room ────────────────────────────
    {
      id: 'locker-fountain', view: 'gym', area: 'lockerRoom',
      activities: ['Getting water', 'Drinking from fountain'], type: 'single',
      slots: [{ position: { x: 663, y: 55 }, facing: 'up', occupantId: null }],
    },
    {
      id: 'locker-lockers', view: 'gym', area: 'lockerRoom',
      activities: ['Checking locker', 'Sniffing lockers'], type: 'multi',
      slots: [
        { position: { x: 920, y: 75 }, facing: 'right', occupantId: null },
        { position: { x: 920, y: 125 }, facing: 'right', occupantId: null },
      ],
    },
    {
      id: 'locker-mirror', view: 'gym', area: 'lockerRoom',
      activities: ['Fixing hair in mirror'], type: 'single',
      slots: [{ position: { x: 750, y: 228 }, facing: 'down', occupantId: null }],
    },
  ];

  // ── Generate Sprite Street bedroom stations ──
  const COL_W = 140;
  const ROW_H = 115;
  for (let row = 0; row < 2; row++) {
    for (let col = 0; col < 7; col++) {
      const areaKey = `bedroomRow${row + 1}Col${col + 1}` as OfficeAreaType;
      const baseX = 5 + col * COL_W;
      const baseY = row === 0 ? 5 : 5 + ROW_H;

      stations.push(
        {
          id: `bedroom-${row + 1}-${col + 1}-bed`, view: 'spriteStreet', area: areaKey,
          activities: ['Napping in bed', 'Reading in bed', 'Napping on bed', 'Hiding under bed'],
          type: 'single',
          slots: [{ position: { x: baseX + 95, y: baseY + 45 }, facing: 'left', occupantId: null }],
        },
        {
          id: `bedroom-${row + 1}-${col + 1}-closet`, view: 'spriteStreet', area: areaKey,
          activities: ['Checking closet', 'Scratching at closet'],
          type: 'single',
          slots: [{ position: { x: baseX + 25, y: baseY + 80 }, facing: 'up', occupantId: null }],
        },
        {
          id: `bedroom-${row + 1}-${col + 1}-mirror`, view: 'spriteStreet', area: areaKey,
          activities: ['Looking in mirror'],
          type: 'single',
          slots: [{ position: { x: baseX + 45, y: baseY + 20 }, facing: 'up', occupantId: null }],
        },
        {
          id: `bedroom-${row + 1}-${col + 1}-floor`, view: 'spriteStreet', area: areaKey,
          activities: ['Relaxing at home'],
          type: 'single',
          slots: [{ position: { x: baseX + 68, y: baseY + 80 }, facing: 'down', occupantId: null }],
        },
      );
    }
  }

  return stations;
}

// ── Activity Manager ──────────────────────────────────────

export class ActivityManager {
  private stations: Station[];
  /** Agent ID → current station reservation */
  private agentSlots = new Map<string, { stationId: string; slotIndex: number }>();
  /** Activity label → stations that manage it */
  private labelToStations = new Map<string, Station[]>();

  constructor() {
    this.stations = createStations();
    for (const station of this.stations) {
      for (const label of station.activities) {
        const existing = this.labelToStations.get(label) ?? [];
        existing.push(station);
        this.labelToStations.set(label, existing);
      }
    }
  }

  /**
   * Pick an available activity and reserve a slot if station-based.
   * Respects capacity limits and Sprite St. room ownership.
   * Auto-releases any existing reservation for this agent.
   */
  pickAndReserve(
    agentId: string,
    characterType: CharacterType,
    currentView?: OfficeView,
  ): ActivityAssignment | null {
    this.release(agentId);

    const isDog = DOG_TYPES.has(characterType);
    const viewPrefs = CHARACTER_VIEW_PREFERENCES[characterType] ?? ['office'];

    // 60% stay in current view, 40% switch
    const baseView = currentView ?? 'office';
    let targetView: OfficeView;
    if (Math.random() < 0.4 && viewPrefs.length > 1) {
      const others = viewPrefs.filter(v => v !== baseView);
      targetView = others.length > 0 ? others[Math.floor(Math.random() * others.length)] : baseView;
    } else {
      targetView = baseView;
    }

    // Dogs can't visit the gym
    if (isDog && targetView === 'gym') targetView = 'office';

    // Merge activity maps for this character type
    const allActivities: Record<string, IdleActivity[]> = isDog
      ? { ...DOG_IDLE_ACTIVITIES, ...DOG_PARK_DOG_ACTIVITIES, ...GYM_DOG_ACTIVITIES, ...SPRITE_ST_DOG_ACTIVITIES }
      : { ...HUMAN_IDLE_ACTIVITIES, ...DOG_PARK_HUMAN_ACTIVITIES, ...GYM_HUMAN_ACTIVITIES, ...SPRITE_ST_HUMAN_ACTIVITIES };

    // Get areas in the target view
    const viewConfig = OFFICE_VIEWS.find(v => v.id === targetView);
    const viewAreas = viewConfig?.areas ?? [];

    // Build list of available activities
    const available: ActivityAssignment[] = [];

    for (const areaType of viewAreas) {
      // Room ownership: humans can only enter their own Sprite St. bedroom
      if (targetView === 'spriteStreet' && !this.canEnterBedroom(characterType, areaType)) {
        continue;
      }

      const activities = allActivities[areaType];
      if (!activities) continue;

      for (const activity of activities) {
        const stations = this.labelToStations.get(activity.label);

        if (stations && stations.length > 0) {
          // Station-managed: find a station in this area with a free slot
          for (const station of stations) {
            if (station.area !== areaType) continue;
            for (let si = 0; si < station.slots.length; si++) {
              if (station.slots[si].occupantId === null) {
                available.push({
                  activity,
                  walkTarget: { ...station.slots[si].position },
                  facing: station.slots[si].facing,
                  stationId: station.id,
                  slotIndex: si,
                });
                break; // one free slot per station is enough for the pool
              }
            }
          }
        } else {
          // Open activity — always available, no capacity limit
          available.push({
            activity,
            walkTarget: activity.target ? { ...activity.target } : randomPosition(activity.area),
            facing: 'down',
            stationId: null,
            slotIndex: 0,
          });
        }
      }
    }

    if (available.length === 0) return null;

    // Pick randomly from available
    const chosen = available[Math.floor(Math.random() * available.length)];

    // Reserve if station-based
    if (chosen.stationId) {
      this.reserveSlot(chosen.stationId, chosen.slotIndex, agentId);
    }

    return chosen;
  }

  /** Release all station slots held by an agent. Idempotent. */
  release(agentId: string): void {
    const reservation = this.agentSlots.get(agentId);
    if (!reservation) return;
    const station = this.stations.find(s => s.id === reservation.stationId);
    if (station && station.slots[reservation.slotIndex]) {
      station.slots[reservation.slotIndex].occupantId = null;
    }
    this.agentSlots.delete(agentId);
  }

  /** Get station by ID */
  getStation(id: string): Station | null {
    return this.stations.find(s => s.id === id) ?? null;
  }

  /** Check if a character can enter a Sprite St. bedroom */
  canEnterBedroom(characterType: CharacterType, bedroomArea: OfficeAreaType): boolean {
    if (DOG_TYPES.has(characterType)) return true;
    return CHARACTER_BEDROOM[characterType] === bedroomArea;
  }

  /** Reserve a specific station slot for an agent. Returns true if successful.
   *  Used for social interactions that need to reserve exact slots (e.g., ping pong invite). */
  reserveSpecific(agentId: string, stationId: string, slotIndex: number): boolean {
    this.release(agentId);
    const station = this.stations.find(s => s.id === stationId);
    if (!station || !station.slots[slotIndex] || station.slots[slotIndex].occupantId !== null) {
      return false;
    }
    this.reserveSlot(stationId, slotIndex, agentId);
    return true;
  }

  /** Reset all reservations */
  reset(): void {
    for (const station of this.stations) {
      for (const slot of station.slots) {
        slot.occupantId = null;
      }
    }
    this.agentSlots.clear();
  }

  private reserveSlot(stationId: string, slotIndex: number, agentId: string): void {
    const station = this.stations.find(s => s.id === stationId);
    if (!station || !station.slots[slotIndex]) return;
    station.slots[slotIndex].occupantId = agentId;
    this.agentSlots.set(agentId, { stationId, slotIndex });
  }
}
