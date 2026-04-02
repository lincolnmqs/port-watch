import SwiftUI

@main
struct PortWatchApp: App {
    @StateObject private var menuBarController = MenuBarController()

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
