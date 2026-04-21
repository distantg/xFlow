import SwiftUI
import WebKit

struct MediaLightboxView: View {
    @Environment(\.colorScheme) private var colorScheme

    let request: MediaRequest
    let accountID: UUID
    let onClose: () -> Void

    @State private var showClose = false
    @State private var didAppear = false

    var body: some View {
        ZStack {
            lightboxBackdrop
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            ZStack(alignment: .topTrailing) {
                content
                    .background(lightboxSurface)

                if showClose {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.55))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: 1160, maxHeight: 780)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 30, x: 0, y: 16)
            .padding(34)
            .scaleEffect(didAppear ? 1 : 0.92)
            .opacity(didAppear ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    didAppear = true
                }
            }
            .onHover { hovering in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                    showClose = hovering
                }
            }
        }
    }

    private var lightboxBackdrop: some View {
        Color.black.opacity(colorScheme == .dark ? 0.2 : 0.12)
    }

    private var lightboxSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.1 : 0.16),
                    Color.white.opacity(colorScheme == .dark ? 0.04 : 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if request.kind == .image, isHTTPURL(request.url) {
            imageContent(url: request.url)
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
                    enableMediaCapture: false,
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
    private func imageContent(url: URL) -> some View {
        GeometryReader { proxy in
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                case .failure:
                    Color.black.opacity(0.55)
                        .overlay(
                            Text("Could not load image")
                                .foregroundStyle(.white.opacity(0.9))
                        )
                default:
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.45))
                }
            }
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
        if let mediaURL = request.mediaURL, isHTTPURL(mediaURL) {
            return mediaURL
        }
        if isDirectMediaURL(request.url) {
            return request.url
        }
        return nil
    }

    private func videoSeekScript(startTime: Double) -> String {
        let clamped = max(0, startTime)
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

    private func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    private func isLikelyXRoute(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }
        return host.contains("x.com") || host.contains("twitter.com")
    }

    private func isDirectMediaURL(_ url: URL) -> Bool {
        guard isHTTPURL(url), let host = url.host?.lowercased() else {
            return false
        }
        if host.contains("video.twimg.com") || host.contains("pbs.twimg.com") {
            return true
        }
        let path = url.path.lowercased()
        return path.hasSuffix(".m3u8") || path.hasSuffix(".mp4") || path.hasSuffix(".mov")
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
        configuration.mediaTypesRequiringUserActionForPlayback = []

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
        let escapedURL = videoURL.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let clamped = max(0, startTime)
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width,initial-scale=1" />
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
