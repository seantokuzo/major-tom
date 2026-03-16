## Overview

<!-- Brief description of what this PR accomplishes -->

| Property  | Value |
| --------- | ----- |
| **Phase** | Phase N: "Theme Name" |
| **Scope** | What this PR delivers |

---

## Labels Applied

<!-- Agent: Apply these labels when creating the PR -->

**Component Labels** (based on files changed):

- [ ] Relay — Changes to `relay/`
- [ ] iOS — Changes to `ios/`
- [ ] Extension — Changes to `vscode-extension/`
- [ ] Docs — Documentation changes

**Type Labels**:

- [ ] Bug Fix — For `fix/` branches
- [ ] Breaking Change — Breaking protocol or API changes

**Status Labels**:

- [x] Needs Review — Agent applies on PR creation
- [ ] Accepted — Human applies when ready to merge

**Auto-Applied Labels** (by GitHub Actions CI):

- Lint Failure / Type Error / Test Failure / Build Failure / CI Pass

---

## Changes

### Added

-

### Changed

-

### Removed

-

---

## Related Links

| Resource    | Link |
| ----------- | ---- |
| Planning Doc | [PLANNING.md](docs/PLANNING.md) |
| Related PRs | #XX |

---

## Tests

| Test File | Description |
| --------- | ----------- |
| `path/to/test.ts` | What's tested |

### Testing Instructions

**Automated:**

```bash
# Relay server
cd relay && npm test

# VSCode extension
cd vscode-extension && npm test
```

**Manual (if UI changes):**

```
1. Navigate to...
2. Expected result:...
```

---

## Screenshots

<!-- If UI changes, add before/after screenshots -->

| Before | After |
| ------ | ----- |
| N/A    | N/A   |

---

## Deployment Notes

- [ ] No new environment variables
- [ ] No breaking protocol changes
- [ ] No new dependencies requiring native builds

---

## Checklist

### Code Quality

- [ ] Code follows project conventions (see CLAUDE.md)
- [ ] No `any` types (relay/extension)
- [ ] No force unwraps (iOS)
- [ ] No hardcoded secrets
- [ ] Proper error handling

### Pre-merge

- [ ] Branch is up to date with `main`
- [ ] All CI checks pass
- [ ] Self-reviewed the diff

---

## Notes for Reviewers

<!-- Anything specific reviewers should focus on -->

---

<sub>Created using [PR Template](.github/PULL_REQUEST_TEMPLATE.md)</sub>
