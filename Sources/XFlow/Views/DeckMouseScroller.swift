import AppKit
import SwiftUI

/// Honors macOS device-sensitive scroller preferences, and detects wheel mice
/// even when the user has chosen to hide system scrollbars automatically.
struct DeckMouseScroller: NSViewRepresentable {
    @Binding var showsScroller: Bool

    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.onChange = { if showsScroller != $0 { showsScroller = $0 } }
        return view
    }

    func updateNSView(_ view: Probe, context: Context) {
        view.onChange = { if showsScroller != $0 { showsScroller = $0 } }
        view.apply()
    }

    final class Probe: NSView {
        var onChange: ((Bool) -> Void)?
        private var wheelMonitor: Any?
        private var styleObserver: NSObjectProtocol?
        private var wheelMouse = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                if event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
                    self.wheelMouse = !event.hasPreciseScrollingDeltas
                    self.apply()
                }
                return event
            }
            styleObserver = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in self?.apply() }
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func apply() {
            let visible = wheelMouse || NSScroller.preferredScrollerStyle == .legacy
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.onChange?(visible)
                guard let scrollView = self.enclosingScrollView else { return }
                scrollView.scrollerStyle = visible ? .legacy : .overlay
                scrollView.hasHorizontalScroller = visible
                scrollView.autohidesScrollers = true
            }
        }

        private func stopMonitoring() {
            if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }
            if let styleObserver { NotificationCenter.default.removeObserver(styleObserver) }
            wheelMonitor = nil
            styleObserver = nil
        }

        deinit { stopMonitoring() }
    }
}
