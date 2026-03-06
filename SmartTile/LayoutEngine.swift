import Foundation

/// Layout engine: learned templates -> local llama.cpp -> grid fallback
class LayoutEngine {

    static let shared = LayoutEngine()
    private let preferenceStore = PreferenceStore.shared

    // MARK: - Public API

    func suggestLayout(windows: [WindowInfo], screen: ScreenInfo, settings: AppSettings) async throws -> LayoutProposal {
        // Stop any previous auto-learn observation
        preferenceStore.stopAutoLearn()

        // 1. Try learned template (matches by window count)
        if let template = preferenceStore.bestTemplate(for: windows.count) {
            NSLog("SmartTile: Using learned template for %d windows (used %dx)", windows.count, template.useCount)
            let placements = PreferenceAnalyzer.applyTemplate(template, to: windows, screen: screen, gap: settings.gapBetweenWindows)
            let proposal = LayoutProposal(windows: placements, reasoning: "Learned layout for \(windows.count) windows")

            // Start auto-learn to detect corrections
            DispatchQueue.main.async {
                self.preferenceStore.startAutoLearn(appliedLayout: placements, windows: windows)
            }
            return proposal
        }

        // 2. Try local llama.cpp model
        let localModel = LocalModelManager.shared
        if localModel.findLlamaCli() != nil && localModel.hasModel {
            NSLog("SmartTile: Using local llama.cpp model")
            ToastController.shared.show("AI thinking...", icon: "brain", duration: 60)

            do {
                let proposal = try await withThrowingTaskGroup(of: LayoutProposal.self) { group in
                    group.addTask {
                        try await self.callLocalLlama(windows: windows, screen: screen, gap: settings.gapBetweenWindows)
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(60))
                        throw LayoutError.apiError("Model timed out after 60s")
                    }
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                }
                NSLog("SmartTile: Local model returned: %@", proposal.reasoning ?? "no reasoning")

                // Start auto-learn to detect corrections
                DispatchQueue.main.async {
                    self.preferenceStore.startAutoLearn(appliedLayout: proposal.windows, windows: windows)
                }
                return proposal
            } catch {
                NSLog("SmartTile: Local model failed: %@", error.localizedDescription)
            }
        } else {
            switch localModel.checkStatus() {
            case .missingLlamaCli:
                NSLog("SmartTile: llama-cli not installed")
            case .missingModel:
                NSLog("SmartTile: Model not downloaded")
            default:
                break
            }
        }

        // 3. Fallback to grid
        let fallbackReason: String
        switch localModel.checkStatus() {
        case .missingLlamaCli:
            fallbackReason = "Install llama.cpp for AI: brew install llama.cpp"
        case .missingModel:
            fallbackReason = "Download AI model in Settings"
        default:
            fallbackReason = "Grid layout (AI failed)"
        }
        let cols = windows.count <= 3 ? windows.count : (windows.count <= 6 ? 3 : 4)
        let grid = gridLayout(windows: windows, screen: screen, columns: cols, gap: settings.gapBetweenWindows)

