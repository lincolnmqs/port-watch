# Settings Modal, Launch at Login, Green Pulse & Refresh Interval

**Date:** 2026-04-03
**Status:** Approved

---

## Overview

Four related improvements to PortWatch:

1. `AppSettings` singleton to manage persistent user preferences
2. Settings modal (NSPanel) accessible via a gear icon in the popover header
3. "Launch at Login" toggle as the first preference, powered by `SMAppService`
4. Green circle with pulse animation per service row in `PortRowView`
5. Auto-refresh interval change from 3s → 5s when popover is visible

---

## Architecture

### AppSettings (`Services/AppSettings.swift`)

A new singleton `ObservableObject` that owns all user preferences. Follows the same pattern as `AliasStore.shared`.

```swift
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false {
        didSet { applyLaunchAtLogin() }
    }

    private func applyLaunchAtLogin() {
        // SMAppService.mainApp.register() or .unregister()
    }
}
```

- Persists via `UserDefaults` through `@AppStorage` — no manual serialization needed.
- `SMAppService` (from `ServiceManagement` framework, macOS 13+) handles the actual OS-level login item registration.
- Errors from `SMAppService` are caught and logged silently; the toggle reverts to its previous value on failure.

### SettingsView (`Views/SettingsView.swift`)

A SwiftUI view rendered inside an `NSPanel` with the same floating style used by `ServiceInfoView`. Opened and managed by `MenuBarController`.

Structure:
- Section "General" with a `Toggle` for "Launch at Login" + a short description label
- Designed to grow: each new setting is a new row/section in this view
- Fixed size (e.g. 360×240 initial), auto-adjustable as settings grow

### Gear Icon in Header (`PortWatchPopoverView`)

- `Image(systemName: "gearshape")` button added to the header `HStack`
- Positioned between the `ProgressView` spinner and the refresh button
- Taps call an `onOpenSettings: () -> Void` closure injected by `MenuBarController` at panel creation time — keeps panel management out of the ViewModel
- Uses `.buttonStyle(.plain)` and `.foregroundStyle(.white.opacity(0.45))` to match the existing refresh button style

### Green Pulse in PortRowView

- A `Circle().fill(Color.green).frame(width: 6, height: 6)` inserted before `Text(service.primaryName)` in the row's leading `HStack`
- Animated with `scaleEffect` (1.0 → 1.35) + `opacity` (1.0 → 0.4), `.repeatForever(autoreverses: true)`, duration ~1.5s
- Driven by a `@State private var pulse = false` toggled in `.onAppear`

### Refresh Interval (`PortWatchViewModel`)

- `return 3` → `return 5` in `refreshInterval` (panel visible case)
- Footer label `"auto · 3s"` → `"auto · 5s"`

---

## Data Flow

```
AppSettings.shared.launchAtLogin (UserDefaults)
    └── didSet → SMAppService.mainApp.register/unregister

MenuBarController
    └── opens SettingsView (NSPanel) on gear icon tap

PortWatchPopoverView (header)
    └── gear button → calls openSettings action
```

---

## Error Handling

- If `SMAppService.register()` throws, the `launchAtLogin` property is reverted to `false` and the error is printed to console (no user-facing alert for now — can be added later as a setting-specific inline error).
- `SMAppService` requires macOS 13+. The app's deployment target should be verified to be ≥ 13.0.

---

## Files Changed

| File | Change |
|------|--------|
| `Services/AppSettings.swift` | **New** — singleton with `launchAtLogin` |
| `Views/SettingsView.swift` | **New** — settings panel UI |
| `MenuBar/MenuBarController.swift` | Add `openSettings()`, create settings NSPanel |
| `Views/PortWatchPopoverView.swift` | Add gear icon button in header |
| `ViewModels/PortWatchViewModel.swift` | Refresh interval 3s→5s |
| `Views/PortRowView.swift` | Add green pulse circle before service name |
| `PortWatch.xcodeproj/project.pbxproj` | Add new files to project |

---

## Out of Scope

- Other settings beyond "Launch at Login" (will be added in future iterations)
- Settings sync or iCloud
- Onboarding or first-run prompts
