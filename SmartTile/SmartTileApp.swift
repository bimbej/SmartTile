import AppKit
import Carbon.HIToolbox
import UserNotifications
import SwiftUI

// MARK: - Pure AppKit entry point (no SwiftUI App / MenuBarExtra / NSHostingView in menu bar)

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // LSUIElement-like: no dock icon
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    let appState = AppState()
    private var accessibilityTimer: Timer?
    private var appLaunchObserver: NSObjectProtocol?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarMenu()

        if WindowManager.hasAccessibilityPermission() {
            appState.hasAccessibility = true
            registerGlobalShortcuts()
            startAppLaunchObserver()
        } else {
            showAccessibilityOnboarding()
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Status Bar Menu

    private func setupStatusBarMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "uiwindow.split.2x1", accessibilityDescription: "SmartTile")
        }

        let menu = NSMenu()

        menu.addItem(withTitle: "Smart Arrange", action: #selector(menuSmartArrange), keyEquivalent: "")
        menu.addItem(withTitle: "Grid Tile Window", action: #selector(menuGridTile), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings...", action: #selector(menuShowSettings), keyEquivalent: "")
        menu.addItem(withTitle: "Quit SmartTile", action: #selector(menuQuit), keyEquivalent: "q")

        for item in menu.items where item.action != nil {
            item.target = self
        }

        statusItem?.menu = menu
    }

    @objc private func menuSmartArrange() { performAutoArrange() }
    @objc private func menuGridTile() { OverlayWindowController.shared.showForFrontWindow() }
    @objc private func menuShowSettings() { showSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - Accessibility

    private func startAccessibilityPolling() {
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if WindowManager.hasAccessibilityPermission() {
                timer.invalidate()
                self.accessibilityTimer = nil
                self.appState.hasAccessibility = true
                self.registerGlobalShortcuts()
                self.startAppLaunchObserver()
                ToastController.shared.show("Accessibility granted — ready!", icon: "checkmark.circle.fill")
            }
        }
    }

    private func showAccessibilityOnboarding() {
        WindowManager.requestAccessibilityPermission()
        appState.lastResult = "Waiting for Accessibility permission..."
        startAccessibilityPolling()
    }

    // MARK: - Auto-Arrange on App Launch

    private func startAppLaunchObserver() {
        appLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, self.appState.settings.autoArrangeOnLaunch else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.performAutoArrange()
            }
        }
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func registerGlobalShortcuts() {
        let hk = HotkeyManager.shared
        hk.register(action: .arrange, combo: hk.combo(for: .arrange)) { [weak self] in
            self?.performAutoArrange()
        }
        hk.register(action: .grid, combo: hk.combo(for: .grid)) {
            OverlayWindowController.shared.showForFrontWindow()
        }
    }

    func performAutoArrange() {
        guard appState.hasAccessibility else {
            appState.lastResult = "Grant Accessibility permission first"
            ToastController.shared.show("No Accessibility permission", icon: "lock.fill")
            return
        }
        guard !appState.isArranging else { return }

        Task { @MainActor in
            appState.isArranging = true
            appState.lastResult = "Analyzing windows..."

            let windows = WindowManager.shared.getVisibleWindows()
            appState.windowCount = windows.count

            guard !windows.isEmpty else {
                appState.lastResult = "No windows found"
                ToastController.shared.show("No windows found", icon: "rectangle.on.rectangle.slash")
                appState.isArranging = false
                return
            }

            let screen = ScreenInfo.current()

            do {
                let proposal = try await LayoutEngine.shared.suggestLayout(
                    windows: windows,
                    screen: screen,
                    settings: appState.settings
                )

                WindowManager.shared.applyLayout(proposal.windows, windows: windows)
                appState.lastResult = proposal.reasoning ?? "Layout applied"
                // Show concise toast — don't show AI reasoning (often inaccurate)
                let source: String
                if proposal.reasoning?.contains("Learned") == true {
                    source = "from learned preferences"
                } else if proposal.reasoning?.contains("Grid") == true {
                    source = "grid layout"
                } else {
                    source = "arranged by AI"
                }
                ToastController.shared.show("\(windows.count) windows \(source)", icon: "checkmark.circle.fill")
            } catch {
                ToastController.shared.show("Error: \(error.localizedDescription)", icon: "exclamationmark.triangle.fill")
                let cols = windows.count <= 3 ? windows.count : 3
                let grid = LayoutEngine.shared.gridLayout(
                    windows: windows, screen: screen,
                    columns: cols, gap: appState.settings.gapBetweenWindows
                )
                WindowManager.shared.applyLayout(grid.windows, windows: windows)
                appState.lastResult = "Grid fallback: \(error.localizedDescription)"
            }

            appState.isArranging = false
        }
    }

    func saveCurrentLayout() {
        guard appState.hasAccessibility else {
            appState.lastResult = "Grant Accessibility permission first"
            ToastController.shared.show("No Accessibility permission", icon: "lock.fill")
            return
        }
        let windows = WindowManager.shared.getVisibleWindows()
        guard !windows.isEmpty else { return }

        let placements = windows.map { w in
            WindowPlacement(windowID: w.id, frame: w.frame)
        }

        let screen = ScreenInfo.current()
        PreferenceStore.shared.learnLayout(windows: windows, layout: placements, screen: screen)
        appState.lastResult = "Layout saved for \(windows.count) windows"
        ToastController.shared.show("Layout saved for \(windows.count) windows", icon: "checkmark.circle.fill")
    }

    func showSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            settings: Binding(
                get: { [weak self] in self?.appState.settings ?? .defaultSettings },
                set: { [weak self] newValue in
                    self?.appState.settings = newValue
                    newValue.save()
                }
            )
        )

        let hostingView = NSHostingView(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "SmartTile Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    func showNotification(title: String, body: String) {
        appState.lastResult = "\(title): \(body)"

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - App State

class AppState {
    var settings: AppSettings
    var isArranging = false
    var lastResult: String = ""
    var windowCount: Int = 0
    var hasAccessibility = false

    init() {
        self.settings = AppSettings.load()
        self.hasAccessibility = WindowManager.hasAccessibilityPermission()
    }
}
