import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_model.dart';

/// Manage Local Authentication and user data persistence.
/// This replaces the Firebase implementation to avoid Windows build issues.
class FirebaseAuthService {
  static final FirebaseAuthService _instance = FirebaseAuthService._internal();
  factory FirebaseAuthService() => _instance;
  FirebaseAuthService._internal() {
    _init();
  }

  static const String _userKey = 'local_user_data';
  static const String _isLoggedInKey = 'is_logged_in';

  final _authStateController = StreamController<LocalUser?>.broadcast();

  /// Stream of authentication state changes.
  Stream<LocalUser?> get authStateChanges => _authStateController.stream;

  Future<void> _init() async {
    final user = await currentUser;
    _authStateController.add(user);
  }

  /// Get the currently logged-in local user.
  Future<LocalUser?> get currentUser async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(_isLoggedInKey) ?? false;
    if (!isLoggedIn) return null;

    final userData = prefs.getString(_userKey);
    if (userData == null) return null;

    try {
      final map = jsonDecode(userData);
      return LocalUser(uid: map['uid'], email: map['email']);
    } catch (e) {
      return null;
    }
  }

  /// Sign up a new user locally.
  Future<String?> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      await Future.delayed(const Duration(milliseconds: 800)); // Simulate network
      
      final prefs = await SharedPreferences.getInstance();
      
      // Basic check if user already "exists" (we only support one user for now)
      // In a real local app, we'd use a database of users.
      
      final userModel = UserModel(
        uid: 'local_user_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        email: email,
        createdAt: DateTime.now(),
      );

      await prefs.setString(_userKey, jsonEncode({
        'uid': userModel.uid,
        'email': email,
        'name': name,
      }));
      await prefs.setBool(_isLoggedInKey, true);

      final localUser = LocalUser(uid: userModel.uid, email: email);
      _authStateController.add(localUser);
      
      return null;
    } catch (e) {
      return "An unexpected error occurred: ${e.toString()}";
    }
  }

  /// Sign in an existing user locally.
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await Future.delayed(const Duration(milliseconds: 500)); // Simulate network
      
      final prefs = await SharedPreferences.getInstance();
      final userData = prefs.getString(_userKey);
      
      if (userData == null) {
        return "No account found. Please sign up first.";
      }

      final map = jsonDecode(userData);
      if (map['email'] != email) {
        return "Invalid email or password.";
      }

      // In this mock, any password works if email matches
      await prefs.setBool(_isLoggedInKey, true);
      
      final localUser = LocalUser(uid: map['uid'], email: email);
      _authStateController.add(localUser);
      
      return null;
    } catch (e) {
      return "An unexpected error occurred: ${e.toString()}";
    }
  }

  /// Logs the user out.
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, false);
    _authStateController.add(null);
  }

  /// Fetches extended user profile data.
  Future<UserModel?> getUserData(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString(_userKey);
    if (userData != null) {
      return UserModel.fromMap(jsonDecode(userData));
    }
    return null;
  }

  /// Updates the user's best score locally.
  Future<void> updateBestScore(int score) async {
    // This could be stored in SharedPreferences or the local database
    debugPrint("Local: Best Score updated to: $score");
  }

  /// Syncs the local student progress (Mocked).
  Future<void> syncProgress(dynamic progress) async {
    debugPrint("Local: Progress synced: XP ${progress.xp}");
  }
}

/// A simple class to mimic Firebase's User object.
class LocalUser {
  final String uid;
  final String email;
  LocalUser({required this.uid, required this.email});
}
