<script lang="ts">
  import { SCENE_WIDTH, SCENE_HEIGHT, AREAS, DESKS, DOOR_POSITION } from '../office/layout';
  import { renderCharacter, getCharacterSize } from '../office/pixel-art';
  import type { OfficeEngine, EngineAgent } from '../office/engine';

  interface Props {
    engine: OfficeEngine;
    desks: Array<{ id: number; position: { x: number; y: number }; occupantId: string | null }>;
    onAgentClick?: (agentId: string) => void;
  }

  let { engine, desks, onAgentClick }: Props = $props();

  let canvasEl: HTMLCanvasElement | undefined = $state();
  let containerEl: HTMLDivElement | undefined = $state();
  let scale = $state(1);

  // ── Responsive scaling ─────────────────────────────────────

  function updateScale() {
    if (!containerEl) return;
    const { clientWidth, clientHeight } = containerEl;
    const scaleX = clientWidth / SCENE_WIDTH;
    const scaleY = clientHeight / SCENE_HEIGHT;
    scale = Math.min(scaleX, scaleY);
  }

  $effect(() => {
    if (!containerEl) return;
    const observer = new ResizeObserver(() => updateScale());
    observer.observe(containerEl);
    updateScale();
    return () => observer.disconnect();
  });

  // ── Engine render loop ─────────────────────────────────────

  $effect(() => {
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
  });

  // ── Click handler ──────────────────────────────────────────

  /** Rounded rect with fallback for browsers lacking ctx.roundRect */
  function safeRoundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
    ctx.beginPath();
    if (typeof ctx.roundRect === 'function') {
      ctx.roundRect(x, y, w, h, r);
    } else {
      ctx.moveTo(x + r, y);
      ctx.lineTo(x + w - r, y);
      ctx.arcTo(x + w, y, x + w, y + r, r);
      ctx.lineTo(x + w, y + h - r);
      ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
      ctx.lineTo(x + r, y + h);
      ctx.arcTo(x, y + h, x, y + h - r, r);
      ctx.lineTo(x, y + r);
      ctx.arcTo(x, y, x + r, y, r);
      ctx.closePath();
    }
  }

  function handleClick(event: MouseEvent) {
    if (!canvasEl || !onAgentClick) return;
    const rect = canvasEl.getBoundingClientRect();
    const x = (event.clientX - rect.left) / scale;
    const y = (event.clientY - rect.top) / scale;

    const agent = engine.getAgentAtPoint({ x, y });
    if (agent) {
      onAgentClick(agent.id);
    }
  }

  // ── Rendering ──────────────────────────────────────────────

  function renderScene(ctx: CanvasRenderingContext2D, eng: OfficeEngine) {
    // Clear
    ctx.fillStyle = 'rgb(31, 31, 38)';
    ctx.fillRect(0, 0, SCENE_WIDTH, SCENE_HEIGHT);

    // Draw areas
    for (const area of AREAS) {
      const { x, y, width, height } = area.bounds;

      // Fill
      ctx.fillStyle = area.color;
      ctx.fillRect(x, y, width, height);

      // Border
      ctx.strokeStyle = 'rgba(128, 128, 128, 0.3)';
      ctx.lineWidth = 1;
      ctx.strokeRect(x, y, width, height);

      // Label
      ctx.fillStyle = 'rgba(128, 128, 128, 0.5)';
      ctx.font = '10px Menlo, monospace';
      ctx.textAlign = 'center';
      ctx.fillText(area.name.toUpperCase(), x + width / 2, y + 15);
    }

    // Draw desks
    for (const desk of desks) {
      const { x, y } = desk.position;
      const isOccupied = desk.occupantId !== null;

      const dw = 40, dh = 25;
      const dx = x - dw / 2, dy = y - dh / 2;
      const radius = 3;

      // Rounded rectangle
      safeRoundRect(ctx, dx, dy, dw, dh, radius);

      if (isOccupied) {
        ctx.fillStyle = 'rgb(115, 89, 64)';
        ctx.fill();
        ctx.strokeStyle = 'rgba(242, 166, 64, 0.6)';
        ctx.lineWidth = 1.5;
        ctx.stroke();
      } else {
        ctx.fillStyle = 'rgb(89, 64, 46)';
        ctx.fill();
        ctx.strokeStyle = 'rgba(128, 128, 128, 0.35)';
        ctx.lineWidth = 1;
        ctx.stroke();
      }

      // Desk number
      ctx.fillStyle = 'rgba(128, 128, 128, 0.5)';
      ctx.font = '8px Menlo, monospace';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(`${desk.id + 1}`, x, y);
    }

    // Draw door
    {
      const dx = DOOR_POSITION.x, dy = DOOR_POSITION.y;
      const dw = 30, dh = 10;
      safeRoundRect(ctx, dx - dw / 2, dy - dh / 2, dw, dh, 2);
      ctx.fillStyle = 'rgba(242, 166, 64, 0.8)';
      ctx.fill();

      ctx.fillStyle = 'white';
      ctx.font = 'bold 7px Menlo, monospace';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('DOOR', dx, dy);
    }

    // Draw agents
    for (const agent of eng.agents.values()) {
      renderAgent(ctx, agent);
    }

    // Reset text baseline
    ctx.textBaseline = 'alphabetic';
  }

  function renderAgent(ctx: CanvasRenderingContext2D, agent: EngineAgent) {
    const x = agent.position.x + agent.animOffset.x;
    const y = agent.position.y + agent.animOffset.y;

    // Draw sprite with rotation if celebrating
    if (agent.rotation !== 0) {
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(agent.rotation);
      renderCharacter(ctx, agent.characterType, 0, 0, agent.alpha);
      ctx.restore();
    } else {
      renderCharacter(ctx, agent.characterType, x, y, agent.alpha);
    }

    if (agent.alpha <= 0) return;

    // Save alpha for labels
    const prevAlpha = ctx.globalAlpha;
    ctx.globalAlpha = agent.alpha;

    // Name label above sprite
    const size = getCharacterSize(agent.characterType);
    ctx.fillStyle = 'white';
    ctx.font = '9px Menlo, monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'bottom';
    ctx.fillText(agent.name, x, y - size.height / 2 - 4);

    // Status dot
    ctx.beginPath();
    ctx.arc(x, y - size.height / 2 - 10, 3, 0, Math.PI * 2);
    ctx.fillStyle = agent.statusColor;
    ctx.fill();

    ctx.globalAlpha = prevAlpha;
  }
</script>

<div class="office-container" bind:this={containerEl}>
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
</div>

<style>
  .office-container {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgb(31, 31, 38);
    overflow: hidden;
    min-height: 0;
  }

  canvas {
    cursor: pointer;
    image-rendering: pixelated;
  }
</style>
