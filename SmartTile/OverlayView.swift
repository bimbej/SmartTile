import SwiftUI
import AppKit

// MARK: - Overlay Window Controller

/// NSWindow subclass that handles ESC key to dismiss the overlay
class OverlayNSWindow: NSWindow {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

class OverlayWindowController {
    static let shared = OverlayWindowController()

    private var overlayWindow: OverlayNSWindow?
    private var targetWindow: WindowInfo?

    /// Show overlay grid for the frontmost window
    func showForFrontWindow() {
        let myBundleID = Bundle.main.bundleIdentifier ?? ""
        let windows = WindowManager.shared.getVisibleWindows()
            .filter { $0.bundleID != myBundleID }

        // Use frontmost non-SmartTile app, or fall back to first visible window
        let front = NSWorkspace.shared.frontmostApplication
        let target: WindowInfo?
        if let frontID = front?.bundleIdentifier, frontID != myBundleID {
            target = windows.first(where: { $0.bundleID == frontID })
        } else {
            target = windows.first
        }

        guard let target else {
            ToastController.shared.show("No windows to tile", icon: "rectangle.on.rectangle.slash")
            return
        }
        targetWindow = target
        showOverlay(for: target)
    }

    /// Show overlay grid for a specific window
    func showOverlay(for window: WindowInfo) {
        targetWindow = window

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        let contentView = NSHostingView(rootView: GridOverlayView(
            screenInfo: ScreenInfo.current(),
            windowName: "\(window.appName): \(window.windowTitle)",
            onSelect: { [weak self] frame in
                self?.applySelection(frame: frame)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        ))

        let nsWindow = OverlayNSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        nsWindow.level = .floating
        nsWindow.isOpaque = false
        nsWindow.backgroundColor = NSColor.black.withAlphaComponent(0.3)
        nsWindow.contentView = contentView
        nsWindow.ignoresMouseEvents = false
        nsWindow.onEscape = { [weak self] in self?.dismiss() }
        nsWindow.makeKeyAndOrderFront(nil)

        // Activate our app so the window can receive key events
        NSApp.activate(ignoringOtherApps: true)

        self.overlayWindow = nsWindow
    }
    
    private func applySelection(frame: WindowFrame) {
        guard let target = targetWindow else { return }
        _ = WindowManager.shared.setWindowFrame(
            pid: target.pid,
            windowIndex: target.windowIndex,
            frame: frame
        )
        dismiss()
    }

    func dismiss() {
        guard let window = overlayWindow else { return }
        overlayWindow = nil
        targetWindow = nil
        // Just hide — don't close() or clear contentView.
        // Closing causes use-after-free when the autorelease pool
        // drains the NSHostingView that SwiftUI still references.
        window.orderOut(nil)
    }
}

// MARK: - Grid Overlay SwiftUI View

struct GridOverlayView: View {
    let screenInfo: ScreenInfo
    let windowName: String
    let onSelect: (WindowFrame) -> Void
    let onDismiss: () -> Void
    
    @State private var columns: Int = 6
    @State private var rows: Int = 3
    @State private var dragStart: GridCell? = nil
    @State private var dragEnd: GridCell? = nil
    @State private var hoveredCell: GridCell? = nil
    
    struct GridCell: Equatable {
        let col: Int
        let row: Int
    }
    
