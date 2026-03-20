# iOS Office — Status (Paused)

> Last updated: 2026-03-20. iOS work paused in favor of web PWA MVP.

## Done
- Pixel art sprites for all 9 characters (PixelArtBuilder.swift) — PR #18
- Dachshund blanket mechanic (shiver, snowflake, blanket overlay) — PR #19
- Agent state model, character catalog, office layout coordinates
- OfficeScene with floor plan, desks, door rendering
- OfficeViewModel with full agent lifecycle handling
- AgentInspectorView (tap-to-inspect sheet)
- OfficeView with SpriteKit wrapper and state sync

## Not Started (Deferred)
- Isometric office layout (currently flat top-down rectangles)
- Wiring OfficeViewModel to live RelayService agent events (currently mock-only)
- Mini-map interactivity
- Sound effects / haptics

## Notes for Resuming
- All Office code is self-contained in `Features/Office/`
- The web PWA now has a Canvas-based Office — keep feature parity in mind
- PixelArtBuilder pixel data can be used as reference for the web pixel art
- Coordinate system: SpriteKit origin (0,0) = bottom-left, 800x600 scene
