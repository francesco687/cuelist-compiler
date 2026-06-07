# Mandatory operator name — design

**Date:** 2026-06-07
**Status:** Approved

## Problem

Operator identity in the relay roster is derived from `UIDevice.current.name`
(set in `App.swift` `onAppear`). On iOS 16+ that returns a generic `"iPhone"`
unless the app holds the `user-assigned-device-name` entitlement, so every phone
shows up as bare `"iPhone"` in the roster — operators can't tell each other
apart. This bit on the desk during the first multi-phone smoke.

This reverses the original locked decision (`identity = UIDevice.current.name,
no settings field`) in favor of a user-entered, persisted, **required** name.

## Goal

Every operator names themselves. A nameless phone cannot connect, and a
first-run user is forced to set a name before using the app.

## Design

### 1. Data layer — `Sources/Kit/Hub/HubClient.swift`

- Persist `operatorName` like the other connection settings: add
  `didSet { defaults.set(operatorName, forKey: Keys.operatorName) }`, read it
  back in `init` (`defaults.string(forKey: Keys.operatorName) ?? ""`), and add
  `static let operatorName = "hubOperatorName"` to `Keys`. Fresh install → `""`.
- Add `var hasName: Bool` — true when `operatorName` is non-empty after trimming
  whitespace. Single shared definition of "named" for UI + connect logic.

### 2. Identity source — `Sources/App/App.swift`

- Delete `hub.operatorName = UIDevice.current.name`. The name now comes only
  from the persisted field.
- Change the auto-connect-on-launch guard so it does **not** connect while
  nameless (`hub.hasName` required before any auto-connect). No silent nameless
  join.

### 3. Mandatory enforcement

- **`Sources/App/SettingsView.swift`:**
  - Add a "Your name" `TextField` bound to `$hub.operatorName` at the top of the
    Connection section. Empty by default, `.textInputAutocapitalization(.words)`,
    autocorrection disabled. Footer hint: "Required — this is how others see you
    in the session."
  - Gate the **Done** toolbar button: `.disabled(!hub.hasName)`. Cannot leave
    Settings without a name.
  - Gate **Connect**: `.disabled(!hub.hasName)`.
- **Auto-open on launch — `Sources/App/RootView.swift`:** a `.sheet` presenting
  `SettingsView`, shown automatically when `hub.operatorName.isEmpty` at launch.
  Because Done is gated, a first-run user must name themselves before dismissing.

### 4. No change

- Roster already renders `op.name`; real names just appear.
- Relay's `trimmed || 'iPhone'` fallback stays as a harmless (now effectively
  unreachable) backstop.

## Out of scope (YAGNI)

- Live rename without reconnect — editing the name mid-session updates the roster
  on the next **Connect** (re-join), not instantly.
- No pre-fill of the field (avoids everyone accepting a pre-filled "iPhone").
- No length cap beyond what the relay already tolerates.

## Tests (SaettaKit)

- `operatorName` persists across re-init with the same `UserDefaults`.
- The relay join frame carries the entered name.
- `hasName` is false for `""` and whitespace-only, true otherwise.
