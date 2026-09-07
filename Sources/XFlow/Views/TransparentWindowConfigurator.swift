import AppKit
import SwiftUI

struct TransparentWindowConfigurator: NSViewRepresentable {
    var isLaunching = false
    var reduceMotion = false
    var allowsContinue = false
    var onContinue: () -> Void = {}
    var onSplashPresented: () -> Void = {}
    var onSplashDismissed: () -> Void = {}

    func makeCoordinator() -> SplashCoordinator { SplashCoordinator() }

    private let sidebarWidth: CGFloat = 82

    func makeNSView(context: Context) -> NSView {
        let view = WindowAttachmentView(frame: .zero)
        view.onAttachment = { window in
            context.coordinator.update(window: window, isLaunching: isLaunching, reduceMotion: reduceMotion, onPresented: onSplashPresented, onDismissed: onSplashDismissed, allowsContinue: allowsContinue, onContinue: onContinue)
        }
        configureWindowIfAvailable(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            context.coordinator.update(window: window, isLaunching: isLaunching, reduceMotion: reduceMotion, onPresented: onSplashPresented, onDismissed: onSplashDismissed, allowsContinue: allowsContinue, onContinue: onContinue)
        }
        configureWindowIfAvailable(from: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: SplashCoordinator) {
        coordinator.finish(animated: false)
    }

    final class WindowAttachmentView: NSView {
        var onAttachment: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onAttachment?(window) }
        }
    }

    final class SplashCoordinator {
        private var panel: NSPanel?
        private weak var mainWindow: NSWindow?
        private var didPresent = false
        private var onDismissed: (() -> Void)?

        func update(window: NSWindow, isLaunching: Bool, reduceMotion: Bool, onPresented: @escaping () -> Void, onDismissed: @escaping () -> Void, allowsContinue: Bool, onContinue: @escaping () -> Void) {
            self.onDismissed = onDismissed
            if isLaunching, !didPresent {
                didPresent = true
                mainWindow = window
                // Keep the deck ordered and loading, but hide all its window chrome.
                window.alphaValue = 0
                let splash = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 820, height: 460),
                    styleMask: [.borderless], backing: .buffered, defer: false
                )
                splash.isReleasedWhenClosed = false
                splash.isOpaque = false
                splash.backgroundColor = .clear
                splash.hasShadow = true
                splash.hidesOnDeactivate = false
                splash.isMovable = false
                splash.contentView = NSHostingView(rootView: LaunchSplashView())
                let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
                splash.setFrameOrigin(NSPoint(x: screenFrame.midX - 410, y: screenFrame.midY - 230))
                panel = splash
                splash.orderFrontRegardless()
                DispatchQueue.main.async(execute: onPresented)
            } else if !isLaunching {
                finish(animated: !reduceMotion)
            } else if let host = panel?.contentView as? NSHostingView<LaunchSplashView> {
                host.rootView = LaunchSplashView(allowsContinue: allowsContinue, onContinue: onContinue)
            }
        }

        func finish(animated: Bool) {
            guard let splash = panel else { return }
            panel = nil
            let window = mainWindow
            let completion = onDismissed
            onDismissed = nil
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animated ? 0.4 : 0
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window?.animator().alphaValue = 1
                splash.animator().alphaValue = 0
            } completionHandler: {
                splash.orderOut(nil)
                splash.close()
                completion?()
            }
        }
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
