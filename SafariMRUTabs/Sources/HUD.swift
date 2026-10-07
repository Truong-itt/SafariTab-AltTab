import AppKit

/// Thông báo ngắn giữa màn hình, kiểu overlay — không cần quyền Notifications.
enum HUD {

    private static var window: NSWindow?
    private static var hideTimer: Timer?

    static func show(_ text: String, duration: TimeInterval = 1.1) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { show(text, duration: duration) }
            return
        }

        hideTimer?.invalidate()
        window?.orderOut(nil)
        window = nil

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.sizeToFit()

        let padding = NSSize(width: 28, height: 18)
        let size = NSSize(
            width: max(label.frame.width + padding.width * 2, 160),
            height: label.frame.height + padding.height * 2)

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true

        label.frame = NSRect(
            x: padding.width,
            y: (size.height - label.frame.height) / 2,
            width: size.width - padding.width * 2,
            height: label.frame.height)
        effect.addSubview(label)

        guard let screen = NSScreen.main else { return }
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2)

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.contentView = effect
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            panel.animator().alphaValue = 1
        }

        window = panel
        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                if window === panel { window = nil }
            })
        }
    }
}
