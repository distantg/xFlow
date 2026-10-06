import Foundation

/// X Chat renders its route and overlays in separate shadow roots. Keep their
/// styles local, while inheriting Mosaic's appearance variables from the page.
enum DirectMessageThemeBridge {
    static var installScript: String {
        let cssLiteral = String(decoding: try! JSONEncoder().encode(DirectMessageTheme.css), as: UTF8.self)
        return """
        (() => {
          const hostSelectors = ['[data-testid="xchatEmbedRoute"]', '[data-testid="xchatEmbedOverlays"]'];
          const hostSelector = hostSelectors.join(', ');
          const isChatRoute = () => /^\\/(?:messages|i\\/chat)(?:\\/|$)/.test(
            globalThis.location ? globalThis.location.pathname : ''
          );
          const existing = globalThis.__mosaicDirectMessageThemeBridge;
          const hasChatHost = typeof document.querySelector === 'function' && document.querySelector(hostSelector);
          if (!isChatRoute() && !hasChatHost) {
            if (existing) existing.stop();
            delete globalThis.__mosaicDirectMessageThemeBridge;
            return 'inactive-direct-messages';
          }
          const css = \(cssLiteral);
          if (existing) {
            existing.refresh(css);
            return 'mosaic-direct-messages';
          }
          if (typeof document.querySelector !== 'function' || typeof MutationObserver === 'undefined') return;

          const styleID = 'mosaic-direct-message-shadow-style';
          const hosts = new Map();
          let currentCSS = css;
          let discoveryTimer = 0;
          let pendingRootTimer = 0;
          let stopped = false;

          function removeHost(host, entry) {
            if (entry.observer) entry.observer.disconnect();
            if (entry.style) entry.style.remove();
            hosts.delete(host);
          }

          function pruneDisconnectedHosts() {
            let removed = false;
            hosts.forEach((entry, host) => {
              if (!host.isConnected || host.ownerDocument !== document) {
                removeHost(host, entry);
                removed = true;
              }
            });
            return removed;
          }

          function ensureStyle(host, entry) {
            const root = host.shadowRoot;
            if (!root) return;
            if (!entry.style || entry.style.parentNode !== root) {
              const style = root.getElementById(styleID) || document.createElement('style');
              style.id = styleID;
              entry.style = style;
              if (style.parentNode !== root) root.appendChild(style);
            }
            if (entry.style.textContent !== currentCSS) entry.style.textContent = currentCSS;
            if (!entry.observer) {
              // Watch only the shadow root's direct children for style removal.
              // Message rows and their virtualized descendants are never observed.
              entry.observer = new MutationObserver(() => {
                if (stopped) return;
                if (!host.isConnected) {
                  removeHost(host, entry);
                  updatePendingRootTimer();
                  return;
                }
                ensureStyle(host, entry);
                updatePendingRootTimer();
              });
              entry.observer.observe(root, { childList: true });
            }
          }

          function updatePendingRootTimer() {
            const hasPendingStyle = Array.from(hosts).some(([host, entry]) =>
              !host.shadowRoot || !entry.style || entry.style.parentNode !== host.shadowRoot
            );
            if (!hasPendingStyle && pendingRootTimer) {
              clearInterval(pendingRootTimer);
              pendingRootTimer = 0;
            } else if (hasPendingStyle && !pendingRootTimer && !stopped) {
              // attachShadow does not emit a DOM mutation. Retry only the at most
              // two known hosts until their styles are installed. A root appearing
              // between document mutations must not cancel its pending injection.
              pendingRootTimer = setInterval(() => {
                if (stopped) return;
                pruneDisconnectedHosts();
                hosts.forEach((entry, host) => ensureStyle(host, entry));
                updatePendingRootTimer();
              }, 250);
            }
          }

          function discover() {
            if (stopped) return;
            const activeHosts = new Set(hostSelectors.map(selector => document.querySelector(selector)).filter(Boolean));
            if (activeHosts.size === 0 && !isChatRoute()) {
              // SPA navigation can change the URL before removing its old hosts.
              // Finish cleanup when that later DOM removal reaches discovery.
              globalThis.__mosaicDirectMessageThemeBridge.stop();
              delete globalThis.__mosaicDirectMessageThemeBridge;
              return;
            }
            hosts.forEach((entry, host) => {
              if (!activeHosts.has(host)) removeHost(host, entry);
            });
            activeHosts.forEach(host => {
              let entry = hosts.get(host);
              if (!entry) {
                entry = { style: null, observer: null };
                hosts.set(host, entry);
              }
              ensureStyle(host, entry);
            });
            updatePendingRootTimer();
          }

          function scheduleDiscovery() {
            if (discoveryTimer || stopped) return;
            discoveryTimer = setTimeout(() => {
              discoveryTimer = 0;
              discover();
            }, 0);
          }

          const documentObserver = new MutationObserver(records => {
            if (stopped) return;
            const removedHost = pruneDisconnectedHosts();
            updatePendingRootTimer();
            const hasHostChange = records.some(record => {
              if (record.type === 'attributes') {
                return hosts.has(record.target) || record.target.matches(hostSelector);
              }
              return Array.from(record.addedNodes).some(node => node.nodeType === 1 &&
                (node.matches(hostSelector) || node.querySelector(hostSelector)));
            });
            if (removedHost || hasHostChange) scheduleDiscovery();
          });
          // KVO may activate the theme before parsing/hydration replaces <html>.
          // Observe its stable Document owner so later Chat hosts are still found.
          documentObserver.observe(document, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['data-testid']
          });

          globalThis.__mosaicDirectMessageThemeBridge = {
            refresh(nextCSS) {
              if (stopped) return;
              currentCSS = nextCSS;
              discover();
            },
            stop() {
              stopped = true;
              documentObserver.disconnect();
              if (discoveryTimer) clearTimeout(discoveryTimer);
              if (pendingRootTimer) clearInterval(pendingRootTimer);
              discoveryTimer = 0;
              pendingRootTimer = 0;
              hosts.forEach((entry, host) => removeHost(host, entry));
            }
          };
          discover();
          return 'mosaic-direct-messages';
        })();
        """
    }

    static let removeScript = """
    (() => {
      const bridge = globalThis.__mosaicDirectMessageThemeBridge;
      if (bridge) bridge.stop();
      delete globalThis.__mosaicDirectMessageThemeBridge;
      return 'original-x-direct-messages';
    })();
    """
}
