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
        menu.addItem(withTitle: "Save Current Layout", action: #selector(menuSaveLayout), keyEquivalent: "")
        menu.addItem(.separator())

        let quickLayout = NSMenu()
        quickLayout.addItem(withTitle: "2 columns", action: #selector(menuGrid2), keyEquivalent: "")
        quickLayout.addItem(withTitle: "3 columns", action: #selector(menuGrid3), keyEquivalent: "")
        quickLayout.addItem(withTitle: "4 columns", action: #selector(menuGrid4), keyEquivalent: "")
        quickLayout.addItem(.separator())
        quickLayout.addItem(withTitle: "Left 2/3 + Right 1/3", action: #selector(menuSplit67), keyEquivalent: "")
        quickLayout.addItem(withTitle: "Left 1/3 + Right 2/3", action: #selector(menuSplit33), keyEquivalent: "")
        quickLayout.addItem(withTitle: "Left 1/2 + Right 1/2", action: #selector(menuSplit50), keyEquivalent: "")

        let quickItem = NSMenuItem(title: "Quick Layout", action: nil, keyEquivalent: "")
        quickItem.submenu = quickLayout
        menu.addItem(quickItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings...", action: #selector(menuShowSettings), keyEquivalent: "")
        menu.addItem(withTitle: "Quit SmartTile", action: #selector(menuQuit), keyEquivalent: "q")

        for item in menu.items where item.action != nil {
            item.target = self
        }
        for item in quickLayout.items where item.action != nil {
            item.target = self
        }

        statusItem?.menu = menu
    }

    @objc private func menuSmartArrange() { performAutoArrange() }
    @objc private func menuGridTile() { OverlayWindowController.shared.showForFrontWindow() }
    @objc private func menuSaveLayout() { saveCurrentLayout() }
    @objc private func menuGrid2() { quickGrid(columns: 2) }
    @objc private func menuGrid3() { quickGrid(columns: 3) }
    @objc private func menuGrid4() { quickGrid(columns: 4) }
    @objc private func menuSplit67() { quickSplit(mainRatio: 0.667) }
    @objc private func menuSplit33() { quickSplit(mainRatio: 0.333) }
    @objc private func menuSplit50() { quickSplit(mainRatio: 0.5) }
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
        hk.register(action: .save, combo: hk.combo(for: .save)) { [weak self] in
            self?.saveCurrentLayout()
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
                let reasoning = proposal.reasoning ?? "Layout applied"
                appState.lastResult = reasoning
                ToastController.shared.show("\(windows.count) windows: \(reasoning)", icon: "checkmark.circle.fill")
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

        PreferenceStore.shared.savePreference(windows: windows, layout: placements)
        appState.lastResult = "Layout saved for \(windows.count) windows"
        ToastController.shared.show("Layout saved for \(windows.count) windows", icon: "checkmark.circle.fill")
    }

    func quickGrid(columns: Int) {
        let windows = WindowManager.shared.getVisibleWindows()
        let screen = ScreenInfo.current()
        let layout = LayoutEngine.shared.gridLayout(
            windows: windows, screen: screen,
            columns: columns, gap: appState.settings.gapBetweenWindows
        )
        WindowManager.shared.applyLayout(layout.windows, windows: windows)
        appState.lastResult = "Grid: \(columns) columns"
    }

    func quickSplit(mainRatio: Double) {
        let windows = WindowManager.shared.getVisibleWindows()
        guard windows.count >= 2 else {
            quickGrid(columns: 1)
            return
        }

        let screen = ScreenInfo.current()
        let gap = appState.settings.gapBetweenWindows

        let mainWidth = (screen.usableWidth - gap * 3) * mainRatio
        let sideWidth = screen.usableWidth - mainWidth - gap * 3
        let sideHeight = (screen.usableHeight - gap * Double(windows.count)) / Double(windows.count - 1)

        var placements: [WindowPlacement] = []

        placements.append(WindowPlacement(
            windowID: windows[0].id,
            frame: WindowFrame(
                x: screen.usableOriginX + gap,
                y: screen.usableOriginY + gap,
                width: mainWidth,
                height: screen.usableHeight - gap * 2
            )
        ))

        for (i, window) in windows.dropFirst().enumerated() {
            placements.append(WindowPlacement(
                windowID: window.id,
                frame: WindowFrame(
                    x: screen.usableOriginX + mainWidth + gap * 2,
                    y: screen.usableOriginY + gap + Double(i) * (sideHeight + gap),
                    width: sideWidth,
                    height: sideHeight - gap
                )
            ))
        }

        WindowManager.shared.applyLayout(placements, windows: windows)
        appState.lastResult = "Split: \(Int(mainRatio * 100))% / \(Int((1 - mainRatio) * 100))%"
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
            ),
            preferenceCount: PreferenceStore.shared.count,
            onClearPreferences: {
                PreferenceStore.shared.clearAll()
            }
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
