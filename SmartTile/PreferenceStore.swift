import Foundation

/// Stores layout templates learned from user behavior.
/// Templates are abstract (relative slots keyed by window count), not tied to specific apps.
class PreferenceStore {

    static let shared = PreferenceStore()

    private(set) var templates: [PreferenceAnalyzer.LayoutTemplate] = []
    private let storageURL: URL

    // Auto-learn state (not persisted)
    private var lastAppliedLayout: [WindowPlacement]?
    private var lastAppliedWindows: [WindowInfo]?
    private var autoLearnTimer: Timer?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SmartTile")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("templates.json")
        load()
    }

    // MARK: - Template Matching

    /// Find the best template for the given number of windows and current screen.
    func bestTemplate(for windowCount: Int, screen: ScreenInfo? = nil) -> PreferenceAnalyzer.LayoutTemplate? {
        PreferenceAnalyzer.bestTemplate(for: windowCount, from: templates, screen: screen)
    }

    // MARK: - Learning

    /// Save a layout as a template (extracts abstract slots from concrete positions).
    func learnLayout(windows: [WindowInfo], layout: [WindowPlacement], screen: ScreenInfo) {
        // Map each placement to its category
        let categories: [WindowCategory] = layout.map { placement in
            if let window = windows.first(where: { $0.id == placement.windowID }) {
                return window.category
            }
            return .other
        }

        let newTemplate = PreferenceAnalyzer.extractTemplate(from: layout, categories: categories, screen: screen)

        // Check if we already have a similar template — merge category stats
        if let existingIdx = templates.firstIndex(where: {
            PreferenceAnalyzer.areSimilar($0, newTemplate)
        }) {
            PreferenceAnalyzer.mergeCategories(existing: &templates[existingIdx], new: newTemplate)
        } else {
            templates.append(newTemplate)
        }

        save()
        NSLog("SmartTile: Learned template for %d windows (total: %d templates)", windows.count, templates.count)
    }

    // MARK: - Auto-Learn

    /// Start observing for user corrections after Smart Arrange.
    func startAutoLearn(appliedLayout: [WindowPlacement], windows: [WindowInfo]) {
        lastAppliedLayout = appliedLayout
        lastAppliedWindows = windows
        stopAutoLearn()

        var stableCount = 0
        var lastPositions: [WindowFrame]?

        // Poll every 5 seconds for up to 2 minutes
        autoLearnTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
            guard let self, let originalLayout = self.lastAppliedLayout,
                  let originalWindows = self.lastAppliedWindows else {
                timer.invalidate()
                return
            }

            let currentWindows = WindowManager.shared.getVisibleWindows()
            let currentPositions = currentWindows.map(\.frame)

            // Check if positions are stable (same as last poll)
            if let last = lastPositions, Self.framesEqual(currentPositions, last, tolerance: 10) {
                stableCount += 1
            } else {
                stableCount = 0
            }
            lastPositions = currentPositions

            // Stable for 2 consecutive polls (10 seconds) — user is done adjusting
            if stableCount >= 2 {
                timer.invalidate()

                // Did the user actually change anything?
                let originalFrames = originalLayout.map(\.frame)
                let changed = !Self.framesEqual(originalFrames, currentPositions, tolerance: 20)

                if changed {
                    // User corrected the layout — learn from it
                    let correctedPlacements = currentWindows.map {
                        WindowPlacement(windowID: $0.id, frame: $0.frame)
                    }
                    let screen = ScreenInfo.current()
                    self.learnLayout(windows: currentWindows, layout: correctedPlacements, screen: screen)
                    DispatchQueue.main.async {
                        ToastController.shared.show("Layout learned", icon: "brain.head.profile", duration: 2)
                    }
                } else {
                    // User accepted our layout — also learn it as positive reinforcement
                    let screen = ScreenInfo.current()
                    self.learnLayout(windows: originalWindows, layout: originalLayout, screen: screen)
                }

                self.lastAppliedLayout = nil
                self.lastAppliedWindows = nil
            }
        }
    }

    /// Stop auto-learn polling (e.g., when user triggers another Smart Arrange).
    func stopAutoLearn() {
        autoLearnTimer?.invalidate()
        autoLearnTimer = nil
    }

    // MARK: - Helpers

    /// Compare two frame arrays with tolerance.
    private static func framesEqual(_ a: [WindowFrame], _ b: [WindowFrame], tolerance: Double) -> Bool {
        guard a.count == b.count else { return false }
        let sortedA = a.sorted { $0.x + $0.y * 10000 < $1.x + $1.y * 10000 }
        let sortedB = b.sorted { $0.x + $0.y * 10000 < $1.x + $1.y * 10000 }
        for (fa, fb) in zip(sortedA, sortedB) {
            if abs(fa.x - fb.x) > tolerance || abs(fa.y - fb.y) > tolerance ||
               abs(fa.width - fb.width) > tolerance || abs(fa.height - fb.height) > tolerance {
                return false
            }
        }
        return true
    }

    /// Clear all templates
    func clearAll() {
        templates = []
        save()
    }

    var count: Int { templates.count }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(templates) {
            try? data.write(to: storageURL)
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: storageURL),
           let loaded = try? JSONDecoder().decode([PreferenceAnalyzer.LayoutTemplate].self, from: data) {
            templates = loaded
            NSLog("SmartTile: Loaded %d layout templates", templates.count)
        }
    }
}
