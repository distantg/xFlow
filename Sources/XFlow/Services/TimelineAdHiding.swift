import Foundation

enum TimelineAdHiding {
    static let storageKey = "mosaic.hideTimelineAds"

    // CSS follows inserted and recycled timeline cells automatically. Own a separate
    // stylesheet so disabling this never clears keyword filters or X's inline styles.
    // Only explicit promotion markers count; never match words in a user's post.
    static func script(enabled: Bool) -> String {
        """
        (() => {
          const id = 'mosaic-timeline-ad-hiding';
          let style = document.getElementById(id);
          if (!\(enabled ? "true" : "false")) {
            if (style) style.remove();
            return;
          }
          if (style) return;
          style = document.createElement('style');
          style.id = id;
          style.textContent = `
            [data-testid="primaryColumn"] [data-testid="cellInnerDiv"]:has([data-testid="placementTracking"]),
            [data-testid="primaryColumn"] [data-testid="cellInnerDiv"]:has([data-testid="promotedIndicator"]) {
              display: none !important;
            }
          `;
          (document.head || document.documentElement).appendChild(style);
        })();
        """
    }
}
