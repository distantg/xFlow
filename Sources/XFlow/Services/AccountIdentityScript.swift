import Foundation

/// Only signed-in account controls identify the viewer; feed content never does.
enum AccountIdentityScript {
    static let extractionScript = #"""
    (function() {
      function collect() {
        const profile = document.querySelector('a[data-testid="AppTabBar_Profile_Link"]');
        const switcher = document.querySelector('[data-testid="SideNav_AccountSwitcher_Button"]');
        const path = profile ? (profile.getAttribute('href') || '') : '';
        const match = path.match(/^\/([A-Za-z0-9_]{1,15})\/?$/);
        const text = switcher ? (switcher.innerText || '') + ' ' + (switcher.getAttribute('aria-label') || '') : '';
        const accountMatch = text.match(/@([A-Za-z0-9_]{1,15})\b/);
        const handle = match ? match[1] : (accountMatch ? accountMatch[1] : '');
        const img = (switcher && switcher.querySelector('img')) || (profile && profile.querySelector('img'));
        return { handle: handle.toLowerCase(), avatar: handle && img ? (img.src || '') : '' };
      }
      return new Promise(function(resolve) {
        let attempts = 0;
        function tick() {
          const result = collect();
          if (result.handle || attempts >= 25) {
            resolve(JSON.stringify(result));
            return;
          }
          attempts += 1;
          setTimeout(tick, 120);
        }
        tick();
      });
    })();
    """#
}
