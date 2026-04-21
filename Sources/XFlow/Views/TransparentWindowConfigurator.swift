import AppKit
import SwiftUI

struct TransparentWindowConfigurator: NSViewRepresentable {
    private let sidebarWidth: CGFloat = 96

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWindowIfAvailable(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindowIfAvailable(from: nsView)
    }

    private func configureWindowIfAvailable(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }

            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarSeparatorStyle = .none
            // Prevent window dragging from stealing column reorder drag gestures.
            window.isMovableByWindowBackground = false
            window.hasShadow = true

            window.contentView?.wantsLayer = true
            window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

            alignWindowButtons(in: window)
        }
    }

    private func alignWindowButtons(in window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton) else {
            return
        }

        let buttons = [close, mini, zoom]
        let spacing = max(6, mini.frame.minX - close.frame.maxX)
        let buttonWidth = close.frame.width
        let clusterWidth = (buttonWidth * CGFloat(buttons.count)) + (spacing * CGFloat(buttons.count - 1))
        let originX = max(10, (sidebarWidth - clusterWidth) * 0.5)

        for (index, button) in buttons.enumerated() {
            guard let container = button.superview else {
                continue
            }
            let y = round((container.bounds.height - button.frame.height) * 0.5)
            let x = round(originX + (CGFloat(index) * (buttonWidth + spacing)))
            button.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}
