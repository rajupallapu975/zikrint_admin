importScripts('https://www.gstatic.com/firebasejs/9.0.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.0.0/firebase-messaging-compat.js');

// 🛡️ High-fidelity Firebase synchronization for Web Background Alerts.
// This allows PC/Website users to receive notifications even when the browser tab is closed.
firebase.initializeApp({
  apiKey: "AIzaSyAM_UmfDJyCSObGjyb2-Cp0titzv068CLM",
  authDomain: "zikrint-admin.firebaseapp.com",
  projectId: "zikrint-admin",
  storageBucket: "zikrint-admin.firebasestorage.app",
  messagingSenderId: "71044416645",
  appId: "1:71044416645:web:20135d3480fc6e3ab7d5ec",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Background Message received: ', payload);
  const notificationTitle = payload.notification.title || "Zikrint Order Update";
  const notificationOptions = {
    body: payload.notification.body || "A new order requires your attention.",
    icon: '/icons/Icon-192.png',
    badge: '/favicon.png',
    data: payload.data
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});
