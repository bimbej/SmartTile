import AppKit

/// Shows a brief toast notification in the top-right corner of the screen.
/// Pure AppKit — no NSHostingView / SwiftUI to avoid display cycle crashes.
class ToastController {
    static let shared = ToastController()

    private var toastWindow: NSWindow?
    private var dismissWork: DispatchWorkItem?

    func show(_ message: String, icon: String = "info.circle.fill", duration: TimeInterval = 5.0) {
        DispatchQueue.main.async { [weak self] in
            self?.showOnMain(message, icon: icon, duration: duration)
        }
    }

    private func showOnMain(_ message: String, icon: String, duration: TimeInterval) {
        dismissWork?.cancel()
        toastWindow?.orderOut(nil)
        toastWindow = nil

        guard let screen = NSScreen.main else { return }

        // Build pure AppKit content view
        let contentView = ToastNSView(message: message, icon: icon)
        let size = contentView.fittingSize
        let width = min(max(size.width, 200), 500)
        let height = max(size.height, 44)

        let frame = NSRect(
            x: screen.frame.maxX - width - 16,
            y: screen.frame.maxY - height - 40,
            width: width,
            height: height
        )

        contentView.frame = NSRect(origin: .zero, size: frame.size)

        let window = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentView = contentView
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.alphaValue = 0

        toastWindow = window
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            window.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, let w = self.toastWindow else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                w.animator().alphaValue = 0
            }, completionHandler: {
                w.orderOut(nil)
            })
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}

// MARK: - Pure AppKit Toast View

private class ToastNSView: NSView {
    private let message: String
    private let iconName: String

    init(message: String, icon: String) {
        self.message = message
        self.iconName = icon
        super.init(frame: .zero)
        wantsLayer = true
        setupSubviews()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: NSSize {
        let textWidth = min(max(estimateTextWidth(message, font: .systemFont(ofSize: 13, weight: .medium)), 120), 400)
        let lines = max(1, Int(ceil(estimateTextWidth(message, font: .systemFont(ofSize: 13, weight: .medium)) / textWidth)))
        let textHeight = CGFloat(lines) * 18 + 16 // line height + title
        return NSSize(width: textWidth + 60, height: max(textHeight + 20, 50))
    }

    private func estimateTextWidth(_ text: String, font: NSFont) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).size(withAttributes: attrs).width
    }

    private func setupSubviews() {
        // Icon
        let iconView = NSImageView()
        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            iconView.image = image.withSymbolConfiguration(config)
        }
        iconView.contentTintColor = .white
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        // Title label
        let titleLabel = NSTextField(labelWithString: "SmartTile")
        titleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // Message label
        let messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.font = .systemFont(ofSize: 13, weight: .medium)
        messageLabel.textColor = .white
        messageLabel.maximumNumberOfLines = 3
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),

            messageLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            messageLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)

        // Dark translucent background
        NSColor(white: 0.15, alpha: 0.85).setFill()
        path.fill()

        // Subtle border
        NSColor(white: 1.0, alpha: 0.1).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}