    var body: some View {
        ZStack {
            // Background - click to dismiss
            Color.black.opacity(0.01)
                .onTapGesture { DispatchQueue.main.async { onDismiss() } }
            
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("SmartTile")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("— \(windowName)")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Grid size controls
                    HStack(spacing: 8) {
                        Text("Grid:")
                            .foregroundColor(.white.opacity(0.7))
                        
                        Button(action: { if columns > 2 { columns -= 1 } }) {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        
                        Text("\(columns)×\(rows)")
                            .foregroundColor(.white)
                            .monospacedDigit()
                        
                        Button(action: { if columns < 12 { columns += 1 } }) {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                    }
                    
                    Button("ESC") {
                        onDismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
                }
                .padding(.horizontal, 20)
                
                // Grid
                GeometryReader { geometry in
                    let cellWidth = geometry.size.width / CGFloat(columns)
                    let cellHeight = geometry.size.height / CGFloat(rows)
                    
                    ZStack {
                        // Grid cells
                        ForEach(0..<rows, id: \.self) { row in
                            ForEach(0..<columns, id: \.self) { col in
                                let cell = GridCell(col: col, row: row)
                                let isSelected = isCellInSelection(cell)
                                
                                Rectangle()
                                    .fill(isSelected ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.05))
                                    .border(Color.white.opacity(0.2), width: 0.5)
                                    .frame(width: cellWidth, height: cellHeight)
                                    .position(
                                        x: CGFloat(col) * cellWidth + cellWidth / 2,
                                        y: CGFloat(row) * cellHeight + cellHeight / 2
                                    )
                            }
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let col = Int(value.location.x / cellWidth)
                                let row = Int(value.location.y / cellHeight)
                                let cell = GridCell(
                                    col: max(0, min(col, columns - 1)),
                                    row: max(0, min(row, rows - 1))
                                )
                                
                                if dragStart == nil {
                                    dragStart = cell
                                }
                                dragEnd = cell
                            }
                            .onEnded { _ in
                                if let start = dragStart, let end = dragEnd {
                                    let frame = selectionToFrame(
                                        start: start, end: end
                                    )
                                    // Defer to escape the gesture handler's stack frame
                                    DispatchQueue.main.async {
                                        onSelect(frame)
                                    }
                                }
                                dragStart = nil
                                dragEnd = nil
                            }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                
                // Quick presets
                HStack(spacing: 12) {
                    PresetButton(label: "Full", icon: "rectangle.fill") {
                        let f = fullFrame(); DispatchQueue.main.async { onSelect(f) }
                    }
                    PresetButton(label: "Left ½", icon: "rectangle.lefthalf.filled") {
                        let f = halfFrame(left: true); DispatchQueue.main.async { onSelect(f) }
                    }
                    PresetButton(label: "Right ½", icon: "rectangle.righthalf.filled") {
                        let f = halfFrame(left: false); DispatchQueue.main.async { onSelect(f) }
                    }
                    PresetButton(label: "Left ⅓", icon: "rectangle.split.3x1") {
                        let f = thirdFrame(position: 0); DispatchQueue.main.async { onSelect(f) }
                    }
                    PresetButton(label: "Center ⅓", icon: "rectangle.center.inset.filled") {
                        let f = thirdFrame(position: 1); DispatchQueue.main.async { onSelect(f) }
                    }
                    PresetButton(label: "Right ⅓", icon: "rectangle.split.3x1") {
                        let f = thirdFrame(position: 2); DispatchQueue.main.async { onSelect(f) }
                    }
                    PresetButton(label: "Left ⅔", icon: "rectangle.leftthird.inset.filled") {
                        let f = twoThirdsFrame(left: true); DispatchQueue.main.async { onSelect(f) }
                    }
                    PresetButton(label: "Right ⅔", icon: "rectangle.rightthird.inset.filled") {
                        let f = twoThirdsFrame(left: false); DispatchQueue.main.async { onSelect(f) }
                    }
                }
                .padding(.bottom, 16)
            }
            .padding(.top, 16)
        }
    }
    
    // MARK: - Selection Logic
    
    private func isCellInSelection(_ cell: GridCell) -> Bool {
        guard let start = dragStart, let end = dragEnd ?? dragStart else { return false }
        let minCol = min(start.col, end.col)
        let maxCol = max(start.col, end.col)
        let minRow = min(start.row, end.row)
        let maxRow = max(start.row, end.row)
        return cell.col >= minCol && cell.col <= maxCol && cell.row >= minRow && cell.row <= maxRow
    }
    
    private func selectionToFrame(start: GridCell, end: GridCell) -> WindowFrame {
        let gap = 8.0
        let minCol = min(start.col, end.col)
        let maxCol = max(start.col, end.col)
        let minRow = min(start.row, end.row)
        let maxRow = max(start.row, end.row)

        // Map grid cell fractions directly to usable screen area
        let x = screenInfo.usableOriginX + Double(minCol) / Double(columns) * screenInfo.usableWidth + gap
        let y = screenInfo.usableOriginY + Double(minRow) / Double(rows) * screenInfo.usableHeight + gap
        let w = Double(maxCol - minCol + 1) / Double(columns) * screenInfo.usableWidth - gap * 2
        let h = Double(maxRow - minRow + 1) / Double(rows) * screenInfo.usableHeight - gap * 2

        return WindowFrame(x: x, y: y, width: w, height: h)
    }
    
    // MARK: - Preset Frames
    
    private func fullFrame() -> WindowFrame {
        let gap = 8.0
        return WindowFrame(
            x: screenInfo.usableOriginX + gap,
            y: screenInfo.usableOriginY + gap,
            width: screenInfo.usableWidth - gap * 2,
            height: screenInfo.usableHeight - gap * 2
        )
    }
    
    private func halfFrame(left: Bool) -> WindowFrame {
        let gap = 8.0
        let halfWidth = (screenInfo.usableWidth - gap * 3) / 2
        return WindowFrame(
            x: screenInfo.usableOriginX + (left ? gap : halfWidth + gap * 2),
            y: screenInfo.usableOriginY + gap,
            width: halfWidth,
            height: screenInfo.usableHeight - gap * 2
        )
    }
    
    private func thirdFrame(position: Int) -> WindowFrame {
        let gap = 8.0
        let thirdWidth = (screenInfo.usableWidth - gap * 4) / 3
        return WindowFrame(
            x: screenInfo.usableOriginX + gap + Double(position) * (thirdWidth + gap),
            y: screenInfo.usableOriginY + gap,
            width: thirdWidth,
            height: screenInfo.usableHeight - gap * 2
        )
    }
    
    private func twoThirdsFrame(left: Bool) -> WindowFrame {
        let gap = 8.0
        let twoThirdsWidth = (screenInfo.usableWidth - gap * 4) / 3 * 2 + gap
        let oneThirdWidth = (screenInfo.usableWidth - gap * 4) / 3
        return WindowFrame(
            x: screenInfo.usableOriginX + (left ? gap : oneThirdWidth + gap * 2),
            y: screenInfo.usableOriginY + gap,
            width: twoThirdsWidth,
            height: screenInfo.usableHeight - gap * 2
        )
    }
}

// MARK: - Preset Button

struct PresetButton: View {
    let label: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundColor(.white)
            .frame(width: 64, height: 44)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
