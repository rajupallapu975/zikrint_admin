import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  AuthService._internal();
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  // Web Client ID from your google-services.json (client_type 3)
  static final String webClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? "71044416645-9je3u2l0usttn4kutngksqv0un3itscm.apps.googleusercontent.com";

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: webClientId,
  );

  // Sign in with Google
  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      return userCredential.user;
    } catch (e) {
      debugPrint('Error signing in with Google: $e');
      return null;
    }
  }

  // Sign in with Email & Password (Reviewer Test Account)
  Future<User?> signInWithEmail(String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPass = password.trim();

    // 🔑 Special Reviewer Test Account Fallback: reviewer@zikrint.app / raju@975
    if (cleanEmail == 'reviewer@zikrint.app' && cleanPass == 'raju@975') {
      // 1. Attempt standard Email/Password sign-in
      try {
        final credential = await _auth.signInWithEmailAndPassword(
          email: cleanEmail,
          password: cleanPass,
        );
        await credential.user?.updateDisplayName('Reviewer User');
        return credential.user;
      } catch (e) {
        debugPrint('⚠️ Admin Email Auth failed ($e), attempting custom token from backend...');
      }

      // 2. Attempt custom token from backend (bypasses Firebase Console Email Provider restriction)
      try {
        final urlsToTry = [
          dotenv.env['BACKEND_URL'] ?? 'https://zikrint.duckdns.org',
          'http://192.168.0.206:5001',
          'http://localhost:5001',
        ];
        for (final baseUrl in urlsToTry) {
          try {
            final res = await http.post(
              Uri.parse('$baseUrl/api/reviewer-token'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'email': cleanEmail, 'password': cleanPass}),
            ).timeout(const Duration(seconds: 4));
            if (res.statusCode == 200) {
              final data = jsonDecode(res.body);
              if (data['success'] == true && data['token'] != null) {
                final userCred = await _auth.signInWithCustomToken(data['token']);
                await userCred.user?.updateDisplayName('Reviewer User');
                debugPrint('✅ Reviewer custom token sign-in successful!');
                return userCred.user;
              }
            }
          } catch (_) {}
        }
      } catch (tokenErr) {
        debugPrint('⚠️ Custom token fetch failed: $tokenErr');
      }

      // 3. Attempt anonymous sign-in fallback
      try {
        final anonCred = await _auth.signInAnonymously();
        await anonCred.user?.updateDisplayName('Reviewer User');
        return anonCred.user;
      } catch (_) {
        return _auth.currentUser;
      }
    }

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: cleanPass,
      );
      return credential.user;
    } catch (e) {
      debugPrint('❌ Admin Email Sign-In Error: $e');
      if (e is FirebaseAuthException) {
        throw Exception("Auth Error: ${e.message}");
      }
      throw Exception("Authentication Failed: $e");
    }
  }

  // Check if user has completed onboarding
  Future<bool> isUserOnboarded() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    
    // 🔑 Tester/Reviewer account bypasses onboarding and opens Dashboard directly
    if (user.email != null && user.email!.toLowerCase().contains('reviewer')) {
      await _ensureReviewerShopExists();
      return true;
    }

    final doc = await _db.collection('shops').doc(user.uid).get();
    return doc.exists;
  }

  // 🔑 Helper to ensure reviewer test shop document exists in Firestore
  Future<void> _ensureReviewerShopExists() async {
    try {
      final doc = await _db.collection('shops').doc('reviewer_shop_store').get();
      if (!doc.exists) {
        await _db.collection('shops').doc('reviewer_shop_store').set({
          'uid': 'reviewer_shop_store',
          'shopName': 'Zikrint Reviewer Test Shop',
          'address': 'Test Kiosk Environment',
          'pincode': '530068',
          'mobile': '+91 9750000000',
          'openingTime': '08:00 AM',
          'closingTime': '11:00 PM',
          'isAcceptingOrders': true,
          'isBlocked': false,
          'isActive': true,
          'isTestShop': true,
          'isCurrentlyOpen': true,
          'isOpen': true,
          'pricePerBWPage': 2.0,
          'pricePerColorPage': 10.0,
          'createdAt': FieldValue.serverTimestamp(),
          'walletBalance': 0,
          'totalBwPages': 0,
          'totalColorPages': 0,
        }, SetOptions(merge: true));
        debugPrint("✅ Reviewer test shop automatically seeded in Firestore");
      }
    } catch (e) {
      debugPrint("⚠️ Ensure Reviewer Shop Error: $e");
    }
  }

  // Save shop details
  Future<void> saveShopDetails(Map<String, dynamic> details) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    final bool isReviewer = (user.email ?? '').toLowerCase().contains('reviewer');
    final String shopDocId = isReviewer ? 'reviewer_shop_store' : user.uid;

    final dataToSave = {
      ...details,
      'uid': shopDocId,
      if (isReviewer) 'isTestShop': true,
      'createdAt': FieldValue.serverTimestamp(),
    };

    // 1. Save to primary Admin project (shops collection)
    await _db.collection('shops').doc(shopDocId).set(dataToSave, SetOptions(merge: true));

    // 2. Sync to secondary Customer project (users collection) - "Before Users" storage
    try {
      final psfcApp = Firebase.app('psfc');
      final psfcFirestore = FirebaseFirestore.instanceFor(app: psfcApp);
      
      await psfcFirestore.collection('users').doc(user.uid).set({
        ...details,
        'uid': user.uid,
        'role': 'shop_admin',
        if (isReviewer) 'isTestShop': true,
        'lastSyncAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint("✅ Admin profile dual-synced to PSFC users collection");
    } catch (e) {
      debugPrint("⚠️ Dual-sync to PSFC failed (secondary app might not be initialized): $e");
    }
  }

  // Update shop details
  Future<void> updateShopDetails(Map<String, dynamic> details) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    await _db.collection('shops').doc(user.uid).set({
      ...details,
      'uid': user.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    try {
      final psfcApp = Firebase.app('psfc');
      final psfcFirestore = FirebaseFirestore.instanceFor(app: psfcApp);
      
      await psfcFirestore.collection('users').doc(user.uid).set({
        ...details,
        'uid': user.uid,
        'role': 'shop_admin',
        'lastSyncAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("⚠️ Dual-sync to PSFC failed: $e");
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      debugPrint('Error signing out: $e');
    }
  }

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();
}
