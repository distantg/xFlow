import AppKit
import SwiftUI
import WebKit

/// A real child browsing context preserves window.opener and the untouched draft.
@MainActor
final class ComposerPopupController: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    private let panel: NSPanel
    private let onClose: () -> Void
    private var isClosed = false
    private let status = ComposerPopupStatus()

    init(configuration: WKWebViewConfiguration, onClose: @escaping () -> Void) {
        self.onClose = onClose
        // The popup must not inherit the parent's dialog-only visibility script.
        let content = WKUserContentController()
        content.addUserScript(WKUserScript(
            source: WebColumnView.Coordinator.columnAppearanceScript(for: .mosaicIntegrated),
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
        content.addUserScript(WKUserScript(source: GrokComposerTheme.installScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        configuration.userContentController = content
        webView = WKWebView(frame: .zero, configuration: configuration)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 940, height: 650),
                        styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        panel.title = "Post tools"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ComposerPopupView(webView: webView, status: status, onRetry: { [weak self] in self?.webView.reload() }) { [weak self] in self?.close() })
    }

    func present(in parent: NSWindow) {
        panel.setContentSize(NSSize(width: min(940, parent.frame.width - 48), height: min(650, parent.frame.height - 80)))
        parent.beginSheet(panel)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        webView.stopLoading()
        panel.sheetParent?.endSheet(panel)
        panel.orderOut(nil)
        onClose()
    }

    func webViewDidClose(_ webView: WKWebView) { close() }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if action.targetFrame?.isMainFrame != false && TrustedURLPolicy.isTrustedComposerToolPage(url) {
            status.error = nil
            decisionHandler(.allow)
            return
        }
        switch WebColumnView.Coordinator.navigationDisposition(for: url,
                isMainFrame: action.targetFrame?.isMainFrame ?? true, navigationType: action.navigationType) {
        case .allowInWebView: decisionHandler(.allow)
        case .openExternally:
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        case .cancel:
            if action.targetFrame?.isMainFrame != false {
                status.error = "This page could not open in Post tools. You can return to your post without losing it."
            }
            decisionHandler(.cancel)
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { status.error = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { status.error = "Couldn't load this page. Check your connection and try again." }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { status.error = "Couldn't finish loading this page. Please try again." }
    }

}

private final class ComposerPopupStatus: ObservableObject {
    @Published var error: String?
}

private struct ComposerPopupView: View {
    let webView: WKWebView
    @ObservedObject var status: ComposerPopupStatus
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) { Label("Back to post", systemImage: "arrow.left") }
                    .buttonStyle(MosaicButtonStyle(kind: .quiet, cornerRadius: 12, compact: true))
                Spacer()
                Text("Post tools").font(.headline)
            }
            .padding(16)
            if let error = status.error {
                HStack {
                    Text(error).font(.callout)
                    Button("Try again", action: onRetry)
                        .buttonStyle(MosaicButtonStyle(kind: .quiet, cornerRadius: 12, compact: true))
                }.padding(16)
            }
            Divider()
            PopupWebView(webView: webView)
        }
        .background(.regularMaterial)
    }
}

private struct PopupWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
