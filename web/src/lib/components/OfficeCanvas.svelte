<script lang="ts">
  import { SCENE_WIDTH, SCENE_HEIGHT, AREAS, DOOR_POSITION, getAreasForView, VIEW_ROOM_ORDERS } from '../office/layout';
  import { renderCharacterAnimated, getCharacterSize } from '../office/pixel-art';
  import type { OfficeEngine, EngineAgent } from '../office/engine';
  import type { OfficeArea, OfficeView } from '../office/types';
  import {
    safeRoundRect,
    drawFloorPattern,
    drawOfficeWalls,
    drawFurniture,
    drawAnimatedMonitor,
    drawAnimatedTv,
    drawAnimatedArcade,
    drawToasterFire,
    drawPingPongBall,
  } from '../office/furniture-renderers';

  interface Props {
    engine: OfficeEngine;
    desks: Array<{ id: number; position: { x: number; y: number }; occupantId: string | null; label?: string; width?: number; height?: number }>;
    onAgentClick?: (agentId: string) => void;
    onEmptyClick?: () => void;
    activeView?: OfficeView;
  }

  let { engine, desks, onAgentClick, onEmptyClick, activeView = 'office' as OfficeView }: Props = $props();

  let canvasEl: HTMLCanvasElement | undefined = $state();
  let containerEl: HTMLDivElement | undefined = $state();
  let scale = $state(1);
  let isMobile = $state(false);

  // Mobile room canvases — keyed by area type
  let roomCanvasEls: Record<string, HTMLCanvasElement | undefined> = $state({});

  // Room display order for mobile layout — derived from active view
  let roomOrder = $derived(VIEW_ROOM_ORDERS[activeView]);

  // ── Responsive scaling ─────────────────────────────────────

  function updateScale() {
    if (!containerEl) return;
    // Use window.innerWidth for mobile detection — the container itself may be
    // inflated by the canvas dimensions, giving a false reading.
    isMobile = window.innerWidth < 640;
    if (!isMobile) {
      const { clientWidth, clientHeight } = containerEl;
      const scaleX = clientWidth / SCENE_WIDTH;
      const scaleY = clientHeight / SCENE_HEIGHT;
      scale = Math.min(scaleX, scaleY);
    }
  }

  $effect(() => {
    if (!containerEl) return;
    const observer = new ResizeObserver(() => updateScale());
    observer.observe(containerEl);
    // Also listen for window resize to catch viewport changes (e.g. orientation)
    window.addEventListener('resize', updateScale);
    updateScale();
    return () => {
      observer.disconnect();
      window.removeEventListener('resize', updateScale);
    };
  });

  // ── Engine render loop ─────────────────────────────────────

  $effect(() => {
    if (isMobile) {
      // Mobile: render each room canvas separately
      engine.onRender = () => {
        const viewAreas = getAreasForView(activeView);
        for (const room of roomOrder) {
          const canvas = roomCanvasEls[room.type];
          if (!canvas) continue;
          const ctx = canvas.getContext('2d');
          if (!ctx) continue;
          const area = viewAreas.find(a => a.type === room.type);
          if (!area) continue;
          renderRoom(ctx, engine, area);
        }
      };

      engine.start();

      return () => {
        engine.onRender = null;
        engine.stop();
      };
    } else {
      if (!canvasEl) return;
      const ctx = canvasEl.getContext('2d');
      if (!ctx) return;

      engine.onRender = () => {
        renderScene(ctx, engine);
      };

      engine.start();

      return () => {
        engine.onRender = null;
        engine.stop();
      };
    }
  });

  // ── Click handler ──────────────────────────────────────────

  function handleClick(event: MouseEvent) {
    if (!canvasEl) return;
    const rect = canvasEl.getBoundingClientRect();
    const x = (event.clientX - rect.left) / scale;
    const y = (event.clientY - rect.top) / scale;

    const agent = engine.getAgentAtPoint({ x, y });
    if (agent) {
      onAgentClick?.(agent.id);
    } else {
      onEmptyClick?.();
    }
  }

  function handleRoomClick(event: MouseEvent, area: OfficeArea) {
    const canvas = event.currentTarget as HTMLCanvasElement;
    const rect = canvas.getBoundingClientRect();
    const roomScale = rect.width / area.bounds.width;
    // Convert click coords back to scene space
    const sceneX = (event.clientX - rect.left) / roomScale + area.bounds.x;
    const sceneY = (event.clientY - rect.top) / roomScale + area.bounds.y;

    const agent = engine.getAgentAtPoint({ x: sceneX, y: sceneY });
    if (agent) {
      onAgentClick?.(agent.id);
    } else {
      onEmptyClick?.();
    }
  }

  // ── Mobile room rendering ──────────────────────────────────

  function isAgentInArea(agent: EngineAgent, area: OfficeArea, padding: number = 20): boolean {
    const ax = agent.position.x;
    const ay = agent.position.y;
    const b = area.bounds;
    return ax >= b.x - padding && ax <= b.x + b.width + padding &&
           ay >= b.y - padding && ay <= b.y + b.height + padding;
  }

  function renderRoom(ctx: CanvasRenderingContext2D, eng: OfficeEngine, area: OfficeArea) {
    const now = performance.now();
    const b = area.bounds;

    // Clear canvas
    ctx.fillStyle = 'rgb(20, 20, 26)';
    ctx.fillRect(0, 0, b.width, b.height);

    ctx.save();
    // Shift coordinate system so room renders at (0,0)
    ctx.translate(-b.x, -b.y);

    // Floor
    ctx.fillStyle = area.color;
    ctx.fillRect(b.x, b.y, b.width, b.height);

    // Floor pattern
    drawFloorPattern(ctx, area);

    // Room label (subtle, in corner — shadow for contrast on light floors)
    ctx.save();
    ctx.font = '8px Menlo, monospace';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    ctx.shadowColor = 'rgba(0, 0, 0, 0.5)';
    ctx.shadowBlur = 2;
    ctx.shadowOffsetX = 1;
    ctx.shadowOffsetY = 1;
    ctx.fillStyle = 'rgba(180, 180, 190, 0.55)';
    ctx.fillText(area.name.toUpperCase(), b.x + 8, b.y + 8);
    ctx.restore();

    // Furniture with animated overlays
    if (area.furniture) {
      for (const item of area.furniture) {
        if (item.type === 'tvScreen') {
          drawAnimatedTv(ctx, item.position.x, item.position.y, item.width, item.height, eng, now);
        } else if (item.type === 'arcadeMachine') {
          drawFurniture(ctx, item);
          drawAnimatedArcade(ctx, item.position.x, item.position.y, item.width, item.height, eng, now, item.color);
        } else {
          drawFurniture(ctx, item);
        }

        if (item.type === 'toaster') {
          drawToasterFire(ctx, item.position.x, item.position.y, eng, now);
        }
      }
    }

    // Desks (only for mainOffice)
    if (area.type === 'mainOffice') {
      for (const d of desks) {
        renderDesk(ctx, d);

        const isOccupiedWorking = d.occupantId !== null &&
          eng.agents.get(d.occupantId)?.animation.type === 'work-shake';

        const deskFurniturePositions = [
          { fx: 368, fy: 120, fw: 56 },  // Desk 0
          { fx: 522, fy: 120, fw: 56 },  // Desk 1
          { fx: 368, fy: 300, fw: 56 },  // Desk 2
          { fx: 522, fy: 300, fw: 56 },  // Desk 3
          { fx: 368, fy: 480, fw: 56 },  // Desk 4
          { fx: 522, fy: 480, fw: 56 },  // Desk 5
        ];

        if (d.id >= 0 && d.id < deskFurniturePositions.length) {
          const fp = deskFurniturePositions[d.id];
          const mw = 16, mh = 10;
          const mx = fp.fx + (fp.fw - mw) / 2;
          const my = fp.fy + 6;
          drawAnimatedMonitor(ctx, mx, my, mw, mh, isOccupiedWorking, now);
        }
      }

      // Door (only in mainOffice)
      renderDoor(ctx);
    }

    // Agents within this room (filtered to active view)
    for (const agent of eng.agents.values()) {
      const agentView = agent.currentView ?? 'office';
      if (agentView === activeView && isAgentInArea(agent, area)) {
        renderAgent(ctx, agent);
      }
    }

    // Ping pong ball (only for breakRoom)
    if (area.type === 'breakRoom') {
      drawPingPongBall(ctx, eng, now);
    }

    ctx.restore();

    // Draw subtle border around room canvas
    ctx.strokeStyle = 'rgba(100, 100, 120, 0.4)';
    ctx.lineWidth = 1;
    ctx.strokeRect(0, 0, b.width, b.height);

    // Reset text baseline
    ctx.textBaseline = 'alphabetic';
  }

  // ── Main rendering ─────────────────────────────────────────

  function renderScene(ctx: CanvasRenderingContext2D, eng: OfficeEngine) {
    const now = performance.now();
    const viewAreas = getAreasForView(activeView);

    // Clear with dark background (visible in gaps)
    ctx.fillStyle = 'rgb(20, 20, 26)';
    ctx.fillRect(0, 0, SCENE_WIDTH, SCENE_HEIGHT);

    // Draw area floors for active view
    for (const area of viewAreas) {
      const { x, y, width, height } = area.bounds;

      // Fill floor
      ctx.fillStyle = area.color;
      ctx.fillRect(x, y, width, height);

      // Floor pattern overlay
      drawFloorPattern(ctx, area);
    }

    // Draw walls (only for office view — other views use area borders)
    if (activeView === 'office') {
      drawOfficeWalls(ctx);
    }

    // Draw area labels (subtle, in corner — shadow for contrast on light floors)
    ctx.save();
    ctx.font = '8px Menlo, monospace';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    ctx.shadowColor = 'rgba(0, 0, 0, 0.5)';
    ctx.shadowBlur = 2;
    ctx.shadowOffsetX = 1;
    ctx.shadowOffsetY = 1;
    ctx.fillStyle = 'rgba(180, 180, 190, 0.55)';
    for (const area of viewAreas) {
      const { x, y } = area.bounds;
      ctx.fillText(area.name.toUpperCase(), x + 8, y + 8);
    }
    ctx.restore();

    // Draw furniture for active view areas, with animated overlays
    for (const area of viewAreas) {
      if (!area.furniture) continue;
      for (const item of area.furniture) {
        if (item.type === 'tvScreen') {
          // Draw animated TV instead of static
          drawAnimatedTv(ctx, item.position.x, item.position.y, item.width, item.height, eng, now);
        } else if (item.type === 'arcadeMachine') {
          // Draw static arcade body, then animated screen overlay
          drawFurniture(ctx, item);
          drawAnimatedArcade(ctx, item.position.x, item.position.y, item.width, item.height, eng, now, item.color);
        } else {
          drawFurniture(ctx, item);
        }

        // Toaster fire overlay
        if (item.type === 'toaster') {
          drawToasterFire(ctx, item.position.x, item.position.y, eng, now);
        }
      }
    }

    // Draw desks and door only in office view
    if (activeView === 'office') {
      // Draw desks (agent assignment targets) with animated monitors
      for (const d of desks) {
        renderDesk(ctx, d);

        // Animated monitor overlay on desk monitors in the main office furniture
        // Check if this desk's occupant is working (has 'work-shake' animation)
        const isOccupiedWorking = d.occupantId !== null &&
          eng.agents.get(d.occupantId)?.animation.type === 'work-shake';

        // The desk monitor is embedded in the deskWithMonitor furniture items
        // Match desk positions to corresponding deskWithMonitor furniture
        // Desks: Row 1 seats at y=85, desks at y=45. Row 2 seats at y=205, desks at y=165
        // Monitor positions: centered on desk furniture
        const deskFurniturePositions = [
          { fx: 368, fy: 120, fw: 56 },  // Desk 0
          { fx: 522, fy: 120, fw: 56 },  // Desk 1
          { fx: 368, fy: 300, fw: 56 },  // Desk 2
          { fx: 522, fy: 300, fw: 56 },  // Desk 3
          { fx: 368, fy: 480, fw: 56 },  // Desk 4
          { fx: 522, fy: 480, fw: 56 },  // Desk 5
        ];

        if (d.id >= 0 && d.id < deskFurniturePositions.length) {
          const fp = deskFurniturePositions[d.id];
          const mw = 16, mh = 10;
          const mx = fp.fx + (fp.fw - mw) / 2;
          const my = fp.fy + 6;
          drawAnimatedMonitor(ctx, mx, my, mw, mh, isOccupiedWorking, now);
        }
      }

      // Draw door
      renderDoor(ctx);
    }

    // Draw agents whose currentView matches the active view
    for (const agent of eng.agents.values()) {
      const agentView = agent.currentView ?? 'office';
      if (agentView === activeView) {
        renderAgent(ctx, agent);
      }
    }

    // Draw ping pong ball on top of agents (only in office view where break room is)
    if (activeView === 'office') {
      drawPingPongBall(ctx, eng, now);
    }

    // Reset text baseline
    ctx.textBaseline = 'alphabetic';
  }

  function renderDesk(ctx: CanvasRenderingContext2D, d: { id: number; position: { x: number; y: number }; occupantId: string | null; label?: string; width?: number; height?: number }) {
    const { x, y } = d.position;
    const isOccupied = d.occupantId !== null;
    const dw = d.width ?? 40;
    const dh = d.height ?? 25;
    const dx = x - dw / 2;
    const dy = y - dh / 2;

    // Desk body
    safeRoundRect(ctx, dx, dy, dw, dh, 3);
    if (isOccupied) {
      ctx.fillStyle = 'rgb(140, 105, 72)';
      ctx.fill();
      ctx.strokeStyle = 'rgba(242, 180, 80, 0.5)';
      ctx.lineWidth = 1.5;
      ctx.stroke();
    } else {
      ctx.fillStyle = 'rgb(115, 85, 58)';
      ctx.fill();
      ctx.strokeStyle = 'rgba(100, 80, 55, 0.5)';
      ctx.lineWidth = 1;
      ctx.stroke();
    }

    // Top highlight
    ctx.fillStyle = 'rgba(255, 255, 255, 0.06)';
    ctx.fillRect(dx + 2, dy + 1, dw - 4, 2);

    // Monitor on desk (tiny rectangle)
    if (!isOccupied) {
      ctx.fillStyle = 'rgba(40, 50, 60, 0.4)';
      ctx.fillRect(x - 4, dy + 3, 8, 5);
    }

    // Name label below desk (hide when occupied — agent name is shown above)
    if (d.label && !isOccupied) {
      ctx.fillStyle = 'rgba(160, 150, 130, 0.5)';
      ctx.font = '7px Menlo, monospace';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'top';
      ctx.fillText(d.label, x, dy + dh + 3);
    }
  }

  function renderDoor(ctx: CanvasRenderingContext2D) {
    const dx = DOOR_POSITION.x;
    const dy = DOOR_POSITION.y;
    const dw = 10;
    const dh = 36;

    // Door frame
    ctx.fillStyle = 'rgb(120, 95, 65)';
    ctx.fillRect(dx - 1, dy - dh / 2, dw + 2, dh);

    // Door panel
    ctx.fillStyle = 'rgb(140, 110, 72)';
    ctx.fillRect(dx, dy - dh / 2 + 1, dw, dh - 2);

    // Door handle
    ctx.fillStyle = 'rgb(200, 180, 120)';
    ctx.beginPath();
    ctx.arc(dx + 3, dy, 2, 0, Math.PI * 2);
    ctx.fill();

    // Label
    ctx.fillStyle = 'rgba(242, 200, 120, 0.6)';
    ctx.font = 'bold 6px Menlo, monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.save();
    ctx.translate(dx + dw / 2, dy);
    ctx.rotate(-Math.PI / 2);
    ctx.fillText('EXIT', 0, 0);
    ctx.restore();
  }

  function drawSpeechBubble(ctx: CanvasRenderingContext2D, agent: EngineAgent) {
    if (!agent.speechBubble) return;

    const now = performance.now();
    const elapsed = now - agent.speechBubble.startTime;
    const remaining = agent.speechBubble.duration - elapsed;
    if (remaining <= 0) return;

    // Calculate alpha — full opacity, fade out in last 500ms
    const fadeStart = 500;
    const alpha = remaining < fadeStart ? remaining / fadeStart : 1;

    const x = agent.position.x + agent.animOffset.x;
    const y = agent.position.y + agent.animOffset.y;
    const size = getCharacterSize(agent.characterType);

    ctx.save();
    ctx.globalAlpha = alpha * agent.alpha;

    // Measure text to size the bubble
    ctx.font = '7px Menlo, monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const textWidth = ctx.measureText(agent.speechBubble.text).width;

    const padH = 6;
    const padV = 4;
    const bubbleW = textWidth + padH * 2;
    const bubbleH = 12 + padV * 2;
    const bubbleX = x - bubbleW / 2;
    const bubbleY = y - size.height / 2 - 20 - bubbleH; // above name + status dot
    const tailSize = 4;

    // Bubble background
    safeRoundRect(ctx, bubbleX, bubbleY, bubbleW, bubbleH, 4);
    ctx.fillStyle = 'rgb(240, 240, 245)';
    ctx.fill();
    ctx.strokeStyle = 'rgb(60, 60, 70)';
    ctx.lineWidth = 1;
    ctx.stroke();

    // Tail triangle pointing down to agent
    ctx.beginPath();
    ctx.moveTo(x - tailSize, bubbleY + bubbleH);
    ctx.lineTo(x, bubbleY + bubbleH + tailSize);
    ctx.lineTo(x + tailSize, bubbleY + bubbleH);
    ctx.closePath();
    ctx.fillStyle = 'rgb(240, 240, 245)';
    ctx.fill();
    // Tail border (just the two angled sides)
    ctx.beginPath();
    ctx.moveTo(x - tailSize, bubbleY + bubbleH);
    ctx.lineTo(x, bubbleY + bubbleH + tailSize);
    ctx.lineTo(x + tailSize, bubbleY + bubbleH);
    ctx.strokeStyle = 'rgb(60, 60, 70)';
    ctx.lineWidth = 1;
    ctx.stroke();
    // Cover the border line where tail meets bubble
    ctx.fillStyle = 'rgb(240, 240, 245)';
    ctx.fillRect(x - tailSize + 1, bubbleY + bubbleH - 1, tailSize * 2 - 2, 2);

    // Text
    ctx.fillStyle = 'rgb(30, 30, 40)';
    ctx.fillText(agent.speechBubble.text, x, bubbleY + bubbleH / 2);

    ctx.restore();
  }

  function renderAgent(ctx: CanvasRenderingContext2D, agent: EngineAgent) {
    const x = agent.position.x + agent.animOffset.x;
    const y = agent.position.y + agent.animOffset.y;
    const now = performance.now();

    // Draw sprite with rotation if celebrating
    if (agent.rotation !== 0) {
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(agent.rotation);
      renderCharacterAnimated(ctx, agent.characterType, 0, 0, now, agent.alpha,
        agent.facing, agent.isMoving, agent.walkPhase, agent.idleActivity);
      ctx.restore();
    } else {
      renderCharacterAnimated(ctx, agent.characterType, x, y, now, agent.alpha,
        agent.facing, agent.isMoving, agent.walkPhase, agent.idleActivity);
    }

    if (agent.alpha <= 0) return;

    const prevAlpha = ctx.globalAlpha;
    ctx.globalAlpha = agent.alpha;

    // Name label above sprite
    const size = getCharacterSize(agent.characterType);
    const nameY = y - size.height / 2 - 6;
    ctx.fillStyle = 'white';
    ctx.font = '9px Menlo, monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'bottom';
    ctx.fillText(agent.name, x, nameY);

    // Status dot (above the name text)
    ctx.beginPath();
    ctx.arc(x, nameY - 11, 3, 0, Math.PI * 2);
    ctx.fillStyle = agent.statusColor;
    ctx.fill();

    ctx.globalAlpha = prevAlpha;

    // Speech bubble (drawn after restoring alpha so it has its own fade logic)
    drawSpeechBubble(ctx, agent);
  }
