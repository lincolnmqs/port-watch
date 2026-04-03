import AppKit
import Combine
import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class PortWatchViewModel: ObservableObject {
    private struct ProjectGroupKey: Hashable {
        let name: String
        let directory: String?
    }

    struct ProjectSection: Identifiable {
        let name: String
        let directory: String?
        let services: [PortService]

        var id: String {
            [name, directory ?? "unknown"].joined(separator: "::")
        }

        var subtitle: String {
            return "\(services.count) service\(services.count == 1 ? "" : "s")"
        }
    }

    @Published private(set) var services: [PortService] = []
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var newServiceIDs: Set<String> = []
    @Published private(set) var recentlyStopped: PortService?
    @Published private(set) var recentSnapshots: [SessionSnapshot] = []

    private let scanner: PortScanner
    private let aliasStore: AliasStore
    private let snapshotStore: SnapshotStore
    private var refreshTimer: Timer?
    private var powerStateObserver: NSObjectProtocol?
    private var infoPanel: NSPanel?
    private var isFirstLoad = true
    private var isPanelVisible = false

    private var refreshInterval: TimeInterval {
        if isPanelVisible {
            return 5
        }

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return 45
        }

        return 20
    }

    var visibleServices: [PortService] {
        services.filter { ProjectDetector.isUserProjectDirectory($0.projectDirectory) }
    }

    var filteredServices: [PortService] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return visibleServices }

        return visibleServices.filter { service in
            let haystacks = [
                service.primaryName,
                service.processName,
                service.projectName ?? "",
                service.projectDirectory ?? "",
                service.commandSummary ?? "",
                String(service.port)
            ]

            return haystacks.contains { $0.lowercased().contains(query) }
        }
    }

    var projectSections: [ProjectSection] {
        let grouped = Dictionary(grouping: filteredServices) { service in
            ProjectGroupKey(
                name: service.projectDisplayName,
                directory: service.projectDirectory
            )
        }

        return grouped
            .map { key, services in
                ProjectSection(
                    name: key.name,
                    directory: key.directory,
                    services: services.sorted {
                        $0.port < $1.port
                    }
                )
            }
            .sorted { lhs, rhs in
                if lhs.name == "Ungrouped" { return false }
                if rhs.name == "Ungrouped" { return true }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    init(
        scanner: PortScanner,
        aliasStore: AliasStore = .shared,
        snapshotStore: SnapshotStore = SnapshotStore()
    ) {
        self.scanner = scanner
        self.aliasStore = aliasStore
        self.snapshotStore = snapshotStore
        self.recentSnapshots = snapshotStore.loadRecent()
        observePowerState()
        requestNotificationPermission()
        startAutoRefresh()
        refresh()
    }

    deinit {
        refreshTimer?.invalidate()
        if let powerStateObserver {
            NotificationCenter.default.removeObserver(powerStateObserver)
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil

        Task.detached(priority: .userInitiated) { [scanner] in
            do {
                let newServices = try scanner.scanOpenPorts()
                await MainActor.run {
                    self.handleRefreshResult(newServices: newServices)
                    self.isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    self.services = []
                    self.errorMessage = error.localizedDescription
                    self.isRefreshing = false
                }
            }
        }
    }

    func setPanelVisible(_ visible: Bool) {
        guard isPanelVisible != visible else { return }
        isPanelVisible = visible
        startAutoRefresh()

        if visible {
            refresh()
        }
    }

    private func handleRefreshResult(newServices: [PortService]) {
        let previousIDs = Set(services.map(\.id))
        let currentIDs = Set(newServices.map(\.id))

        let appearedIDs = currentIDs.subtracting(previousIDs)
        let disappearedIDs = previousIDs.subtracting(currentIDs)

        if !isFirstLoad {
            let previousByPort = Dictionary(uniqueKeysWithValues: services.map { ($0.port, $0) })

            for id in appearedIDs {
                if let s = newServices.first(where: { $0.id == id }) {
                    sendNotification(
                        title: "New service on :\(s.port)",
                        body: "\(s.primaryName) is now listening"
                    )
                }
            }

            for service in newServices {
                guard let previous = previousByPort[service.port], previous.id != service.id else { continue }
                sendNotification(
                    title: "Port conflict on :\(service.port)",
                    body: "\(service.primaryName) replaced \(previous.primaryName)"
                )
            }

            if let stopped = services.first(where: { disappearedIDs.contains($0.id) }) {
                sendNotification(
                    title: "Service stopped",
                    body: "\(stopped.primaryName) on :\(stopped.port) is no longer listening"
                )
                recentlyStopped = stopped
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if self.recentlyStopped?.id == stopped.id {
                        self.recentlyStopped = nil
                    }
                }
            }
        }

        services = newServices
        lastUpdated = Date()

        if !appearedIDs.isEmpty {
            newServiceIDs = appearedIDs
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.newServiceIDs = []
            }
        }

        isFirstLoad = false
    }

    func openInBrowser(_ service: PortService) {
        guard service.canOpenInBrowser,
              let url = URL(string: service.localhostURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    func killProcess(_ service: PortService) {
        sendKill(signal: "-TERM", service: service)
    }

    func forceKillProcess(_ service: PortService) {
        sendKill(signal: "-KILL", service: service)
    }

    func copyURL(_ service: PortService) {
        copyToPasteboard(service.localhostURLString)
    }

    func copyPort(_ service: PortService) {
        copyToPasteboard(String(service.port))
    }

    func revealProcess(_ service: PortService) {
        guard let executablePath = service.executablePath else {
            errorMessage = "Unable to reveal process binary for PID \(service.pid)."
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: executablePath)])
    }

    func showCommand(_ service: PortService) {
        guard let command = service.commandSummary else {
            errorMessage = "PortWatch could not read the launch command for PID \(service.pid)."
            return
        }

        let alert = NSAlert()
        alert.messageText = service.primaryName
        alert.informativeText = command
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "Close")

        if alert.runModal() == .alertFirstButtonReturn {
            copyToPasteboard(command)
        }
    }

    func showInfo(_ service: PortService) {
        let lines = [
            "Port: \(service.port)",
            "PID: \(service.pid)",
            "Process: \(service.processName)",
            "Runtime: \(service.runtimeBadgeText ?? "Unknown")",
            "Project: \(service.projectName ?? "-")",
            "Directory: \(service.projectDirectory ?? "-")",
            "Command: \(service.commandSummary ?? "-")"
        ]

        showInfoPanel(
            title: service.primaryName,
            body: lines.joined(separator: "\n"),
            command: service.commandSummary
        )
    }

    func renameAlias(_ service: PortService) {
        let alert = NSAlert()
        alert.messageText = "Alias for :\(service.port)"
        alert.informativeText = "Use a short label like Frontend, API, or Database."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: service.alias ?? service.detectedName ?? "")
        field.placeholderString = service.primaryName
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            aliasStore.set(field.stringValue, for: service.port)
            refresh()
        case .alertSecondButtonReturn:
            aliasStore.remove(for: service.port)
            refresh()
        default:
            break
        }
    }

    func saveSnapshot() {
        do {
            _ = try snapshotStore.saveSnapshot(services: visibleServices)
            recentSnapshots = snapshotStore.loadRecent()
            sendNotification(
                title: "Session snapshot saved",
                body: "\(visibleServices.count) service\(visibleServices.count == 1 ? "" : "s") captured"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendKill(signal: String, service: PortService) {
        let process = Process()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = [signal, String(service.pid)]
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                refresh()
                return
            }

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            errorMessage = message?.isEmpty == false ? message : "Failed to terminate PID \(service.pid)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func observePowerState() {
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("NSProcessInfoPowerStateDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.startAutoRefresh()
            }
        }
    }

    private func showInfoPanel(title: String, body: String, command: String?) {
        infoPanel?.close()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 292),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = title
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.level = .floating

        let rootView = ServiceInfoView(
            title: title,
            bodyText: body,
            hasCommand: command != nil,
            onCopyCommand: { [weak self] in
                guard let self, let command else { return }
                self.copyToPasteboard(command)
            },
            onClose: { [weak panel] in
                panel?.close()
            }
        )

        let hostingController = NSHostingController(rootView: rootView)
        panel.contentViewController = hostingController
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        infoPanel = panel
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.interruptionLevel = .passive
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

private struct ServiceInfoView: View {
    let title: String
    let bodyText: String
    let hasCommand: Bool
    let onCopyCommand: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)

            ScrollView {
                Text(bodyText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }

            HStack {
                Spacer()

                if hasCommand {
                    Button("Copy Command", action: onCopyCommand)
                }

                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 292)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
