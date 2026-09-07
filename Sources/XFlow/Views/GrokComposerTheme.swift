import Foundation

/// Give Grok the same single, multiline pill as Direct Messages, with a
/// dedicated glass layer that remains legible over a scrolling conversation.
enum GrokComposerTheme {
    static let css = """
    html [data-mosaic-grok-composer="true"] {
      position: relative !important;
      isolation: isolate !important;
      background: transparent !important;
      border: 1px solid var(--mosaic-accent-line) !important;
      border-radius: 26px !important;
      box-shadow: inset 0 1px 0 var(--mosaic-hairline), 0 8px 24px var(--mosaic-shadow) !important;
      backdrop-filter: none !important;
      -webkit-backdrop-filter: none !important;
    }
    html [data-mosaic-grok-composer="true"]::before {
      content: "" !important;
      position: absolute !important;
      inset: 0 !important;
      z-index: -1 !important;
      pointer-events: none !important;
      border-radius: inherit !important;
      background: rgba(30, 40, 39, 0.9) !important;
      -webkit-backdrop-filter: blur(32px) saturate(1.15) !important;
      backdrop-filter: blur(32px) saturate(1.15) !important;
    }
    html [data-mosaic-grok-composer="true"]:focus-within {
      border-color: var(--mosaic-accent) !important;
      box-shadow: 0 0 0 3px var(--mosaic-accent-soft) !important;
    }
    html [data-mosaic-grok-input-wrapper="true"],
    html [data-mosaic-grok-composer="true"] textarea,
    html [data-mosaic-grok-composer="true"] [role="textbox"],
    html [data-mosaic-grok-composer="true"] [contenteditable],
    html [data-mosaic-grok-composer="true"] input {
      background: transparent !important;
      border: 0 !important;
      border-radius: 0 !important;
      outline: none !important;
      box-shadow: none !important;
      -webkit-backdrop-filter: none !important;
      backdrop-filter: none !important;
      color: var(--mosaic-ink) !important;
      caret-color: var(--mosaic-accent) !important;
    }
    html [data-mosaic-grok-composer="true"] textarea::placeholder {
      color: var(--mosaic-secondary) !important;
    }
    @media (prefers-color-scheme: light) {
      html [data-mosaic-grok-composer="true"]::before {
        background: rgba(246, 243, 236, 0.94) !important;
      }
    }
    @media (prefers-reduced-transparency: reduce) {
      html [data-mosaic-grok-composer="true"]::before {
        background: rgb(30, 40, 39) !important;
        -webkit-backdrop-filter: none !important;
        backdrop-filter: none !important;
      }
    }
    @media (prefers-reduced-transparency: reduce) and (prefers-color-scheme: light) {
      html [data-mosaic-grok-composer="true"]::before {
        background: rgb(246, 243, 236) !important;
      }
    }
    """

    static var installScript: String {
        """
        (function() {
          \(markingScript)
          markGrokComposer();
          if (!window.__mosaicGrokComposerObserver && document.body) {
            window.__mosaicGrokComposerObserver = new MutationObserver(function() { markGrokComposer(); });
            window.__mosaicGrokComposerObserver.observe(document.body, { childList: true, subtree: true });
          }
        })();
        """
    }

    static let markingScript = #"""
    function markGrokComposer() {
      if (typeof window === 'undefined' || !window.location || typeof document.querySelector !== 'function') return;
      if (!/^\/i\/grok(?:\/|$)/.test(window.location.pathname)) return;
      const primary = document.body;
      if (!primary) return;
      primary.querySelectorAll('textarea, [role="textbox"], [contenteditable]:not([contenteditable="false"]), input[placeholder="Ask anything"]').forEach(editor => {
        // The first ancestor containing both the editor and its action controls
        // is the input shell, not the conversation or the entire bottom dock.
        let shell = editor.parentElement;
        while (shell && shell !== primary) {
          if (shell.querySelector('button, [role="button"], input[type="file"]')) break;
          shell = shell.parentElement;
        }
        if (!shell || shell === primary) return;
        shell.setAttribute('data-mosaic-grok-composer', 'true');
        for (let wrapper = editor.parentElement; wrapper && wrapper !== shell; wrapper = wrapper.parentElement) {
          wrapper.setAttribute('data-mosaic-grok-input-wrapper', 'true');
        }
      });
    }
    """#
}
