import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smart_student_ai/database_service.dart';

/// Base URL of the account API (the smart.chrif.net PHP backend).
/// Override with `--dart-define=AUTH_BASE_URL=...` if needed.
const String kAuthBaseUrl = String.fromEnvironment(
  'AUTH_BASE_URL',
  defaultValue: 'https://smart.chrif.net/auth',
);

/// The signed-in user, as returned by the account API.
@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.verified,
    this.createdAt,
  });

  final int id;
  final String name;
  final String email;
  final bool verified;
  final String? createdAt;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        verified: json['verified'] == true || json['verified'] == 1,
        createdAt: json['created_at']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'verified': verified,
        'created_at': createdAt,
      };

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

/// The cloud copy of the student's XP / level / activity.
@immutable
class CloudProgress {
  const CloudProgress({
    required this.xp,
    required this.level,
    required this.xpIntoLevel,
    required this.xpPerLevel,
    required this.levelProgress,
    required this.revisionCount,
    required this.dictationCount,
    required this.bestScore,
    required this.streak,
    required this.longestStreak,
    required this.todayXp,
    required this.dailyGoal,
    this.lastActive,
    this.updatedAt,
  });

  final int xp;
  final int level;
  final int xpIntoLevel;
  final int xpPerLevel;
  final double levelProgress;
  final int revisionCount;
  final int dictationCount;
  final int bestScore;
  final int streak;
  final int longestStreak;
  final int todayXp;
  final int dailyGoal;
  final String? lastActive;
  final String? updatedAt;

  factory CloudProgress.fromJson(Map<String, dynamic> json) => CloudProgress(
        xp: (json['xp'] as num?)?.toInt() ?? 0,
        level: (json['level'] as num?)?.toInt() ?? 1,
        xpIntoLevel: (json['xp_into_level'] as num?)?.toInt() ?? 0,
        xpPerLevel: (json['xp_per_level'] as num?)?.toInt() ?? 100,
        levelProgress: (json['level_progress'] as num?)?.toDouble() ?? 0,
        revisionCount: (json['revision_count'] as num?)?.toInt() ?? 0,
        dictationCount: (json['dictation_count'] as num?)?.toInt() ?? 0,
        bestScore: (json['best_score'] as num?)?.toInt() ?? 0,
        streak: (json['streak'] as num?)?.toInt() ?? 0,
        longestStreak: (json['longest_streak'] as num?)?.toInt() ?? 0,
        todayXp: (json['today_xp'] as num?)?.toInt() ?? 0,
        dailyGoal: (json['daily_goal'] as num?)?.toInt() ?? 50,
        lastActive: json['last_active']?.toString(),
        updatedAt: json['updated_at']?.toString(),
      );
}

/// A row on the leaderboard.
@immutable
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.name,
    required this.xp,
    required this.level,
    required this.streak,
    required this.revisionCount,
    required this.dictationCount,
  });

  final int rank;
  final String name;
  final int xp;
  final int level;
  final int streak;
  final int revisionCount;
  final int dictationCount;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        name: (json['name'] ?? '').toString(),
        xp: (json['xp'] as num?)?.toInt() ?? 0,
        level: (json['level'] as num?)?.toInt() ?? 1,
        streak: (json['streak'] as num?)?.toInt() ?? 0,
        revisionCount: (json['revision_count'] as num?)?.toInt() ?? 0,
        dictationCount: (json['dictation_count'] as num?)?.toInt() ?? 0,
      );
}

/// An achievement with its unlocked state.
@immutable
class Achievement {
  const Achievement({
    required this.code,
    required this.title,
    required this.description,
    required this.icon,
    required this.unlocked,
  });

  final String code;
  final String title;
  final String description;
  final String icon;
  final bool unlocked;

