---
applyTo: "**/*"
---

# CI / Pre-Push Quality Gates

**MANDATORY**: Before EVERY `git commit` or `git push`, run the full CI pipeline locally and confirm all steps pass. No exceptions.

## The CI Pipeline

The CI pipeline mirrors `.github/workflows/ci.yml`:

### Relay Server (`relay/`)

```bash
cd relay && npm run lint && npm run typecheck && npm test && npm run build
```

### VSCode Extension (`vscode-extension/`)

```bash
cd vscode-extension && npm run lint && npm run typecheck && npm run build
```

### iOS App (`ios/`)

```bash
# Build via Xcode (when project exists)
xcodebuild build \
  -project ios/MajorTom.xcodeproj \
  -scheme MajorTom \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

## Rules

1. **Run ALL steps** before every commit and push — not just the component you changed.
2. **Fix failures immediately** — do NOT commit or push code that fails any step.
3. **Re-run after fixes** — a lint fix can break typecheck or tests. Always re-run from the top.
4. **Never skip steps** — even if you think nothing changed.
5. **Check output** — read the output. Non-zero exit = failed.

## Common Pitfalls

### TypeScript (Relay + Extension)

- **`async` without `await`**: If a handler doesn't use `await`, don't mark it `async`.
- **`||` vs `??`**: Use `??` for nullish coalescing.
- **`any` types**: Never. Use `unknown` and narrow.
- **Type-only imports**: Use `import type { Foo }` when only used as a type.

### Swift (iOS)

- **Force unwraps (`!`)**: Never. Use `guard let` or `if let`.
- **`@ObservableObject`**: Never. Use `@Observable` (iOS 17+).
- **Combine**: Never. Use async/await.
- **UIKit**: Never (unless absolutely unavoidable). SwiftUI only.

## Workflow

```
1. Make code changes
2. Run CI for affected components
3. ALL pass? -> git add, commit, push
4. ANY fail? -> fix, go back to step 2
```

**NEVER push code that hasn't passed CI locally.**
