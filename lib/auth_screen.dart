import 'package:flutter/material.dart';
import 'package:smart_student_ai/app_controller.dart';
import 'package:smart_student_ai/firebase_auth_service.dart';

/// The primary authentication screen supporting both Login and Sign Up.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  
  bool _isLogin = true;
  bool _isLoading = false;
  String? _errorMessage;

  final FirebaseAuthService _authService = FirebaseAuthService();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// Handles form submission and toggles between SignIn and SignUp.
  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    String? result;
    if (_isLogin) {
      result = await _authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } else {
      result = await _authService.signUp(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMessage = result;
      });
      // Errors are displayed inline; success is handled by the AuthWrapper stream.
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeSpec = AppScope.of(context).themeSpec;
    final brightness = AppScope.of(context).brightnessMode;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
              constraints: const BoxConstraints(maxWidth: 450),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: Card(
                  elevation: 20,
                  shadowColor: Colors.black26,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // App Branding Section
                          Center(
                            child: Column(
                              children: [
                                Hero(
                                  tag: 'app_logo',
                                  child: Image.asset(
                                    'logo.png',
                                    width: 90,
                                    height: 90,
                                    errorBuilder: (_, _, _) => Icon(
                                      Icons.school_rounded,
                                      size: 70,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  _isLogin ? 'Welcome Back!' : 'Create Account',
                                  style: textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: colorScheme.onSurface,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _isLogin 
                                    ? 'Log in to continue your learning journey' 
                                    : 'Join Smart Student AI today for free',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
    
                          // Error Visibility Block
                          if (_errorMessage != null)
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: const Duration(milliseconds: 400),
                              builder: (context, value, child) => Opacity(
                                opacity: value,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 20),
                                  decoration: BoxDecoration(
                                    color: colorScheme.errorContainer.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: colorScheme.error.withValues(alpha: 0.4)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.error_outline_rounded, color: colorScheme.error, size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: TextStyle(color: colorScheme.error, fontSize: 13, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
    
                          // Dynamic Name Field for Registration
                          if (!_isLogin)
                            _buildTextField(
                              controller: _nameController,
                              label: 'Full Name',
                              icon: Icons.person_outline_rounded,
                              validator: (val) => val == null || val.isEmpty ? 'Please enter your name' : null,
                            ),
                          if (!_isLogin) const SizedBox(height: 16),
    
                          // Email Field for Both
                          _buildTextField(
                            controller: _emailController,
                            label: 'Email Address',
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            validator: (val) {
                              if (val == null || val.isEmpty) return 'Please enter your email';
                              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val)) return 'Invalid email format';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
    
                          // Password Field for Both
                          _buildTextField(
                            controller: _passwordController,
                            label: 'Password',
                            icon: Icons.lock_outline_rounded,
                            isPassword: true,
                            validator: (val) {
                              if (val == null || val.isEmpty) return 'Please enter your password';
                              if (val.length < 6) return 'Password must be at least 6 characters';
                              return null;
                            },
                          ),
                          const SizedBox(height: 32),
    
                          // Action Button
                          ElevatedButton(
                            onPressed: _isLoading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              elevation: 4,
                              shadowColor: colorScheme.primary.withValues(alpha: 0.4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                  )
                                : Text(
                                    _isLogin ? 'LOGIN' : 'CREATE ACCOUNT',
                                    style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
                                  ),
                          ),
                          const SizedBox(height: 20),
    
                          // Auth Perspective Toggle
                          TextButton(
                            onPressed: () => setState(() {
                              _isLogin = !_isLogin;
                              _errorMessage = null;
                            }),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7)),
                                children: [
                                  TextSpan(text: _isLogin ? "Don't have an account? " : "Already have an account? "),
                                  TextSpan(
                                    text: _isLogin ? "Sign Up" : "Login",
                                    style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ),
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

  /// Helper to build consistent styling for text inputs.
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextFormField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: keyboardType,
      style: const TextStyle(fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 22),
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.1)),
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
