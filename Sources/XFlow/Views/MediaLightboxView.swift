import SwiftUI
import WebKit

struct MediaLightboxView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let request: MediaRequest
    let accountID: UUID
    let onClose: () -> Void

    @State private var selectedIndex: Int
    @State private var keyMonitor: Any?

    init(request: MediaRequest, accountID: UUID, onClose: @escaping () -> Void) {
        self.request = request
        self.accountID = accountID
        self.onClose = onClose
        _selectedIndex = State(initialValue: request.selectedIndex)
    }

    private var activeItem: MediaRequest {
        request.items.indices.contains(selectedIndex) ? request.items[selectedIndex] : request
    }

    private func navigate(_ offset: Int) {
        let next = selectedIndex + offset
        guard request.items.indices.contains(next) else { return }
        selectedIndex = next
    }

    @State private var showClose = false
    @State private var didAppear = false

    var body: some View {
        ZStack {
            lightboxBackdrop
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    onClose()
                }

            ZStack(alignment: .topTrailing) {
                content
                    .id(activeItem.id)
                    .background(lightboxSurface)

                if request.items.count > 1 {
                    HStack {
                        navigationButton(offset: -1, symbol: "chevron.left", label: "Previous media")
                        Spacer()
                        navigationButton(offset: 1, symbol: "chevron.right", label: "Next media")
                    }
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity)
                }

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MosaicTheme.primaryText(for: colorScheme))
                }
                .buttonStyle(MosaicIconButtonStyle(size: 34, prominent: showClose))
                .opacity(showClose ? 1 : 0.72)
                .padding(12)
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }
            .frame(maxWidth: 1160, maxHeight: 780)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(34)
            .scaleEffect(didAppear || reduceMotion ? 1 : 0.94)
            .opacity(didAppear ? 1 : 0)
            .onAppear {
                withAnimation(MosaicMotion.expressive(reduceMotion: reduceMotion)) {
                    didAppear = true
                }
            }
            .onHover { hovering in
                withAnimation(MosaicMotion.micro(reduceMotion: reduceMotion)) {
                    showClose = hovering
                }
            }
        }
        .onAppear {
            guard request.items.count > 1, keyMonitor == nil else { return }
            let window = NSApp.keyWindow
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.window === window,
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
                if event.keyCode == 123 { navigate(-1); return nil }
                if event.keyCode == 124 { navigate(1); return nil }
                return event
            }
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    private func navigationButton(offset: Int, symbol: String, label: String) -> some View {
        Button { navigate(offset) } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MosaicTheme.primaryText(for: colorScheme))
        }
        .buttonStyle(MosaicIconButtonStyle(size: 40, prominent: true))
        .disabled(!request.items.indices.contains(selectedIndex + offset))
        .accessibilityLabel(label)
        .help(label)
    }

    @ViewBuilder
    private var lightboxBackdrop: some View {
        if activeItem.kind == .image {
            MosaicModalBackdrop()
        } else {
            Color.black.opacity(colorScheme == .dark ? 0.48 : 0.25)
        }
    }

    private var lightboxSurface: some View {
        MosaicSurface(level: .overlay, cornerRadius: MosaicTheme.Radius.panel)
    }

    @ViewBuilder
    private var content: some View {
        if activeItem.kind == .image, TrustedURLPolicy.isTrustedImageMediaURL(activeItem.url) {
            let preferredURL = activeItem.mediaURL.flatMap {
                TrustedURLPolicy.isTrustedImageMediaURL($0) ? $0 : nil
            } ?? activeItem.url
            imageContent(
                preferredURL: preferredURL,
                fallbackURL: activeItem.url
            )
        } else if activeItem.kind == .video {
            if let directSource = inlineVideoSourceURL {
                InlineVideoPlayerWebView(
                    videoURL: directSource,
                    startTime: activeItem.currentTime ?? 0
                )
            } else {
                WebColumnView(
                    url: mediaPlaybackURL,
                    refreshKey: "media-lightbox-\(activeItem.id.uuidString)",
                    accountID: accountID,
                    filter: .none,
                    enableChromeStripping: false,
                    enableMediaCapture: true,
                    enableHandleDetection: false,
                    onPageReadyScript: videoSeekScript(startTime: activeItem.currentTime ?? 0),
                    routeHorizontalScrollToParent: false
                )
            }
        } else {
            WebColumnView(
                url: activeItem.url,
                refreshKey: "media-lightbox-\(activeItem.id.uuidString)",
                accountID: accountID,
                filter: .none,
                enableChromeStripping: false,
                enableMediaCapture: false,
                enableHandleDetection: false,
                routeHorizontalScrollToParent: false
            )
        }
    }

    @ViewBuilder
    private func imageContent(preferredURL: URL, fallbackURL: URL) -> some View {
        GeometryReader { proxy in
            FallbackRemoteImageView(
                preferredURL: preferredURL,
                fallbackURL: fallbackURL
            )
            .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
        }
    }

    private var mediaPlaybackURL: URL {
        if isLikelyXRoute(activeItem.url) {
            return activeItem.url
        }
        if let mediaURL = activeItem.mediaURL, isLikelyXRoute(mediaURL) {
            return mediaURL
        }
        return activeItem.url
    }

    private var inlineVideoSourceURL: URL? {
        if let mediaURL = activeItem.mediaURL, TrustedURLPolicy.isTrustedVideoMediaURL(mediaURL) {
            return mediaURL
        }
        if isDirectMediaURL(activeItem.url) {
            return activeItem.url
        }
        return nil
    }

    private func videoSeekScript(startTime: Double) -> String {
        let clamped = startTime.isFinite ? min(max(0, startTime), 24 * 60 * 60) : 0
        return """
        (function() {
          const target = \(clamped);
          let attempts = 0;
          const timer = setInterval(function() {
            const video = document.querySelector('video');
            if (video) {
              try {
                if (Number.isFinite(target) && target > 0) {
                  video.currentTime = target;
                }
                if (video.play) {
                  video.play().catch(function() {});
                }
              } catch (_) {}
              clearInterval(timer);
              return;
            }
            attempts += 1;
            if (attempts > 200) {
              clearInterval(timer);
            }
          }, 120);
        })();
        """
    }

    private func isLikelyXRoute(_ url: URL) -> Bool {
        TrustedURLPolicy.isTrustedXPage(url)
    }

    private func isDirectMediaURL(_ url: URL) -> Bool {
        TrustedURLPolicy.isTrustedVideoMediaURL(url)
    }
}

