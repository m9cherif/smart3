import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:smart_student_ai/app_controller.dart';
import 'package:smart_student_ai/auth_service.dart';

enum _AuthMode { signIn, signUp, verify, forgot, reset }

/// The primary authentication screen: login, sign up, email OTP verification
/// and the forgot / reset-password flows.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();

  final AuthService _authService = AuthService.instance;

  _AuthMode _mode = _AuthMode.signIn;
  bool _isLoading = false;
  bool _obscure = true;
  String? _errorMessage;
  String? _infoMessage;
  String? _pendingEmail;

  late final AnimationController _animController;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _animController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _setMode(_AuthMode mode, {String? error, String? info}) {
    setState(() {
      _mode = mode;
      _errorMessage = error;
      _infoMessage = info;
      _codeController.clear();
      _newPasswordController.clear();
    });
    _animController
      ..reset()
      ..forward();
  }

  Future<void> _run(Future<AuthResult> Function() action, {void Function(AuthResult)? onOk}) async {
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
        error: result.error,
        info: 'Enter the 6-digit code we emailed to $_pendingEmail.',
      );
      return;
    }

    setState(() => _errorMessage = result.error);
  }

  void _submitSignIn() {
    if (!_formKey.currentState!.validate()) return;
    _run(
      () => _authService.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      ),
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
          info: r.message ?? 'Enter the 6-digit code we emailed to $_pendingEmail.',
        );
      },
    );
  }

  void _submitVerify() {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit code.');
      return;
    }
    _run(
      () => _authService.verify(
        email: _pendingEmail ?? _emailController.text,
        code: code,
      ),
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
          info: r.message ?? 'If that email exists, a reset code has been sent.',
        );
      },
    );
  }

  void _submitReset() {
    if (!_formKey.currentState!.validate()) return;
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit code.');
      return;
    }
    _run(
      () => _authService.reset(
        email: _pendingEmail ?? _emailController.text,
        code: code,
        password: _newPasswordController.text,
      ),
      onOk: (r) => _setMode(_AuthMode.signIn, info: r.message ?? 'Password updated. Please sign in.'),
    );
  }

  Future<void> _resend() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    final purpose = _mode == _AuthMode.reset ? 'reset' : 'verify';
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

  @override
  Widget build(BuildContext context) {
    final themeSpec = AppScope.of(context).themeSpec;
    final brightness = AppScope.of(context).brightnessMode;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final (title, subtitle) = switch (_mode) {
      _AuthMode.signIn => ('Welcome Back!', 'Log in to continue your learning journey'),
      _AuthMode.signUp => ('Create Account', 'Join Smart Student AI today for free'),
      _AuthMode.verify => ('Verify Your Email', 'We sent a 6-digit code to your inbox'),
      _AuthMode.forgot => ('Forgot Password', 'We\'ll email you a reset code'),
      _AuthMode.reset => ('Reset Password', 'Enter the code and choose a new password'),
    };

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: themeSpec.pageGradientFor(brightness),
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: FadeTransition(
                opacity: _fadeIn,
                child: Card(
                  elevation: 24,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeInOut,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeader(context, title, subtitle, textTheme, colorScheme),
                          const SizedBox(height: 26),
                          if (_errorMessage != null) _buildBanner(_errorMessage!, isError: true),
                          if (_infoMessage != null) _buildBanner(_infoMessage!, isError: false),
                          Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: _buildFields(colorScheme),
                            ),
                          ),
                          const SizedBox(height: 28),
                          _buildPrimaryButton(context, colorScheme),
                          const SizedBox(height: 12),
                          _buildSecondaryActions(context, textTheme, colorScheme),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    String title,
    String subtitle,
    TextTheme textTheme,
    ColorScheme colorScheme,
  ) {
    return Column(
      children: [
        Hero(
          tag: 'app_logo',
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
            ),
            child: Image.asset(
              'logo.png',
              width: 64,
              height: 64,
              errorBuilder: (_, _, _) => Icon(
                Icons.school_rounded,
                size: 56,
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  List<Widget> _buildFields(ColorScheme colorScheme) {
    switch (_mode) {
      case _AuthMode.signIn:
        return [
          _field(
            controller: _emailController,
            label: 'Email Address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: _emailValidator,
          ),
          const SizedBox(height: 16),
          _field(
            controller: _passwordController,
            label: 'Password',
            icon: Icons.lock_outline_rounded,
            isPassword: true,
            validator: (v) => (v == null || v.isEmpty) ? 'Please enter your password' : null,
          ),
        ];
      case _AuthMode.signUp:
        return [
          _field(
            controller: _nameController,
            label: 'Full Name',
            icon: Icons.person_outline_rounded,
            validator: (v) => (v == null || v.trim().length < 2) ? 'Please enter your name' : null,
          ),
          const SizedBox(height: 16),
          _field(
            controller: _emailController,
            label: 'Email Address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: _emailValidator,
          ),
          const SizedBox(height: 16),
          _field(
            controller: _passwordController,
            label: 'Password',
            icon: Icons.lock_outline_rounded,
            isPassword: true,
            validator: (v) => (v == null || v.length < 8)
                ? 'Use at least 8 characters'
                : null,
          ),
        ];
      case _AuthMode.verify:
        return [
          _field(
            controller: _codeController,
            label: 'Verification Code',
            icon: Icons.verified_outlined,
            keyboardType: TextInputType.number,
            maxLength: 6,
            big: true,
          ),
        ];
      case _AuthMode.forgot:
        return [
          _field(
            controller: _emailController,
            label: 'Email Address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: _emailValidator,
          ),
        ];
      case _AuthMode.reset:
        return [
          _field(
            controller: _codeController,
            label: 'Reset Code',
            icon: Icons.password_rounded,
            keyboardType: TextInputType.number,
            maxLength: 6,
            big: true,
          ),
          const SizedBox(height: 16),
          _field(
            controller: _newPasswordController,
            label: 'New Password',
            icon: Icons.lock_reset_rounded,
            isPassword: true,
            validator: (v) => (v == null || v.length < 8)
                ? 'Use at least 8 characters'
                : null,
          ),
        ];
    }
  }

  Widget _buildPrimaryButton(BuildContext context, ColorScheme colorScheme) {
    final label = switch (_mode) {
      _AuthMode.signIn => 'LOGIN',
      _AuthMode.signUp => 'CREATE ACCOUNT',
      _AuthMode.verify => 'VERIFY & CONTINUE',
      _AuthMode.forgot => 'SEND RESET CODE',
      _AuthMode.reset => 'SET NEW PASSWORD',
    };
    final onPressed = _isLoading
        ? null
        : switch (_mode) {
            _AuthMode.signIn => _submitSignIn,
            _AuthMode.signUp => _submitSignUp,
            _AuthMode.verify => _submitVerify,
            _AuthMode.forgot => _submitForgot,
            _AuthMode.reset => _submitReset,
          };

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 6,
        shadowColor: colorScheme.primary.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: _isLoading
          ? SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: colorScheme.onPrimary),
            )
          : Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
            ),
    );
  }

  Widget _buildSecondaryActions(
    BuildContext context,
    TextTheme textTheme,
    ColorScheme colorScheme,
  ) {
    switch (_mode) {
      case _AuthMode.signIn:
        return Column(
          children: [
            TextButton(
              onPressed: _isLoading ? null : () => _setMode(_AuthMode.forgot),
              child: Text(
                'Forgot password?',
                style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w600),
              ),
            ),
            _toggleText(
              textTheme,
              colorScheme,
              "Don't have an account? ",
              'Sign Up',
              () => _setMode(_AuthMode.signUp),
            ),
          ],
        );
      case _AuthMode.signUp:
        return _toggleText(
          textTheme,
          colorScheme,
          'Already have an account? ',
          'Login',
          () => _setMode(_AuthMode.signIn),
        );
      case _AuthMode.verify:
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
                        _mode == _AuthMode.reset ? _AuthMode.forgot : _AuthMode.signIn,
                      ),
              child: const Text('Back'),
            ),
          ],
        );
      case _AuthMode.forgot:
        return TextButton(
          onPressed: _isLoading ? null : () => _setMode(_AuthMode.signIn),
          child: const Text('Back to login'),
        );
    }
  }

  Widget _toggleText(
    TextTheme textTheme,
    ColorScheme colorScheme,
    String lead,
    String action,
    VoidCallback onTap,
  ) {
    return TextButton(
      onPressed: _isLoading ? null : onTap,
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          children: [
            TextSpan(text: lead),
            TextSpan(
              text: action,
              style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBanner(String message, {required bool isError}) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isError ? colorScheme.error : colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String? _emailValidator(String? val) {
    if (val == null || val.trim().isEmpty) return 'Please enter your email';
    if (!RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(val.trim())) {
      return 'Invalid email format';
    }
    return null;
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool big = false,
    int? maxLength,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextFormField(
      controller: controller,
      obscureText: isPassword && _obscure,
      keyboardType: keyboardType,
      maxLength: maxLength,
      textAlign: big ? TextAlign.center : TextAlign.start,
      inputFormatters: maxLength != null && keyboardType == TextInputType.number
          ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(maxLength)]
          : null,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: big ? 26 : 15,
        letterSpacing: big ? 12 : 0,
      ),
      decoration: InputDecoration(
        counterText: '',
        labelText: label,
        prefixIcon: !big ? Icon(icon, size: 22) : null,
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              )
            : null,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
        ),
        floatingLabelStyle: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold),
      ),
      validator: validator,
    );
  }
}