  factory Achievement.fromJson(Map<String, dynamic> json) => Achievement(
        code: (json['code'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        description: (json['desc'] ?? '').toString(),
        icon: (json['icon'] ?? 'star').toString(),
        unlocked: json['unlocked'] == true,
      );
}

/// Outcome of an auth call. [error] is null on success.
class AuthResult {
  const AuthResult({
    required this.ok,
    this.error,
    this.message,
    this.requiresVerification = false,
    this.requiresOtp = false,
    this.email,
    this.user,
    this.progress,
    this.newAchievements = const <String>[],
  });

  final bool ok;
  final String? error;
  final String? message;
  final bool requiresVerification;

  /// True when the password was correct and a sign-in code was emailed.
  final bool requiresOtp;
  final String? email;
  final AuthUser? user;
  final CloudProgress? progress;
  final List<String> newAchievements;
}

/// Email-OTP account service backed by the smart.chrif.net API.
///
/// Replaces the old local/Firebase mock. Everything is stored remotely; only
/// the session token and a small cache live on the device.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();
  factory AuthService() => instance;

  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';
  static const String _progressKey = 'auth_progress';
  static const String _pendingPrefix = 'auth_pending_';

  /// Shorter timeout for background sync, so an offline device fails fast
  /// instead of blocking the UI for the full request timeout.
  static const Duration _syncTimeout = Duration(seconds: 8);

  final _authStateController = StreamController<AuthUser?>.broadcast();

  AuthUser? _user;
  CloudProgress? _progress;
  String? _token;
  bool _initialized = false;
  Future<void>? _initFuture;

  /// Stream of authentication state changes.
  Stream<AuthUser?> get authStateChanges => _authStateController.stream;

  /// Currently signed-in user (null when signed out).
  AuthUser? get currentUser => _user;

  /// Latest cloud progress snapshot (may be null right after sign-in).
  CloudProgress? get progress => _progress;

  bool get isSignedIn => _user != null;

  /// Loads any cached session from disk and verifies it with the server.
  Future<void> initialize() {
    _initFuture ??= _doInitialize();
    return _initFuture!;
  }

  Future<void> _doInitialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_tokenKey);
      final userRaw = prefs.getString(_userKey);
      if (userRaw != null) {
        final decoded = jsonDecode(userRaw);
        if (decoded is Map<String, dynamic>) {
          _user = AuthUser.fromJson(decoded);
        }
      }
      final progressRaw = prefs.getString(_progressKey);
      if (progressRaw != null) {
        final decoded = jsonDecode(progressRaw);
        if (decoded is Map<String, dynamic>) {
          _progress = CloudProgress.fromJson(decoded);
        }
      }
    } catch (e) {
      debugPrint('AuthService: could not read cached session: $e');
    }

    _authStateController.add(_user);

    // Validate the cached token in the background; sign out if it is stale.
    if (_token != null) {
      // Push anything earned while offline before reading the server state.
      await _flushPending();
      final refreshed =
          await _request('me', method: 'GET', silent: true, timeout: _syncTimeout);
      if (refreshed != null) {
        if (refreshed.statusCode == 401) {
          await logout(notifyServer: false);
        } else {
          _applyPayload(refreshed.body);
          _emit();
        }
      }
    }
  }

  /// Registers a new account. The server emails a 6-digit verification code.
  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
  }) async {
    return _authAction('register', {
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'password': password,
    });
  }

  /// Completes email verification and signs the user in.
  Future<AuthResult> verify({required String email, required String code}) async {
    final result = await _authAction('verify', {
      'email': email.trim().toLowerCase(),
      'code': code.trim(),
    });
    if (result.ok) {
      await _persistSession();
    }
    return result;
  }

  /// Signs in with email + password. The server then emails a one-time code;
  /// the session is only created by [loginVerify].
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    return _authAction('login', {
      'email': email.trim().toLowerCase(),
      'password': password,
    });
  }

  /// Completes the two-factor sign-in with the emailed code.
  Future<AuthResult> loginVerify({
    required String email,
    required String code,
  }) async {
    final result = await _authAction('login_verify', {
      'email': email.trim().toLowerCase(),
      'code': code.trim(),
    });
    if (result.ok) {
      await _persistSession();
    }
    return result;
  }

  /// Requests a fresh verification code (or reset code).
  Future<AuthResult> resend({
    required String email,
    String purpose = 'verify',
  }) async {
    return _authAction('resend', {
      'email': email.trim().toLowerCase(),
      'purpose': purpose,
    });
  }

  /// Starts the forgot-password flow (emails a reset code).
  Future<AuthResult> forgot({required String email}) async {
    return _authAction('forgot', {'email': email.trim().toLowerCase()});
  }

  /// Completes the forgot-password flow with a reset code.
  Future<AuthResult> reset({
    required String email,
    required String code,
    required String password,
  }) async {
    return _authAction('reset', {
      'email': email.trim().toLowerCase(),
      'code': code.trim(),
      'password': password,
    });
  }

  /// Signs out locally and invalidates the session on the server.
  ///
  /// Returns `false` when the device is offline (the server could not be
  /// reached). In that case the session is kept so the user stays signed in and
  /// never ends up logged out while unreachable.
  Future<bool> logout({bool notifyServer = true}) async {
    if (notifyServer && _token != null) {
      // Push anything earned offline before the session is invalidated.
      await _flushPending();
      final res = await _request(
        'logout',
        method: 'POST',
        body: const {},
        timeout: _syncTimeout,
      );
      if (res == null) {
        // No HTTP response at all: we are offline, so refuse to sign out.
        return false;
      }
    }
    _token = null;
    _user = null;
    _progress = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_progressKey);
    _emit();
    return true;
  }

  /// Refreshes the cached profile and progress from the server.
  ///
  /// Any XP earned while offline is pushed first, so the server (and the local
  /// mirror) end up holding the complete, authoritative state.
  Future<void> refresh() async {
    if (_token == null) return;
    await _flushPending();
    final res =
        await _request('me', method: 'GET', silent: true, timeout: _syncTimeout);
    if (res == null) return;
    if (res.statusCode == 401) {
      await logout(notifyServer: false);
      return;
    }
    if (res.statusCode == 200) {
      _applyPayload(res.body);
      _emit();
    }
  }

  /// Pushes an XP / activity delta to the cloud and returns the new snapshot.
  ///
  /// The delta is queued locally first: if the device is offline it stays
  /// pending and is flushed on the next [refresh]. On success the server values
  /// are mirrored into the local database.
  Future<CloudProgress?> pushProgress({
    int xpDelta = 0,
    int revisionDelta = 0,
    int dictationDelta = 0,
    int bestScore = 0,
    String source = 'app',
  }) async {
    if (_token == null) return null;

    // Accumulate everything the server has not confirmed yet.
    final pending = await _loadPending();
    pending['xp_delta'] = (pending['xp_delta'] as int) + xpDelta;
    pending['revision_delta'] = (pending['revision_delta'] as int) + revisionDelta;
    pending['dictation_delta'] =
        (pending['dictation_delta'] as int) + dictationDelta;
    if (bestScore > (pending['best_score'] as int)) {
      pending['best_score'] = bestScore;
    }

    final res = await _request('progress', method: 'POST', body: {
      ...pending,
      'source': source,
    });
    if (res == null || res.statusCode != 200) {
      // Offline or refused: keep the deltas queued for the next sync.
      await _savePending(pending);
      return null;
    }

    // The server accepted everything we sent, so the queue is now empty.
    await _savePending(_zeroPending());
    _applyPayload(res.body);
    _emit();
    return _progress;
  }

  /// Fetches the global leaderboard.
  Future<List<LeaderboardEntry>> fetchLeaderboard({int limit = 50}) async {
    final res = await _request('leaderboard', method: 'GET', query: {'limit': '$limit'}, silent: true);
    if (res == null || res.statusCode != 200) return const [];
    final list = (res.body['leaderboard'] as List?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(LeaderboardEntry.fromJson)
        .toList();
  }

  /// Fetches every achievement definition with its unlocked state.
  Future<List<Achievement>> fetchAchievements() async {
    if (_token == null) return const [];
    final res = await _request('achievements', method: 'GET', silent: true);
    if (res == null || res.statusCode != 200) return const [];
    final list = (res.body['achievements'] as List?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(Achievement.fromJson)
        .toList();
  }

  /* ------------------------------------------------------------------ */
  /* internals                                                          */
  /* ------------------------------------------------------------------ */

  Future<AuthResult> _authAction(String action, Map<String, dynamic> body) async {
    final res = await _request(action, method: 'POST', body: body);
    if (res == null) {
      return const AuthResult(
        ok: false,
        error: 'Could not reach the server. Check your connection and try again.',
      );
    }
    final payload = res.body;
    if (res.statusCode == 200 && payload['requires_otp'] == true) {
      return AuthResult(
        ok: true,
        requiresOtp: true,
        email: payload['email']?.toString() ?? body['email']?.toString(),
        message: payload['message']?.toString(),
      );
    }
    if (res.statusCode == 200 && payload['ok'] == true && payload['token'] != null) {
      _applyPayload(payload);
      return AuthResult(
        ok: true,
        message: payload['message']?.toString(),
        user: _user,
        progress: _progress,
        newAchievements: _stringList(payload['new_achievements']),
      );
    }
    if (payload['requires_verification'] == true) {
      return AuthResult(
        ok: false,
        requiresVerification: true,
        email: payload['email']?.toString() ?? body['email']?.toString(),
        error: _errorMessage(payload) ?? 'Please confirm your email first.',
      );
    }
    final msg = _errorMessage(payload);
    if (res.statusCode == 200 && payload['ok'] == true) {
      return AuthResult(
        ok: true,
        message: payload['message']?.toString(),
        email: payload['email']?.toString(),
        requiresVerification: payload['requires_verification'] == true,
      );
    }
    if (msg == null && payload['ok'] == true) {
      return AuthResult(ok: true, message: payload['message']?.toString());
    }
    return AuthResult(ok: false, error: msg ?? 'Something went wrong. Please try again.');
  }

  void _applyPayload(Map<String, dynamic> payload) {
    final token = payload['token'];
    if (token is String && token.isNotEmpty) {
      _token = token;
    }
    final userJson = payload['user'];
    if (userJson is Map<String, dynamic>) {
      _user = AuthUser.fromJson(userJson);
    }
    final progressJson = payload['progress'];
    if (progressJson is Map<String, dynamic>) {
      final progress = CloudProgress.fromJson(progressJson);
      _progress = progress;
      // Kept in step with the server so the device copy never shows another
      // account's numbers while signed in.
      unawaited(_mirrorProgressToLocal(progress));
    }
    final ach = payload['achievements'];
    if (ach is List) {
      // Kept for callers that only need the codes.
      _lastAchievementCodes = _stringList(ach);
    }
  }

  List<String> _lastAchievementCodes = const [];

  /// Codes of the achievements currently unlocked (from the last payload).
  List<String> get unlockedAchievementCodes => _lastAchievementCodes;

  Future<void> _persistSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) {
      await prefs.setString(_tokenKey, _token!);
    }
    if (_user != null) {
      await prefs.setString(_userKey, jsonEncode(_user!.toJson()));
    }
    if (_progress != null) {
      await prefs.setString(_progressKey, jsonEncode(_progressToJson(_progress!)));
      // Make sure the device DB reflects this account before the UI reads it.
      await _mirrorProgressToLocal(_progress!);
    }
    _emit();
  }

  void _emit() {
    if (!_authStateController.isClosed) {
      _authStateController.add(_user);
    }
  }

  /* ------------------------------------------------------------------ */
  /* offline queue + local mirror                                       */
  /* ------------------------------------------------------------------ */

  /// Per-account key so queued deltas are never attributed to another user.
  String? get _pendingKey => _user == null ? null : '$_pendingPrefix${_user!.id}';

  Map<String, dynamic> _zeroPending() => <String, dynamic>{
        'xp_delta': 0,
        'revision_delta': 0,
        'dictation_delta': 0,
        'best_score': 0,
      };

  Future<Map<String, dynamic>> _loadPending() async {
    final key = _pendingKey;
    if (key == null) return _zeroPending();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return _zeroPending();
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return <String, dynamic>{
          'xp_delta': (decoded['xp_delta'] as num?)?.toInt() ?? 0,
          'revision_delta': (decoded['revision_delta'] as num?)?.toInt() ?? 0,
          'dictation_delta': (decoded['dictation_delta'] as num?)?.toInt() ?? 0,
          'best_score': (decoded['best_score'] as num?)?.toInt() ?? 0,
        };
      }
    } catch (e) {
      debugPrint('AuthService: could not read pending deltas: $e');
    }
    return _zeroPending();
  }

  Future<void> _savePending(Map<String, dynamic> pending) async {
    final key = _pendingKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final isZero = pending.values.every((v) => (v as num) == 0);
    if (isZero) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(pending));
    }
  }

  /// Sends any deltas accumulated while offline.
  ///
  /// Returns `true` when nothing remains queued (either the queue was empty or
  /// the server accepted it), `false` while the device is still offline.
  Future<bool> _flushPending({String source = 'offline_sync'}) async {
    if (_token == null || _user == null) return true;
    final pending = await _loadPending();
    if (pending.values.every((v) => (v as num) == 0)) return true;

    final res = await _request(
      'progress',
      method: 'POST',
      body: {...pending, 'source': source},
      timeout: _syncTimeout,
    );
    if (res == null || res.statusCode != 200) return false;

    await _savePending(_zeroPending());
    _applyPayload(res.body);
    _emit();
    return true;
  }

  /// Copies the server values into the local database so the on-device copy
  /// mirrors the signed-in account. Await it during sign-in so the device DB is
  /// correct before the home screen reads it.
  Future<void> _mirrorProgressToLocal(CloudProgress progress) async {
    try {
      await DatabaseService.instance.applyRemoteProgress(
        xp: progress.xp,
        level: progress.level,
        revisionCount: progress.revisionCount,
        dictationCount: progress.dictationCount,
      );
    } catch (e) {
      debugPrint('AuthService: could not mirror progress locally: $e');
    }
  }

  Map<String, dynamic> _progressToJson(CloudProgress p) => {
        'xp': p.xp,
        'level': p.level,
        'xp_into_level': p.xpIntoLevel,
        'xp_per_level': p.xpPerLevel,
        'level_progress': p.levelProgress,
        'revision_count': p.revisionCount,
        'dictation_count': p.dictationCount,
        'best_score': p.bestScore,
        'streak': p.streak,
        'longest_streak': p.longestStreak,
        'today_xp': p.todayXp,
        'daily_goal': p.dailyGoal,
        'last_active': p.lastActive,
        'updated_at': p.updatedAt,
      };

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return const [];
  }

  String? _errorMessage(Map<String, dynamic> payload) {
    final err = payload['error'];
    if (err is Map && err['message'] != null) {
      return err['message'].toString();
    }
    if (err is String && err.isNotEmpty) {
      return err;
    }
    if (payload['message'] is String &&
        payload['ok'] != true &&
        payload['token'] == null) {
      return payload['message'].toString();
    }
    return null;
  }

  Future<_HttpResult?> _request(
    String action, {
    required String method,
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool silent = false,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    var uri = Uri.parse('$kAuthBaseUrl/$action');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }

    try {
      late http.Response response;
      if (method == 'GET') {
        response = await http.get(uri, headers: headers).timeout(timeout);
      } else {
        response =
            await http.post(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(timeout);
      }
      Map<String, dynamic> decoded = const {};
      if (response.body.isNotEmpty) {
        final raw = jsonDecode(response.body);
        if (raw is Map<String, dynamic>) decoded = raw;
      }
      return _HttpResult(response.statusCode, decoded);
    } catch (e) {
      if (!silent) {
        debugPrint('AuthService: $action failed: $e');
      }
      return null;
    }
  }
}

class _HttpResult {
  const _HttpResult(this.statusCode, this.body);
  final int statusCode;
  final Map<String, dynamic> body;
}
