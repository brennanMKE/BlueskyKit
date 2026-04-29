# BlueskySettings

The `BlueskySettings` module contains the settings hub and all settings sub-screens: Appearance, Language, Notifications, Privacy, Content, Accessibility, About, App Passwords, and Find Contacts.

## Module Overview

```
Sources/BlueskySettings/
  SettingsScreen.swift
  SettingsViewModel.swift
  AppearanceSettingsScreen.swift
  LanguageSettingsScreen.swift
  NotificationSettingsScreen.swift
  PrivacySettingsScreen.swift
  ContentSettingsScreen.swift
  AccessibilitySettingsScreen.swift
  AboutScreen.swift
  AppPasswordsScreen.swift
  AppPasswordsStore.swift
  AppPasswordsViewModel.swift
  FindContactsScreen.swift
  FindContactsStore.swift
  FindContactsViewModel.swift
```

Like all feature modules in BlueskyKit, this module uses `@MainActor` default isolation. Network I/O is handled through the `NetworkClient` protocol; local preferences are read and written through the `PreferencesStore` protocol, both defined in `BlueskyKit`.

---

## Architecture

Settings screens that require no network round-trip (Appearance, Language, Accessibility) depend only on `PreferencesStore`. Screens that must read from or write to the server (App Passwords, Find Contacts) pair a `Store` with a `ViewModel` using the same three-tier Store / ViewModel / View pattern used in other BlueskyKit modules.

| Screen | Has Store | Network? |
|--------|-----------|---------|
| `SettingsScreen` | No | No |
| `AppearanceSettingsScreen` | No | No (local prefs) |
| `LanguageSettingsScreen` | No | No (local prefs) |
| `NotificationSettingsScreen` | No | Push token via OS, no AT Proto call |
| `PrivacySettingsScreen` | No | No (local prefs) |
| `ContentSettingsScreen` | No | No (delegated to BlueskyModeration) |
| `AccessibilitySettingsScreen` | No | No (local prefs) |
| `AboutScreen` | No | No |
| `AppPasswordsScreen` | Yes — `AppPasswordsStore` | Yes |
| `FindContactsScreen` | Yes — `FindContactsStore` | Yes |

---

## SettingsScreen

The root settings navigation list. Groups entries into sections:

- **Account** — current signed-in account summary, link to switch accounts
- **Preferences** — Appearance, Language, Notifications, Privacy, Content
- **Accessibility** — Accessibility
- **Security** — App Passwords
- **Contacts** — Find Contacts
- **About** — app version, legal, sign out

`SettingsScreen` observes `SettingsViewModel` for the currently signed-in account's display name and avatar URL, sourced from `SessionManaging`.

---

## SettingsViewModel

Minimal ViewModel that exposes:

- `displayName: String` — current account's display name or handle fallback
- `avatarURL: URL?` — current account's avatar
- `appVersion: String` — bundle version string for display in the About row

No async loading is required; all values come from already-resolved session state.

---

## AppearanceSettingsScreen

Controls visual presentation preferences stored locally via `PreferencesStore`.

### Settings

| Setting | Type | Options |
|---------|------|---------|
| Color scheme | Enum | System / Light / Dark |
| App icon | Enum | Default + alternate icon variants |
| Font size | Enum | Small / Medium / Large / Extra Large |
| True black dark mode | Bool | Toggles pure-black backgrounds |

Changes write through to `PreferencesStore` immediately. Color scheme changes call `UIApplication.shared.windows.first?.overrideUserInterfaceStyle` so the effect is instant without a restart.

---

## LanguageSettingsScreen

Manages the user's content-language preferences.

### Settings

| Setting | Description |
|---------|-------------|
| Primary language | Language used for composing posts |
| Content languages | List of languages to show in the feed (multi-select) |
| Translate prompt threshold | When to show an inline translate button |

Language codes follow BCP-47 (e.g., `en`, `ja`, `pt-BR`). The multi-select list is sourced from a static bundled list of supported languages; no network call is needed.

---

## NotificationSettingsScreen

Controls which notification types the user wants to receive.

### Settings

| Notification Type | Toggle |
|------------------|--------|
| Likes | Yes/No |
| Reposts | Yes/No |
| Follows | Yes/No |
| Mentions and replies | Yes/No |
| Quotes | Yes/No |
| New followers | Yes/No |

Preferences are stored locally and also synced to `app.bsky.notification.updateSeen` / push-registration endpoints when the user makes a change. Because APNs token registration lives at the OS layer, the screen calls into the system notification framework rather than `NetworkClient` for device token management.

---

## PrivacySettingsScreen

Contains account-level privacy toggles.

### Settings

| Setting | Description |
|---------|-------------|
| Require follow-back to DM | Restricts direct messages to mutual follows |
| Disable search indexing | Requests crawlers not index the account |
| Allow reposts in feeds | Controls whether reposts appear in followers' feeds |

Each toggle writes to `app.bsky.actor.putPreferences` via `NetworkClient`. The screen reads the current state from `PreferencesStore` on appear.

---

## ContentSettingsScreen

