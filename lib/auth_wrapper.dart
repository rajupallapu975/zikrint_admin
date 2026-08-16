import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'main.dart';
import 'models/app_user.dart';
import 'services/auth_service.dart';
import 'pages/login_page.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthService authService = AuthService();

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        // If a user is logged in AND has a valid email address
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          final email = user.email;

          if (email != null && email.trim().isNotEmpty) {
            return FutureBuilder<bool>(
              future: authService.isUserOnboarded(),
              builder: (context, onboardSnapshot) {
                // While checking onboarding status
                if (onboardSnapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                // Handle errors or non-onboarded state: Show LoginPage as first!
                if (onboardSnapshot.hasError || onboardSnapshot.data == false) {
                  return const LoginPage();
                }

                // Normal flow: User is logged in and onboarded
                return MyHomePage(
                  user: AppUser(
                    uid: user.uid,
                    displayName: user.displayName,
                    email: user.email,
                    photoURL: user.photoURL,
                  ),
                );
              },
            );
          }
        }

        // Whenever no email is logged in, show the first landing / login page
        return const LoginPage();
      },
    );
  }
}
