<script lang="ts">
  import { onDestroy } from 'svelte';
  import { CHARACTER_CATALOG } from '../office/characters';
  import type { CharacterType } from '../office/types';
  import { getCharacterSprite, getIdleAnimation, getCharacterSize } from '../office/pixel-art';

  let currentIndex = $state(0);
  let canvas = $state<HTMLCanvasElement | null>(null);
  let containerEl = $state<HTMLDivElement | null>(null);

  // Touch/swipe tracking
  let touchStartX = $state(0);
  let touchDeltaX = $state(0);
  let isSwiping = $state(false);

  const characters = CHARACTER_CATALOG;
  const currentCharacter = $derived(characters[currentIndex]);

  // Animation loop
  let rafId: number | null = null;

  function drawCharacter(ctx: CanvasRenderingContext2D, type: CharacterType, w: number, h: number, time: number, offsetX: number = 0) {
    const sprite = getCharacterSprite(type, time);
    const { breathOffset } = getIdleAnimation(time);

    // Calculate scale to fit ~60% of the smaller dimension
    const targetSize = Math.min(w, h) * 0.6;
    const spriteMax = Math.max(sprite.width, sprite.height);
    const scale = Math.floor(targetSize / spriteMax);

    const drawW = sprite.width * scale;
    const drawH = sprite.height * scale;
    const x = (w - drawW) / 2 + offsetX;
    const y = (h - drawH) / 2 - breathOffset * scale;

    ctx.imageSmoothingEnabled = false;

    // Flip vertically — sprites are stored Y-up (SpriteKit convention)
    ctx.save();
    ctx.translate(x + drawW / 2, y + drawH / 2);
    ctx.scale(1, -1);
    ctx.drawImage(sprite.canvas, -drawW / 2, -drawH / 2, drawW, drawH);
    ctx.restore();
  }

  function redraw(time: number) {
    if (!canvas || !containerEl) return;
    const w = containerEl.clientWidth;
    const h = containerEl.clientHeight;
    const dpr = window.devicePixelRatio || 1;

    canvas.width = w * dpr;
    canvas.height = h * dpr;
    canvas.style.width = `${w}px`;
    canvas.style.height = `${h}px`;

    const ctx = canvas.getContext('2d')!;
    ctx.scale(dpr, dpr);
    ctx.clearRect(0, 0, w, h);

    // Draw current character with swipe offset
    drawCharacter(ctx, currentCharacter.type, w, h, time, touchDeltaX);

    // Draw peek of adjacent characters during swipe
    if (touchDeltaX > 0 && currentIndex > 0) {
      drawCharacter(ctx, characters[currentIndex - 1].type, w, h, time, touchDeltaX - w);
    }
    if (touchDeltaX < 0 && currentIndex < characters.length - 1) {
      drawCharacter(ctx, characters[currentIndex + 1].type, w, h, time, touchDeltaX + w);
    }
  }

  function tick(now: number) {
    redraw(now);
    rafId = requestAnimationFrame(tick);
  }

  // Start animation loop when canvas and container are ready
  $effect(() => {
    if (!canvas || !containerEl) return;
    rafId = requestAnimationFrame(tick);
    return () => {
      if (rafId !== null) {
        cancelAnimationFrame(rafId);
        rafId = null;
      }
    };
  });

  $effect(() => {
    if (!containerEl) return;
    const observer = new ResizeObserver(() => redraw(performance.now()));
    observer.observe(containerEl);
    return () => observer.disconnect();
  });

  onDestroy(() => {
    if (rafId !== null) cancelAnimationFrame(rafId);
  });

  function onTouchStart(e: TouchEvent) {
    touchStartX = e.touches[0].clientX;
    touchDeltaX = 0;
    isSwiping = true;
  }

  function onTouchMove(e: TouchEvent) {
    if (!isSwiping) return;
    touchDeltaX = e.touches[0].clientX - touchStartX;
  }

  function onTouchEnd() {
    if (!isSwiping) return;
    isSwiping = false;

    const threshold = 50;
    if (touchDeltaX > threshold && currentIndex > 0) {
      currentIndex--;
    } else if (touchDeltaX < -threshold && currentIndex < characters.length - 1) {
      currentIndex++;
    }
    touchDeltaX = 0;
  }

  function goNext() {
    if (currentIndex < characters.length - 1) currentIndex++;
  }

  function goPrev() {
    if (currentIndex > 0) currentIndex--;
  }
</script>

<div
  class="gallery"
  bind:this={containerEl}
  ontouchstart={onTouchStart}
  ontouchmove={onTouchMove}
  ontouchend={onTouchEnd}
>
  <canvas bind:this={canvas}></canvas>

  <!-- Character info -->
  <div class="character-info">
    <h2 class="character-name">{currentCharacter.displayName}</h2>
    <p class="character-role">{currentCharacter.type.replace(/([A-Z])/g, ' $1').replace(/^./, s => s.toUpperCase()).trim()}</p>
  </div>

  <!-- Dot indicators -->
  <div class="dots">
    {#each characters as _, i}
      <button
        class="dot"
        class:active={i === currentIndex}
        onclick={() => (currentIndex = i)}
        aria-label="Character {i + 1}"
      ></button>
    {/each}
  </div>

  <!-- Arrow buttons for non-touch -->
  {#if currentIndex > 0}
    <button class="arrow arrow-left" onclick={goPrev} aria-label="Previous">
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <polyline points="15 18 9 12 15 6"></polyline>
      </svg>
    </button>
  {/if}
  {#if currentIndex < characters.length - 1}
    <button class="arrow arrow-right" onclick={goNext} aria-label="Next">
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <polyline points="9 18 15 12 9 6"></polyline>
      </svg>
    </button>
  {/if}
</div>

<style>
  .gallery {
    flex: 1;
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    touch-action: pan-y;
    user-select: none;
    -webkit-user-select: none;
  }

  canvas {
    position: absolute;
    inset: 0;
  }

  .character-info {
    position: absolute;
    bottom: 60px;
    left: 0;
    right: 0;
    text-align: center;
    z-index: 1;
    pointer-events: none;
  }

  .character-name {
    font-family: var(--font-mono);
    font-size: 1.1rem;
    font-weight: 700;
    color: var(--accent);
    text-transform: uppercase;
    letter-spacing: 0.08em;
    margin-bottom: 4px;
  }

  .character-role {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--text-secondary);
  }

  .dots {
    position: absolute;
    bottom: var(--sp-xl);
    display: flex;
    gap: var(--sp-md);
    z-index: 1;
  }

  .dot {
    width: 12px;
    height: 12px;
    border-radius: var(--r-full);
    border: 2px solid var(--text-tertiary);
    background: transparent;
    padding: 0;
    cursor: pointer;
    transition: all 0.2s;
    /* Ensure 44px touch target */
    position: relative;
  }

  .dot::before {
    content: '';
    position: absolute;
    inset: -16px;
  }

  .dot.active {
    background: var(--accent);
    border-color: var(--accent);
    transform: scale(1.3);
  }

  .arrow {
    position: absolute;
    top: 50%;
    transform: translateY(-50%);
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-full);
    color: var(--text-secondary);
    width: 40px;
    height: 40px;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    opacity: 0.6;
    transition: opacity 0.2s;
    z-index: 1;
  }

  .arrow:hover {
    opacity: 1;
  }

  .arrow-left {
    left: var(--sp-md);
  }

  .arrow-right {
    right: var(--sp-md);
  }

  /* Hide arrows on mobile (touch handles it) */
  @media (pointer: coarse) {
    .arrow {
      display: none;
    }
  }
</style>
