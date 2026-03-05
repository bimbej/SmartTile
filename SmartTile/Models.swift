import Foundation
import AppKit

// MARK: - Window Info

struct WindowInfo: Codable, Identifiable {
    let id: String // bundleID + window index (stable within a session)
    let bundleID: String
    let appName: String
    let windowTitle: String
    let pid: Int32
    let windowIndex: Int // index of this window within its app (0-based)
    var frame: WindowFrame
    let isMinimized: Bool
    
    /// Classification for LLM context
    var category: WindowCategory {
        WindowCategory.classify(bundleID: bundleID, title: windowTitle)
    }
}

struct WindowFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    
    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
    
    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    
    init(from cgRect: CGRect) {
        self.x = Double(cgRect.origin.x)
        self.y = Double(cgRect.origin.y)
        self.width = Double(cgRect.size.width)
        self.height = Double(cgRect.size.height)
    }
}

// MARK: - Window Category

enum WindowCategory: String, Codable {
    case editor      // VS Code, Xcode, Sublime, etc.
    case browser     // Safari, Chrome, Arc, Firefox
    case terminal    // Terminal, iTerm, Warp
    case chat        // Slack, Teams, Discord, Messages, Google Chat
    case email       // Mail, Outlook
    case finder      // Finder
    case media       // Music, Spotify, VLC
    case notes       // Notes, Obsidian, Notion
    case reference   // PDF viewer, documentation
    case other
    
    static func classify(bundleID: String, title: String) -> WindowCategory {
        let bid = bundleID.lowercased()
        let t = title.lowercased()
        
        // Editors
        if bid.contains("vscode") || bid.contains("visual-studio-code") ||
           bid.contains("xcode") || bid.contains("sublime") ||
           bid.contains("jetbrains") || bid.contains("intellij") ||
           bid.contains("cursor") || bid.contains("zed") ||
           bid.contains("nova") || bid.contains("bbedit") ||
           bid.contains("textmate") {
            return .editor
        }
        
        // Browsers
        if bid.contains("safari") || bid.contains("chrome") ||
           bid.contains("firefox") || bid.contains("arc") ||
           bid.contains("brave") || bid.contains("opera") ||
           bid.contains("vivaldi") || bid.contains("edge") {
            return .browser
        }
        
        // Terminals
        if bid.contains("terminal") || bid.contains("iterm") ||
           bid.contains("warp") || bid.contains("alacritty") ||
           bid.contains("kitty") || bid.contains("hyper") {
            return .terminal
        }
        
        // Chat
        if bid.contains("slack") || bid.contains("teams") ||
           bid.contains("discord") || bid.contains("messages") ||
           bid.contains("telegram") || bid.contains("whatsapp") ||
           bid.contains("signal") || t.contains("google chat") ||
           t.contains("google meet") {
            return .chat
        }
        
        // Email
        if bid.contains("mail") || bid.contains("outlook") ||
           bid.contains("thunderbird") || bid.contains("spark") {
            return .email
        }
        
        // Finder
        if bid.contains("finder") {
            return .finder
        }
        
        // Media
        if bid.contains("music") || bid.contains("spotify") ||
           bid.contains("vlc") || bid.contains("iina") {
            return .media
        }
        
        // Notes
        if bid.contains("notes") || bid.contains("obsidian") ||
           bid.contains("notion") || bid.contains("bear") ||
           bid.contains("craft") {
            return .notes
        }
        
        // Reference / PDF
        if bid.contains("preview") || bid.contains("pdf") ||
           bid.contains("skim") || t.hasSuffix(".pdf") {
            return .reference
        }
        
        return .other
    }
    
    /// Hint for LLM about preferred sizing
    var layoutHint: String {
        switch self {
        case .editor:    return "wide, primary workspace, usually largest"
        case .browser:   return "flexible, medium to large"
        case .terminal:  return "can be narrow or bottom strip, often smaller"
        case .chat:      return "narrow sidebar, usually on the side"
        case .email:     return "medium width, can share space"
        case .finder:    return "medium, temporary"
        case .media:     return "small, corner or hidden"
        case .notes:     return "medium, can be sidebar"
        case .reference: return "medium to wide, for reading"
        case .other:     return "flexible"
        }
    }
}

// MARK: - Layout

struct LayoutProposal: Codable {
    let windows: [WindowPlacement]
    let reasoning: String?
}

struct WindowPlacement: Codable {
    let windowID: String
    let frame: WindowFrame
}

// MARK: - Screen Info

struct ScreenInfo: Codable {
    let width: Double
    let height: Double
    let menuBarHeight: Double
    let dockHeight: Double
    let usableWidth: Double
    let usableHeight: Double
    let usableOriginX: Double
    let usableOriginY: Double
    
    /// Returns screen info in AXUIElement coordinate system (origin = top-left of primary screen)
    static func current() -> ScreenInfo {
        guard let screen = NSScreen.main else {
            return ScreenInfo(width: 5120, height: 2160,
                            menuBarHeight: 25, dockHeight: 0,
                            usableWidth: 5120, usableHeight: 2135,
                            usableOriginX: 0, usableOriginY: 25)
        }
        let full = screen.frame
        let visible = screen.visibleFrame
        
        // NSScreen: origin bottom-left. AXUIElement: origin top-left.
        // Menu bar is at the top, dock can be bottom/left/right.
        let menuBarH = Double(full.maxY - visible.maxY)
        let dockH = Double(visible.minY - full.minY)
        
        // Convert to AX coordinates (y=0 at top of screen)
        let usableOriginY = menuBarH  // starts below menu bar
        let usableOriginX = Double(visible.origin.x - full.origin.x)
        
        return ScreenInfo(
            width: Double(full.width),
            height: Double(full.height),
            menuBarHeight: menuBarH,
            dockHeight: dockH,
            usableWidth: Double(visible.width),
            usableHeight: Double(visible.height),
            usableOriginX: usableOriginX,
            usableOriginY: usableOriginY
        )
    }
}

// MARK: - User Preferences

struct UserPreference: Codable, Identifiable {
    let id: String // hash of sorted app categories
    let appCombination: [String] // sorted bundle IDs
    let categoryCombo: [String] // sorted categories
    let layout: [WindowPlacement]
    let timestamp: Date
    var useCount: Int
}

// MARK: - Settings

struct AppSettings: Codable {
    var gapBetweenWindows: Double = 8
    var globalShortcutEnabled: Bool = true
    var autoArrangeOnLaunch: Bool = false
    
    static let defaultSettings = AppSettings()
    
    static var settingsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SmartTile")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.settingsURL)
        }
    }
    
    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .defaultSettings
        }
        return settings
    }
}
