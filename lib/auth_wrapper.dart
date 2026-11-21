import 'package:flutter/material.dart';
import 'package:smart_student_ai/auth_service.dart';
import 'package:smart_student_ai/auth_screen.dart';
import 'package:smart_student_ai/home_screen.dart';

/// Decides which screen to show based on the current authentication state.
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // Restore / validate any cached session on launch.
    AuthService.instance.initialize();
  }

  @override
  Widget build(BuildContext context) {
    final authService = AuthService.instance;

    return StreamBuilder<AuthUser?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        final waiting = snapshot.connectionState == ConnectionState.waiting;
        final user = snapshot.data ?? authService.currentUser;

        if (user == null) {
          // Before the first emission we may still be restoring a session.
          if (waiting && !snapshot.hasData && !authService.isSignedIn) {
            return const _BootLoader();
          }
          return const AuthScreen();
        }
        // Use ValueKey to ensure the widget is recreated on identity change.
        return HomeScreen(key: ValueKey('home_${user.id}'));
      },
    );
  }
}

class _BootLoader extends StatelessWidget {
  const _BootLoader();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(strokeWidth: 3)),
    );
  }
}
