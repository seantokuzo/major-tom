# Ground Control Distribution — Spec

> Hand this doc to a fresh Claude session on a worktree branch.
> Branch name: `ground-control/distribution`

---

## Goal

Make Ground Control installable, auto-registrable, and updatable for both
power users and newbies. Ship the macOS app, the MCP server, and a one-click
"connect to Claude Code" experience.

---

## Architecture Overview

```
Distribution Artifacts:
  GroundControl.dmg          → GitHub Releases + Homebrew Cask
  @major-tom/ground-control-mcp  → npm registry
  ground-control (Cask)      → Homebrew tap

User Flow (newbie):
  brew install --cask ground-control
    → App launches
    → "Register with Claude Code?" dialog
    → One click → MCP registered → done

User Flow (power user):
  claude mcp add ground-control -- npx @major-tom/ground-control-mcp
  # or
  ground-control.app already running, MCP already bundled
```

---

## Task 1: npm Package for MCP Server

**Publish `mcp/ground-control-mcp/` to npm as `@major-tom/ground-control-mcp`.**

### package.json updates

```json
{
  "name": "@major-tom/ground-control-mcp",
  "version": "1.0.0",
  "description": "MCP server for Ground Control — programmatic relay/tunnel management",
  "bin": {
    "ground-control-mcp": "./dist/index.js"
  },
  "files": ["dist/"],
  "engines": { "node": ">=20" },
  "keywords": ["mcp", "claude", "ground-control", "major-tom"],
  "repository": "seantokuzo/major-tom",
  "license": "MIT"
}
```

### Registration one-liners

**Claude Code:**
```bash
claude mcp add ground-control -- npx @major-tom/ground-control-mcp
```

**Claude Code (settings.json):**
```json
{
  "mcpServers": {
    "ground-control": {
      "command": "npx",
      "args": ["@major-tom/ground-control-mcp"]
    }
  }
}
```

**VS Code Copilot (.vscode/mcp.json):**
```json
{
  "servers": {
    "ground-control": {
      "command": "npx",
      "args": ["@major-tom/ground-control-mcp"]
    }
  }
}
```

### Environment variables

The MCP server should support:
- `GROUND_CONTROL_URL` — override control API URL (default `http://127.0.0.1:9092`)
- `GROUND_CONTROL_TIMEOUT` — override fetch timeout in ms (default 10000)

### Build + publish flow

```bash
cd mcp/ground-control-mcp
npm run build
npm publish --access public
```

---

## Task 2: Bundle MCP Server in .app

**Include the built MCP server in `Contents/Resources/mcp/`.**

### Updated .app layout

```
GroundControl.app/
  Contents/
    Resources/
      node/
        node              # Stripped Node.js binary
      relay/
        server.js         # Relay entry
        node_modules/
        package.json
      mcp/
        index.js          # MCP server entry (compiled)
        node_modules/     # MCP production deps
        package.json
```

### Changes needed

- `macos/scripts/bundle-mcp.sh` — new script, builds MCP server, stages to
  output dir with production deps only
- `macos/scripts/build-app.sh` — invoke `bundle-mcp.sh`, copy into
  `Contents/Resources/mcp/`
- MCP server should work when invoked via the bundled Node:
  `Contents/Resources/node/node Contents/Resources/mcp/index.js`

---

## Task 3: Auto-Registration UI in Ground Control

**Add "Register with Claude Code" button in Ground Control UI.**

### New file: `macos/GroundControl/Services/MCPRegistrar.swift`

```swift
enum MCPRegistrar {
    enum Client: String, CaseIterable {
        case claudeCode = "Claude Code"
        case vscode = "VS Code Copilot"
        case cursor = "Cursor"
    }

    /// Detect which AI coding tools are installed
    static func detectClients() -> [Client]

    /// Register the MCP server with a specific client
    static func register(client: Client, serverPath: URL) throws

    /// Check if already registered with a client
    static func isRegistered(client: Client) -> Bool

    /// Unregister from a client
    static func unregister(client: Client) throws
}
```

### Detection logic

| Client | How to detect |
|--------|---------------|
| Claude Code | `~/.claude/settings.json` exists |
| VS Code | `~/Library/Application Support/Code/` exists |
| Cursor | `~/Library/Application Support/Cursor/` exists |

### Registration logic

**Claude Code:** Read `~/.claude/settings.json`, merge MCP server entry into
`mcpServers`, write back. Server command points at bundled MCP:
```json
{
  "mcpServers": {
    "ground-control": {
      "command": "<app-path>/Contents/Resources/node/node",
      "args": ["<app-path>/Contents/Resources/mcp/index.js"]
    }
  }
}
```

**VS Code:** Write/merge `.vscode/mcp.json` or user-level settings. Same
pattern, different path.

### UI additions

**ConfigView.swift — new "Integrations" section:**
```
┌─ Integrations ──────────────────────────────────┐
│                                                  │
│  Claude Code    ● Registered    [Unregister]     │
│  VS Code        ○ Not found                      │
│  Cursor         ○ Detected      [Register]       │
│                                                  │
│  [Register All Detected]                         │
│                                                  │
└──────────────────────────────────────────────────┘
```

- Green dot = registered
- Gray dot = not installed
- Blue dot = installed but not registered
- Buttons to register/unregister per client

### First-launch flow

On first launch (no config file exists yet), after onboarding:
1. Detect installed AI coding clients
2. Show dialog: "Ground Control can register with [Claude Code, VS Code] so
   AI agents can control your relay. Register now?"