private struct FallbackRemoteImageView: View {
    let preferredURL: URL
    let fallbackURL: URL

    @State private var loaded: ExpandedImagePayload?
    @State private var failed = false

    var body: some View {
        Group {
            if let loaded {
                ExpandedImageView(payload: loaded)
            } else if failed {
                Color.black.opacity(0.55)
                    .overlay(Text("Could not load image").foregroundStyle(.white.opacity(0.9)))
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.45))
            }
        }
        .task(id: preferredURL) {
            loaded = nil
            failed = false
            for url in preferredURL == fallbackURL ? [preferredURL] : [preferredURL, fallbackURL] {
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    try Task.checkCancellation()
                    guard let response = response as? HTTPURLResponse,
                          (200..<300).contains(response.statusCode),
                          let payload = ExpandedImagePayload(data: data, url: url) else { continue }
                    loaded = payload
                    return
                } catch {
                    if Task.isCancelled { return }
                }
            }
            failed = true
        }
    }
}

private struct InlineVideoPlayerWebView: NSViewRepresentable {
    let videoURL: URL
    let startTime: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(signature: signature)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.signature != signature {
            context.coordinator.signature = signature
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    final class Coordinator {
        var signature: String
        weak var webView: WKWebView?

        init(signature: String) {
            self.signature = signature
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        haltPlayback(in: nsView)
        coordinator.webView = nil
    }

    private var signature: String {
        "\(videoURL.absoluteString)|\(Int(startTime * 1000))"
    }

    private static func haltPlayback(in webView: WKWebView) {
        webView.evaluateJavaScript("""
        (function() {
          document.querySelectorAll('video, audio').forEach(function(node) {
            try {
              node.pause && node.pause();
              node.removeAttribute('src');
              node.load && node.load();
            } catch (_) {}
          });
        })();
        """)
        webView.stopLoading()
        webView.loadHTMLString("<html><body style='background:black;'></body></html>", baseURL: nil)
    }

    private var html: String {
        let escapedURL = HTMLEncoding.attributeValue(videoURL.absoluteString)
        let clamped = startTime.isFinite ? min(max(0, startTime), 24 * 60 * 60) : 0
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width,initial-scale=1" />
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; media-src https://video.twimg.com; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'" />
          <style>
            html, body { margin:0; padding:0; width:100%; height:100%; background:#000; overflow:hidden; }
            #wrap { width:100%; height:100%; display:flex; align-items:center; justify-content:center; background:#000; }
            video { width:100%; height:100%; object-fit:contain; background:#000; }
          </style>
        </head>
        <body>
          <div id="wrap">
            <video id="xflow-video" controls playsinline autoplay src='\(escapedURL)'></video>
          </div>
          <script>
            (function() {
              const target = \(clamped);
              const player = document.getElementById('xflow-video');
              if (!player) return;

              player.addEventListener('loadedmetadata', function() {
                try {
                  if (Number.isFinite(target) && target > 0) {
                    player.currentTime = target;
                  }
                } catch (_) {}
                player.play && player.play().catch(function() {});
              });
            })();
          </script>
        </body>
        </html>
        """
    }
}