A thin wrapper that embeds the content-filter and labeler controls from `BlueskyModeration`. This screen exists so the settings navigation hierarchy has a "Content" entry point without duplicating the filter UI.

It hosts `ContentFilterSettingsScreen` from `BlueskyModeration` directly as a child view, passing through the shared `ModerationStore` instance.

---

## AccessibilitySettingsScreen

Controls accessibility-focused display preferences.

### Settings

| Setting | Type | Description |
|---------|------|-------------|
| Reduce motion | Bool | Disables animated transitions |
| Disable auto-play GIFs | Bool | Shows static first frame instead |
| Alt text reminder | Bool | Prompts to add alt text when composing images |
| Increase button size | Bool | Enlarges tap targets |

All settings are local; no network call is made. Changes are applied immediately via `PreferencesStore`.

---

## AboutScreen

Static informational screen. Displays:

- App name and version (from `SettingsViewModel.appVersion`)
- Build number
- Links: Terms of Service, Privacy Policy, Open Source Licenses
- A "Send Feedback" row that opens a mailto URL
- Sign Out button

The Sign Out button calls `SessionManaging.signOut()`, which clears the keychain record and returns the app to the login screen.

---

## AppPasswordsScreen

App passwords are secondary credentials scoped to specific third-party clients. They allow a user to revoke access for a single app without changing their main password.

`AppPasswordsScreen` observes `AppPasswordsViewModel` and displays:

- A list of existing app passwords (name, creation date)
- A "Create" button that opens a sheet for naming a new password
- A delete swipe action per row

### AppPasswordsStore

Manages the server-side lifecycle of app passwords.

#### State

| Property | Type | Description |
|----------|------|-------------|
| `passwords` | `[AppPassword]` | Fetched list of app passwords |
| `newlyCreated` | `AppPassword?` | The password value returned after creation (shown once) |
| `isLoading` | `Bool` | Loading state |
| `error` | `Error?` | Last error |

#### Key Actions

```swift
func load() async
func create(name: String) async
func delete(name: String) async
```

`create(name:)` calls `com.atproto.server.createAppPassword`. The plaintext password value is present only in the server response and stored in `newlyCreated` so the UI can display it once. It is never persisted locally.

`delete(name:)` calls `com.atproto.server.revokeAppPassword`.

### AppPasswordsViewModel

Formats `AppPassword` records for display:

- Sorts passwords by creation date descending
- Formats `createdAt` as a locale-aware relative date string (e.g., "3 days ago")

### AppPassword

```swift
struct AppPassword: Identifiable {
    let name: String           // user-chosen label
    let createdAt: Date
    var id: String { name }
}
```

---

## FindContactsScreen

Allows the user to find Bluesky accounts from their device contacts or by searching for known handles from other social networks.

`FindContactsScreen` observes `FindContactsViewModel` and shows:

- A "Search from contacts" button that requests Contacts permission and then runs a match
- A search field for manual handle / email lookup
- Matched results as a list of profile rows with Follow / Following toggle buttons

### FindContactsStore

Drives the contact-search network calls.

#### State

| Property | Type | Description |
|----------|------|-------------|
| `results` | `[Profile]` | Matched Bluesky profiles |
| `isSearching` | `Bool` | Search in progress |
| `contactsPermissionDenied` | `Bool` | Set if CNContactStore access was denied |
| `error` | `Error?` | Last error |

#### Key Actions

```swift
func searchFromContacts() async
func search(query: String) async
func follow(_ did: DID) async
func unfollow(_ did: DID) async
```

`searchFromContacts()` reads email addresses from `CNContactStore`, batches them, and calls `app.bsky.actor.searchActorsTypeahead` or a dedicated lookup endpoint. Results are deduplicated and sorted by mutual-follow status.

`search(query:)` calls `app.bsky.actor.searchActorsTypeahead` with the raw query string and replaces `results`.

### FindContactsViewModel

Adapts `FindContactsStore` state for display:

- Builds `ContactResultRow` presentation types combining profile data with a `isFollowing` flag
- Provides a `emptyStateMessage: String` that changes based on whether permission was denied, no results were found, or the search has not been run yet

---

## Core Types Used

| Type | Source | Notes |
|------|--------|-------|
| `DID` | `BlueskyCore/Identifiers.swift` | Current user DID and match targets |
| `Profile` | `BlueskyCore/Graph.swift` | Returned from contact search |
| `PreferencesStore` | `BlueskyKit/` | Protocol for local preferences I/O |
| `NetworkClient` | `BlueskyKit/` | Protocol for all remote API calls |
| `SessionManaging` | `BlueskyKit/` | Current user identity and sign-out |

---

## Dependencies

| Dependency | Role |
|-----------|------|
| `BlueskyCore` | Shared value types |
| `BlueskyKit` | `NetworkClient`, `PreferencesStore`, `SessionManaging` protocols |
| `BlueskyModeration` | `ContentFilterSettingsScreen` embedded in `ContentSettingsScreen` |
| `Contacts` (Apple framework) | Device contact access in `FindContactsStore` |
