import Foundation

/// Shared by the legacy document layout and X Chat's isolated shadow roots.
/// Only paint changes: X keeps its controls, message nodes and virtual row sizes.
enum DirectMessageTheme {
    static let css = """
    :host, [data-testid="dm-container"] {
      --chat-accent: var(--mosaic-accent);
      --mosaic-dm-timestamp: rgb(224, 221, 214);
      --mosaic-dm-date-surface: rgba(45, 47, 44, 0.72);
      --mosaic-dm-incoming: rgba(255, 255, 255, 0.075);
      --mosaic-dm-outgoing: rgba(231, 216, 190, 0.19);
    }

    /* X Chat now mounts under xchatEmbedRoute, outside the document cascade.
       Clear its canvas, not every descendant: badges, avatars and media retain
       their own backgrounds and native states. No blur/compositing per row. */
    :host > .bg-background,
    [data-testid="dm-container"],
    [data-testid="dm-container"] .bg-background {
      background: transparent !important;
      color: var(--mosaic-ink) !important;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
    }
    :host .font-chirp,
    [data-testid="dm-container"] .font-chirp,
    [data-testid="dm-container"] :is(button, input, textarea) {
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
    }
    :host :is(.text-primary, .text-text),
    [data-testid="dm-container"] :is(.text-primary, .text-text) {
      color: var(--mosaic-ink) !important;
    }
    :host :is(.text-secondary, .text-tertiary),
    [data-testid="dm-container"] :is(.text-secondary, .text-tertiary) {
      color: var(--mosaic-secondary) !important;
    }
    [data-testid="dm-container"] [data-testid="dm-inbox-panel"] {
      min-width: 0 !important;
      border-color: var(--mosaic-hairline) !important;
    }
    [data-testid="dm-container"] [data-testid="dm-inbox-header"] {
      background: var(--mosaic-surface) !important;
      box-shadow: inset 0 -1px 0 var(--mosaic-hairline) !important;
    }
    [data-testid="dm-container"] [data-testid="dm-inbox-title"] {
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Rounded", sans-serif !important;
      letter-spacing: -0.02em !important;
      color: var(--mosaic-ink) !important;
    }
    [data-testid="dm-container"] :is([data-testid="dm-inbox-dropdown-trigger"], [data-testid="dm-new-chat-button"]) {
      color: var(--mosaic-accent) !important;
      background: var(--mosaic-accent-soft) !important;
      border-color: var(--mosaic-accent-line) !important;
      border-radius: 12px !important;
      box-shadow: inset 0 0 0 1px var(--mosaic-accent-line) !important;
    }
    [data-testid="dm-container"] :is([data-testid="dm-inbox-dropdown-trigger"], [data-testid="dm-new-chat-button"]):is(:hover, [aria-expanded="true"]) {
      background: var(--mosaic-surface-hover) !important;
    }
    /* Match feed dividers on the full-width row without changing the dimensions
       measured by X's virtualizer. Paint hover and selection on this same row. */
    [data-testid="dm-container"] [data-testid^="dm-conversation-item-"] {
      /* X's entrance animation can stay at opacity zero in a restored column.
         Rows are already laid out and interactive; paint them immediately. */
      opacity: 1 !important;
      border-radius: 0 !important;
      background: transparent !important;
      box-shadow: inset 0 -1px 0 var(--mosaic-hairline) !important;
    }
    [data-testid="dm-container"] [data-testid^="dm-conversation-item-"] [role="option"],
    [data-testid="dm-container"] [data-testid^="dm-conversation-item-"] [role="option"] > div {
      border-radius: 0 !important;
      background: transparent !important;
      box-shadow: none !important;
    }
    [data-testid="dm-container"] [data-testid^="dm-conversation-item-"]:hover {
      background: var(--mosaic-surface-hover) !important;
    }
    [data-testid="dm-container"] [data-testid^="dm-conversation-item-"]:has([role="option"][aria-selected="true"]) {
      background: var(--mosaic-accent-soft) !important;
    }
    [data-testid="dm-container"] :is(button, a, [role="option"], [role="button"]):focus-visible {
      outline: 2px solid var(--mosaic-accent-line) !important;
      outline-offset: -2px !important;
    }
    /* The search test ID wraps the control plus its outer spacing. Paint the
       actual input so the icon/clear action stay inside one inset field. */
    [data-testid="dm-container"] [data-testid="dm-search-input"] {
      background: var(--mosaic-inset) !important;
      color: var(--mosaic-ink) !important;
      border-color: var(--mosaic-hairline) !important;
      border-radius: 12px !important;
      box-shadow: inset 0 1px 0 var(--mosaic-hairline) !important;
      caret-color: var(--mosaic-accent) !important;
    }
    [data-testid="dm-container"] [data-testid="dm-search-input"]:focus {
      border-color: var(--mosaic-accent-line) !important;
      box-shadow: 0 0 0 3px var(--mosaic-accent-soft) !important;
      outline: none !important;
    }
    [data-testid="dm-container"] [data-testid="dm-search-input"]::placeholder {
      color: var(--mosaic-secondary) !important;
    }
    /* Chat portals live in a second named shadow root. Keep its menus and
       dialogs legible, including request filters and the new-message flow. */
    :host :is([role="menu"], [role="dialog"], [role="listbox"]):not([data-testid="dm-container"] *) {
      color: var(--mosaic-ink) !important;
      background: var(--mosaic-tab-surface) !important;
      border-color: var(--mosaic-accent-line) !important;
      border-radius: 16px !important;
      box-shadow: 0 12px 32px var(--mosaic-shadow), inset 0 0 0 1px var(--mosaic-hairline) !important;
    }
    :host [role="menuitem"]:is(:hover, :focus, [data-highlighted]) {
      background: var(--mosaic-accent-soft) !important;
    }

    /* Replace the stacked black fades with one continuous Mosaic surface. */
    [data-testid="dm-container"] [data-testid="dm-conversation-header"] {
      background: var(--mosaic-tab-surface) !important;
      box-shadow: inset 0 -1px 0 var(--mosaic-hairline) !important;
    }
    [data-testid="dm-container"] [data-testid="dm-conversation-header"] .pointer-events-none,
    [data-testid="dm-container"] [data-testid="dm-conversation-content"] > .pointer-events-none {
      background: transparent !important;
      background-image: none !important;
      backdrop-filter: none !important;
      -webkit-backdrop-filter: none !important;
      mask-image: none !important;
      -webkit-mask-image: none !important;
    }
    [data-testid="dm-container"] [data-testid="dm-composer-container"] {
      background: var(--mosaic-tab-surface) !important;
      box-shadow: inset 0 1px 0 var(--mosaic-hairline) !important;
    }

    /* Keep X's message grouping, timestamps, reactions and action hit targets. */
    [data-testid="dm-container"] [data-testid="dm-message-list"] [data-testid^="message-text-"] {
      background: var(--mosaic-dm-incoming) !important;
      color: var(--mosaic-ink) !important;
      border-radius: 19px 19px 19px 6px !important;
      box-shadow: inset 0 0 0 1px var(--mosaic-hairline) !important;
    }
    [data-testid="dm-container"] [data-testid="dm-message-list"] [data-testid^="message-"].justify-end [data-testid^="message-text-"] {
      background: var(--mosaic-dm-outgoing) !important;
      border-radius: 19px 19px 6px 19px !important;
      box-shadow: inset 0 0 0 1px var(--mosaic-accent-line) !important;
    }
    [data-testid="dm-container"] [data-testid="dm-message-list"] [data-testid^="message-text-"] * {
      color: var(--mosaic-ink) !important;
    }
    [data-testid="dm-container"] [data-testid="dm-message-list"] [data-testid^="message-text-"] a {
      color: var(--mosaic-accent) !important;
      text-decoration: underline;
      text-underline-offset: 2px;
    }
    [data-testid="dm-container"] [data-testid="dm-message-list"] .rounded-chat:not([data-testid^="message-text-"]) {
      background-color: var(--mosaic-dm-incoming) !important;
      border-color: var(--mosaic-hairline) !important;
      border-radius: 18px !important;
    }
    [data-testid="dm-container"] [data-testid="dm-message-list"] .rounded-chat:has([data-testid^="message-text-"]) {
      background: transparent !important;
      box-shadow: none !important;
    }

    /* X wraps the floating date in its own pill. Let only the text label
       own the glass surface, avoiding nested outlines and double blur. */
    [data-testid="dm-container"] [data-testid="dm-conversation-content"] .rounded-full:has(.text-gray-600.text-subtext2),
    [data-testid="dm-container"] [data-testid="dm-conversation-content"] div:has(> .text-gray-600.text-subtext2) {
      background: transparent !important;
      border-color: transparent !important;
      outline: none !important;
      box-shadow: none !important;
      backdrop-filter: none !important;
      -webkit-backdrop-filter: none !important;
    }
    [data-testid="dm-container"] [data-testid="dm-conversation-content"] .text-gray-600.text-subtext2 {
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
    [data-testid="dm-container"] [data-testid="dm-conversation-content"] .text-gray-600.text-subtext2::before {
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
    [data-testid="dm-container"] [data-testid="dm-message-list"] .align-end .text-subtext3,
    [data-testid="dm-container"] [data-testid="dm-message-list"] [data-testid^="message-text-"] .text-subtext3 {
      color: var(--mosaic-dm-timestamp) !important;
      font-weight: 500 !important;
      opacity: 1 !important;
    }

    /* One pill and one focus ring, including multiline input and voice controls. */
    [data-testid="dm-container"] [data-testid="dm-composer-input-container"] {
      background: var(--mosaic-inset) !important;
      border: 1px solid var(--mosaic-accent-line) !important;
      border-radius: 26px !important;
      box-shadow: inset 0 1px 0 var(--mosaic-hairline) !important;
    }
    [data-testid="dm-container"] [data-testid="dm-composer-input-container"]:focus-within {
      border-color: var(--mosaic-accent) !important;
      box-shadow: 0 0 0 3px var(--mosaic-accent-soft) !important;
    }
    [data-testid="dm-container"] [data-testid="dm-composer-input-container"] > div,
    [data-testid="dm-container"] [data-testid="dm-composer-textarea"],
    [data-testid="dm-container"] [data-testid="dm-composer-textarea"]:focus,
    [data-testid="dm-container"] [data-testid="dm-composer-textarea"]:focus-visible {
      background: transparent !important;
      color: var(--mosaic-ink) !important;
      border: 0 !important;
      border-radius: 0 !important;
      outline: none !important;
      box-shadow: none !important;
      caret-color: var(--mosaic-accent) !important;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
    }
    [data-testid="dm-container"] [data-testid="dm-composer-textarea"]::placeholder {
      color: var(--mosaic-secondary) !important;
    }
    [data-testid="dm-container"] [data-testid="dm-composer-container"] button,
    [data-testid="dm-container"] [data-testid="dm-conversation-header"] button {
      color: var(--mosaic-accent) !important;
      border-radius: 999px !important;
    }
    [data-testid="dm-container"] [data-testid="dm-composer-container"] button:hover,
    [data-testid="dm-container"] [data-testid="dm-conversation-header"] button:hover {
      background: var(--mosaic-accent-soft) !important;
    }
    @media (prefers-color-scheme: light) {
      :host, [data-testid="dm-container"] {
        --mosaic-dm-timestamp: rgb(76, 70, 61);
        --mosaic-dm-date-surface: rgba(248, 246, 240, 0.72);
        --mosaic-dm-incoming: rgba(35, 45, 52, 0.065);
        --mosaic-dm-outgoing: rgba(157, 126, 79, 0.16);
      }
    }
    @media (prefers-reduced-transparency: reduce) {
      :host, [data-testid="dm-container"] {
        --mosaic-dm-date-surface: rgb(55, 56, 53);
        --mosaic-dm-incoming: rgb(52, 54, 55);
        --mosaic-dm-outgoing: rgb(80, 73, 61);
      }
      [data-testid="dm-container"] [data-testid="dm-conversation-content"] .text-gray-600.text-subtext2::before {
        backdrop-filter: none !important;
        -webkit-backdrop-filter: none !important;
      }
    }
    @media (prefers-reduced-transparency: reduce) and (prefers-color-scheme: light) {
      :host, [data-testid="dm-container"] {
        --mosaic-dm-date-surface: rgb(240, 237, 230);
        --mosaic-dm-incoming: rgb(232, 233, 232);
        --mosaic-dm-outgoing: rgb(232, 221, 202);
      }
    }
    """
}
