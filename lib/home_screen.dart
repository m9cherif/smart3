import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'package:smart_student_ai/app_controller.dart';
import 'package:smart_student_ai/app_strings.dart';
import 'package:smart_student_ai/database_service.dart';
import 'package:smart_student_ai/app_customization_panel.dart';
import 'package:smart_student_ai/student_progress_card.dart';
import 'package:smart_student_ai/google_ocr_service.dart';
import 'package:smart_student_ai/ai_service.dart';
import 'package:smart_student_ai/speech_service.dart';
import 'package:smart_student_ai/interactive_quiz_dialog.dart';
import 'dictation_screen.dart';
import 'planner_screen.dart';
import 'revision_screen.dart';
import 'package:smart_student_ai/auth_service.dart';
import 'package:smart_student_ai/profile_screen.dart';
import 'package:smart_student_ai/leaderboard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  StudentProgress? _progress;
  bool _isLoadingProgress = true;
  List<Map<String, dynamic>> _openTasks = [];
  bool _isLoadingTasks = true;
  AuthUser? _userData;
  CloudProgress? _cloudProgress;

  // Learning Hub controllers and services
  final TextEditingController _inputTextController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final GoogleOCRService _ocrService = GoogleOCRService();
  final SpeechService _speechService = SpeechService();
  bool _isProcessingImage = false;
  bool _isGeneratingSummary = false;
  bool _isGeneratingQuiz = false;
  bool _isProcessingPDF = false;
  bool _isListening = false;

  late AnimationController _heroAnimationController;
  late Animation<double> _heroOpacityAnimation;
  late Animation<Offset> _heroSlideAnimation;

  late AnimationController _cardsAnimationController;

  @override
  void initState() {
    super.initState();
    _loadProgress();
    _loadTodayTasks();
    _loadUserData();
    TaskEvents.instance.addListener(_loadTodayTasks);
    _initializeAnimations();
  }

  Future<void> _loadTodayTasks() async {
    try {
      // Debug: First try to get all tasks to see if any exist
      final allTasks = await DatabaseService.instance.getTasks();
      debugPrint('All tasks count: ${allTasks.length}');

      // Then get open tasks
      final taskMaps = await DatabaseService.instance.getTodayTasks();
      debugPrint('Open tasks count: ${taskMaps.length}');

      if (taskMaps.isNotEmpty) {
        debugPrint('First task: ${taskMaps.first}');
      }

      if (mounted) {
        setState(() {
          _openTasks = taskMaps;
          _isLoadingTasks = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading today tasks: $e');
      if (mounted) {
        setState(() {
          _isLoadingTasks = false;
        });
      }
    }
  }

  Future<void> _loadUserData() async {
    final authService = AuthService.instance;
    await authService.initialize();
    final user = authService.currentUser;
    if (user != null && mounted) {
      setState(() {
        _userData = user;
        _cloudProgress = authService.progress;
      });
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in at any time to keep your progress.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirm ?? false) {
      await AuthService.instance.logout();
    }
  }

  Future<void> _toggleTaskCompletion(int taskId, bool completed) async {
    try {
      await DatabaseService.instance.updateTaskStatus(taskId, completed);
      TaskEvents.instance.refresh(); // Notify everyone else and ourselves
    } catch (e) {
      // Handle error silently or show a snackbar
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'High':
        return Colors.red;
      case 'Medium':
        return Colors.orange;
      case 'Low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // Learning Hub functionality
  Future<void> _openTextDialog() async {
    final strings = AppStrings.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        final controller = TextEditingController()
          ..text = _inputTextController.text;
        return AlertDialog(
          title: Text(strings.hubTypeYourText),
          content: SizedBox(
            width: 400,
            child: TextField(
              controller: controller,
              minLines: 6,
              maxLines: 12,
              decoration: InputDecoration(
                hintText: strings.hubEnterHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.hubCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: Text(strings.hubDone),
            ),
          ],
        );
      },
    );

    if (result != null) {
      setState(() {
        _inputTextController.text = result;
      });
    }
  }

  Future<void> _pickFile() async {
    final strings = AppStrings.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'pdf', 'doc', 'docx'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);

        setState(() {
          _isProcessingPDF = true;
          _inputTextController.clear();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(strings.hubProcessingProgress(file.path.split('/').last)),
              duration: const Duration(seconds: 2),
            ),
          );
        }

        try {
          // Extract text from the file (PDF or text)
          final text = await AIService.extractTextFromFile(file);

          setState(() {
            _inputTextController.text = text;
            _isProcessingPDF = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(strings.hubDetectionSuccess),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } catch (e) {
          setState(() {
            _isProcessingPDF = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error extracting text: $e')),
            );
          }
        }
      }
    } catch (e) {
      setState(() {
        _isProcessingPDF = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading file: $e')));
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final strings = AppStrings.of(context);
    try {
      final image = await _imagePicker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _isProcessingImage = true;
        });

        final text = await _ocrService.readText(image.path);
        setState(() {
          _inputTextController.text = text;
          _isProcessingImage = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.hubImageSuccess)),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isProcessingImage = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error processing image: $e')));
      }
    }
  }

  Future<void> _showImageSourceDialog() async {
    final strings = AppStrings.of(context);
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(strings.hubSelectSource),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: Text(strings.hubCamera),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(strings.hubGallery),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source != null) {
      await _pickImage(source);
    }
  }

  Future<void> _speakText() async {
    final strings = AppStrings.of(context);
    setState(() => _isListening = true);

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strings.hubSpeakingStatus),
            duration: const Duration(seconds: 5),
          ),
        );
      }

      // Record for up to 30 seconds (standard for short notes)
      final text = await _speechService.record(
        duration: const Duration(seconds: 30),
        locale: AppScope.of(context).locale,
      );

      if (text.isNotEmpty && !text.startsWith('Error')) {
        setState(() {
          _inputTextController.text = text;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.hubSpeakSuccess)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isListening = false);
      }
    }
  }

  Future<void> _generateSummary() async {
    final strings = AppStrings.of(context);
    if (_inputTextController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.hubSummarizeHint)),
      );
      return;
    }

    setState(() {
      _isGeneratingSummary = true;
    });

    try {
      final summary = await AIService.generateSummary(
        _inputTextController.text,
        language: AppScope.of(context).language,
      );

      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Row(
                children: [
                  Text(strings.hubGeneratedSummary),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              content: SingleChildScrollView(child: Text(summary)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings.hubClose),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingSummary = false;
        });
      }
    }
  }

  Future<void> _generateQuiz() async {
    final strings = AppStrings.of(context);
    if (_inputTextController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.hubQuizHint),
        ),
      );
      return;
    }

    setState(() {
      _isGeneratingQuiz = true;
    });

    try {
      final quizData = await AIService.generateQuiz(
        _inputTextController.text,
        language: AppScope.of(context).language,
      );

      if (mounted && quizData.isNotEmpty) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return InteractiveQuizDialog(
              questions: quizData,
              onClose: () => Navigator.of(context).pop(),
            );
          },
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to generate quiz. Please try with different text.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingQuiz = false;
        });
      }
    }
  }

  void _initializeAnimations() {
    // Hero section animations
    _heroAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _heroOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _heroAnimationController, curve: Curves.easeOut),
    );

    _heroSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _heroAnimationController,
            curve: Curves.easeOut,
          ),
        );

    // Cards animations
    _cardsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // Start animations
    _heroAnimationController.forward();
    _cardsAnimationController.forward();
  }

  Future<void> _loadProgress() async {
    setState(() {
      _isLoadingProgress = true;
    });

    try {
      final progress = await DatabaseService.instance.getStudentProgress();
      if (!mounted) {
        return;
      }

      setState(() {
        _progress = progress;
        _isLoadingProgress = false;
      });

      _syncCloudProgress(progress);
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _progress = null;
        _isLoadingProgress = false;
      });
    }
  }

  /// Mirrors the local XP/activity to the account backend and keeps the
  /// home screen's streak / level chip in sync.
  Future<void> _syncCloudProgress(StudentProgress local) async {
    final auth = AuthService.instance;
    if (!auth.isSignedIn) return;
    try {
      await auth.seedFromLocal(
        xp: local.xp,
        revisionCount: local.revisionCount,
        dictationCount: local.dictationCount,
      );
      await auth.refresh();
      if (mounted) {
        setState(() {
          _cloudProgress = auth.progress;
        });
      }
    } catch (e) {
      debugPrint('Sync cloud progress failed: $e');
    }
  }

  Future<void> _openModule(Widget page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    if (!mounted) {
      return;
    }
    await _loadProgress();
  }

  Future<void> _handleDictationModuleClick() async {
    final strings = AppStrings.of(context);
    final hubText = _inputTextController.text.trim();
    
    if (hubText.isEmpty) {
      _openModule(const DictationScreen());
      return;
    }

    final choice = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.dictationImportTitle),
        content: Text(strings.dictationImportMessage),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 0),
            child: Text(strings.dictationImportNew),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 1),
            child: Text(strings.dictationImportHub),
          ),
        ],
      ),
    );

    if (!mounted || choice == null) return;

    if (choice == 1) {
      _openModule(DictationScreen(initialText: hubText));
    } else {
      _openModule(const DictationScreen());
    }
  }

  @override
  void dispose() {
    TaskEvents.instance.removeListener(_loadTodayTasks);
    _inputTextController.dispose();
    _heroAnimationController.dispose();
    _cardsAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final themeSpec = controller.themeSpec;

    final features = <_FeatureEntry>[
      _FeatureEntry(
        title: strings.plannerTitle,
        subtitle: strings.plannerSubtitle,
        badge: strings.plannerBadge,
        icon: Icons.event_note_rounded,
        accent: colorScheme.primary,
        page: const PlannerScreen(),
      ),
      _FeatureEntry(
        title: strings.revisionTitle,
        subtitle: strings.revisionSubtitle,
        badge: strings.revisionBadge,
        icon: Icons.auto_stories_rounded,
        accent: colorScheme.tertiary,
        page: const RevisionScreen(),
      ),
      _FeatureEntry(
        title: strings.dictationTitle,
        subtitle: strings.dictationSubtitle,
        badge: strings.dictationBadge,
        icon: Icons.mic_external_on_rounded,
        accent: colorScheme.secondary,
        page: const DictationScreen(),
      ),
      _FeatureEntry(
        title: 'Profile & Stats',
        subtitle: 'Your XP, streaks, accuracy and rank',
        badge: 'NEW',
        icon: Icons.insights_rounded,
        accent: colorScheme.primary,
        page: const ProfileScreen(),
      ),
      _FeatureEntry(
        title: 'Leaderboard',
        subtitle: 'See how you rank against other students',
        badge: 'CLASS',
        icon: Icons.emoji_events_rounded,
        accent: const Color(0xFFF59E0B),
        page: const LeaderboardScreen(),
      ),
    ];

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: themeSpec.pageGradient,
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: <Widget>[
              AnimatedBuilder(
                animation: Listenable.merge(<Animation<dynamic>>[
                  _heroOpacityAnimation,
                  _heroSlideAnimation,
                ]),
                builder: (BuildContext context, Widget? child) {
                  return Opacity(
                    opacity: _heroOpacityAnimation.value,
                    child: SlideTransition(
                      position: _heroSlideAnimation,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: themeSpec.heroGradient,
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: themeSpec.primary.withValues(alpha: 0.22),
                              blurRadius: 24,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                // Logo and title inline
                                Image.asset('logo.png', height: 32, width: 32),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    strings.heroTitle,
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(
                                          color: themeSpec.heroForeground,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Settings button
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colorScheme.onPrimary.withValues(
                                      alpha: 0.14,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    onPressed: () =>
                                        showAppCustomizationSheet(context),
                                    tooltip: strings.settingsTooltip,
                                    icon: Icon(
                                      Icons.tune_rounded,
                                      color: themeSpec.heroForeground,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Logout button
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(
                                      alpha: 0.14,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    onPressed: _logout,
                                    tooltip: 'Logout',
                                    icon: Icon(
                                      Icons.logout_rounded,
                                      color: themeSpec.heroForeground,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _userData != null 
                                ? 'Hello, ${_userData!.name}! 👋' 
                                : strings.heroSubtitle,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onPrimary.withValues(
                                  alpha: 0.92,
                                ),
                              ),
                            ),
                            if (_cloudProgress != null) ...[
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: <Widget>[
                                  _heroChip(
                                    icon: Icons.local_fire_department_rounded,
                                    label: '${_cloudProgress!.streak} day streak',
                                    color: themeSpec.heroForeground,
                                  ),
                                  _heroChip(
                                    icon: Icons.bolt_rounded,
                                    label:
                                        '${_cloudProgress!.todayXp}/${_cloudProgress!.dailyGoal} XP today',
                                    color: themeSpec.heroForeground,
                                  ),
                                  _heroChip(
                                    icon: Icons.military_tech_rounded,
                                    label: 'Level ${_cloudProgress!.level}',
                                    color: themeSpec.heroForeground,
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              // Study Planner and Reminder Section
              Row(
                children: <Widget>[
                  // Study Planner Card
                  Expanded(
                    child: _FeatureCard(
                      entry: features[0], // Planner
                      onTap: () => _openModule(features[0].page),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Reminder Card
                  Expanded(
                    child: Card(
                      elevation: 4,
                      shadowColor: colorScheme.primary.withValues(alpha: 0.2),
                      child: InkWell(
                        onTap: () => _openModule(
                          features[0].page,
                        ), // Link to Study Planner
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: <Widget>[
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primary,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: colorScheme.primary
                                                  .withValues(alpha: 0.3),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          strings.hubTasksTitle,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: colorScheme.onPrimary,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: colorScheme.primary
                                                .withValues(alpha: 0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        Icons.checklist_rounded,
                                        color: colorScheme.onPrimary,
                                        size: 24,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  strings.hubStudyTasksTitle,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: colorScheme.primary,
                                        fontSize: 22,
                                      ),
                                ),
                                const SizedBox(height: 12),
                                if (_isLoadingTasks)
                                  SizedBox(
                                    height: 80,
                                    child: Center(
                                      child: SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                colorScheme.primary,
                                              ),
                                        ),
                                      ),
                                    ),
                                  )
                                else if (_openTasks.isEmpty)
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle_outline,
                                          color: colorScheme.primary,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              strings.hubAllTasksDone,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                    color: colorScheme.primary,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 16,
                                                  ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  )
                                else
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.orange.withValues(
                                              alpha: 0.3,
                                            ),
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          strings.hubPendingLabel(_openTasks.length),
                                          style: TextStyle(
                                            color: Colors.orange.shade700,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      ..._openTasks
                                          .take(3)
                                          .map(
                                            (task) => Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              padding: const EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                color: colorScheme.surface,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: colorScheme.outline
                                                      .withValues(alpha: 0.3),
                                                  width: 1,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: 0.05,
                                                        ),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Row(
                                                children: [
                                                  // Priority indicator
                                                  Container(
                                                    width: 6,
                                                    height: 24,
                                                    decoration: BoxDecoration(
                                                      color: _getPriorityColor(
                                                        task['priority']
                                                                as String? ??
                                                            'Medium',
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            3,
                                                          ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  // Checkbox
                                                  InkWell(
                                                    onTap: () =>
                                                        _toggleTaskCompletion(
                                                          task['id'] as int,
                                                          ((task['completed']
                                                                          as int? ??
                                                                      0) ==
                                                                  1)
                                                              ? false
                                                              : true,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                    child: Container(
                                                      width: 24,
                                                      height: 24,
                                                      decoration: BoxDecoration(
                                                        border: Border.all(
                                                          color: colorScheme
                                                              .primary,
                                                          width: 2.5,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                        color:
                                                            (task['completed']
                                                                        as int? ??
                                                                    0) ==
                                                                1
                                                            ? colorScheme
                                                                  .primary
                                                            : Colors
                                                                  .transparent,
                                                      ),
                                                      child:
                                                          (task['completed']
                                                                      as int? ??
                                                                  0) ==
                                                              1
                                                          ? Icon(
                                                              Icons.check,
                                                              size: 16,
                                                              color: colorScheme
                                                                  .onPrimary,
                                                            )
                                                          : null,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  // Task title
                                                  Expanded(
                                                    child: Text(
                                                       task['title']
                                                               as String? ??
                                                           strings.hubUntitledTask,
                                                      style: theme
                                                          .textTheme
                                                          .titleMedium
                                                          ?.copyWith(
                                                            color: colorScheme
                                                                .onSurface,
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            decoration:
                                                                (task['completed']
                                                                            as int? ??
                                                                        0) ==
                                                                    1
                                                                ? TextDecoration
                                                                      .lineThrough
                                                                : null,
                                                          ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                      if (_openTasks.length > 3)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: colorScheme.primary
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                               strings.hubMoreTasks(_openTasks.length - 3),
                                               style: theme.textTheme.bodyLarge
                                                   ?.copyWith(
                                                     color: colorScheme.primary,
                                                     fontWeight: FontWeight.w700,
                                                     fontSize: 14,
                                                   ),
                                             ),
                                          ),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Big Learning Box
              Card(
                elevation: 6,
                shadowColor: colorScheme.primary.withValues(alpha: 0.15),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // Header
                        Row(
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                 strings.hubLearningHubBadge,
                                 style: TextStyle(
                                   color: colorScheme.onPrimary,
                                   fontSize: 14,
                                   fontWeight: FontWeight.w800,
                                   letterSpacing: 1.2,
                                 ),
                               ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.school_rounded,
                              color: colorScheme.primary,
                              size: 28,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Input Section (from Dictation)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.outline.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                               Text(
                                 strings.hubTypeYourText,
                                 style: theme.textTheme.titleLarge?.copyWith(
                                   fontWeight: FontWeight.w700,
                                 ),
                               ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _inputTextController,
                                minLines: 4,
                                maxLines: 6,
                                enabled: !_isProcessingPDF,
                                decoration: InputDecoration(
                                   hintText: _isProcessingPDF
                                       ? strings.hubProcessingPDF
                                       : strings.hubEnterHint,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: _isProcessingPDF
                                      ? Theme.of(
                                          context,
                                        ).disabledColor.withValues(alpha: 0.1)
                                      : colorScheme.surface,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: <Widget>[
                                  ElevatedButton.icon(
                                    onPressed: _isProcessingImage || _isProcessingPDF
                                        ? null
                                        : _openTextDialog,
                                    icon: const Icon(Icons.edit_note_rounded),
                                     label: Text(strings.hubTypeTextButton),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _isProcessingImage || _isProcessingPDF
                                        ? null
                                        : _pickFile,
                                    icon: const Icon(Icons.folder_open_rounded),
                                     label: Text(strings.hubUploadFileButton),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _isProcessingImage || _isProcessingPDF
                                        ? null
                                        : () => _showImageSourceDialog(),
                                    icon: _isProcessingPDF
                                        ? const Icon(Icons.hourglass_empty)
                                        : const Icon(
                                            Icons.photo_camera_outlined,
                                          ),
                                     label: Text(
                                       _isProcessingPDF
                                           ? strings.hubProcessing
                                           : strings.hubScanImageButton,
                                     ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _isProcessingImage || _isProcessingPDF || _isListening
                                        ? null
                                        : _speakText,
                                    icon: _isListening
                                        ? const Icon(Icons.graphic_eq_rounded)
                                        : const Icon(Icons.mic_none_rounded),
                                    label: Text(strings.hubSpeakTextButton),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Three inline sections
                        Row(
                          children: <Widget>[
                            Expanded(
                                child: _GenerationButtonSection(
                                  title: strings.hubSummaryTitle,
                                  subtitle: strings.hubSummarySubtitle,
                                  icon: Icons.summarize_rounded,
                                  color: colorScheme.primary,
                                  isLoading: _isGeneratingSummary,
                                  onGenerate: _generateSummary,
                                  actionLabel: strings.hubGenerateSummaryAction,
                                ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _GenerationButtonSection(
                                  title: strings.hubQuizTitle,
                                  subtitle: strings.hubQuizSubtitle,
                                  icon: Icons.quiz_rounded,
                                  color: colorScheme.tertiary,
                                  isLoading: _isGeneratingQuiz,
                                  onGenerate: _generateQuiz,
                                  actionLabel: strings.hubGenerateQuizAction,
                                ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _GenerationButtonSection(
                                  title: strings.hubDictationTitle,
                                  subtitle: strings.hubDictationSubtitle,
                                   icon: Icons.record_voice_over_rounded,
                                  color: colorScheme.secondary,
                                  onGenerate: _handleDictationModuleClick,
                                  actionLabel: strings.hubPracticeDictationAction,
                                ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Level and XP Section
              if (_isLoadingProgress)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          strings.progressLoading,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                )
              else if (_progress != null)
                StudentProgressCard(
                  progress: _progress!,
                  strings: strings,
                  title: strings.progressTitle,
                  subtitle: strings.progressSubtitle,
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      strings.progressUnavailable,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              // Study tools: profile & leaderboard
              Row(
                children: <Widget>[
                  Expanded(
                    child: _FeatureCard(
                      entry: features[3],
                      onTap: () => _openModule(features[3].page),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FeatureCard(
                      entry: features[4],
                      onTap: () => _openModule(features[4].page),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatefulWidget {
  const _FeatureCard({required this.entry, required this.onTap});

  final _FeatureEntry entry;
  final VoidCallback onTap;

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _scaleController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _scaleController.reverse();
  }

  void _handleTapCancel() {
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (BuildContext context, Widget? child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: widget.onTap,
                onTapDown: _handleTapDown,
                onTapUp: _handleTapUp,
                onTapCancel: _handleTapCancel,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: widget.entry.accent.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(
                              widget.entry.icon,
                              color: widget.entry.accent,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  widget.entry.title,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  widget.entry.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: widget.entry.accent.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                widget.entry.badge.toUpperCase(),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: widget.entry.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FeatureEntry {
  const _FeatureEntry({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
    required this.accent,
    required this.page,
  });

  final String title;
  final String subtitle;
  final String badge;
  final IconData icon;
  final Color accent;
  final Widget page;
}

class _GenerationButtonSection extends StatelessWidget {
  const _GenerationButtonSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onGenerate,
    required this.actionLabel,
    this.isLoading = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onGenerate;
  final String actionLabel;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Action Buttons Row
          Row(
            children: [
              // Generation Button
              Expanded(
                child: FilledButton.icon(
                  onPressed: isLoading ? null : onGenerate,
                  icon: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(icon, size: 18),
                  label: Text(actionLabel),
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
