import Foundation

/// Scoped to X's chat components so timeline surfaces and native chat behavior
/// remain unchanged. CSS also covers rows inserted by X's virtualized list.
enum DirectMessageTheme {
    static let css = """
    [data-testid="primaryColumn"] [data-testid="dm-container"] {
      --chat-accent: var(--mosaic-accent);
      --mosaic-dm-timestamp: rgb(224, 221, 214);
      --mosaic-dm-date-surface: rgba(45, 47, 44, 0.72);
      --mosaic-dm-incoming: rgba(255, 255, 255, 0.075);
      --mosaic-dm-outgoing: rgba(231, 216, 190, 0.19);
    }

    [data-testid="primaryColumn"] [data-testid="dm-inbox-panel"] {
      min-width: 0 !important;
    }

    /* Replace the stacked black fades with one continuous Mosaic surface. */
    [data-testid="primaryColumn"] [data-testid="dm-conversation-header"] {
      background: var(--mosaic-tab-surface) !important;
      box-shadow: inset 0 -1px 0 var(--mosaic-hairline) !important;
    }
    [data-testid="primaryColumn"] [data-testid="dm-conversation-header"] .pointer-events-none,
    [data-testid="primaryColumn"] [data-testid="dm-conversation-content"] > .pointer-events-none {
      background: transparent !important;
      background-image: none !important;
      backdrop-filter: none !important;
      -webkit-backdrop-filter: none !important;
      mask-image: none !important;
      -webkit-mask-image: none !important;
    }
    [data-testid="primaryColumn"] [data-testid="dm-composer-container"] {
      background: var(--mosaic-tab-surface) !important;
      box-shadow: inset 0 1px 0 var(--mosaic-hairline) !important;
    }

    /* Keep X's message grouping, timestamps, reactions and action hit targets. */
    [data-testid="primaryColumn"] [data-testid="dm-message-list"] [data-testid^="message-text-"] {
      background: var(--mosaic-dm-incoming) !important;
      color: var(--mosaic-ink) !important;
      border-radius: 19px 19px 19px 6px !important;
      box-shadow: inset 0 0 0 1px var(--mosaic-hairline) !important;
    }
    [data-testid="primaryColumn"] [data-testid="dm-message-list"] [data-testid^="message-"].justify-end [data-testid^="message-text-"] {
      background: var(--mosaic-dm-outgoing) !important;
      border-radius: 19px 19px 6px 19px !important;
      box-shadow: inset 0 0 0 1px var(--mosaic-accent-line) !important;
    }
    [data-testid="primaryColumn"] [data-testid="dm-message-list"] [data-testid^="message-text-"] * {
      color: var(--mosaic-ink) !important;
    }
    [data-testid="primaryColumn"] [data-testid="dm-message-list"] [data-testid^="message-text-"] a {
      color: var(--mosaic-accent) !important;
      text-decoration: underline;
      text-underline-offset: 2px;
    }
    [data-testid="primaryColumn"] [data-testid="dm-message-list"] .rounded-chat:not([data-testid^="message-text-"]) {
      background-color: var(--mosaic-dm-incoming) !important;
      border-color: var(--mosaic-hairline) !important;
      border-radius: 18px !important;
    }

    /* X wraps the floating date in its own pill. Let only the text label
       own the glass surface, avoiding nested outlines and double blur. */
    [data-testid="primaryColumn"] [data-testid="dm-conversation-content"] .rounded-full:has(.text-gray-600.text-subtext2),
    [data-testid="primaryColumn"] [data-testid="dm-conversation-content"] div:has(> .text-gray-600.text-subtext2) {
      background: transparent !important;
      border-color: transparent !important;
      outline: none !important;
      box-shadow: none !important;
      backdrop-filter: none !important;
      -webkit-backdrop-filter: none !important;
    }
    [data-testid="primaryColumn"] [data-testid="dm-conversation-content"] .text-gray-600.text-subtext2 {
      color: var(--mosaic-dm-timestamp) !important;
      background: transparent !important;
      position: relative !important;
      isolation: isolate;
      border-radius: 999px !important;
      border: 0 !important;
      outline: none !important;
      box-shadow: none !important;
      padding: 0 !important;
      font-weight: 600 !important;
      opacity: 1 !important;
    }
    /* Paint the glass outside the label without changing the row height that
       X's virtualized scroller measures and uses for its scroll offsets. */
    [data-testid="primaryColumn"] [data-testid="dm-conversation-content"] .text-gray-600.text-subtext2::before {
      content: "";
      position: absolute;
      inset: -3px -10px;
      z-index: -1;
      pointer-events: none;
      border-radius: 999px;
      background: var(--mosaic-dm-date-surface) !important;
      box-shadow: inset 0 0 0 1px var(--mosaic-hairline), 0 2px 8px var(--mosaic-shadow);
      backdrop-filter: blur(18px) saturate(1.15);
      -webkit-backdrop-filter: blur(18px) saturate(1.15);
    }
    [data-testid="primaryColumn"] [data-testid="dm-message-list"] .align-end .text-subtext3,
    [data-testid="primaryColumn"] [data-testid="dm-message-list"] [data-testid^="message-text-"] .text-subtext3 {
      color: var(--mosaic-dm-timestamp) !important;
      font-weight: 500 !important;
      opacity: 1 !important;
    }

    /* One pill and one focus ring, including multiline input and voice controls. */
    [data-testid="primaryColumn"] [data-testid="dm-composer-input-container"],
    [data-testid="primaryColumn"] [data-testid="dm-search-bar"] {
      background: var(--mosaic-inset) !important;
      border: 1px solid var(--mosaic-accent-line) !important;
      border-radius: 26px !important;
      box-shadow: inset 0 1px 0 var(--mosaic-hairline) !important;
    }
    [data-testid="primaryColumn"] [data-testid="dm-composer-input-container"]:focus-within,
    [data-testid="primaryColumn"] [data-testid="dm-search-bar"]:focus-within {
      border-color: var(--mosaic-accent) !important;
      box-shadow: 0 0 0 3px var(--mosaic-accent-soft) !important;
    }
    [data-testid="primaryColumn"] [data-testid="dm-composer-textarea"],
    [data-testid="primaryColumn"] [data-testid="dm-composer-textarea"]:focus,
    [data-testid="primaryColumn"] [data-testid="dm-composer-textarea"]:focus-visible {
      background: transparent !important;
      color: var(--mosaic-ink) !important;
      border: 0 !important;
      border-radius: 0 !important;
      outline: none !important;
      box-shadow: none !important;
      caret-color: var(--mosaic-accent) !important;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
    }
    [data-testid="primaryColumn"] [data-testid="dm-composer-textarea"]::placeholder {
      color: var(--mosaic-secondary) !important;
    }
    [data-testid="primaryColumn"] [data-testid="dm-composer-container"] button,
    [data-testid="primaryColumn"] [data-testid="dm-conversation-header"] button {
      color: var(--mosaic-accent) !important;
      border-radius: 999px !important;
    }
    [data-testid="primaryColumn"] [data-testid="dm-composer-container"] button:hover,
    [data-testid="primaryColumn"] [data-testid="dm-conversation-header"] button:hover {
      background: var(--mosaic-accent-soft) !important;
    }
    @media (prefers-color-scheme: light) {
      [data-testid="primaryColumn"] [data-testid="dm-container"] {
        --mosaic-dm-timestamp: rgb(76, 70, 61);
        --mosaic-dm-date-surface: rgba(248, 246, 240, 0.72);
        --mosaic-dm-incoming: rgba(35, 45, 52, 0.065);
        --mosaic-dm-outgoing: rgba(157, 126, 79, 0.16);
      }
    }
    @media (prefers-reduced-transparency: reduce) {
      [data-testid="primaryColumn"] [data-testid="dm-container"] {
        --mosaic-dm-date-surface: rgb(55, 56, 53);
        --mosaic-dm-incoming: rgb(52, 54, 55);
        --mosaic-dm-outgoing: rgb(80, 73, 61);
      }
    }
    @media (prefers-reduced-transparency: reduce) and (prefers-color-scheme: light) {
      [data-testid="primaryColumn"] [data-testid="dm-container"] {
        --mosaic-dm-date-surface: rgb(240, 237, 230);
        --mosaic-dm-incoming: rgb(232, 233, 232);
        --mosaic-dm-outgoing: rgb(232, 221, 202);
      }
    }
    """
}
