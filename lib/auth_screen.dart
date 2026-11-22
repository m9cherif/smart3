import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:smart_student_ai/app_controller.dart';
import 'package:smart_student_ai/auth_service.dart';

enum _AuthMode { signIn, signUp, verify, loginOtp, forgot, reset }

/// The primary authentication screen: login, sign up, email verification,
/// the mandatory email code on every sign-in, and forgot / reset password.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _newPasswordController = TextEditingController();

  final AuthService _authService = AuthService.instance;

  _AuthMode _mode = _AuthMode.signIn;
  bool _isLoading = false;
  bool _obscure = true;
  String _otpCode = '';
  String? _errorMessage;
  String? _infoMessage;
  String? _pendingEmail;
  int _otpResetKey = 0;

  late final AnimationController _animController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideIn;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    final curve =
        CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _fadeIn = curve;
    _slideIn = Tween<Offset>(
      begin: const Offset(0, 0.045),
      end: Offset.zero,
    ).animate(curve);
    _animController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _newPasswordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  bool get _isOtpMode => _mode == _AuthMode.verify || _mode == _AuthMode.loginOtp;

  void _setMode(_AuthMode mode, {String? error, String? info}) {
    setState(() {
      _mode = mode;
      _errorMessage = error;
      _infoMessage = info;
      _otpCode = '';
      _newPasswordController.clear();
      _otpResetKey++;
    });
    _animController
      ..reset()
      ..forward();
  }

  Future<void> _run(
    Future<AuthResult> Function() action, {
    void Function(AuthResult)? onOk,
  }) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final result = await action();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.ok) {
      onOk?.call(result);
      return;
    }

    if (result.requiresVerification) {
      _pendingEmail = result.email ?? _emailController.text.trim();
      _setMode(
        _AuthMode.verify,
        info: 'Enter the 6-digit code we emailed to $_pendingEmail.',
      );
      return;
    }

    setState(() => _errorMessage = result.error);
  }

  void _submitSignIn() {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim().toLowerCase();
    _run(
      () => _authService.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      ),
      onOk: (r) {
        _pendingEmail = r.email ?? email;
        _setMode(
          _AuthMode.loginOtp,
          info: r.message ??
              'We emailed a 6-digit sign-in code to $_pendingEmail.',
        );
      },
    );
  }

  void _submitSignUp() {
    if (!_formKey.currentState!.validate()) return;
    _run(
      () => _authService.register(
        name: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      ),
      onOk: (r) {
        _pendingEmail = _emailController.text.trim().toLowerCase();
        _setMode(
          _AuthMode.verify,
          info: r.message ??
              'Enter the 6-digit code we emailed to $_pendingEmail.',
        );
      },
    );
  }

  void _submitVerify() {
    if (_otpCode.length != 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit code.');
      return;
    }
    final email = _pendingEmail ?? _emailController.text;
    if (_isOtpMode && _mode == _AuthMode.loginOtp) {
      _run(() => _authService.loginVerify(email: email, code: _otpCode));
      return;
    }
    _run(
      () => _authService.verify(email: email, code: _otpCode),
      // Success is handled by AuthWrapper's stream.
    );
  }

  void _submitForgot() {
    if (!_formKey.currentState!.validate()) return;
    _run(
      () => _authService.forgot(email: _emailController.text),
      onOk: (r) {
        _pendingEmail = _emailController.text.trim().toLowerCase();
        _setMode(
          _AuthMode.reset,
          info: r.message ??
              'If that email exists, a reset code has been sent.',
        );
      },
    );
  }

  void _submitReset() {
    if (!_formKey.currentState!.validate()) return;
    if (_otpCode.length != 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit code.');
      return;
    }
    _run(
      () => _authService.reset(
        email: _pendingEmail ?? _emailController.text,
        code: _otpCode,
        password: _newPasswordController.text,
      ),
      onOk: (r) => _setMode(
        _AuthMode.signIn,
        info: r.message ?? 'Password updated. Please sign in.',
      ),
    );
  }

  Future<void> _resend() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    final purpose = switch (_mode) {
      _AuthMode.reset => 'reset',
      _AuthMode.loginOtp => 'login',
      _ => 'verify',
    };
    final result = await _authService.resend(
      email: _pendingEmail ?? _emailController.text,
      purpose: purpose,
    );
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result.ok) {
        _infoMessage = result.message ?? 'A new code is on its way.';
      } else {
        _errorMessage = result.error;
      }
    });
  }

  /* ------------------------------------------------------------------ */
  /* Layout                                                             */
  /* ------------------------------------------------------------------ */

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final themeSpec = app.themeSpec;
    final brightness = app.brightnessMode;
    final pageGradient = themeSpec.pageGradientFor(brightness);
    final dark = brightness == AppBrightnessMode.dark;

    return Scaffold(
      backgroundColor: pageGradient.last,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: pageGradient,
              ),
            ),
          ),
          Positioned(
            top: -140,
            right: -90,
            child: _Glow(
              color: themeSpec.primary.withValues(alpha: dark ? 0.35 : 0.16),
              size: 380,
            ),
          ),
          Positioned(
            bottom: -160,
            left: -110,
            child: _Glow(
              color: themeSpec.secondary.withValues(alpha: dark ? 0.24 : 0.14),
              size: 420,
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1000;
                if (!wide) {
                  return _buildNarrowLayout(context, dark);
                }
                return Row(
                  children: [
                    Expanded(flex: 11, child: _buildBrandPanel(context, dark)),
                    Expanded(
                      flex: 10,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 32,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: _buildCard(context, compactHeader: false),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout(BuildContext context, bool dark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            children: [
              _buildMobileBrand(context, dark),
              const SizedBox(height: 22),
              _buildCard(context, compactHeader: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileBrand(BuildContext context, bool dark) {
    final themeSpec = AppScope.of(context).themeSpec;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        _LogoMark(size: 74, dark: dark),
        const SizedBox(height: 14),
        Text(
          'Smart Student AI',
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: themeSpec.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Learn smarter, every day',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.6),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildBrandPanel(BuildContext context, bool dark) {
    final app = AppScope.of(context);
    final themeSpec = app.themeSpec;
    final brightness = app.brightnessMode;
    final heroGradient = themeSpec.heroGradientFor(brightness);
    final foreground = themeSpec.heroForegroundFor(brightness);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 0, 22),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: heroGradient,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -70,
                right: -60,
                child: _Glow(
                  color: Colors.white.withValues(alpha: 0.12),
                  size: 300,
                ),
              ),
              Positioned(
                bottom: -90,
                left: -70,
                child: _Glow(
                  color: themeSpec.secondary.withValues(alpha: 0.22),
                  size: 320,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(46, 46, 46, 38),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _LogoMark(size: 52, dark: dark, onHero: true),
                        const SizedBox(width: 14),
                        Text(
                          'Smart Student AI',
                          style: TextStyle(
                            color: foreground,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      'Study smarter,\nnot harder.',
                      style: TextStyle(
                        color: foreground,
                        fontSize: 44,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Your AI study partner for revision, dictation and\n'
                      'everyday progress — synced across all your devices.',
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.82),
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 34),
                    _BrandFeature(
                      icon: Icons.auto_awesome_rounded,
                      title: 'AI revision that adapts to you',
                      subtitle: 'Summaries, quizzes and flashcards in seconds',
                      foreground: foreground,
                      accent: themeSpec.secondary,
                    ),
                    _BrandFeature(
                      icon: Icons.graphic_eq_rounded,
                      title: 'Dictation with instant feedback',
                      subtitle: 'AI picks the passage, you type and improve',
                      foreground: foreground,
                      accent: themeSpec.secondary,
                    ),
                    _BrandFeature(
                      icon: Icons.emoji_events_rounded,
                      title: 'XP, levels and streaks',
                      subtitle: 'Stay motivated with daily goals and leaderboards',
                      foreground: foreground,
                      accent: themeSpec.secondary,
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.shield_outlined,
                              color: foreground.withValues(alpha: 0.9),
                              size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Secure sign-in — every login is confirmed with a one-time email code.',
                              style: TextStyle(
                                color: foreground.withValues(alpha: 0.85),
                                fontSize: 12.5,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, {required bool compactHeader}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final app = AppScope.of(context);
    final dark = app.brightnessMode == AppBrightnessMode.dark;

    final (title, subtitle) = switch (_mode) {
      _AuthMode.signIn => (
          'Welcome back',
          'Sign in to continue your learning journey.'
        ),
      _AuthMode.signUp => (
          'Create your account',
          'Join thousands of students learning smarter — it\'s free.'
        ),
      _AuthMode.verify => (
          'Verify your email',
          'We sent a 6-digit code to your inbox to confirm your account.'
        ),
      _AuthMode.loginOtp => (
          'Check your inbox',
          'Every sign-in is confirmed by email. Enter the code we just sent you.'
        ),
      _AuthMode.forgot => (
          'Forgot your password?',
          'Enter your email and we will send you a reset code.'
        ),
      _AuthMode.reset => (
          'Set a new password',
          'Enter the code from your inbox and choose a new password.'
        ),
    };

    return FadeTransition(
      opacity: _fadeIn,
      child: SlideTransition(
        position: _slideIn,
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
          decoration: BoxDecoration(
            color: dark
                ? colorScheme.surface.withValues(alpha: 0.72)
                : Colors.white.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: dark ? 0.18 : 0.10),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.34 : 0.08),
                blurRadius: 42,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!compactHeader) ...[
                    _ModeBadge(mode: _mode),
                    const SizedBox(height: 18),
                  ],
                  Text(
                    title,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      color:
                          colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                  if (_mode == _AuthMode.loginOtp ||
                      _mode == _AuthMode.verify) ...[
                    const SizedBox(height: 14),
                    _EmailChip(email: _pendingEmail ?? _emailController.text),
                  ],
                  const SizedBox(height: 20),
                  if (_errorMessage != null)
                    _banner(_errorMessage!, isError: true),
                  if (_infoMessage != null)
                    _banner(_infoMessage!, isError: false),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _buildFields(colorScheme),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildPrimaryButton(colorScheme),
                  const SizedBox(height: 10),
                  _buildSecondaryActions(textTheme, colorScheme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /* ------------------------------------------------------------------ */
  /* Form                                                               */
  /* ------------------------------------------------------------------ */

  List<Widget> _buildFields(ColorScheme colorScheme) {
    switch (_mode) {
      case _AuthMode.signIn:
        return [
          _field(
            controller: _emailController,
            label: 'Email address',
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: _emailValidator,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          _passwordField(
            controller: _passwordController,
            label: 'Password',
            validator: (v) => (v == null || v.isEmpty)
                ? 'Please enter your password'
                : null,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitSignIn(),
          ),
        ];
      case _AuthMode.signUp:
        return [
          _field(
            controller: _nameController,
            label: 'Full name',
            icon: Icons.person_outline_rounded,
            textCapitalization: TextCapitalization.words,
            validator: (v) =>
                (v == null || v.trim().length < 2) ? 'Please enter your name' : null,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          _field(
            controller: _emailController,
            label: 'Email address',
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: _emailValidator,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          _passwordField(
            controller: _passwordController,
            label: 'Password',
            validator: (v) =>
                (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
            showStrength: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitSignUp(),
          ),
        ];
      case _AuthMode.verify:
      case _AuthMode.loginOtp:
        return [
          _OtpBoxes(
            key: ValueKey('otp-$_mode-$_otpResetKey'),
            onChanged: (code) => _otpCode = code,
            onCompleted: (_) {
              if (_mode == _AuthMode.loginOtp) {
                _submitVerify();
              }
            },
          ),
        ];
      case _AuthMode.forgot:
        return [
          _field(
            controller: _emailController,
            label: 'Email address',
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: _emailValidator,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitForgot(),
          ),
        ];
      case _AuthMode.reset:
        return [
          _OtpBoxes(
            key: ValueKey('otp-reset-$_otpResetKey'),
            onChanged: (code) => _otpCode = code,
          ),
          const SizedBox(height: 18),
          _passwordField(
            controller: _newPasswordController,
            label: 'New password',
            validator: (v) =>
                (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
            showStrength: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitReset(),
          ),
        ];
    }
  }

  Widget _buildPrimaryButton(ColorScheme colorScheme) {
    final label = switch (_mode) {
      _AuthMode.signIn => 'Continue',
      _AuthMode.signUp => 'Create account',
      _AuthMode.verify => 'Verify and continue',
      _AuthMode.loginOtp => 'Sign in',
      _AuthMode.forgot => 'Send reset code',
      _AuthMode.reset => 'Set new password',
    };
    final onPressed = _isLoading
        ? null
        : switch (_mode) {
            _AuthMode.signIn => _submitSignIn,
            _AuthMode.signUp => _submitSignUp,
            _AuthMode.verify => _submitVerify,
            _AuthMode.loginOtp => _submitVerify,
            _AuthMode.forgot => _submitForgot,
            _AuthMode.reset => _submitReset,
          };

    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 4,
          shadowColor: colorScheme.primary.withValues(alpha: 0.35),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _isLoading
            ? SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: colorScheme.onPrimary,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 19),
                ],
              ),
      ),
    );
  }

  Widget _buildSecondaryActions(
    TextTheme textTheme,
    ColorScheme colorScheme,
  ) {
    switch (_mode) {
      case _AuthMode.signIn:
        return Column(
          children: [
            TextButton(
              onPressed: _isLoading ? null : () => _setMode(_AuthMode.forgot),
              child: const Text('Forgot password?'),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'New here?',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                TextButton(
                  onPressed:
                      _isLoading ? null : () => _setMode(_AuthMode.signUp),
                  child: const Text('Create an account'),
                ),
              ],
            ),
          ],
        );
      case _AuthMode.signUp:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Already have an account?',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            TextButton(
              onPressed: _isLoading ? null : () => _setMode(_AuthMode.signIn),
              child: const Text('Sign in'),
            ),
          ],
        );
      case _AuthMode.verify:
      case _AuthMode.loginOtp:
      case _AuthMode.reset:
        return Column(
          children: [
            TextButton.icon(
              onPressed: _isLoading ? null : _resend,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Resend code'),
            ),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () => _setMode(
                        _mode == _AuthMode.reset
                            ? _AuthMode.forgot
                            : _AuthMode.signIn,
                      ),
              child: Text(
                _mode == _AuthMode.loginOtp
                    ? 'Use a different account'
                    : 'Back',
              ),
            ),
          ],
        );
      case _AuthMode.forgot:
        return TextButton(
          onPressed: _isLoading ? null : () => _setMode(_AuthMode.signIn),
          child: const Text('Back to sign in'),
        );
    }
  }

  Widget _banner(String message, {required bool isError}) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isError ? colorScheme.error : colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(13),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            color: color,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _emailValidator(String? val) {
    if (val == null || val.trim().isEmpty) return 'Please enter your email';
    if (!RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(val.trim())) {
      return 'That email does not look right';
    }
    return null;
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextFormField(
      controller: controller,
      obscureText: isPassword && _obscure,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: isPassword
            ? IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              )
            : null,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide:
              BorderSide(color: colorScheme.outline.withValues(alpha: 0.14)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide:
              BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
        ),
        floatingLabelStyle: TextStyle(
          color: colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
      validator: validator,
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    bool showStrength = false,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    final field = _field(
      controller: controller,
      label: label,
      icon: Icons.lock_outline_rounded,
      isPassword: true,
      validator: validator,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
    );
    if (!showStrength) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final score = _passwordScore(value.text);
            if (value.text.isEmpty) return const SizedBox(height: 2);
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Expanded(
                      child: Container(
                        height: 4,
                        margin: EdgeInsets.only(right: i == 2 ? 0 : 6),
                        decoration: BoxDecoration(
                          color: i < score
                              ? _strengthColor(score)
                              : Theme.of(context)
                                  .colorScheme
                                  .outline
                                  .withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  const SizedBox(width: 10),
                  Text(
                    switch (score) {
                      1 => 'Weak',
                      2 => 'Good',
                      _ => 'Strong',
                    },
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _strengthColor(score),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  int _passwordScore(String value) {
    if (value.isEmpty) return 0;
    var score = 1;
    if (value.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(value) &&
        RegExp(r'[0-9]').hasMatch(value)) {
      score++;
    }
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;
    return score.clamp(1, 3);
  }

  Color _strengthColor(int score) {
    final scheme = Theme.of(context).colorScheme;
    return switch (score) {
      1 => scheme.error,
      2 => const Color(0xFFE0A100),
      _ => const Color(0xFF2E9E6B),
    };
  }
}

/* -------------------------------------------------------------------- */
/* Small presentational widgets                                          */
/* -------------------------------------------------------------------- */

class _LogoMark extends StatelessWidget {
  const _LogoMark({
    required this.size,
    required this.dark,
    this.onHero = false,
  });

  final double size;
  final bool dark;
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.16),
      decoration: BoxDecoration(
        color: onHero
            ? Colors.white.withValues(alpha: 0.14)
            : scheme.primaryContainer.withValues(alpha: dark ? 0.35 : 0.55),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(
          color: onHero
              ? Colors.white.withValues(alpha: 0.25)
              : scheme.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Image.asset(
        'logo.png',
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Icon(
          Icons.school_rounded,
          size: size * 0.5,
          color: scheme.primary,
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _BrandFeature extends StatelessWidget {
  const _BrandFeature({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.foreground,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color foreground;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: accent, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.68),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.mode});

  final _AuthMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, label) = switch (mode) {
      _AuthMode.signIn => (Icons.login_rounded, 'Sign in'),
      _AuthMode.signUp => (Icons.person_add_alt_1_rounded, 'New account'),
      _AuthMode.verify => (Icons.mark_email_read_outlined, 'Email verification'),
      _AuthMode.loginOtp => (Icons.verified_user_outlined, 'Two-step sign-in'),
      _AuthMode.forgot => (Icons.help_outline_rounded, 'Account recovery'),
      _AuthMode.reset => (Icons.lock_reset_rounded, 'New password'),
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: scheme.primary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmailChip extends StatelessWidget {
  const _EmailChip({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(Icons.mail_outline_rounded, size: 17, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              email,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Six-box one-time-code input with auto-advance, backspace and paste support.
class _OtpBoxes extends StatefulWidget {
  const _OtpBoxes({
    super.key,
    required this.onChanged,
    this.onCompleted,
  });

  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;

  @override
  State<_OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<_OtpBoxes> {
  static const int _length = 6;
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_length, (_) => TextEditingController());
    _nodes = List.generate(_length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  void _emit({bool completed = false}) {
    final code = _code;
    widget.onChanged(code);
    if (completed && code.length == _length) {
      widget.onCompleted?.call(code);
    }
  }

  void _handleChanged(int index, String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      _controllers[index].clear();
      _emit();
      return;
    }

    if (digits.length > 1) {
      // Pasted or autofilled full code.
      for (var i = 0; i < _length; i++) {
        _controllers[i].text = i < digits.length ? digits[i] : '';
      }
      final next = (digits.length - 1).clamp(0, _length - 1);
      _nodes[next].requestFocus();
      _emit(completed: true);
      return;
    }

    _controllers[index].text = digits;
    _controllers[index].selection =
        TextSelection.collapsed(offset: digits.length);
    if (index < _length - 1) {
      _nodes[index + 1].requestFocus();
      _emit();
    } else {
      _nodes[index].unfocus();
      _emit(completed: true);
    }
  }

  bool _handleBackspace(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.backspace) return false;
    if (_controllers[index].text.isNotEmpty || index == 0) return false;
    _nodes[index - 1].requestFocus();
    _controllers[index - 1].clear();
    _emit();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < _length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == _length - 1 ? 0 : 7),
                  child: Focus(
                    onKeyEvent: (_, event) =>
                        _handleBackspace(i, event) ? KeyEventResult.handled
                            : KeyEventResult.ignored,
                    child: TextField(
                      controller: _controllers[i],
                      focusNode: _nodes[i],
                      autofocus: i == 0,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      textInputAction: i == _length - 1
                          ? TextInputAction.done
                          : TextInputAction.next,
                      maxLength: 1,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: scheme.outline.withValues(alpha: 0.16),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: scheme.primary,
                            width: 1.8,
                          ),
                        ),
                      ),
                      onChanged: (value) => _handleChanged(i, value),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Tip: you can paste the whole code.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            color: scheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }
}