</script>

<div class="office-wrapper">
  <div class="office-container" bind:this={containerEl}>
    {#if isMobile}
      <!-- Mobile: stacked room canvases (grid for Sprite St.) -->
      <div class="mobile-room-stack" class:bedroom-grid={activeView === 'spriteStreet'}>
        {#each roomOrder as room}
          {@const area = getAreasForView(activeView).find(a => a.type === room.type)}
          {#if area}
            <div class="mobile-room-section" class:bedroom-cell={activeView === 'spriteStreet'}>
              <div class="mobile-room-label">{room.label}</div>
              <canvas
                bind:this={roomCanvasEls[room.type]}
                width={area.bounds.width}
                height={area.bounds.height}
                style="width: 100%;"
                onclick={(e) => handleRoomClick(e, area)}
                role="application"
                tabindex="0"
                aria-label="{room.label} — click agents to inspect"
              ></canvas>
            </div>
          {/if}
        {/each}
      </div>
    {:else}
      <!-- Desktop: single unified canvas -->
      <canvas
        bind:this={canvasEl}
        width={SCENE_WIDTH}
        height={SCENE_HEIGHT}
        style="width: {SCENE_WIDTH * scale}px; height: {SCENE_HEIGHT * scale}px;"
        onclick={handleClick}
        role="application"
        tabindex="0"
        aria-label="Office visualization — click agents to inspect"
      ></canvas>
    {/if}
  </div>
</div>

<style>
  .office-wrapper {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-height: 0;
    background: rgb(20, 20, 26);
  }

  .office-container {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgb(20, 20, 26);
    overflow: hidden;
    min-height: 0;
  }

  canvas {
    cursor: pointer;
    image-rendering: pixelated;
  }

  /* ── Mobile stacked layout ── */

  .mobile-room-stack {
    width: 100%;
    height: 100%;
    overflow-y: auto;
    overflow-x: hidden;
    -webkit-overflow-scrolling: touch;
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 4px;
  }

  .mobile-room-section {
    flex-shrink: 0;
  }

  .mobile-room-label {
    font-family: Menlo, monospace;
    font-size: 10px;
    color: rgba(200, 200, 210, 0.6);
    text-transform: uppercase;
    letter-spacing: 1px;
    padding: 4px 4px 2px;
  }

  .mobile-room-section canvas {
    display: block;
    width: 100%;
    height: auto;
    border-radius: 2px;
  }

  /* ── Sprite St. bedroom grid (2 per row, compact) ── */

  .mobile-room-stack.bedroom-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 2px;
    align-content: start;
  }

  .bedroom-cell {
    flex-shrink: 0;
  }

  .bedroom-cell .mobile-room-label {
    font-size: 8px;
    padding: 2px 2px 1px;
  }
</style>
