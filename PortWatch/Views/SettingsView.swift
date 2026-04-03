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
