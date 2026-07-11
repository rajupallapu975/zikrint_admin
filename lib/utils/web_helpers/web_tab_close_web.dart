// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

void initializeTabCloseListener(String shopId, String baseUrl, String sessionId) {
  void _setOffline() {
    // Rely exclusively on backend sendBeacon to verify the sessionId matches
    // before turning the shop offline, avoiding duplicate or old tabs from setting it offline.
    final blob = html.Blob(
      ['{"shopId":"$shopId","isOpen":false,"sessionId":"$sessionId"}'], 'application/json');
    html.window.navigator.sendBeacon('$baseUrl/set-shop-status', blob);
  }

  // Tab closed or page navigated away
  html.window.addEventListener('beforeunload', (event) => _setOffline());
}
