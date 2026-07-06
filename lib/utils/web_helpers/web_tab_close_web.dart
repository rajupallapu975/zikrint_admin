// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void initializeTabCloseListener(String shopId, String baseUrl) {
  html.window.addEventListener('beforeunload', (event) {
    // Trigger beacon request to set shop offline immediately on tab close
    final url = '$baseUrl/set-shop-status';
    final data = '{"shopId": "$shopId", "isOpen": false}';
    final blob = html.Blob([data], 'application/json');
    html.window.navigator.sendBeacon(url, blob);
  });
}
