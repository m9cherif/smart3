import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:smart_student_ai/app_controller.dart';
import 'package:smart_student_ai/app_strings.dart';
import 'package:smart_student_ai/notification_service.dart';
import 'package:smart_student_ai/ai_service.dart';
import 'package:smart_student_ai/tray_service.dart';
import 'package:smart_student_ai/database_service.dart';
import 'launch_gate.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Force the app to open and stay in horizontal (landscape) mode
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    runApp(const SmartStudentApp());
  } catch (e, stack) {
    debugPrint('Main: FATAL ERROR during startup: $e');
    debugPrint(stack.toString());
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Fatal error during app startup: $e'),
        ),
      ),
    ));
  }
}

Future<void> _initializeBackgroundServices() async {
  try {
    debugPrint('Main: Starting background service initializations...');
    
    // Core orientations are now handled in main() for immediate effect
    

    // We run these in parallel and catch any issues per service
    await Future.wait([
      AIService.initialize().catchError((e) => debugPrint('AIService init failed: $e')),
      NotificationService.instance.initialize().catchError((e) => debugPrint('NotificationService init failed: $e')),
      TrayService.instance.initialize().catchError((e) => debugPrint('TrayService init failed: $e')),
      DatabaseService.instance.initialize().catchError((e) => debugPrint('Database init failed: $e')),
    ]).timeout(const Duration(seconds: 10), onTimeout: () {
      debugPrint('Main: Background services initialization timed out after 10s');
      return [];
    });
    
    debugPrint('Main: Background services initialization completed.');
  } catch (e) {
    debugPrint('Main: Background service initialization threw an error: $e');
  }
}

class SmartStudentApp extends StatefulWidget {
  const SmartStudentApp({super.key});

  @override
  State<SmartStudentApp> createState() => _SmartStudentAppState();
}

class _SmartStudentAppState extends State<SmartStudentApp> {
  late final Future<void> _initFuture;
  final AppController _controller = AppController();

  @override
  void initState() {
    super.initState();
    _initFuture = _fullInitialization();
  }

  Future<void> _fullInitialization() async {
    try {
      // 1. Core platform readiness
      debugPrint('App: Starting full initialization...');
      
      // 2. Start all horizontal services in parallel for maximum speed
      await Future.wait([
        // SharedPreferences and Controller state
        _controller.load(),
        
        // Horizontal background services
        _initializeBackgroundServices(),
      ]);
      
      debugPrint('App: Full initialization completed.');
    } catch (e) {
      debugPrint('App: Error during initialization sequence: $e');
      // We continue anyway and let UI components handle their own error states
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: _controller,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: NotificationService.instance.messengerKey,
            onGenerateTitle: (context) => AppStrings.of(context).appName,
            theme: _controller.themeData,
            locale: _controller.locale,
            supportedLocales: const <Locale>[
              Locale('en'),
              Locale('fr'),
              Locale('ar'),
            ],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: FutureBuilder<void>(
              future: _initFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const _LaunchLoadingScreen();
                }
                return const LaunchGate();
              },
            ),
          );
        },
      ),
    );
  }
}

class _LaunchLoadingScreen extends StatelessWidget {
  const _LaunchLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final themeSpec = AppScope.of(context).themeSpec;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: themeSpec.pageGradient,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -120,
              right: -80,
              child: _LaunchGlow(
                color: themeSpec.primary.withValues(alpha: 0.18),
                size: 340,
              ),
            ),
            Positioned(
              bottom: -140,
              left: -100,
              child: _LaunchGlow(
                color: themeSpec.secondary.withValues(alpha: 0.14),
                size: 380,
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(34),
                      boxShadow: [
                        BoxShadow(
                          color: themeSpec.primary.withValues(alpha: 0.16),
                          blurRadius: 40,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'logo.png',
                      width: 104,
                      height: 104,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.school_rounded,
                        size: 80,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'Smart Student AI',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: themeSpec.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Learn smarter, every day',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.primary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LaunchGlow extends StatelessWidget {
  const _LaunchGlow({required this.color, required this.size});

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
