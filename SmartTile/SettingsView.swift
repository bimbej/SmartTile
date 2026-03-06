import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Binding var settings: AppSettings
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    @State private var arrangeCombo: HotkeyManager.KeyCombo
    @State private var gridCombo: HotkeyManager.KeyCombo

    init(settings: Binding<AppSettings>) {
        self._settings = settings
        self._arrangeCombo = State(initialValue: HotkeyManager.shared.combo(for: .arrange))
        self._gridCombo = State(initialValue: HotkeyManager.shared.combo(for: .grid))
    }

    @State private var selectedTab = 0
    @State private var modelStatus: String = ""
    @State private var isDownloadingModel = false
    @State private var downloadProgress: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 2) {
                tabButton(title: "General", icon: "gear", index: 0)
                tabButton(title: "AI Model", icon: "cpu", index: 2)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Divider()
                .padding(.top, 8)

            // Content
            ScrollView {
                switch selectedTab {
                case 0: generalContent
                case 2: modelContent
                default: generalContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 480, height: 440)
    }

    // MARK: - Tab Button

    private func tabButton(title: String, icon: String, index: Int) -> some View {
        Button {
            selectedTab = index
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedTab == index ? Color.accentColor : .secondary)
        .background(selectedTab == index ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - General

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsSection("Window Gaps") {
                HStack {
                    Text("Gap between windows")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Slider(value: $settings.gapBetweenWindows, in: 0...24, step: 2)
                        .frame(width: 140)
                    Text("\(Int(settings.gapBetweenWindows))px")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
            }

            settingsSection("Keyboard Shortcuts") {
                VStack(spacing: 8) {
                    shortcutRow("Smart Arrange", action: .arrange, combo: $arrangeCombo)
                    shortcutRow("Grid Tile Window", action: .grid, combo: $gridCombo)
                }
                Text("Click a shortcut, then press your desired key combination")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            settingsSection("Startup") {
                Toggle("Launch SmartTile at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue // revert on failure
                        }
                    }
            }

            settingsSection("About") {
                HStack {
                    Text("SmartTile")
                        .fontWeight(.semibold)
                    Text("v0.1.0")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text("AI-powered window manager for ultrawide monitors")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                HStack {
                    Text("Bim-IT Micha\u{0142} Zieli\u{0144}ski")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Link("bim-it.pl", destination: URL(string: "https://www.bim-it.pl")!)
                        .font(.caption)
                }
            }
        }
        .padding(20)
    }

    // MARK: - AI Model

    private var modelContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsSection("llama.cpp") {
                let hasLlama = LocalModelManager.shared.findLlamaCli() != nil
                HStack(spacing: 12) {
                    Image(systemName: hasLlama ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(hasLlama ? .green : .red)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasLlama ? "llama-cli installed" : "llama-cli not found")
                            .fontWeight(.semibold)
                        if !hasLlama {
                            Text("Run in Terminal: brew install llama.cpp")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            settingsSection("AI Model") {
                let hasModel = LocalModelManager.shared.hasModel
                HStack(spacing: 12) {
                    Image(systemName: hasModel ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundStyle(hasModel ? .green : .orange)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasModel ? "Qwen 2.5 1.5B ready" : "Qwen 2.5 1.5B — not downloaded")
                            .fontWeight(.semibold)
                        Text(hasModel ? "Local AI model for smart window layouts" : "~1 GB download, runs locally on your Mac")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !hasModel {
                        if isDownloadingModel {
                            VStack(spacing: 4) {
                                ProgressView(value: downloadProgress)
                                    .frame(width: 80)
                                Text("\(Int(downloadProgress * 100))%")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Button("Download") {
                                startModelDownload()
                            }
                        }
                    }
                }

                if !modelStatus.isEmpty {
                    Text(modelStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            settingsSection("How it works") {
                VStack(alignment: .leading, spacing: 8) {
                    stepRow(number: 1, text: "Install llama.cpp (brew install llama.cpp)")
                    stepRow(number: 2, text: "Download AI model (~1 GB, one time)")
                    stepRow(number: 3, text: "Smart Arrange uses AI to find optimal layout")
                    stepRow(number: 4, text: "Everything runs locally — no internet needed")
                }
            }

        }
        .padding(20)
    }

    private func startModelDownload() {
        isDownloadingModel = true
        downloadProgress = 0
        modelStatus = "Downloading..."

        LocalModelManager.shared.downloadModel(
            onProgress: { progress in
                DispatchQueue.main.async {
                    self.downloadProgress = progress
                }
            },
            onComplete: { result in
                DispatchQueue.main.async {
                    self.isDownloadingModel = false
                    switch result {
                    case .success:
                        self.modelStatus = "Download complete!"
                        ToastController.shared.show("AI model ready!", icon: "checkmark.circle.fill")
                    case .failure(let error):
                        self.modelStatus = "Download failed: \(error.localizedDescription)"
                        ToastController.shared.show("Model download failed", icon: "exclamationmark.triangle.fill")
                    }
                }
            }
        )
    }

    // MARK: - Components

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.callout)
        }
    }

    private func shortcutRow(_ label: String, action: HotkeyManager.HotkeyAction, combo: Binding<HotkeyManager.KeyCombo>) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            KeyRecorderView(action: action, combo: combo)
        }
    }
}
