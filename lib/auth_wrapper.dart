import 'package:flutter/material.dart';
import 'package:smart_student_ai/firebase_auth_service.dart';
import 'package:smart_student_ai/auth_screen.dart';
import 'package:smart_student_ai/home_screen.dart';

/// Decides which screen to show based on the current authentication state.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = FirebaseAuthService();

    return StreamBuilder<LocalUser?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        // We consider the state active once we have data or it's waiting but we have a snapshot
        if (snapshot.connectionState == ConnectionState.active || snapshot.hasData || snapshot.connectionState == ConnectionState.done) {
          LocalUser? user = snapshot.data;
          if (user == null) {
            return const AuthScreen();
          }
          // Use ValueKey to ensure the widget is recreated on identity change
          return const HomeScreen(key: ValueKey('home_active'));
        }
        
        // Initializing or waiting: show a sleek loading state
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(
              strokeWidth: 3,
            ),
          ),
        );
      },
    );
  }
}
