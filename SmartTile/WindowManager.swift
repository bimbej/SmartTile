import Foundation
import AppKit
import ApplicationServices

/// Manages window discovery and manipulation via macOS Accessibility API
class WindowManager {
    
    static let shared = WindowManager()
    
    // MARK: - Window Discovery
    
    /// Get all visible windows on screen, sorted with frontmost app first
    func getVisibleWindows() -> [WindowInfo] {
        var windows: [WindowInfo] = []

        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden
        }.sorted { a, _ in
            // Frontmost app first, rest in original order
            a.bundleIdentifier == frontBundleID
        }

        for app in runningApps {
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            
            var windowsRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
            
            guard result == .success, let axWindows = windowsRef as? [AXUIElement] else {
                continue
            }
            
            var windowIndex = 0
            for axWindow in axWindows {
                guard let windowInfo = extractWindowInfo(
                    from: axWindow,
                    pid: pid,
                    appName: app.localizedName ?? "Unknown",
                    bundleID: app.bundleIdentifier ?? "unknown",
                    windowIndex: windowIndex
                ) else { continue }

                // Skip minimized and tiny windows (floating panels, etc.)
                guard !windowInfo.isMinimized && windowInfo.frame.width > 100 && windowInfo.frame.height > 100 else {
                    continue
                }

                // Skip Finder's desktop window (covers entire screen, starts at y=0)
                if windowInfo.bundleID == "com.apple.finder" {
                    let screen = NSScreen.main?.frame ?? .zero
                    if windowInfo.frame.width >= Double(screen.width) - 10 &&
                       windowInfo.frame.height >= Double(screen.height) - 10 &&
                       windowInfo.frame.y <= 1 {
                        continue
                    }
                }

                windows.append(windowInfo)
                windowIndex += 1
            }
        }
        
        return windows
    }
    
    private func extractWindowInfo(from element: AXUIElement, pid: Int32, appName: String, bundleID: String, windowIndex: Int) -> WindowInfo? {
        // Get title
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String) ?? ""
        
        // Get position
        var positionRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
        var position = CGPoint.zero
        if let posRef = positionRef {
            AXValueGetValue(posRef as! AXValue, .cgPoint, &position)
        }
        
        // Get size
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        var size = CGSize.zero
        if let szRef = sizeRef {
            AXValueGetValue(szRef as! AXValue, .cgSize, &size)
        }
        
        // Check if minimized
        var minimizedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedRef)
        let isMinimized = (minimizedRef as? Bool) ?? false
        
        // Check subrole — skip non-standard windows
        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        let subrole = (subroleRef as? String) ?? ""
        if subrole == "AXSystemDialog" || subrole == "AXDialog" {
            // Still include dialogs, they're real windows
        }
        
        let frame = WindowFrame(x: Double(position.x), y: Double(position.y),
                               width: Double(size.width), height: Double(size.height))

        let id = "\(bundleID)_\(windowIndex)"

        return WindowInfo(
            id: id,
            bundleID: bundleID,
            appName: appName,
            windowTitle: title,
            pid: pid,
            windowIndex: windowIndex,
            frame: frame,
            isMinimized: isMinimized
        )
    }
    
    // MARK: - Window Manipulation
    
    /// Move and resize a window by pid + window index
    func setWindowFrame(pid: Int32, windowIndex: Int, frame: WindowFrame) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let axWindows = windowsRef as? [AXUIElement] else {
            return false
        }

        // Filter to visible (non-minimized, non-tiny) windows to match getVisibleWindows() indexing
        let visibleWindows = axWindows.filter { axWindow in
            var minimizedRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef)
            if (minimizedRef as? Bool) == true { return false }

            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)
            var size = CGSize.zero
            if let szRef = sizeRef { AXValueGetValue(szRef as! AXValue, .cgSize, &size) }
            return size.width > 100 && size.height > 100
        }

        if windowIndex < visibleWindows.count {
            return applyFrame(to: visibleWindows[windowIndex], frame: frame)
        }

        // Fallback: try first visible window
        if let first = visibleWindows.first {
            return applyFrame(to: first, frame: frame)
        }

        return false
    }
    
    private func applyFrame(to window: AXUIElement, frame: WindowFrame) -> Bool {
        // Set position first, then size
        var position = CGPoint(x: frame.x, y: frame.y)
        guard let posValue = AXValueCreate(.cgPoint, &position) else { return false }
        let posResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        
        var size = CGSize(width: frame.width, height: frame.height)
        guard let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        
        return posResult == .success && sizeResult == .success
    }
    
    /// Apply a complete layout
    func applyLayout(_ placements: [WindowPlacement], windows: [WindowInfo]) {
        var debugLines: [String] = []
        for placement in placements {
            if let window = windows.first(where: { $0.id == placement.windowID }) {
                let success = setWindowFrame(
                    pid: window.pid,
                    windowIndex: window.windowIndex,
                    frame: placement.frame
                )
                debugLines.append("\(window.appName) [\(placement.windowID)]: target x=\(Int(placement.frame.x)) y=\(Int(placement.frame.y)) w=\(Int(placement.frame.width)) h=\(Int(placement.frame.height)) → \(success ? "OK" : "FAILED")")
            } else {
                debugLines.append("NOT FOUND: \(placement.windowID)")
            }
        }
        let debugPath = NSHomeDirectory() + "/Library/Application Support/SmartTile/last_apply_debug.txt"
        try? debugLines.joined(separator: "\n").write(toFile: debugPath, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Accessibility Permissions

    /// Check if we have Accessibility permission (flag only — may be stale after rebuild)
    static func hasAccessibilityPermission() -> Bool {
        let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [checkOptPrompt: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Verify accessibility actually works by trying a real AX call.
    /// After a rebuild, macOS may report permission as granted but AX calls fail.
    static func verifyAccessibilityWorks() -> Bool {
        guard hasAccessibilityPermission() else { return false }

        // Try to read windows from any running regular app
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden
        }
        for app in apps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
            if result == .success {
                return true
            }
        }
        // No apps to test against, assume it works if flag says so
        return apps.isEmpty
    }

    /// Request Accessibility permission (shows system dialog)
    static func requestAccessibilityPermission() {
        let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [checkOptPrompt: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
