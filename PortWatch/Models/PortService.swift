import Foundation

struct PortService: Identifiable, Hashable {
    let processName: String
    let pid: Int
    let protocolName: String
    let port: Int
    let rawAddress: String
    let host: String
    let startTime: Date?
    let executablePath: String?
    let workingDirectory: String?
    let commandLine: [String]
    let projectName: String?
    let projectDirectory: String?
    let detectedName: String?
    let alias: String?

    var id: String {
        "\(pid)-\(protocolName)-\(port)-\(processName)"
    }

    var primaryName: String {
        if let alias, !alias.isEmpty { return alias }
        if let projectName, !projectName.isEmpty { return projectName }
        return processName
    }

    var secondaryName: String {
        let normalizedProcess = processName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedRuntime = detectedName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPrimary = primaryName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalizedProcess.isEmpty || normalizedProcess == normalizedPrimary || normalizedProcess == normalizedRuntime {
            return "PID \(pid)"
        }

        return "\(processName) · PID \(pid)"
    }

    var projectDisplayName: String {
        projectName ?? "Ungrouped"
    }

    var commandSummary: String? {
        guard !commandLine.isEmpty else { return nil }
        return commandLine.joined(separator: " ")
    }

    var localhostURLString: String {
        "http://localhost:\(port)"
    }

    var runtimeBadgeText: String? {
        detectedName
    }

    var runtimeSymbolName: String {
        let value = (detectedName ?? processName).lowercased()

        if value.contains("vite") { return "bolt.fill" }
        if value.contains("next") || value.contains("react") || value.contains("webpack") || value.contains("angular") { return "globe" }
        if value.contains("node") || value.contains("nest") || value.contains("express") || value.contains("fastify") { return "server.rack" }
        if value.contains("python") || value.contains("django") || value.contains("flask") || value.contains("fastapi") { return "chevron.left.forwardslash.chevron.right" }
        if value.contains("java") || value.contains("spring") { return "cup.and.saucer.fill" }
        if value.contains("c#") || value.contains(".net") || value.contains("dotnet") { return "number.square.fill" }
        if value.contains("postgres") || value.contains("mysql") || value.contains("maria") || value.contains("mongo") { return "cylinder.fill" }
        if value.contains("redis") { return "shippingbox.fill" }
        if value.contains("docker") { return "shippingbox.circle.fill" }
        return "terminal.fill"
    }

    var canOpenInBrowser: Bool {
        protocolName.uppercased() == "TCP" && isBrowserReachableHost
    }

    var isBrowserReachableHost: Bool {
        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        return normalizedHost == "*" || normalizedHost == "127.0.0.1" || normalizedHost == "::1" || normalizedHost == "localhost"
    }

    var uptimeString: String? {
        guard let startTime else { return nil }
        let elapsed = Date().timeIntervalSince(startTime)
        switch elapsed {
        case ..<60: return "<1m"
        case ..<3600: return "\(Int(elapsed / 60))m"
        case ..<86400: return "\(Int(elapsed / 3600))h"
        default: return "\(Int(elapsed / 86400))d"
        }
    }
}