3. User picks which clients → auto-register
4. Can always change later in Settings → Integrations

---

## Task 4: GitHub Releases + DMG

### DMG creation script

New: `macos/scripts/build-dmg.sh`

```bash
#!/bin/bash
# Creates GroundControl.dmg from the built .app
# Uses hdiutil (built into macOS, no deps)

APP_PATH="build/GroundControl.app"
DMG_PATH="build/GroundControl.dmg"
VOLUME_NAME="Ground Control"

# Create temporary DMG
hdiutil create -size 200m -fs HFS+ -volname "$VOLUME_NAME" build/tmp.dmg
hdiutil attach build/tmp.dmg -mountpoint /Volumes/"$VOLUME_NAME"

# Copy app + symlink to Applications
cp -R "$APP_PATH" /Volumes/"$VOLUME_NAME"/
ln -s /Applications /Volumes/"$VOLUME_NAME"/Applications

# Detach and convert to compressed read-only DMG
hdiutil detach /Volumes/"$VOLUME_NAME"
hdiutil convert build/tmp.dmg -format UDZO -o "$DMG_PATH"
rm build/tmp.dmg
```

### GitHub Release workflow

New: `.github/workflows/release.yml`

Triggered on version tags (`v*`):
1. Build app (`build-app.sh --release`)
2. Create DMG (`build-dmg.sh`)
3. Code sign + notarize (if certs available)
4. Upload DMG to GitHub Release
5. Update Homebrew Cask formula (if tap exists)

### Versioning

- Use git tags: `v1.0.0`, `v1.1.0`, etc.
- `Info.plist` version derived from tag
- MCP npm package version stays in sync

---

## Task 5: Homebrew Cask

### Tap repository

Create `seantokuzo/homebrew-tap` with a cask formula:

```ruby
cask "ground-control" do
  version "1.0.0"
  sha256 "abc123..."

  url "https://github.com/seantokuzo/major-tom/releases/download/v#{version}/GroundControl.dmg"
  name "Ground Control"
  desc "macOS relay manager for Major Tom — AI agent infrastructure"
  homepage "https://github.com/seantokuzo/major-tom"

  app "GroundControl.app"

  postflight do
    # Optionally prompt MCP registration
  end

  zap trash: [
    "~/Library/Application Support/GroundControl",
    "~/.claude/settings.json", # only remove our entry, not the whole file
  ]
end
```

### Install flow

```bash
brew tap seantokuzo/tap
brew install --cask ground-control
```

---

## Task 6: Code Signing + Notarization

**Required for Gatekeeper to not block the app.**

### What's needed

- Apple Developer account ($99/year)
- Developer ID Application certificate
- Developer ID Installer certificate (for pkg, optional)
- App-specific password for notarytool

### Build script changes

`build-app.sh` additions:
```bash
# Code sign
codesign --deep --force --options runtime \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  --timestamp \
  "$APP_PATH"

# Notarize
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_SPECIFIC_PASSWORD" \
  --wait

# Staple
xcrun stapler staple "$DMG_PATH"
```

### Without Apple Developer account

The app still works — users just need to:
1. Right-click → Open (bypasses Gatekeeper first time)
2. Or: System Settings → Privacy & Security → "Open Anyway"

Document this in README if not signing.

---

## Task 7: Update Checker

**File:** `macos/GroundControl/Services/UpdateChecker.swift` (already exists
as a stub)

### Implementation

```swift
@Observable
final class UpdateChecker {
    var updateAvailable = false
    var latestVersion: String?
    var downloadURL: URL?

    func checkForUpdates() async {
        // Hit GitHub API: GET /repos/seantokuzo/major-tom/releases/latest
        // Compare tag_name against Bundle.main.infoDictionary version
        // If newer, set updateAvailable + downloadURL
    }
}
```

- Check on launch (once, non-blocking)
- Check on manual "Check for Updates" button
- Show banner in menu bar if update available
- "Download Update" opens browser to GitHub Release

---

## Implementation Order

1. **npm publish** — get `@major-tom/ground-control-mcp` on npm
2. **bundle-mcp.sh** — bundle MCP into .app
3. **MCPRegistrar** — detection + registration logic
4. **Integrations UI** — ConfigView section + first-launch dialog
5. **build-dmg.sh** — DMG creation
6. **GitHub Release workflow** — CI/CD for releases
7. **Homebrew Cask** — tap + formula
8. **Code signing** — if Apple Developer account available
9. **Update checker** — GitHub Releases API polling

## Size Budget (Updated)

| Component | Size |
|-----------|------|
| Node binary (stripped) | ~28-32MB |
| Relay dist + prod deps | ~3-4MB |
| MCP server + prod deps | ~1-2MB |
| GroundControl Swift | ~5-6MB |
| Icon + plists | ~0.3MB |
| **Total .app** | **~38-45MB** |
| **DMG (compressed)** | **~20-25MB** |

---

## Open Questions

1. **npm org:** Use `@major-tom/` scope or `ground-control-mcp` flat name?
   Rec: `@major-tom/ground-control-mcp` — clear namespace.

2. **Apple Developer account:** Worth $99/year for notarization?
   Rec: Skip for now, document the right-click workaround. Revisit if
   distributing to non-technical users.

3. **Auto-update:** Sparkle framework vs. manual GitHub check?
   Rec: GitHub API check + banner for now. Sparkle is heavier than needed.

4. **Homebrew tap vs. core:** Submit to homebrew-cask core?
   Rec: Own tap first (`seantokuzo/homebrew-tap`), move to core later if
   popular enough.
