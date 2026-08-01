# Apple Signing Setup — Free Personal Team → Paid Developer Program

> Written 2026-08-01. Covers the move from free provisioning (7-day profiles, weekly
> "Xcode recovery dance") to the paid Apple Developer Program.
>
> **Headline: your Team ID did not change, and `project.pbxproj` does not need editing.**
> See [What the evidence says](#0-what-the-evidence-says-read-this-first).

---

## 0. What the evidence says (read this first)

Everything below was measured on this Mac on 2026-08-01, not assumed.

| Probe | Result | Meaning |
|-------|--------|---------|
| `defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier` | `teamID = 4B8499Z59P`, `teamName = "Sean Simpson"`, `teamType = Individual`, **`isFreeProvisioningTeam = 0`** | Xcode already sees `4B8499Z59P` as a **paid Individual** team. Only one team is listed for the Apple Account. |
| Last device build's `embedded.mobileprovision` (built 2026-06-01) | `TeamIdentifier = 4B8499Z59P`, **`TimeToLive = 7`**, `ExpirationDate = Jun 08 2026` | On 2026-06-01 the *same* team ID `4B8499Z59P` was still issuing **free** 7-day profiles. |
| `security find-certificate` → `openssl x509` on both Apple Development certs | `OU=4B8499Z59P`, validity `Apr 11 2026 → Apr 11 2027` and `May 23 2026 → May 23 2027` | Certificates were **already 1 year**, even under the free team. |
| `codesign -dv` on the last device build | `TeamIdentifier=4B8499Z59P` | Confirms OU is the team. |
| `ios/MajorTom.xcodeproj/project.pbxproj` | `DEVELOPMENT_TEAM = 4B8499Z59P` everywhere it appears | Already the correct (now paid) team. |

**Conclusion:** the paid enrollment **converted the existing personal team in place** — same
Team ID `4B8499Z59P`, flipped from `isFreeProvisioningTeam = 1` to `0` sometime between
2026-06-01 and 2026-07-27 (`~/Library/Preferences/com.apple.dt.Xcode.plist` last written
2026-07-27 21:58). Nothing in the repo needs a team-ID change.

> ⚠️ This is the single load-bearing assumption in this doc. Confirm it in
> **step 2** below (Xcode → Settings → Accounts should show exactly one team,
> `Sean Simpson (4B8499Z59P)`, with no "(Personal Team)" suffix). If a *second*
> team with a *different* ID appears, jump to [§9 Open questions](#9-open-questions).

### Correction to existing project memory

`memory/project_free_apple_account.md` states the current team ID is `QWA2JXVLHT`.
**That is wrong.** `QWA2JXVLHT` is the parenthetical in the certificate's Common Name —
a per-certificate identifier, not a team. The Team ID lives in the certificate's `OU`
field and in the profile's `TeamIdentifier`, and both say `4B8499Z59P`:

```
subject=UID=A8WHQZYZ7N, CN=Apple Development: seantokuzo@gmail.com (QWA2JXVLHT), OU=4B8499Z59P, O=Sean Simpson, C=US
                                                                  ^^^^^^^^^^                ^^^^^^^^^^
                                                                  cert ID, NOT team          ← Team ID
```

`security find-identity -v -p codesigning` prints the CN only, which is why the earlier
session mistook the cert ID for a team ID. When you need the team, read `OU`, not the CN.

That memory file should be retired/rewritten once you've confirmed §2 — it is now
describing a world that no longer exists.

---

## 1. What actually changes

### The 7-day thing was a *profile* limit, not a certificate limit

This is the part everyone gets wrong. Your **certificates were already 1-year** under the
free team (measured above: Apr 2026 → Apr 2027). What died every week was the
**provisioning profile**, which free provisioning stamps with `TimeToLive = 7`.

| | Free personal team (before) | Paid Developer Program (now) |
|---|---|---|
| Apple Development certificate | 1 year (measured) | 1 year (measured — same certs still valid) |
| Development provisioning profile | **7 days** (`TimeToLive = 7`, measured) | Bounded by the signing certificate → **~1 year** |
| App IDs registered at once | 10, **each expiring after 7 days** ([Apple](https://developer.apple.com/support/compare-memberships/)) | No 7-day expiry; standard App ID limits |
| Test devices per platform | **3, each expiring after 7 days** ([Apple](https://developer.apple.com/support/compare-memberships/)) | 100 per device type per membership year |
| App on phone survives a week? | **No** — profile expires, app refuses to launch | **Yes** — survives until the profile/cert expires (~1 year) |
| Ad hoc distribution | No | Yes |
| TestFlight / App Store | No | Yes |
| Apple Distribution certificate | Not available | Available (Account Holder creates it) |

> **On the "3-app cap" in the original framing:** it isn't 3 apps. Apple's
> [Choosing a Membership](https://developer.apple.com/support/compare-memberships/) page
> caps free provisioning at **10 App IDs** and **3 test devices per platform**, both
> expiring after 7 days. Major Tom uses 3 App IDs (`com.majortom.app`, `.widgets`,
> `.watchkitapp`), so the App ID cap was never the binding constraint — the 7-day expiry was.

### What does *not* change

- **Team ID** — still `4B8499Z59P` (see §0).
- **Bundle IDs** — unchanged.
- **`project.pbxproj`** — no edit required for this migration (see §3).
- **Your existing certificates** — the two Apple Development certs in your login keychain
  are already issued under `OU=4B8499Z59P` and remain valid to Apr 2027 / May 2027. You do
  not need to revoke or recreate them.
- **App Groups still work.** Contrary to a lot of blog folklore, free provisioning *did*
  grant `com.apple.security.application-groups` here — the widget's June profile carried
  `group.com.majortom.shared`. Apple's
  [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios)
  lists App groups as available to the plain "Apple Developer" (free) membership too.

### Honest caveat on the exact numbers

Apple **does not publish** certificate or provisioning-profile validity durations in its
current help docs. [Certificates overview](https://developer.apple.com/support/certificates/)
lists every certificate type but states no lifetime;
[Provisioning profile updates](https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates/)
only quotes a 7-day figure for *offline* profiles (a different feature — see §8).
The "1 year" figures above come from **measuring the actual certificates on this Mac**,
plus Apple's
[Cloud-managed certificates](https://developer.apple.com/help/account/certificates/cloud-managed-certificates/)
page, which says manual rotation unlocks "once the certificate has less than half of its
validity duration left (often 180 days)" — implying a 360–365 day validity.

**Do not treat "1 year" as a documented guarantee.** Verify the real number after your
first paid build using the `embedded.mobileprovision` check in §6.

---

## 2. Xcode walkthrough

Xcode version on this machine: **26.5 (17F42)**. Menu paths below are Apple's own wording
from [Synchronizing code signing identities with your developer account](https://developer.apple.com/documentation/Xcode/sharing-your-teams-signing-certificates)
and [Adding capabilities to your app](https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app).

### Step 1 — Quit anything holding the project

Close Xcode entirely (`Xcode > Quit Xcode`) if it's open, then reopen it. Xcode caches
team metadata aggressively; a fresh launch after enrollment is the cheapest way to make it
re-fetch.

### Step 2 — Confirm the account and team (the important one)

1. Open **Xcode**.
2. Choose **Xcode > Settings**.
3. In the toolbar, click **Accounts**.
4. Select your Apple Account (`seantokuzo@gmail.com`) from the list on the left.
5. Look at the **team list** on the right.

**What you should see:** exactly one row — `Sean Simpson`, role `Account Holder` (or
`Agent`), Team ID `4B8499Z59P`, with **no "(Personal Team)" suffix**.

- ✅ **One team, no "(Personal Team)":** confirmed — the personal team was converted in
  place. Skip to Step 4.
- ⚠️ **The row still says "(Personal Team)":** Xcode hasn't refreshed. Click the
  **Refresh / circular-arrow** control (or remove the account with the **–** button and
  re-add it with **+ > Apple ID**, then sign in). Recheck.
- 🚨 **Two teams, one "(Personal Team)" and one with a *different* 10-char ID:** enrollment
  created a *new* team rather than converting. This is the one scenario that **does**
  require a `project.pbxproj` edit — see [§3](#3-does-projectpbxproj-need-editing) and
  [§9](#9-open-questions).

If you were signed out entirely: click the **+** button in the lower-left of the Accounts
pane, choose **Apple ID**, click **Continue**, and sign in with `seantokuzo@gmail.com`.

### Step 3 — Confirm the signing certificate

Still in **Xcode > Settings > Accounts**:

1. Select your Apple Account.
2. Select the team `Sean Simpson` from the list of your Apple Account teams.
3. Click **Manage Certificates**.
4. You should see an **Apple Development** certificate. It should not be marked expired
   or missing a key.
5. If there is no usable Apple Development certificate: in the lower-left corner of the
   signing certificates sheet, click the **Add** button (**+**) and choose
   **Apple Development** from the pop-up menu.
6. Click **Done**.

> Don't revoke the existing certs. They're valid to Apr/May 2027 and already carry
> `OU=4B8499Z59P`. Revoking would invalidate every profile that references them for no gain.

### Step 4 — Set the team on every target

1. Open `ios/MajorTom.xcodeproj`.
2. In the **Project navigator**, select the project — the root group named **MajorTom**.
3. In the project editor on the right, select a target in the sidebar.
4. Click the **Signing & Capabilities** tab.
5. Leave the build-configuration selector on **All** (not Debug/Release individually).
6. Confirm **Automatically manage signing** is checked.
7. In the **Team** pop-up menu, select **Sean Simpson (4B8499Z59P)**.
8. Watch the **Signing Certificate** and **Provisioning Profile** rows resolve to
   "Apple Development: seantokuzo@gmail.com" and "Xcode Managed Profile". No red text.

**Repeat steps 3–8 for all three targets** — see the table in §4. Do not skip
`MajorTomWidgets`: it currently inherits `DEVELOPMENT_TEAM` from the project level rather
than declaring its own, so its Signing & Capabilities pane is where you'll actually see
whether the widget's App Group provisioned.

### Step 5 — Let Xcode regenerate profiles

Automatic signing regenerates on demand. To force it now:

1. Choose **Product > Clean Build Folder** (`⇧⌘K`).
2. Select the **MajorTom** scheme and **Sean's iPhone** as the run destination.
3. Choose **Product > Build** (`⌘B`).

Xcode will contact the developer portal, register/refresh the App IDs, mint fresh profiles,
and drop them in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`.

### Step 6 — If stale free-team artifacts conflict

Symptoms: `"provisioning profile ... has expired"`, `"doesn't match the entitlements"`,
`"No profiles for 'com.majortom.app' were found"` **after** doing steps 2–5.

Nuke the profile cache and let Xcode refetch. Note the path — **Xcode 16 moved it**;
the old `~/Library/MobileDevice/Provisioning Profiles/` does not exist on this machine:

```bash
# Back up first, then clear
mkdir -p /tmp/profile-backup
mv ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/* /tmp/profile-backup/ 2>/dev/null
# Legacy location, harmless if absent
mv ~/Library/MobileDevice/Provisioning\ Profiles/* /tmp/profile-backup/ 2>/dev/null

# Clear DerivedData for this project only
rm -rf ~/Library/Developer/Xcode/DerivedData/MajorTom-*
```

Then rebuild (Step 5). If Xcode still won't refetch, in **Xcode > Settings > Accounts**
select the team and click **Download Manual Profiles** if that button is present in your
Xcode version — automatic signing does not require it, so skip it if you don't see it.

Last resort: remove the Apple Account (**–** in Accounts) and re-add it, then redo Step 4.

---

## 3. Does `project.pbxproj` need editing?

**No — not for this migration.** `DEVELOPMENT_TEAM = 4B8499Z59P` is already correct at the
project level and on every target that declares it. `CODE_SIGN_STYLE = Automatic` is
already set. `PROVISIONING_PROFILE_SPECIFIER = ""` is the correct value for automatic
signing (empty = let Xcode choose).

Do **not** open the project file for this. There are two open PRs in flight and
`project.pbxproj` is a merge-conflict magnet.

### Contingency: only if Step 2 reveals a *new* Team ID

If Xcode shows a second team with a different ID (call it `NEWTEAMID`), then — and only
then — the fix is to change the team everywhere. Prefer doing it through the Xcode UI
(Step 4), which rewrites the file correctly. If you must do it by hand, the change is a
straight substitution across all 5 occurrences:

```diff
-				DEVELOPMENT_TEAM = 4B8499Z59P;
+				DEVELOPMENT_TEAM = NEWTEAMID;
```

Occurrences in `ios/MajorTom.xcodeproj/project.pbxproj` (line numbers as of commit
`9411478`):

| Line | Build configuration | Applies to |
|------|---------------------|------------|
| 1865 | `00E0CC7A…` Release | MajorTomWatch |
| 1889 | `4D2D3FF4…` Debug | MajorTomWatch |
| 1913 | `5B6995D6…` Debug | MajorTom (app) |
| 1975 | `6703709D…` Release | **Project level** (inherited by MajorTomWidgets) |
| 2025 | `92732455…` Release | MajorTom (app) |
| 2109 | `D2214030…` Debug | **Project level** (inherited by MajorTomWidgets) |

Equivalent one-liner, to run **only** after the in-flight PRs merge and on a dedicated branch:

```bash
sed -i '' 's/DEVELOPMENT_TEAM = 4B8499Z59P;/DEVELOPMENT_TEAM = NEWTEAMID;/g' \
  ios/MajorTom.xcodeproj/project.pbxproj
```

### Unrelated cleanups worth queueing (not needed now)

These are pre-existing and don't block the paid-account switch. Filed here so they're not lost:

1. **`CODE_SIGN_IDENTITY = "iPhone Developer"`** on the `MajorTom` app target (lines 1912
   and 2024) is a legacy alias. It resolves fine for development builds today. It will be
   **wrong** the first time you cut a Release build for TestFlight/App Store, because it
   pins a development identity. Change to `"Apple Development"` for Debug and delete it
   entirely from Release (letting automatic signing pick `Apple Distribution`) when you get
   to distribution.
2. **The main app target has no `CODE_SIGN_ENTITLEMENTS`.** Confirmed by
   `codesign -d --entitlements` on the last build — the app ships with only
   `application-identifier`, `com.apple.developer.team-identifier`, `get-task-allow`.
   But `MajorTom/Core/Services/PhoneWatchConnectivityService.swift`,
   `MajorTom/Features/Shortcuts/MajorTomShortcuts.swift`, and
   `MajorTom/Features/Widgets/WidgetDataProvider.swift` all call
   `UserDefaults(suiteName: "group.com.majortom.shared")`. **Without the App Group
   entitlement on the app, those return `nil`** — so the phone side of the widget/watch/
   Shortcuts data bridge is silently dead. This is a real bug, orthogonal to signing, and
   should be its own ticket. Fix = add the **App Groups** capability to the `MajorTom`
   target (§5), which creates `MajorTom/MajorTom.entitlements` and wires
   `CODE_SIGN_ENTITLEMENTS`.
3. **`MajorTomWatch` is not embedded in the app** — it is neither a target dependency of
   `MajorTom` nor in an "Embed Watch Content" copy phase. It only builds via its own
   scheme. Not a signing problem, just a thing to know before you go hunting for why the
   watch app never lands on the phone.

---

## 4. Targets that need the team set

Three native targets, all in `ios/MajorTom.xcodeproj`:

| Target | Product | Bundle ID | Type | `DEVELOPMENT_TEAM` source | Entitlements file |
|--------|---------|-----------|------|---------------------------|-------------------|
| **MajorTom** | `Major Tom.app` | `com.majortom.app` | iOS app | Declared on target (Debug + Release) | **none** (see §3.2) |
| **MajorTomWidgets** | `MajorTomWidgets.appex` | `com.majortom.app.widgets` | App extension (WidgetKit) | **Inherited from project level** — target configs don't declare it | `MajorTomWidgets/MajorTomWidgets.entitlements` (App Group) |
| **MajorTomWatch** | `MajorTomWatch.app` | `com.majortom.app.watchkitapp` | watchOS app (`SDKROOT = watchos`) | Declared on target (Debug + Release) | **none** — but its code reads the App Group |

Bundle ID nesting is **correct**: both `com.majortom.app.widgets` and
`com.majortom.app.watchkitapp` are prefixed by the parent `com.majortom.app`, as required.

There is no separate WatchKit *extension* target — this is the modern single-target
watchOS app layout (`WKCompanionAppBundleIdentifier = com.majortom.app`,
`WKRunsIndependentlyOfCompanionApp = YES`). Nothing extra to sign there.

Note `MajorTomWidgets` also has no `CODE_SIGN_STYLE` of its own — it inherits `Automatic`
from the project. That's fine, but it means the widget's team is only correct as long as
the *project-level* setting is. If you ever set the team per-target in the UI, Xcode may
write it onto the widget target explicitly; that's harmless.

---

## 5. Portal-side setup

**Short answer: almost none. Automatic signing handles it.**

Capabilities actually in use, and what each needs:

| Capability / entitlement | Where it's used | Portal work needed? |
|---|---|---|
| **App Groups** `group.com.majortom.shared` | `MajorTomWidgets.entitlements`; read by widget, watch, and (attempted) app | **Xcode creates and registers it for you.** Per [Configuring app groups](https://developer.apple.com/documentation/xcode/configuring-app-groups): click **+** below the App Groups list, enter a container ID beginning with `group.`, click **OK** — "Xcode will create a new container if the named container doesn't already exist, add it to your App ID, and add the new container to your app's entitlements." Already provisioned for the widget (verified in the June profile). |
| **Local Network / Bonjour** | `Info.plist`: `NSLocalNetworkUsageDescription`, `NSBonjourServices = _majortom._tcp` | **None.** These are Info.plist keys and a runtime permission prompt, not an entitlement. No App ID configuration. |
| **App Transport Security exceptions** | `Info.plist`: `NSAllowsLocalNetworking`, `NSAllowsArbitraryLoads` | **None.** (Will need an App Review justification if you ever ship to the App Store — `NSAllowsArbitraryLoads` is a red flag there.) |
| **Custom URL scheme** `majortom://` | `Info.plist`: `CFBundleURLTypes` | **None.** |
| **App Intents / App Shortcuts** | `MajorTom/Features/Shortcuts/MajorTomShortcuts.swift` | **None.** The modern AppIntents framework needs no capability and no App ID configuration. Only legacy SiriKit *intents extensions* need the Siri capability. |
| **WatchConnectivity** | `WatchConnectivityService.swift`, `PhoneWatchConnectivityService.swift` | **None.** WatchConnectivity requires no entitlement — just the paired-app bundle ID relationship, which is already correct. |
| **Live Activities** | `INFOPLIST_KEY_NSSupportsLiveActivities = YES`; `LiveActivityManager.swift` uses `pushType: nil` | **None** while updates are local. Would need **Push Notifications** if you ever switch to `pushType: .token`. |
| **Local notifications** (`UNUserNotificationCenter`) | `NotificationService.swift` | **None.** |
| **Remote notifications (APNs)** | `NotificationService.swift:74` calls `UIApplication.shared.registerForRemoteNotifications()` | ⚠️ **Currently unprovisioned.** There is no `aps-environment` entitlement in the built app, so registration fails and the code falls back to local notifications (as the comment at line 87 says). If you want real APNs now that you're paid: add the **Push Notifications** capability to the `MajorTom` target (§2 Step 4 pane → **+ Capability** → Push Notifications), which makes Xcode enable the service on the App ID automatically. You'll also need an **APNs Auth Key** created manually in Certificates, Identifiers & Profiles, and relay-side work to actually send pushes. Out of scope for this migration. |

Nothing here requires you to log into
[developer.apple.com/account](https://developer.apple.com/account) for the basic
"make the app stop dying weekly" goal.

### Register the device (one-time, if needed)

Your iPhone (`00008130-001625913CF0001C`) was already provisioned under the free team.
Paid teams register devices separately; Xcode does it automatically the first time you
build to the device with the paid team selected. If Xcode prompts "Register device?",
say yes. Paid memberships allow 100 iPhones per membership year, and **device slots only
reset at annual renewal** — don't burn them casually.

---

## 6. Verification

Run these **after** your first successful build with the paid team.

### 6a. Certificate check

```bash
security find-identity -v -p codesigning
```

Expected: at least one `Apple Development: seantokuzo@gmail.com (…)` identity.

> Remember: the parenthetical is the **certificate ID**, not the team. To see the team,
> dump the cert and read `OU`:

```bash
security find-certificate -a -c "Apple Development" -p \
  | awk '/BEGIN CERT/{n++} {print > ("/tmp/mtcert" n ".pem")}'
for f in /tmp/mtcert*.pem; do openssl x509 -in "$f" -noout -subject -dates; done
rm -f /tmp/mtcert*.pem
```

Expected output shape:

```
subject=UID=…, CN=Apple Development: seantokuzo@gmail.com (…), OU=4B8499Z59P, O=Sean Simpson, C=US
notBefore=… 2026 GMT
notAfter=… 2027 GMT          ← ~1 year out
```

### 6b. Provisioning profile check — the real test

This is the one that proves the 7-day curse is broken.

```bash
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/MajorTom-*/Build/Products/Debug-iphoneos/"Major Tom.app" | head -1)
security cms -D -i "$APP/embedded.mobileprovision" -o /tmp/mtprof.plist
for k in Name TeamIdentifier CreationDate ExpirationDate TimeToLive; do
  printf "%-16s: " "$k"
  /usr/libexec/PlistBuddy -c "Print :$k" /tmp/mtprof.plist 2>&1 | tr '\n' ' '; echo
done
/usr/libexec/PlistBuddy -c "Print :Entitlements" /tmp/mtprof.plist
rm -f /tmp/mtprof.plist
```

| Field | Free team (measured, 2026-06-01) | Paid team (what you want) |
|-------|----------------------------------|---------------------------|
| `TeamIdentifier` | `4B8499Z59P` | `4B8499Z59P` (unchanged) |
| `TimeToLive` | **`7`** | **absent, or ~365** |
| `ExpirationDate` | 7 days after creation | **~1 year after creation** |

**If `TimeToLive` is still `7`, the paid team is not being used.** Go back to §2 Step 2.

Do the same for the widget — swap `"Major Tom.app"` for
`"Major Tom.app/PlugIns/MajorTomWidgets.appex"` — and confirm its `Entitlements` dict
still contains `com.apple.security.application-groups → group.com.majortom.shared`.

### 6c. What the built binary is actually signed with

```bash
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p -
```

Expect `TeamIdentifier=4B8499Z59P` and `Authority=Apple Development: seantokuzo@gmail.com (…)`.

### 6d. The lazy check

Build, install, **and then don't touch it for 8 days**. If the app still launches on day 9,
you're done. That's the actual success criterion.

---

## 7. Device install flow afterward

Unchanged commands, fewer reasons to run them. From `reference_wireless_device_deploy`:

```bash
# Build (from ios/)
xcodebuild -project MajorTom.xcodeproj -scheme MajorTom \
  -destination 'id=00008130-001625913CF0001C' \
  -allowProvisioningUpdates build

# Install
xcrun devicectl device install app \
  --device 00008130-001625913CF0001C \
  ~/Library/Developer/Xcode/DerivedData/MajorTom-*/Build/Products/Debug-iphoneos/"Major Tom.app"
```

Still true:
- Both devices on the same Wi-Fi. Wireless pairing is persistent — no USB.
- Phone must be **unlocked** for install.
- `-allowProvisioningUpdates` still only works if an Apple Account is signed into Xcode
  (Xcode holds the portal credentials; `xcodebuild` borrows them).

**No longer needed — the free-team dance is dead:**
- ❌ Weekly "open Xcode, click through Signing & Capabilities on all three targets to
  re-mint a 7-day profile." Steps 1–4 of the old dance in
  `memory/project_free_apple_account.md` are obsolete.
- ❌ Re-checking the team ID in the keychain before every build because "the personal team
  ID can drift." Paid Team IDs are stable for the life of the membership.
- ❌ Treating `error: No profiles for 'com.majortom.app' were found` as a routine weekly
  event. It's now a genuine failure worth investigating.

**Still needed:**
- ✅ An Apple Account signed into Xcode for CLI provisioning updates.
- ✅ Xcode opened at least once after enrollment (Step 1) so it caches paid-team metadata.
- ✅ Annual renewal. Put `2027-07` in a calendar — when the membership lapses, *everything*
  reverts and profiles start expiring again.

**New failure mode to know about:** Apple requires development- and ad-hoc-signed iOS apps
from memberships created after 2021-06-06 to check in with the PPQ service
(`https://ppq.apple.com`) on first launch. Per
[Provisioning profile updates](https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates/):
"Your device must be connected to the internet to verify the certificate used to sign your
app… If the device can't successfully make a connection, the app may not launch."
Practically: don't first-launch a fresh build while the phone is in airplane mode. Whether
this applies to a *converted* personal team is unverified — flagged in §9.

---

## 8. Known pitfalls

**Keychain "Always Allow" prompts.** Per `memory/feedback_keychain_always_allow`: `codesign`
pops a macOS Keychain dialog asking permission to use the signing key. If you're AFK, the
build hangs forever at near-zero CPU and you may end up installing a stale `.app` without
noticing. You already set **Always Allow** on the existing certificate — but that grant is
**per-certificate**, so if a *new* Apple Development certificate gets minted (Step 3 case 5,
or a cert rotation), the prompt comes back for the new one.

If a build hangs on `CodeSign` with no CPU: check your Mac's screen for a dialog. Then make
it permanent:

1. Open **Keychain Access** (`/Applications/Utilities/`).
2. Select the **login** keychain, category **My Certificates**.
3. Expand the `Apple Development: seantokuzo@gmail.com (…)` entry and double-click the
   private key beneath it.
4. Go to the **Access Control** tab.
5. Select **Allow all applications to access this item**, or keep
   "Confirm before allowing access" **unchecked** for `codesign`.
6. Click **Save Changes** and enter your login password.

**Other pitfalls:**

- **Provisioning profile directory moved.** Xcode 16+ uses
  `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`, not
  `~/Library/MobileDevice/Provisioning Profiles/`. Old blog posts and some third-party
  tooling still point at the dead path. On this Mac the old path doesn't exist at all.
- **The profile dir is currently empty.** Normal — automatic signing keeps working profiles
  in DerivedData and refetches on demand. Don't panic-diagnose from an empty directory.
- **`security find-identity` shows two identical-looking certs.** They are two different
  Apple Development certs (Apr 2026 and May 2026) with the same CN. Harmless; Xcode picks
  the newest. Don't "clean up" by deleting one unless you've checked which the current
  profile references.
- **Don't manually flip `CODE_SIGN_STYLE` to `Manual`.** Everything in this project assumes
  automatic. Manual signing means you own App ID registration, profile creation, and
  renewal by hand — reintroducing exactly the toil you just paid $99 to delete.
- **Don't commit team-ID churn during the in-flight PRs.** `project.pbxproj` conflicts are
  miserable. If Xcode rewrites the file as a side effect of clicking through Signing &
  Capabilities, `git checkout -- ios/MajorTom.xcodeproj/project.pbxproj` after verifying
  the build works — the on-disk value is already correct, so discarding Xcode's rewrite
  loses nothing.
- **`xcuserdata` noise.** `UserInterfaceState.xcuserstate` and `xcschememanagement.plist`
  will show as modified after you open Xcode. Ignore them; they're already dirty on this
  branch.

---

## 9. Open questions

1. **Did the Team ID actually stay `4B8499Z59P`?** All local evidence says yes — Xcode's
   own cache lists one team, `4B8499Z59P`, with `isFreeProvisioningTeam = 0` and
   `teamType = Individual`, and the same ID was issuing 7-day profiles in June. But Apple
   does not document whether individual enrollment converts a personal team in place or
   mints a new one, and community sources disagree. **Sean: confirm in §2 Step 2.** This is
   the only thing that could turn this from a zero-code-change migration into a
   `project.pbxproj` edit.

2. **Exact certificate and profile lifetimes are not documented by Apple.** The 1-year
   figures here are measured from your keychain, not quoted from Apple. Apple's
   [Certificates overview](https://developer.apple.com/support/certificates/) and
   [Provisioning profile updates](https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates/)
   both omit durations. Treat §6b as the source of truth once you've built.

3. **Ad hoc profile validity — unverified.** Couldn't confirm from Apple docs. Forum
   sources claim 90 days for ad hoc vs 1 year for in-house; that contradicts the general
   rule that a profile can't outlive its certificate. Not relevant until you distribute.

4. **Does the PPQ first-launch check-in apply here?** Apple scopes it to "new Apple
   Developer Program memberships created after June 6, 2021." Whether a *converted*
   personal team counts as created-in-2026 or inherits an older creation date is not
   documented. Low stakes — just keep the phone online on first launch of a new build.

5. **When exactly did enrollment happen?** Inferred as between 2026-06-01 (last free
   7-day profile) and 2026-07-27 (Xcode prefs rewritten with `isFreeProvisioningTeam = 0`).
   If Sean enrolled *after* 2026-07-27, then that `isFreeProvisioningTeam = 0` came from
   somewhere else and conclusion #1 needs rechecking.

6. **Do you want APNs now?** Push Notifications is the one capability the code reaches for
   (`NotificationService.swift:74`) but was never provisioned for. It's now available. Needs
   its own ticket: Xcode capability + APNs Auth Key + relay-side sender.

7. **Should the App Group bug (§3.2) be fixed in the same pass?** It's a genuine broken
   feature — the phone side of widget/watch/Shortcuts data sharing silently no-ops — but
   it touches `project.pbxproj` and adds a new entitlements file, so it fights the in-flight
   PRs. Recommend a separate branch after they land.

---

## Sources

- [Choosing a Membership](https://developer.apple.com/support/compare-memberships/) — free vs paid, 10 App IDs / 3 devices / 7-day expiry
- [Certificates overview](https://developer.apple.com/support/certificates/) — certificate types, who can create them
- [Provisioning profile updates](https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates/) — PPQ check-in, offline profiles
- [Cloud-managed certificates](https://developer.apple.com/help/account/certificates/cloud-managed-certificates/) — 90-day pre-expiry rotation, "often 180 days"
- [Synchronizing code signing identities with your developer account](https://developer.apple.com/documentation/Xcode/sharing-your-teams-signing-certificates) — Xcode Settings → Accounts → Manage Certificates paths
- [Adding capabilities to your app](https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app) — Signing & Capabilities pane, Capability (+) button
- [Configuring app groups](https://developer.apple.com/documentation/xcode/configuring-app-groups) — Xcode auto-registers `group.` containers
- [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios) — App groups / Push notifications availability by membership
- [Team ID glossary](https://developer.apple.com/help/glossary/team-id) — "unique 10-character string generated by Apple"
