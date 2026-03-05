import Foundation

/// Stores and retrieves user layout preferences, learning from corrections
class PreferenceStore {
    
    static let shared = PreferenceStore()
    
    private var preferences: [UserPreference] = []
    private let storageURL: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SmartTile")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("preferences.json")
        load()
    }
    
    // MARK: - Matching
    
    /// Find a saved preference that matches the current window combination
    func findMatch(for windows: [WindowInfo]) -> UserPreference? {
        let currentCategories = windows.map { $0.category.rawValue }.sorted()
        let currentBundles = windows.map { $0.bundleID }.sorted()
        
        // First try exact bundle ID match
        if let exact = preferences.first(where: {
            $0.appCombination.sorted() == currentBundles && $0.useCount >= 1
        }) {
            return exact
        }
        
        // Then try category match (more flexible)
        if let categoryMatch = preferences
            .filter({ $0.categoryCombo.sorted() == currentCategories && $0.useCount >= 2 })
            .sorted(by: { $0.useCount > $1.useCount })
            .first {
            return categoryMatch
        }
        
        return nil
    }
    
    // MARK: - Learning
    
    /// Save a layout as user preference (called after manual correction)
    func savePreference(windows: [WindowInfo], layout: [WindowPlacement]) {
        let bundles = windows.map { $0.bundleID }.sorted()
        let categories = windows.map { $0.category.rawValue }.sorted()
        let id = bundles.joined(separator: "+").hashValue.description
        
        // Update existing or create new
        if let index = preferences.firstIndex(where: { $0.id == id }) {
            preferences[index] = UserPreference(
                id: id,
                appCombination: bundles,
                categoryCombo: categories,
                layout: layout,
                timestamp: Date(),
                useCount: preferences[index].useCount + 1
            )
        } else {
            preferences.append(UserPreference(
                id: id,
                appCombination: bundles,
                categoryCombo: categories,
                layout: layout,
                timestamp: Date(),
                useCount: 1
            ))
        }
        
        save()
        print("💾 Saved layout preference for: \(categories.joined(separator: " + "))")
    }
    
    /// Record that a saved preference was used
    func incrementUseCount(for id: String) {
        if let index = preferences.firstIndex(where: { $0.id == id }) {
            preferences[index].useCount += 1
            save()
        }
    }
    
    /// Get recent preferences for LLM context
    func getRecentPreferences(limit: Int) -> [UserPreference] {
        return Array(preferences
            .sorted(by: { $0.timestamp > $1.timestamp })
            .prefix(limit))
    }
    
    /// Clear all preferences
    func clearAll() {
        preferences = []
        save()
    }
    
    /// Get number of saved preferences
    var count: Int { preferences.count }
    
    // MARK: - Persistence
    
    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(preferences) {
            try? data.write(to: storageURL)
        }
    }
    
    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: storageURL),
           let loaded = try? decoder.decode([UserPreference].self, from: data) {
            preferences = loaded
            print("📂 Loaded \(preferences.count) layout preferences")
        }
    }
}
