import SwiftUI
import WebKit

struct MediaLightboxView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let request: MediaRequest
    let accountID: UUID
    let onClose: () -> Void

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
                    .background(lightboxSurface)

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
    }

    @ViewBuilder
    private var lightboxBackdrop: some View {
        if request.kind == .image {
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
        if request.kind == .image, TrustedURLPolicy.isTrustedImageMediaURL(request.url) {
            let preferredURL = request.mediaURL.flatMap {
                TrustedURLPolicy.isTrustedImageMediaURL($0) ? $0 : nil
            } ?? request.url
            imageContent(
                preferredURL: preferredURL,
                fallbackURL: request.url
            )
        } else if request.kind == .video {
            if let directSource = inlineVideoSourceURL {
                InlineVideoPlayerWebView(
                    videoURL: directSource,
                    startTime: request.currentTime ?? 0
                )
            } else {
                WebColumnView(
                    url: mediaPlaybackURL,
                    refreshKey: "media-lightbox-\(request.id.uuidString)",
                    accountID: accountID,
                    filter: .none,
                    enableChromeStripping: false,
                    enableMediaCapture: true,
                    enableHandleDetection: false,
                    onPageReadyScript: videoSeekScript(startTime: request.currentTime ?? 0),
                    routeHorizontalScrollToParent: false
                )
            }
        } else {
            WebColumnView(
                url: request.url,
                refreshKey: "media-lightbox-\(request.id.uuidString)",
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
        if isLikelyXRoute(request.url) {
            return request.url
        }
        if let mediaURL = request.mediaURL, isLikelyXRoute(mediaURL) {
            return mediaURL
        }
        return request.url
    }

    private var inlineVideoSourceURL: URL? {
        if let mediaURL = request.mediaURL, TrustedURLPolicy.isTrustedVideoMediaURL(mediaURL) {
            return mediaURL
        }
        if isDirectMediaURL(request.url) {
            return request.url
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
