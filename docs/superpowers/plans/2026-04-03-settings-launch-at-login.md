# Settings Modal, Launch at Login, Green Pulse & Refresh Interval — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a settings modal with a "Launch at Login" toggle, a green pulse indicator per service row, and change the auto-refresh interval to 5s.

**Architecture:** `AppSettings.shared` singleton manages user preferences via `@AppStorage` and controls `SMAppService` login-item registration. A gear icon in the popover header opens `SettingsView` as an `NSPanel` managed by `MenuBarController`. UI tweaks (green pulse, 5s refresh) are isolated to their respective views/viewmodel.

**Tech Stack:** Swift, SwiftUI, AppKit, ServiceManagement (SMAppService, macOS 13+), UserDefaults (@AppStorage)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `PortWatch/Services/AppSettings.swift` | **Create** | Singleton: `launchAtLogin` flag + SMAppService calls |
| `PortWatch/Views/SettingsView.swift` | **Create** | Settings NSPanel UI (toggle + future sections) |
| `PortWatch/MenuBar/MenuBarController.swift` | **Modify** | Wire gear icon → open settings panel |
| `PortWatch/Views/PortWatchPopoverView.swift` | **Modify** | Add gear icon button + `onOpenSettings` closure param |
| `PortWatch/ViewModels/PortWatchViewModel.swift` | **Modify** | Refresh interval 3s → 5s |
| `PortWatch/Views/PortRowView.swift` | **Modify** | Add green pulse circle before service name |
| `PortWatch.xcodeproj/project.pbxproj` | **Modify** | Register new Swift files in Xcode project |

---

## Task 1: Create `AppSettings` singleton

**Files:**
- Create: `PortWatch/Services/AppSettings.swift`

- [ ] **Step 1: Create the file**

```swift
import Foundation
import ServiceManagement

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false {
        didSet {
            guard oldValue != launchAtLogin else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    private init() {}

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[AppSettings] SMAppService error: \(error)")
            // Revert the stored value without re-triggering didSet
            UserDefaults.standard.set(!enabled, forKey: "launchAtLogin")
            objectWillChange.send()
        }
    }
}
```

- [ ] **Step 2: Register the file in `project.pbxproj`**

In `PortWatch.xcodeproj/project.pbxproj`, make three edits:

**2a. Add to `/* Begin PBXBuildFile section */`** (after the last entry `A10000000000000000000010`):
```
		A10000000000000000000011 /* AppSettings.swift in Sources */ = {isa = PBXBuildFile; fileRef = A20000000000000000000013 /* AppSettings.swift */; };
```

**2b. Add to `/* Begin PBXFileReference section */`** (after the last entry `A20000000000000000000012`):
```
		A20000000000000000000013 /* AppSettings.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppSettings.swift; sourceTree = "<group>"; };
```

**2c. Add to the Services group children** (`A40000000000000000000006 /* Services */`), insert before the closing `);`:
```
				A20000000000000000000013 /* AppSettings.swift */,
```

**2d. Add to `/* Begin PBXSourcesBuildPhase section */`** files list, insert before the closing `);`:
```
				A10000000000000000000011 /* AppSettings.swift in Sources */,
```

- [ ] **Step 3: Commit**

```bash
git add PortWatch/Services/AppSettings.swift PortWatch.xcodeproj/project.pbxproj
git commit -m "feat: add AppSettings singleton with launch-at-login via SMAppService"
```

---

## Task 2: Create `SettingsView`

**Files:**
- Create: `PortWatch/Views/SettingsView.swift`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .opacity(0.15)

            generalSection

            Spacer()

            footer
        }
        .frame(width: 340, height: 220)
        .background(Color(nsColor: NSColor(calibratedWhite: 0.12, alpha: 1.0)))
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("General")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            settingRow(
                icon: "power",
                title: "Launch at Login",
                description: "Start PortWatch automatically when you log in."
            ) {
                Toggle("", isOn: $settings.launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") {
                onClose()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func settingRow<Control: View>(
        icon: String,
        title: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.38))
            }

            Spacer()
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
```

- [ ] **Step 2: Register the file in `project.pbxproj`**

In `PortWatch.xcodeproj/project.pbxproj`, make three edits:

**2a. Add to `/* Begin PBXBuildFile section */`** (after `A10000000000000000000011`):
```
		A10000000000000000000012 /* SettingsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = A20000000000000000000014 /* SettingsView.swift */; };
