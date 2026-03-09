import Foundation

/// Learns layout PATTERNS from user behavior — not per-app positions, but abstract templates.
/// A template is a set of relative slots (x%, y%, w%, h%) keyed by window count.
/// Each slot tracks which categories have been placed there, enabling smart assignment.
class PreferenceAnalyzer {

    /// A slot in a layout template (relative to screen)
    struct Slot: Codable {
        let x: Double    // 0.0–1.0 fraction of usable width
        let y: Double    // 0.0–1.0 fraction of usable height
        let width: Double
        let height: Double
        /// Tracks how many times each category was placed in this slot.
        /// e.g. ["terminal": 3, "editor": 1] means terminal was here 3 times.
        var categoryCounts: [String: Int]
    }

    /// A layout template: abstract arrangement for N windows
    struct LayoutTemplate: Codable {
        let windowCount: Int
        let slots: [Slot]       // order preserved from first save
        var useCount: Int
    }

    // MARK: - Extract template from a concrete layout

    /// Convert a saved layout (absolute pixels) into an abstract template.
    /// `categories` maps each placement index to its window category.
    static func extractTemplate(from placements: [WindowPlacement], categories: [WindowCategory],
                                 screen: ScreenInfo) -> LayoutTemplate {
        let slots = zip(placements, categories).map { p, cat -> Slot in
            Slot(
                x: clamp((p.frame.x - screen.usableOriginX) / screen.usableWidth),
                y: clamp((p.frame.y - screen.usableOriginY) / screen.usableHeight),
                width: clamp(p.frame.width / screen.usableWidth),
                height: clamp(p.frame.height / screen.usableHeight),
                categoryCounts: [cat.rawValue: 1]
            )
        }
        return LayoutTemplate(windowCount: placements.count, slots: slots, useCount: 1)
    }

    // MARK: - Find best template for N windows

    /// Find the best template for a given window count.
    /// Priority: exact match → closest larger (has room) → closest smaller (extras split in).
    static func bestTemplate(for windowCount: Int, from templates: [LayoutTemplate]) -> LayoutTemplate? {
        // Exact match — preferred
        let exact = templates.filter { $0.windowCount == windowCount }
            .sorted { $0.useCount > $1.useCount }
        if let best = exact.first { return best }

        // Closest larger template — already has enough slots for all windows
        let larger = templates.filter { $0.windowCount > windowCount }
            .sorted { a, b in
                if a.windowCount != b.windowCount { return a.windowCount < b.windowCount }
                return a.useCount > b.useCount
            }
        if let best = larger.first { return best }

        // Closest smaller template (at least 2 slots) — known windows keep positions, extras split in
        let smaller = templates.filter { $0.windowCount < windowCount && $0.windowCount >= 2 }
            .sorted { a, b in
                if a.windowCount != b.windowCount { return a.windowCount > b.windowCount }
                return a.useCount > b.useCount
            }
        return smaller.first
    }

    // MARK: - Apply template to windows

    /// Assign windows to template slots using category preference statistics.
    /// Each slot prefers the category it's seen most often. Unmatched windows
    /// fall back to priority-based assignment (bigger slot → higher priority category).
    static func applyTemplate(_ template: LayoutTemplate, to windows: [WindowInfo],
                               screen: ScreenInfo, gap: Double) -> [WindowPlacement] {
        let assignments = assignWindowsToSlots(template: template, windows: windows)

        var placements: [WindowPlacement] = []
        for (slotIdx, windowIdx) in assignments {
            let slot = template.slots[slotIdx]
            let window = windows[windowIdx]
            placements.append(WindowPlacement(
                windowID: window.id,
                frame: WindowFrame(
                    x: screen.usableOriginX + slot.x * screen.usableWidth + gap,
                    y: screen.usableOriginY + slot.y * screen.usableHeight + gap,
                    width: slot.width * screen.usableWidth - gap * 2,
                    height: slot.height * screen.usableHeight - gap * 2
                )
            ))
        }

        // If more windows than slots, split the lowest-priority assigned slot
        let assignedWindowIdxs = Set(assignments.map(\.1))
        let unassigned = windows.indices.filter { !assignedWindowIdxs.contains($0) }
            .sorted { windows[$0].category.priority < windows[$1].category.priority }

        for windowIdx in unassigned {
            // Find the slot with the lowest-priority window that has the most height to split
            guard let splitIdx = placements.indices
                .sorted(by: { placements[$0].frame.height > placements[$1].frame.height })
                .first(where: { idx in
                    let wid = placements[idx].windowID
                    let cat = windows.first(where: { $0.id == wid })?.category ?? .other
                    return cat.priority <= windows[windowIdx].category.priority || placements[idx].frame.height > 200
                }) ?? placements.indices.max(by: { placements[$0].frame.height < placements[$1].frame.height })
            else { break }

            // Split the slot vertically: existing window gets top half, new window gets bottom half
            let original = placements[splitIdx].frame
            let halfH = (original.height - gap) / 2
            placements[splitIdx] = WindowPlacement(
                windowID: placements[splitIdx].windowID,
                frame: WindowFrame(x: original.x, y: original.y, width: original.width, height: halfH)
            )
            placements.append(WindowPlacement(
                windowID: windows[windowIdx].id,
                frame: WindowFrame(x: original.x, y: original.y + halfH + gap, width: original.width, height: halfH)
            ))
        }

        return placements
    }