        // Start auto-learn even for grid fallback
        DispatchQueue.main.async {
            self.preferenceStore.startAutoLearn(appliedLayout: grid.windows, windows: windows)
        }
        return LayoutProposal(windows: grid.windows, reasoning: fallbackReason)
    }

    /// Simple grid layout (fallback)
    func gridLayout(windows: [WindowInfo], screen: ScreenInfo, columns: Int, gap: Double) -> LayoutProposal {
        let count = windows.count
        guard count > 0 else {
            return LayoutProposal(windows: [], reasoning: "No windows to arrange")
        }

        let rows = Int(ceil(Double(count) / Double(columns)))
        let cellWidth = (screen.usableWidth - gap * Double(columns + 1)) / Double(columns)
        let cellHeight = (screen.usableHeight - gap * Double(rows + 1)) / Double(rows)

        var placements: [WindowPlacement] = []
        for (i, window) in windows.enumerated() {
            let col = i % columns
            let row = i / columns
            let x = screen.usableOriginX + gap + Double(col) * (cellWidth + gap)
            let y = screen.usableOriginY + gap + Double(row) * (cellHeight + gap)

            placements.append(WindowPlacement(
                windowID: window.id,
                frame: WindowFrame(x: x, y: y, width: cellWidth, height: cellHeight)
            ))
        }

        return LayoutProposal(windows: placements, reasoning: "Grid layout: \(columns) columns x \(rows) rows")
    }

    // MARK: - Local llama.cpp Inference

    private let llamaSystemPrompt = """
        You are a window layout manager for macOS. \
        Output ONLY valid JSON: {"placements":[{"id":"...","x":0,"y":0,"width":0,"height":0}],"reasoning":"..."}. \
        Arrange windows to fill the entire screen without overlapping. Leave small gaps between windows. \
        Editors and browsers should get more space. Terminals and chat windows can be smaller.
        """

    private func callLocalLlama(windows: [WindowInfo], screen: ScreenInfo, gap: Double) async throws -> LayoutProposal {
        let prompt = buildPrompt(windows: windows, screen: screen)
        let promptDebugPath = NSHomeDirectory() + "/Library/Application Support/SmartTile/last_prompt.txt"
        try? "SYSTEM:\n\(llamaSystemPrompt)\n\nUSER:\n\(prompt)".write(toFile: promptDebugPath, atomically: true, encoding: .utf8)
        let output = try await LocalModelManager.shared.runInference(prompt: prompt, systemPrompt: llamaSystemPrompt)

        NSLog("SmartTile: llama output length: %d", output.count)
        let llamaDebugPath = NSHomeDirectory() + "/Library/Application Support/SmartTile/last_llama_output.txt"
        try? output.write(toFile: llamaDebugPath, atomically: true, encoding: .utf8)

        let json = extractJSON(from: output)
        guard let jsonData = json.data(using: .utf8) else {
            throw LayoutError.parseError("Could not convert output to data")
        }

        struct LlamaResponse: Decodable {
            let placements: [LlamaPlacement]
            let reasoning: String?
        }
        struct LlamaPlacement: Decodable {
            let id: String
            let x: Double
            let y: Double
            let width: Double
            let height: Double
        }

        let response = try JSONDecoder().decode(LlamaResponse.self, from: jsonData)

        var windowPlacements: [WindowPlacement] = []
        for p in response.placements {
            let frame = WindowFrame(
                x: max(screen.usableOriginX, min(p.x, screen.usableOriginX + screen.usableWidth - 200)),
                y: max(screen.usableOriginY, min(p.y, screen.usableOriginY + screen.usableHeight - 200)),
                width: max(200, min(p.width, screen.usableWidth)),
                height: max(200, min(p.height, screen.usableHeight))
            )
            windowPlacements.append(WindowPlacement(windowID: p.id, frame: frame))
        }

        let placedIDs = Set(windowPlacements.map(\.windowID))
        let missingWindows = windows.filter { !placedIDs.contains($0.id) }
        if !missingWindows.isEmpty {
            let missingPlacements = placeMissingWindows(missingWindows, existing: windowPlacements, screen: screen, gap: gap)
            windowPlacements.append(contentsOf: missingPlacements)
        }

        // Normalize AI output to fill screen
        windowPlacements = normalizeToFillScreen(windowPlacements, screen: screen, gap: gap)

        return LayoutProposal(windows: windowPlacements, reasoning: response.reasoning ?? "AI layout (local)")
    }

    private func extractJSON(from text: String) -> String {
        if let start = text.range(of: "```json"),
           let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = text.range(of: "```"),
           let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompt Building

    private func buildPrompt(windows: [WindowInfo], screen: ScreenInfo) -> String {
        let windowDescriptions = windows.enumerated().map { i, w in
            "Window \(i+1): id=\"\(w.id)\" app=\(w.appName) category=\(w.category.rawValue)(\(w.category.layoutHint))"
        }.joined(separator: "\n")

        let aspectRatio = screen.usableWidth / screen.usableHeight
        let isUltrawide = aspectRatio > 1.8

        return """
        Arrange \(windows.count) windows on \(isUltrawide ? "an ULTRAWIDE" : "a") \(Int(screen.usableWidth))x\(Int(screen.usableHeight)) screen.
        Origin: x=\(Int(screen.usableOriginX)), y=\(Int(screen.usableOriginY)). Y=0 is top. Gap=8px.

        \(windowDescriptions)

        Editors and browsers should get more space. Terminals and chat can be smaller.
        Windows must not overlap and should fill the screen. Use exact window id values. Output JSON only.
        """
    }

    /// Normalize AI placements: preserve relative width ratios but fill the full screen.
    private func normalizeToFillScreen(_ placements: [WindowPlacement], screen: ScreenInfo, gap: Double) -> [WindowPlacement] {
        guard !placements.isEmpty else { return placements }

        let sorted = placements.sorted { $0.frame.x < $1.frame.x }
        let totalAIWidth = sorted.map(\.frame.width).reduce(0, +)
        guard totalAIWidth > 0 else { return placements }

        let totalGaps = gap * Double(sorted.count + 1)
        let availableWidth = screen.usableWidth - totalGaps
        let fullHeight = screen.usableHeight - gap * 2

        var result: [WindowPlacement] = []
        var currentX = screen.usableOriginX + gap

        for (i, p) in sorted.enumerated() {
            let ratio = p.frame.width / totalAIWidth
            let newWidth: Double
            if i == sorted.count - 1 {
                newWidth = screen.usableOriginX + screen.usableWidth - gap - currentX
            } else {
                newWidth = availableWidth * ratio
            }

            result.append(WindowPlacement(
                windowID: p.windowID,
                frame: WindowFrame(
                    x: currentX,
                    y: screen.usableOriginY + gap,
                    width: newWidth,
                    height: fullHeight
                )
            ))
            currentX += newWidth + gap
        }

        return result
    }

    /// Place windows that the model omitted.
    private func placeMissingWindows(_ missing: [WindowInfo], existing: [WindowPlacement],
                                      screen: ScreenInfo, gap: Double) -> [WindowPlacement] {
        let maxX = existing.map { $0.frame.x + $0.frame.width }.max() ?? screen.usableOriginX
        let availableWidth = screen.usableOriginX + screen.usableWidth - maxX - gap
        let slotWidth = max(300, availableWidth - gap)
        let slotHeight = (screen.usableHeight - gap * Double(missing.count + 1)) / Double(missing.count)

        return missing.enumerated().map { i, window in
            WindowPlacement(
                windowID: window.id,
                frame: WindowFrame(
                    x: maxX + gap,
                    y: screen.usableOriginY + gap + Double(i) * (slotHeight + gap),
                    width: min(slotWidth, screen.usableOriginX + screen.usableWidth - maxX - gap * 2),
                    height: slotHeight
                )
            )
        }
    }
}

// MARK: - Errors

enum LayoutError: LocalizedError {
    case modelUnavailable
    case apiError(String)
    case parseError(String)
    case noWindows

    var errorDescription: String? {
        switch self {
        case .modelUnavailable: return "AI model not available."
        case .apiError(let msg): return "AI error: \(msg)"
        case .parseError(let msg): return "Parse error: \(msg)"
        case .noWindows: return "No windows found to arrange."
        }
    }
}