```

**2b. Add to `/* Begin PBXFileReference section */`** (after `A20000000000000000000013`):
```
		A20000000000000000000014 /* SettingsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SettingsView.swift; sourceTree = "<group>"; };
```

**2c. Add to the Views group children** (`A40000000000000000000008 /* Views */`), insert before the closing `);`:
```
				A20000000000000000000014 /* SettingsView.swift */,
```

**2d. Add to `/* Begin PBXSourcesBuildPhase section */`** files list, insert before the closing `);`:
```
				A10000000000000000000012 /* SettingsView.swift in Sources */,
```

- [ ] **Step 3: Commit**

```bash
git add PortWatch/Views/SettingsView.swift PortWatch.xcodeproj/project.pbxproj
git commit -m "feat: add SettingsView panel UI with launch-at-login toggle"
```

---

## Task 3: Wire gear icon in `PortWatchPopoverView`

**Files:**
- Modify: `PortWatch/Views/PortWatchPopoverView.swift`

- [ ] **Step 1: Add `onOpenSettings` closure parameter to the struct**

Replace:
```swift
struct PortWatchPopoverView: View {
    @ObservedObject var viewModel: PortWatchViewModel
    @State private var appeared = false
```

With:
```swift
struct PortWatchPopoverView: View {
    @ObservedObject var viewModel: PortWatchViewModel
    let onOpenSettings: () -> Void
    @State private var appeared = false
```

- [ ] **Step 2: Add the gear icon button in the header `HStack`**

In the `header` computed property, locate the block that starts with `if viewModel.isRefreshing {` and ends with the refresh button. Replace it with:

```swift
if viewModel.isRefreshing {
    ProgressView()
        .controlSize(.small)
        .tint(.white.opacity(0.4))
        .padding(.trailing, 6)
        .transition(.opacity)
}

Button {
    onOpenSettings()
} label: {
    Image(systemName: "gearshape")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.45))
}
.buttonStyle(.plain)
.help("Settings")

Button {
    viewModel.refresh()
} label: {
    Image(systemName: "arrow.clockwise")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.45))
}
.buttonStyle(.plain)
.keyboardShortcut("r", modifiers: [.command])
.help("Refresh (⌘R)")
```

- [ ] **Step 3: Commit**

```bash
git add PortWatch/Views/PortWatchPopoverView.swift
git commit -m "feat: add gear icon to popover header for settings access"
```

---

## Task 4: Open settings panel from `MenuBarController`

**Files:**
- Modify: `PortWatch/MenuBar/MenuBarController.swift`

- [ ] **Step 1: Add settings panel property**

Add a private property after `private var panel: MenuBarPanel?`:
```swift
private var settingsPanel: NSPanel?
```

- [ ] **Step 2: Add `openSettings()` method**

Add this method to `MenuBarController` (after `setupDismissMonitors()`):

```swift
@objc func openSettings() {
    if let existing = settingsPanel, existing.isVisible {
        existing.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let settingsView = SettingsView {
        self.settingsPanel?.orderOut(nil)
        self.settingsPanel = nil
    }

    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 340, height: 220),
        styleMask: [.titled, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    panel.title = "Settings"
    panel.titlebarAppearsTransparent = true
    panel.isReleasedWhenClosed = false
    panel.center()
    panel.level = .floating
    panel.contentViewController = NSHostingController(rootView: settingsView)
    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    settingsPanel = panel
}
```

- [ ] **Step 3: Pass `onOpenSettings` closure when building the popover content**

In `setupPanel()`, replace:
```swift
let contentView = PortWatchPopoverView(viewModel: viewModel)
```

With:
```swift
let contentView = PortWatchPopoverView(viewModel: viewModel, onOpenSettings: { [weak self] in
    self?.openSettings()
})
```

- [ ] **Step 4: Add "Settings" item to the right-click context menu**

In `setupStatusItem()`, after the `Open PortWatch` menu item and before the separator, add:

```swift
let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
menu.addItem(settingsItem)
```

So the full menu setup becomes:
```swift
let menu = NSMenu()
menu.addItem(NSMenuItem(title: "Open PortWatch", action: #selector(openFromMenu), keyEquivalent: ""))
menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
menu.addItem(.separator())
menu.addItem(NSMenuItem(title: "Quit PortWatch", action: #selector(quitApp), keyEquivalent: "q"))
menu.items.forEach { $0.target = self }
statusMenu = menu
```

- [ ] **Step 5: Commit**

```bash
git add PortWatch/MenuBar/MenuBarController.swift
git commit -m "feat: wire settings panel from gear icon and right-click menu"
```

---

## Task 5: Change auto-refresh interval to 5s

**Files:**
- Modify: `PortWatch/ViewModels/PortWatchViewModel.swift`
- Modify: `PortWatch/Views/PortWatchPopoverView.swift`

- [ ] **Step 1: Update `refreshInterval` in `PortWatchViewModel.swift`**

Replace:
```swift
if isPanelVisible {
    return 3
}
```

With:
```swift
if isPanelVisible {
    return 5
}
```

- [ ] **Step 2: Update the footer label in `PortWatchPopoverView.swift`**

Replace:
```swift
Text("auto · 3s")
```

With:
```swift
Text("auto · 5s")
```

- [ ] **Step 3: Commit**

```bash
git add PortWatch/ViewModels/PortWatchViewModel.swift PortWatch/Views/PortWatchPopoverView.swift
git commit -m "chore: change auto-refresh interval from 3s to 5s"
```

---

## Task 6: Add green pulse circle to `PortRowView`

**Files:**
- Modify: `PortWatch/Views/PortRowView.swift`

- [ ] **Step 1: Add `@State` for pulse animation**

Add a state variable after `@State private var showNewFlash = false`:
```swift
@State private var isPulsing = false
```

- [ ] **Step 2: Add the green pulse circle before the service name**

In the leading `VStack`, the first `HStack` currently starts with `Text(service.primaryName)`. Replace that entire `HStack` with:

```swift
HStack(spacing: 6) {
    Circle()
        .fill(Color.green)
        .frame(width: 6, height: 6)
        .scaleEffect(isPulsing ? 1.35 : 1.0)
        .opacity(isPulsing ? 0.4 : 1.0)
        .animation(
            .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
            value: isPulsing
        )

    Text(service.primaryName)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .lineLimit(1)

    if let runtime = service.runtimeBadgeText {
        HStack(spacing: 4) {
            Image(systemName: service.runtimeSymbolName)
                .font(.system(size: 8, weight: .bold))

            Text(runtime)
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(.white.opacity(0.82))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }
}
```

- [ ] **Step 3: Start the pulse animation on appear**

In the `.onAppear` modifier, add the pulse trigger alongside the existing flash logic:

```swift
.onAppear {
    isPulsing = true
    if isNew {
        showNewFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showNewFlash = false
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add PortWatch/Views/PortRowView.swift
git commit -m "feat: add green pulse circle indicator to service rows"
```

---

## Self-Review Checklist

- [x] `AppSettings` singleton covers "Launch at Login" with SMAppService ✓
- [x] `SettingsView` panel with toggle + extensible `settingRow` helper ✓
- [x] Gear icon in popover header + Settings in right-click menu ✓
- [x] `openSettings()` prevents duplicate panels (checks `isVisible`) ✓
- [x] Refresh interval 3s → 5s in ViewModel + footer label ✓
- [x] Green pulse circle with `repeatForever` animation in PortRowView ✓
- [x] All new files registered in `project.pbxproj` with correct IDs ✓
- [x] `onOpenSettings` closure keeps panel management in `MenuBarController` ✓
- [x] Deployment target is macOS 13.0 — `SMAppService` available ✓
