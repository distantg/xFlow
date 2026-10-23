import Foundation

/// Reply actions in narrow columns use a full-page compose route rather than
/// X's desktop dialog. Keep both surfaces in the integrated appearance without
/// hiding the timeline or changing X's editor, navigation, and draft handling.
enum PostComposerTheme {
    static let css = #"""
    [data-mosaic-post-composer="true"] {
      --mosaic-compose-panel: rgb(30, 30, 28);
      --mosaic-compose-ink: rgb(242, 240, 234);
      --mosaic-compose-accent: rgb(231, 216, 190);
      --mosaic-compose-edge: rgba(231, 216, 190, 0.18);
      color: var(--mosaic-compose-ink) !important;
      background: transparent !important;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
    }
    @media (prefers-color-scheme: light) {
      [data-mosaic-post-composer="true"] {
        --mosaic-compose-panel: rgb(247, 245, 239);
        --mosaic-compose-ink: rgb(38, 35, 30);
        --mosaic-compose-accent: rgb(113, 94, 65);
        --mosaic-compose-edge: rgba(113, 94, 65, 0.2);
      }
    }
    [data-mosaic-post-composer="true"]:is([role="dialog"], [data-testid="sheetDialog"]) {
      background: var(--mosaic-compose-panel) !important;
      border: 1px solid var(--mosaic-compose-edge) !important;
      border-radius: 22px !important;
      box-shadow: 0 18px 60px rgba(0, 0, 0, 0.28) !important;
    }
    /* Neutral X panels can sit above primaryColumn on mobile compose routes.
       Clear only those surfaces; avatars, attachments and controls keep paint. */
    [data-mosaic-post-compose-surface="true"] {
      background-color: transparent !important;
      background-image: none !important;
    }
    [data-mosaic-post-composer="true"] :is([data-testid="tweetTextarea_0"], [role="textbox"], textarea) {
      color: var(--mosaic-compose-ink) !important;
      -webkit-text-fill-color: var(--mosaic-compose-ink) !important;
      caret-color: var(--mosaic-compose-accent) !important;
      background: transparent !important;
    }
    [data-mosaic-post-composer="true"] :is(button, [role="button"], a) {
      color: var(--mosaic-compose-accent) !important;
    }
    [data-mosaic-post-composer="true"] :is(button, [role="button"], a) :is(div, span, svg) {
      color: inherit !important;
    }
    [data-mosaic-post-composer="true"] :is([data-testid="tweetButton"], [data-testid="tweetButtonInline"], [data-mosaic-reply-submit]) {
      background: rgb(231, 216, 190) !important;
      border-color: transparent !important;
      border-radius: 999px !important;
      color: rgb(34, 28, 21) !important;
      opacity: 1 !important;
    }
    [data-mosaic-post-composer="true"] :is([data-testid="tweetButton"], [data-testid="tweetButtonInline"], [data-mosaic-reply-submit]) :is(div, span) {
      color: rgb(34, 28, 21) !important;
      -webkit-text-fill-color: rgb(34, 28, 21) !important;
      opacity: 1 !important;
    }
    [data-mosaic-post-composer="true"] :is([data-testid="tweetButton"], [data-testid="tweetButtonInline"], [data-mosaic-reply-submit]):is(:disabled, [aria-disabled="true"]) {
      background: rgb(151, 143, 130) !important;
      cursor: default !important;
    }
    [data-mosaic-post-composer="true"] :is([data-testid="tweetButton"], [data-testid="tweetButtonInline"], [data-mosaic-reply-submit]):not(:disabled):not([aria-disabled="true"]):hover {
      background: rgb(240, 228, 207) !important;
    }
    [data-mosaic-reply-submit-source] { display: none !important; }
    [data-mosaic-reply-footer] {
      display: flex !important;
      flex-direction: row !important;
      align-items: center !important;
      flex-wrap: nowrap !important;
      gap: 8px !important;
    }
    [data-mosaic-reply-tools] {
      flex: 1 1 auto !important;
      min-width: 0 !important;
      overflow-x: auto !important;
    }
    [data-mosaic-reply-counter] { flex-shrink: 0 !important; }
    [data-mosaic-reply-submit] {
      flex: 0 0 auto !important;
      min-width: 72px !important;
      min-height: 36px !important;
      padding: 0 18px !important;
      margin-inline-start: auto !important;
      font: 700 15px -apple-system, BlinkMacSystemFont, sans-serif !important;
      cursor: pointer;
    }
    [data-mosaic-post-composer="true"] :is(button, [role="button"], input, textarea):focus-visible {
      outline: 2px solid var(--mosaic-compose-accent) !important;
      outline-offset: 2px;
    }
    """#

    static let markingScript = #"""
    const replyActions = new Map();
    function restoreReplyAction(source, action) {
      action.button.remove();
      delete source.dataset.mosaicReplySubmitSource;
      delete action.footer.dataset.mosaicReplyFooter;
      if (action.tools) delete action.tools.dataset.mosaicReplyTools;
      if (action.counter) delete action.counter.dataset.mosaicReplyCounter;
      replyActions.delete(source);
    }
    function layoutReplyAction(surface, used) {
      const source = surface.querySelector('[data-testid="tweetButton"], [data-testid="tweetButtonInline"]');
      const toolbar = surface.querySelector('[data-testid="toolBar"]');
      let counter = toolbar?.querySelector('[role="progressbar"]') || surface.querySelector('[role="progressbar"]');
      if (!source || !toolbar || toolbar.contains(source)) return;
      // Use the existing tools/counter row. Leave React's submit node in place;
      // the visible action forwards to it and mirrors its disabled state.
      let footer = counter?.parentElement;
      while (footer && footer !== surface && !footer.contains(toolbar)) footer = footer.parentElement;
      if (!footer || footer === surface || footer.contains(source)) {
        // X removes the character meter for an empty draft. Keep the disabled
        // action in the tools row instead of jumping back to the header.
        counter = null;
        footer = toolbar;
        const parent = toolbar.parentElement;
        if (parent && parent !== surface && !parent.contains(source)) {
          const style = getComputedStyle(parent);
          if (style.display.includes('flex') && style.flexDirection === 'row') footer = parent;
        }
      }
      function branch(node) {
        while (node && node.parentElement !== footer && node !== footer) node = node.parentElement;
        return node === footer ? null : node;
      }
      let action = replyActions.get(source);
      if (action && action.footer !== footer) { restoreReplyAction(source, action); action = null; }
      if (!action) {
        const button = document.createElement('button');
        button.type = 'button';
        button.dataset.mosaicReplySubmit = 'true';
        button.addEventListener('click', () => {
          if (source.isConnected && !source.disabled && source.getAttribute('aria-disabled') !== 'true') source.click();
        });
        action = {button, footer,
          tools: branch(toolbar) || Array.from(footer.children).find(node => node.querySelector('input[type="file"], [data-testid="fileInput"]')),
          counter: counter ? branch(counter) : null};
        replyActions.set(source, action);
      }
      const label = source.textContent.trim();
      if (action.button.textContent !== label) action.button.textContent = label;
      const disabled = source.disabled || source.getAttribute('aria-disabled') === 'true';
      if (action.button.disabled !== disabled) action.button.disabled = disabled;
      footer.dataset.mosaicReplyFooter = 'true';
      if (action.tools && action.tools !== action.counter) action.tools.dataset.mosaicReplyTools = 'true';
      if (action.counter) action.counter.dataset.mosaicReplyCounter = 'true';
      if (action.button.parentElement !== footer) footer.appendChild(action.button);
      source.dataset.mosaicReplySubmitSource = 'true';
      used.add(source);
    }
    function markPostComposers() {
      if (typeof document.querySelectorAll !== 'function') return;
      const active = new Set();
      const usedActions = new Set();
      const surfaces = new Set();
      const composeRoute = /^\/compose\/(?:post|tweet)(?:\/|$)/.test(location.pathname);
      document.querySelectorAll('[data-testid="tweetTextarea_0"], [contenteditable="true"][role="textbox"]').forEach(editor => {
        // Inline timeline editors already have their own integrated theme.
        const dialog = editor.closest('[role="dialog"], [data-testid="sheetDialog"]');
        let surface = dialog;
        if (!surface && composeRoute) {
          surface = editor.closest('[data-testid="primaryColumn"]');
          // Some mobile layouts omit primaryColumn. Stop at the smallest shell
          // containing both editor and submit action, never the whole document.
          if (!surface) {
            for (let node = editor.parentElement; node && node !== document.body; node = node.parentElement) {
              if (node.querySelector('[data-testid="tweetButton"], [data-testid="tweetButtonInline"]')) {
                surface = node;
                break;
              }
            }
          }
        }
        if (!surface) return;
        layoutReplyAction(surface, usedActions);
        active.add(surface);
        surface.dataset.mosaicPostComposer = 'true';
        const neutral = new Set(['rgb(0, 0, 0)', 'rgb(255, 255, 255)', 'rgb(21, 32, 43)', 'rgb(22, 24, 28)', 'rgb(18, 18, 18)', 'rgb(20, 20, 20)']);
        function mark(node) {
          // Never erase media, badges, switches or selected controls.
          if (node.closest('button, [role="button"], [role="switch"], [role="checkbox"], [data-testid="tweetPhoto"], [data-testid="videoPlayer"]')) return;
          const background = getComputedStyle(node).backgroundColor;
          const channels = background.match(/[\d.]+/g)?.map(Number) || [];
          const grayPanel = channels.length >= 3 && (channels.length < 4 || channels[3] > 0) &&
            Math.max(...channels.slice(0, 3)) - Math.min(...channels.slice(0, 3)) <= 3 &&
            (Math.max(...channels.slice(0, 3)) <= 32 || Math.min(...channels.slice(0, 3)) >= 245);
          if (node.hasAttribute('data-mosaic-post-compose-surface') || neutral.has(background) || grayPanel) {
            node.dataset.mosaicPostComposeSurface = 'true';
            surfaces.add(node);
          }
        }
        surface.querySelectorAll('div, header, section, nav').forEach(mark);
        for (let node = surface.parentElement; node && node !== document.body; node = node.parentElement) mark(node);
      });
      for (const [source, action] of replyActions) {
        if (!usedActions.has(source)) restoreReplyAction(source, action);
      }
      document.querySelectorAll('[data-mosaic-post-composer]').forEach(node => {
        if (!active.has(node)) delete node.dataset.mosaicPostComposer;
      });
      document.querySelectorAll('[data-mosaic-post-compose-surface]').forEach(node => {
        if (!surfaces.has(node)) delete node.dataset.mosaicPostComposeSurface;
      });
    }
    """#

    static var installScript: String {
        """
        (() => {
          if (typeof document.querySelectorAll !== 'function' || typeof MutationObserver === 'undefined') return;
          if (globalThis.__mosaicPostComposerTheme) {
            globalThis.__mosaicPostComposerTheme.refresh();
            return;
          }
          \(markingScript)
          const shouldWatch = () => /^\\/compose\\/(?:post|tweet)(?:\\/|$)/.test(location.pathname) ||
            Array.from(document.querySelectorAll('[data-testid="tweetTextarea_0"], [contenteditable="true"][role="textbox"]'))
              .some(editor => editor.closest('[role="dialog"], [data-testid="sheetDialog"]'));
          if (!shouldWatch()) return;
          let timer = 0;
          function refresh() {
            markPostComposers();
            if (!shouldWatch()) {
              globalThis.__mosaicPostComposerTheme.stop();
              delete globalThis.__mosaicPostComposerTheme;
            }
          }
          const observer = new MutationObserver(() => {
            if (timer) return;
            // Appearance must not wait for a rendering frame: WebKit can defer
            // frames in a restored or occluded column while X mounts an editor.
            timer = setTimeout(() => { timer = 0; refresh(); }, 0);
          });
          observer.observe(document, {childList: true, subtree: true, attributes: true,
            attributeFilter: ['disabled', 'aria-disabled']});
          globalThis.__mosaicPostComposerTheme = {
            refresh,
            stop() {
              observer.disconnect();
              if (timer) clearTimeout(timer);
              for (const [source, action] of replyActions) restoreReplyAction(source, action);
            }
          };
          markPostComposers();
        })();
        """
    }

    static let removeMarkingScript = #"""
    if (globalThis.__mosaicPostComposerTheme) {
      globalThis.__mosaicPostComposerTheme.stop();
      delete globalThis.__mosaicPostComposerTheme;
    }
    if (typeof document.querySelectorAll === 'function') {
      document.querySelectorAll('[data-mosaic-post-composer]').forEach(node => delete node.dataset.mosaicPostComposer);
      document.querySelectorAll('[data-mosaic-post-compose-surface]').forEach(node => delete node.dataset.mosaicPostComposeSurface);
    }
    """#
}
