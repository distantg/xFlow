import Foundation

/// Content supplied by a trusted X notification row, never inferred from a badge alone.
struct NotificationActivity: Equatable {
    let title: String
    let body: String
    let targetURL: URL?

    init?(payload: [String: Any]) {
        let title = Self.clean(payload["title"] as? String, limit: 120)
        let body = Self.clean(payload["body"] as? String, limit: 400)
        guard !title.isEmpty else { return nil }
        self.title = title
        self.body = body
        self.targetURL = Self.validatedTargetURL(payload["url"] as? String)
    }

    static func validatedTargetURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw),
              url.scheme == "https", ["x.com", "www.x.com", "twitter.com", "www.twitter.com"].contains(url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil,
              url.path.range(of: #"^/[A-Za-z0-9_]{1,15}/status/[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "https://x.com" + url.path)
    }

    static func clean(_ value: String?, limit: Int) -> String {
        let clean = (value ?? "").components(separatedBy: .controlCharacters).joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return clean.count > limit ? String(clean.prefix(limit - 1)) + "…" : clean
    }
}

/// Separate from WebColumnView so notification extraction can be exercised without WebKit.
enum NotificationActivityScript {
    static let source = #"""
    (function() {
      if (window.__xflowUnreadCountInstalled) return;
      window.__xflowUnreadCountInstalled = true;
      const clean = value => String(value || '').replace(/\s+/g, ' ').trim();
      const spacedText = node => node.nodeType === 3 ? node.nodeValue : Array.from(node.childNodes || []).map(spacedText).join(' ');
      const count = () => Number((document.title.match(/^\((\d+)\)/) || [0, 0])[1]);
      const onRoute = () => /^\/notifications(?:\/|$)/.test(location.pathname);
      const send = (value, activity, baseline = false) => {
        try { window.webkit.messageHandlers.xflowUnreadCount.postMessage({count: value, activity, baseline}); } catch (_) {}
      };
      function rows() {
        // Never read generic timeline cells: they may be recommendations or unrelated posts.
        return Array.from(document.querySelectorAll('[data-testid="notification"], article[data-testid="tweet"]'))
          .filter(row => !row.parentElement || !row.parentElement.closest('[data-testid="notification"], article[data-testid="tweet"]'))
          .slice(0, 30).map(row => {
          const tweet = row.querySelector('[data-testid="tweetText"]');
          const body = clean(tweet && tweet.innerText);
          const link = row.querySelector('a[href*="/status/"]');
          const url = link ? link.href : '';
          const copy = row.cloneNode(true);
          copy.querySelectorAll('[data-testid="tweetText"], time, button, [role="button"]').forEach(n => n.remove());
          const authorNode = row.querySelector('[data-testid="User-Name"]');
          const author = clean(authorNode && authorNode.innerText.split('\n')[0]);
          const isPost = row.matches && row.matches('article[data-testid="tweet"]');
          const title = isPost ? (author ? 'Post from ' + author : 'New post') : clean(copy.innerText || spacedText(copy) || copy.textContent);
          const text = clean(row.innerText);
          return {key: title + '\n' + body + '\n' + url, url, title: (title || text).slice(0, 120), body: body.slice(0, 400)};
        }).filter(row => row.title);
      }
      let previous = null;
      let seen = new Set();
      let pending = null;
      let recent = [];
      function check() {
        if (!onRoute()) { previous = null; seen.clear(); pending = null; recent = []; return; }
        const current = count();
        const items = rows();
        if (previous === null) {
          previous = current;
          items.forEach(row => seen.add(row.key));
          send(current, null, true); // Baseline: opening the app must not alert on old unread items.
          return;
        }
        if (current < previous) {
          pending = null;
          recent = [];
          send(current, null); // Reset native state after reading, including count zero.
        } else if (current > previous) {
          pending = {count: current, deadline: Date.now() + 7000};
        }
        previous = current;
        recent = recent.filter(row => Date.now() - row.observedAt < 10000);
        items.filter(row => !seen.has(row.key)).forEach(row => recent.push({...row, observedAt: Date.now()}));
        if (pending) {
          const fresh = recent[0];
          if (fresh || Date.now() >= pending.deadline) {
            send(pending.count, fresh ? {title: fresh.title, body: fresh.body, url: fresh.url} : null);
            pending = null;
            recent = [];
          }
        }
        items.forEach(row => seen.add(row.key));
        if (seen.size > 500) seen = new Set(Array.from(seen).slice(-250));
      }
      check();
      setInterval(check, 1500);
      document.addEventListener('visibilitychange', check);
    })();
    """#
}
