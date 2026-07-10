// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

void initializeTabCloseListener(String shopId, String baseUrl) {
  void _setOffline() {
    // 1️⃣ Fastest: call Firestore JS SDK directly (same page, no network round trip)
    try {
      js.context.callMethod('eval', ['''
        (function() {
          try {
            var db = firebase.firestore();
            db.collection("shops").doc("$shopId").update({ isOpen: false });
          } catch(e) {}
        })();
      ''']);
    } catch (_) {}

    // 2️⃣ Fallback: sendBeacon to backend (in case JS SDK not available)
    final blob = html.Blob(
      ['{"shopId":"$shopId","isOpen":false}'], 'application/json');
    html.window.navigator.sendBeacon('$baseUrl/set-shop-status', blob);
  }

  // Tab closed or page navigated away
  html.window.addEventListener('beforeunload', (event) => _setOffline());
}