    /// Smart assignment: match windows to slots using category history, then priority fallback.
    private static func assignWindowsToSlots(template: LayoutTemplate, windows: [WindowInfo]) -> [(Int, Int)] {
        var assignments: [(slotIdx: Int, windowIdx: Int)] = []
        var usedSlots = Set<Int>()
        var usedWindows = Set<Int>()

        // Pass 1: assign windows to slots that strongly prefer their category
        for (wi, window) in windows.enumerated() {
            let cat = window.category.rawValue
            var bestSlot: Int?
            var bestScore = 0

            for (si, slot) in template.slots.enumerated() {
                guard !usedSlots.contains(si) else { continue }
                let score = slot.categoryCounts[cat] ?? 0
                if score > bestScore {
                    bestScore = score
                    bestSlot = si
                }
            }

            if let si = bestSlot, bestScore > 0 {
                assignments.append((si, wi))
                usedSlots.insert(si)
                usedWindows.insert(wi)
            }
        }

        // Pass 2: assign remaining windows by priority (biggest slot → highest priority)
        let remainingWindows = windows.indices.filter { !usedWindows.contains($0) }
            .sorted { windows[$0].category.priority > windows[$1].category.priority }
        let remainingSlots = template.slots.indices.filter { !usedSlots.contains($0) }
            .sorted { template.slots[$0].width * template.slots[$0].height >
                      template.slots[$1].width * template.slots[$1].height }

        for (wi, si) in zip(remainingWindows, remainingSlots) {
            assignments.append((si, wi))
        }

        return assignments
    }

    // MARK: - Template similarity (for deduplication)

    /// Check if two templates are structurally similar (same general arrangement).
    static func areSimilar(_ a: LayoutTemplate, _ b: LayoutTemplate, tolerance: Double = 0.15) -> Bool {
        guard a.windowCount == b.windowCount, a.slots.count == b.slots.count else { return false }
        // Sort both by position for stable comparison
        let slotsA = a.slots.sorted { $0.x + $0.y * 100 < $1.x + $1.y * 100 }
        let slotsB = b.slots.sorted { $0.x + $0.y * 100 < $1.x + $1.y * 100 }
        for (sa, sb) in zip(slotsA, slotsB) {
            if abs(sa.x - sb.x) > tolerance || abs(sa.y - sb.y) > tolerance ||
               abs(sa.width - sb.width) > tolerance || abs(sa.height - sb.height) > tolerance {
                return false
            }
        }
        return true
    }

    /// Merge category counts from a new template into an existing one.
    static func mergeCategories(existing: inout LayoutTemplate, new: LayoutTemplate) {
        // Match slots by position proximity
        let newSorted = new.slots.sorted { $0.x + $0.y * 100 < $1.x + $1.y * 100 }
        var existingSorted = existing.slots.sorted { $0.x + $0.y * 100 < $1.x + $1.y * 100 }

        for (i, newSlot) in newSorted.enumerated() {
            guard i < existingSorted.count else { break }
            var merged = existingSorted[i].categoryCounts
            for (cat, count) in newSlot.categoryCounts {
                merged[cat, default: 0] += count
            }
            existingSorted[i] = Slot(
                x: existingSorted[i].x, y: existingSorted[i].y,
                width: existingSorted[i].width, height: existingSorted[i].height,
                categoryCounts: merged
            )
        }
        existing = LayoutTemplate(windowCount: existing.windowCount, slots: existingSorted,
                                   useCount: existing.useCount + 1)
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
}

// MARK: - Category Priority

extension WindowCategory {
    /// Priority for slot assignment: higher = gets bigger slot
    var priority: Int {
        switch self {
        case .editor:    return 100
        case .browser:   return 90
        case .reference: return 70
        case .notes:     return 60
        case .email:     return 50
        case .finder:    return 40
        case .chat:      return 30
        case .terminal:  return 20
        case .media:     return 10
        case .other:     return 0
        }
    }
}
