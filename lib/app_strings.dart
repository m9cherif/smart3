import 'package:flutter/widgets.dart';

import 'app_controller.dart';

class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;

  static AppStrings of(BuildContext context) {
    return AppStrings(AppScope.of(context).language);
  }

  String get appName => 'Smart Student AI';

  String get heroBadge => _pick(
    en: '',
    fr: '',
    ar: '',
  );

  String get heroTitle => 'Smart Student AI';

  String get heroSubtitle => _pick(
    en: 'Your intelligent companion for academic success.',
    fr: 'Votre compagnon intelligent pour le succès académique.',
    ar: 'رفيقك الذكي للنجاح الأكاديمي.',
  );

  String get metricModules => _pick(
    en: '3 learning modules',
    fr: '3 modules d apprentissage',
    ar: '3 وحدات تعلم',
  );

  String get metricThemes =>
      _pick(en: '3 themes', fr: '3 thèmes', ar: '3 سمات');

  String get metricLanguages =>
      _pick(en: '3 app languages', fr: '3 langues', ar: '3 لغات');

  String get customizeWorkspaceTitle => _pick(
    en: 'Shape the workspace',
    fr: 'Personnalise l espace',
    ar: 'خصص مساحة التعلم',
  );

  String get customizeWorkspaceSubtitle => _pick(
    en: 'Switch theme, brightness and language instantly. Your choices stay saved for the next launch.',
    fr: 'Change le theme, la luminosite et la langue instantanement. Les choix restent enregistres.',
    ar: 'بدّل السمة والسطوع واللغة. يتم حفظ اختياراتك.',
  );

  String get themeSectionTitle =>
      _pick(en: 'Themes', fr: 'Themes', ar: 'السمات');

  String get brightnessSectionTitle =>
      _pick(en: 'Brightness', fr: 'Luminosite', ar: 'السطوع');

  String get brightnessLightLabel =>
      _pick(en: 'Light', fr: 'Clair', ar: 'فاتح');

  String get brightnessDarkLabel =>
      _pick(en: 'Dark', fr: 'Sombre', ar: 'داكن');

  String get languageSectionTitle =>
      _pick(en: 'Languages', fr: 'Langues', ar: 'اللغات');

  String get settingsTooltip => _pick(
    en: 'Theme, brightness and language',
    fr: 'Theme, luminosite et langue',
    ar: 'السمة والسطوع واللغة',
  );


  String get accountLabel =>
      _pick(en: 'Account', fr: 'Compte', ar: 'الحساب');

  String get accountGuest => _pick(
    en: 'Anonymous user',
    fr: 'Utilisateur anonyme',
    ar: 'مستخدم مجهول',
  );

  String get logoutLabel => _pick(
    en: 'Logout',
    fr: 'Se deconnecter',
    ar: 'تسجيل الخروج',
  );



  String get launchModuleTitle =>
      _pick(en: 'Launch a module', fr: 'Lance un module', ar: 'افتح وحدة');

  String get launchModuleSubtitle => _pick(
    en: 'Each module is tuned for a different part of the Primary 7 study cycle.',
    fr: 'Chaque module cible une etape differente du travail en 7e primaire.',
    ar: 'كل وحدة مهيأة لجزء مختلف من دورة الدراسة في الصف السابع.',
  );

  String get progressTitle =>
      _pick(en: 'Level and XP', fr: 'Niveau et XP', ar: 'المستوى وXP');

  String get progressSubtitle => _pick(
    en: 'Revision questions and dictation sessions now build saved progress automatically.',
    fr: 'Les questions de revision et les dictees alimentent maintenant une progression sauvegardee.',
    ar: 'أسئلة المراجعة وجلسات الإملاء تبني الآن تقدماً محفوظاً تلقائياً.',
  );

  String progressLevelLabel(int level) =>
      _pick(en: 'Level $level', fr: 'Niveau $level', ar: 'المستوى $level');

  String progressXpLabel(int xp) =>
      _pick(en: '$xp XP total', fr: '$xp XP au total', ar: '$xp XP إجمالي');

  String progressNextLevelLabel(int current, int target) => _pick(
    en: 'Next level: $current / $target XP',
    fr: 'Niveau suivant : $current / $target XP',
    ar: 'المستوى التالي: $current / $target XP',
  );

  String get progressQuestionsLabel => _pick(
    en: 'Questions saved',
    fr: 'Questions sauvegardees',
    ar: 'الأسئلة المحفوظة',
  );

  String get progressDictationsLabel => _pick(
    en: 'Dictations saved',
    fr: 'Dictees sauvegardees',
    ar: 'الإملاءات المحفوظة',
  );

  String get progressUnavailable => _pick(
    en: 'Saved progress is unavailable on this device right now.',
    fr: 'La progression sauvegardee est indisponible sur cet appareil pour le moment.',
    ar: 'التقدم المحفوظ غير متاح على هذا الجهاز حالياً.',
  );

  String get progressLoading => _pick(
    en: 'Loading progress...',
    fr: 'Chargement de la progression...',
    ar: 'جاري تحميل التقدم...',
  );

  String progressXpSavedMessage(int xp, int level) => _pick(
    en: '+$xp XP saved. Level $level.',
    fr: '+$xp XP sauvegardes. Niveau $level.',
    ar: '+$xp XP تم حفظها. المستوى $level.',
  );

  String progressLevelUpMessage(int xp, int level) => _pick(
    en: '+$xp XP. Level up to $level.',
    fr: '+$xp XP. Passage au niveau $level.',
    ar: '+$xp XP. وصلت إلى المستوى $level.',
  );

  String get progressSaveFailed => _pick(
    en: 'Progress could not be saved right now.',
    fr: 'La progression n a pas pu etre sauvegardee pour le moment.',
    ar: 'تعذر حفظ التقدم الآن.',
  );

  String get plannerTitle => _pick(
    en: 'Study Planner',
    fr: 'Planificateur d etude',
    ar: 'مخطط الدراسة',
  );

  String get plannerSubtitle => _pick(
    en: 'Capture homework, set deadlines, and keep the week under control.',
    fr: 'Ajoute les devoirs, fixe des dates limites et garde la semaine maitrisee.',
    ar: 'سجل الواجبات، وحدد المواعيد، وسيطر على اسبوعك الدراسي.',
  );

  String get plannerBadge => _pick(
    en: 'Persistent tasks',
    fr: 'Taches sauvegardees',
    ar: 'مهام محفوظة',
  );

  String get revisionTitle =>
      _pick(en: 'Revision Coach', fr: 'Coach de revision', ar: 'مدرب المراجعة');

  String get revisionSubtitle => _pick(
    en: 'Practice Primary 7 questions, track scores, and build revision rhythm.',
    fr: 'Entraine toi avec des questions de 7e primaire et suis tes scores.',
    ar: 'تدرّب على اسئلة الصف السابع وتابع تقدمك في المراجعة.',
  );

  String get revisionBadge => _pick(
    en: 'Primary 7 bank',
    fr: 'Banque 7e primaire',
    ar: 'بنك الصف السابع',
  );

  String get dictationTitle => _pick(
    en: 'Dictation Lab',
    fr: 'Laboratoire de dictee',
    ar: 'مختبر الاملاء',
  );

  String get dictationSubtitle => _pick(
    en: 'Scan a passage, record the learner, and inspect accuracy word by word.',
    fr: 'Scanne un texte, enregistre l eleve et verifie la precision mot par mot.',
    ar: 'امسح النص، وسجل التلميذ، ثم راجع الدقة كلمة بكلمة.',
  );

  String get dictationBadge =>
      _pick(en: 'OCR + speech', fr: 'OCR + voix', ar: 'OCR + صوت');

  String get dictationImportTitle => _pick(
    en: 'Use Hub Text?',
    fr: 'Utiliser le texte du Hub ?',
    ar: 'استخدام نص المركز؟',
  );

  String get dictationImportMessage => _pick(
    en: 'Do you want to use the text currently in your Learning Hub, or start with a new input?',
    fr: 'Voulez-vous utiliser le texte actuel du Hub d\'apprentissage ou commencer avec une nouvelle saisie ?',
    ar: 'هل تريد استخدام النص الموجود حالياً في مركز التعلم، أم البدء بمدخلات جديدة؟',
  );

  String get dictationImportNew => _pick(
    en: 'New Input',
    fr: 'Nouvelle saisie',
    ar: 'مدخلات جديدة',
  );

  String get dictationImportHub => _pick(
    en: 'Use Hub Text',
    fr: 'Utiliser le texte du Hub',
    ar: 'استخدام نص المركز',
  );

  String get dictationFileNotFound => _pick(
    en: 'Selected file not found',
    fr: 'Fichier sélectionné introuvable',
    ar: 'الملف المحدد غير موجود',
  );

  String get dictationProcessingCancelled => _pick(
    en: 'Processing cancelled',
    fr: 'Traitement annulé',
    ar: 'تم إلغاء المعالجة',
  );

  String get dictationCancel => _pick(
    en: 'Cancel',
    fr: 'Annuler',
    ar: 'إلغاء',
  );

  String get dictationImagePickerFailed => _pick(
    en: 'Failed to pick image',
    fr: 'Échec de la sélection d\'image',
    ar: 'فشل في اختيار الصورة',
  );

  String get dictationFilePickerFailed => _pick(
    en: 'Failed to pick file',
    fr: 'Échec de la sélection de fichier',
    ar: 'فشل في اختيار الملف',
  );

  String themeName(AppThemeOption option) {
    return switch (option) {
      AppThemeOption.ocean => _pick(en: 'Ocean', fr: 'Océan', ar: 'بحر'),
      AppThemeOption.sunrise => _pick(en: 'Sunrise', fr: 'Aube', ar: 'فجر'),
      AppThemeOption.forest => _pick(en: 'Forest', fr: 'Forêt', ar: 'غابة'),
      AppThemeOption.custom => _pick(en: 'Custom', fr: 'Personnalisé', ar: 'مخصص'),
    };
  }

  String get customColorSectionTitle => _pick(
    en: 'Custom color',
    fr: 'Couleur personnalisée',
    ar: 'اللون المخصص',
  );

  String get customColorPickerHint => _pick(
    en: 'Tap a color to apply, or use the slider to explore.',
    fr: 'Appuie sur une couleur pour l\'appliquer ou utilise la barre.',
    ar: 'اضغط على لون لتطبيقه أو استخدم شريط التمرير.',
  );

  String get settingsResetData => _pick(
    en: 'Reset all data',
    fr: 'Réinitialiser les données',
    ar: 'إعادة تعيين البيانات',
  );

  String get settingsResetDataConfirmTitle => _pick(
    en: 'Clear everything?',
    fr: 'Tout effacer ?',
    ar: 'مسح الكل؟',
  );

  String get settingsResetDataConfirmMessage => _pick(
    en: 'This will delete all stored progress and tasks. This action cannot be undone.',
    fr: 'Cela supprimera toutes les progressions et tâches enregistrées. Cette action est irréversible.',
    ar: 'سيؤدي هذا إلى حذف كل التقدّم والمهام المخزنة. لا يمكن التراجع عن هذا الإجراء.',
  );

  String get settingsResetDataConfirmAction => _pick(
    en: 'Reset',
    fr: 'Réinitialiser',
    ar: 'إعادة',
  );

  String languageName(AppLanguage option) {
    return switch (option) {
      AppLanguage.english => _pick(
        en: 'English',
        fr: 'Anglais',
        ar: 'الانجليزية',
      ),
      AppLanguage.french => _pick(en: 'French', fr: 'Francais', ar: 'الفرنسية'),
      AppLanguage.arabic => _pick(en: 'Arabic', fr: 'Arabe', ar: 'العربية'),
    };
  }

  String get plannerClearCompletedTooltip => _pick(
    en: 'Clear completed',
    fr: 'Supprimer les terminees',
    ar: 'حذف المهام المكتملة',
  );

  String get plannerCaptureTitle => _pick(
    en: 'Capture the next task',
    fr: 'Ajoute la prochaine tache',
    ar: 'اضف المهمة التالية',
  );

  String get plannerCaptureSubtitle => _pick(
    en: 'Add a task, set its priority, and attach a due date when needed.',
    fr: 'Ajoute une tache, choisis sa priorite et fixe une date si besoin.',
    ar: 'اضف مهمة وحدد اولويتها وتاريخها عند الحاجة.',
  );

  String get plannerTaskTitleLabel =>
      _pick(en: 'Task title', fr: 'Titre de la tache', ar: 'عنوان المهمة');

  String get plannerTaskTitleHint => _pick(
    en: 'Finish algebra worksheet',
    fr: 'Finir la fiche d algebre',
    ar: 'انهاء ورقة الجبر',
  );

  String get plannerPriorityLabel =>
      _pick(en: 'Priority', fr: 'Priorite', ar: 'الاولوية');

  String get plannerNoDueDate =>
      _pick(en: 'No due date', fr: 'Pas de date', ar: 'بدون تاريخ');

  String get plannerNoTime =>
      _pick(en: 'No time', fr: 'Pas d\'heure', ar: 'بدون توقيت');

  String get plannerAddTask =>
      _pick(en: 'Add task', fr: 'Ajouter', ar: 'اضف المهمة');

  String get plannerSaving =>
      _pick(en: 'Saving...', fr: 'Enregistrement...', ar: 'جارٍ الحفظ...');

  String get plannerOpen => _pick(en: 'Open', fr: 'Ouvertes', ar: 'مفتوحة');

  String get plannerDone => _pick(en: 'Done', fr: 'Terminees', ar: 'منجزة');

  String get plannerDueSoon =>
      _pick(en: 'Due soon', fr: 'Bientot dues', ar: 'قريبة');

  String get plannerTaskBoard =>
      _pick(en: 'Task board', fr: 'Tableau des taches', ar: 'لوحة المهام');

  String get plannerTaskBoardSubtitle => _pick(
    en: 'Pull to refresh after external changes.',
    fr: 'Tire pour actualiser apres des changements externes.',
    ar: 'اسحب للتحديث بعد اي تغييرات خارجية.',
  );

  String get plannerEmptyTitle => _pick(
    en: 'Your planner is clear.',
    fr: 'Le planning est vide.',
    ar: 'مخططك فارغ.',
  );

  String get plannerEmptySubtitle => _pick(
    en: 'Add the first task above to start structuring the week.',
    fr: 'Ajoute la premiere tache ci-dessus pour organiser la semaine.',
    ar: 'اضف اول مهمة في الاعلى لبدء تنظيم الاسبوع.',
  );

  String get plannerDeleteTaskTooltip =>
      _pick(en: 'Delete task', fr: 'Supprimer la tache', ar: 'حذف المهمة');

  String get plannerErrorTitle => _pick(
    en: 'Planner unavailable',
    fr: 'Planning indisponible',
    ar: 'المخطط غير متاح',
  );

  String plannerErrorMessage(String details) => _pick(
    en: 'The planner storage could not start. $details',
    fr: 'Le stockage du planning n a pas pu demarrer. $details',
    ar: 'تعذر تشغيل تخزين المخطط. $details',
  );

  String get retryAction =>
      _pick(en: 'Retry', fr: 'Reessayer', ar: 'اعادة المحاولة');

  String plannerTaskAddedMessage() => _pick(
    en: 'Task added to your planner.',
    fr: 'La tache a ete ajoutee au planning.',
    ar: 'تمت اضافة المهمة الى المخطط.',
  );

  String plannerTaskRemovedMessage(String taskTitle) => _pick(
    en: 'Removed "$taskTitle" from the planner.',
    fr: '"$taskTitle" a ete retire du planning.',
    ar: 'تم حذف "$taskTitle" من المخطط.',
  );

  String plannerClearedCompletedMessage(int count) => _pick(
    en: 'Cleared $count completed task(s).',
    fr: '$count tache(s) terminee(s) supprimee(s).',
    ar: 'تم حذف $count مهمة مكتملة.',
  );

  String plannerDeadlineLabel(String date) =>
      _pick(en: 'Due $date', fr: 'Pour $date', ar: 'الاستحقاق $date');

  String plannerAddedLabel(String date) =>
      _pick(en: 'Added $date', fr: 'Ajoutee $date', ar: 'اضيفت $date');

  String get plannerNoDeadline =>
      _pick(en: 'No deadline', fr: 'Sans date limite', ar: 'بدون موعد');

  String priorityLabel(String priority) {
    return switch (priority) {
      'High' => _pick(en: 'High', fr: 'Haute', ar: 'عالية'),
      'Low' => _pick(en: 'Low', fr: 'Faible', ar: 'منخفضة'),
      _ => _pick(en: 'Medium', fr: 'Moyenne', ar: 'متوسطة'),
    };
  }

  String get revisionRestartTooltip => _pick(
    en: 'Restart session',
    fr: 'Redemarrer la session',
    ar: 'اعادة الجلسة',
  );

  String get revisionActiveSessionTitle => _pick(
    en: 'Active revision session',
    fr: 'Session de revision active',
    ar: 'جلسة مراجعة نشطة',
  );

  String get revisionActiveSessionSubtitle => _pick(
    en: 'Switch subjects, answer Primary 7 questions, and keep an eye on your score.',
    fr: 'Change de matiere, reponds aux questions de 7e primaire et suis ton score.',
    ar: 'بدّل المواد، واجب عن اسئلة الصف السابع، وراقب نتيجتك.',
  );

  String revisionQuestionCounter(int current, int total) => _pick(
    en: 'Question $current of $total',
    fr: 'Question $current sur $total',
    ar: 'السؤال $current من $total',
  );

  String get revisionSessionScore =>
      _pick(en: 'Session score', fr: 'Score session', ar: 'نتيجة الجلسة');

  String get revisionBestScore =>
      _pick(en: 'Best score', fr: 'Meilleur score', ar: 'افضل نتيجة');

  String get revisionSessions =>
      _pick(en: 'Sessions', fr: 'Sessions', ar: 'الجلسات');

  String get revisionSubjectFocus =>
      _pick(en: 'Subject focus', fr: 'Matiere', ar: 'تركيز المادة');

  String get revisionNoQuestionsTitle => _pick(
    en: 'No questions loaded',
    fr: 'Aucune question chargee',
    ar: 'لا توجد أسئلة محملة',
  );

  String get revisionNoQuestionsSubtitle => _pick(
    en: 'Reset the session or change the subject to load a fresh set of questions.',
    fr: 'Redemarre la session ou change de matiere pour charger de nouvelles questions.',
    ar: 'أعد تشغيل الجلسة أو غيّر المادة لتحميل مجموعة أسئلة جديدة.',
  );

  String get revisionLoadQuestions =>
      _pick(en: 'Load questions', fr: 'Charger', ar: 'حمّل الأسئلة');

  String get revisionAnswerLabel =>
      _pick(en: 'Your answer', fr: 'Ta reponse', ar: 'اجابتك');

  String get revisionAnswerHint => _pick(
    en: 'Type your response here',
    fr: 'Ecris ta reponse ici',
    ar: 'اكتب اجابتك هنا',
  );

  String get revisionCheckAnswer =>
      _pick(en: 'Check answer', fr: 'Verifier', ar: 'تحقق من الاجابة');

  String get revisionRevealAnswer =>
      _pick(en: 'Reveal answer', fr: 'Voir la reponse', ar: 'اكشف الاجابة');

  String get revisionFinishSession =>
      _pick(en: 'Finish session', fr: 'Terminer', ar: 'انهاء الجلسة');

  String get revisionNextQuestion =>
      _pick(en: 'Next question', fr: 'Question suivante', ar: 'السؤال التالي');

  String revisionCorrectFeedback(String tip) =>
      _pick(en: 'Correct. $tip', fr: 'Correct. $tip', ar: 'اجابة صحيحة. $tip');

  String revisionIncorrectFeedback(String answer, String tip) => _pick(
    en: 'Not quite. The expected answer is "$answer". $tip',
    fr: 'Pas encore. La reponse attendue est "$answer". $tip',
    ar: 'ليست صحيحة بعد. الاجابة المتوقعة هي "$answer". $tip',
  );

  String revisionRevealFeedback(String answer, String tip) => _pick(
    en: 'Answer revealed: "$answer". $tip',
    fr: 'Reponse affichee : "$answer". $tip',
    ar: 'تم كشف الاجابة: "$answer". $tip',
  );

  String revisionSessionCompleteMessage(int score, int total) => _pick(
    en: 'Session complete: $score/$total correct.',
    fr: 'Session terminee : $score/$total correct.',
    ar: 'انتهت الجلسة: $score من $total صحيحة.',
  );

  String get revisionAllSubjects => _pick(en: 'All', fr: 'Toutes', ar: 'الكل');

  String subjectLabel(String key) {
    return switch (key) {
      'math' => _pick(en: 'Math', fr: 'Maths', ar: 'رياضيات'),
      'science' => _pick(en: 'Science', fr: 'Sciences', ar: 'علوم'),
      'geography' => _pick(en: 'Geography', fr: 'Geographie', ar: 'جغرافيا'),
      'language' => _pick(en: 'Language', fr: 'Langue', ar: 'لغة'),
      'technology' => _pick(
        en: 'Technology',
        fr: 'Technologie',
        ar: 'تكنولوجيا',
      ),
      _ => revisionAllSubjects,
    };
  }

  String get dictationResetTooltip =>
      _pick(en: 'Reset', fr: 'Reinitialiser', ar: 'اعادة');

  String get dictationCardTitle => _pick(
    en: 'Capture and assess dictation',
    fr: 'Capturer et evaluer la dictee',
    ar: 'التقاط الاملاء وتقييمه',
  );

  String get dictationInitialStatus => _pick(
    en: 'Import a printed passage first, then record the learner reading it aloud.',
    fr: 'Importe d abord un texte imprime, puis enregistre la lecture de l eleve.',
    ar: 'حمّل نصاً مطبوعاً اولاً، ثم سجل قراءة التلميذ بصوت مرتفع.',
  );

  String get dictationReadingImage => _pick(
    en: 'Reading text from the selected image...',
    fr: 'Lecture du texte depuis l image selectionnee...',
    ar: 'جار قراءة النص من الصورة المختارة...',
  );

  String get dictationReadingFile => _pick(
    en: 'Loading text from the selected file...',
    fr: 'Chargement du texte depuis le fichier selectionne...',
    ar: 'جار تحميل النص من الملف المحدد...',
  );

  String get dictationNoTextDetected => _pick(
    en: 'No readable text was detected. Try a clearer image.',
    fr: 'Aucun texte lisible n a ete detecte. Essaie une image plus nette.',
    ar: 'لم يتم العثور على نص واضح. جرّب صورة اوضح.',
  );

  String get dictationPassageLoaded => _pick(
    en: 'Passage loaded. You can now record the learner.',
    fr: 'Texte charge. Tu peux maintenant enregistrer l eleve.',
    ar: 'تم تحميل النص. يمكنك الان تسجيل التلميذ.',
  );

  String get dictationChoosingPassage => _pick(
    en: 'AI is reading the detected text and choosing the best passage to dictate...',
    fr: 'L IA lit le texte detecte et choisit le meilleur passage a dicter...',
    ar: 'يقرأ الذكاء الاصطناعي النص المكتشف ويختار افضل مقطع للاملاء...',
  );

  String get dictationPreviewTitle => _pick(
    en: 'AI picked your passage',
    fr: 'L IA a choisi ton passage',
    ar: 'اختار الذكاء الاصطناعي المقطع',
  );

  String get dictationPreviewSubtitle => _pick(
    en: 'Review the passage below. Proceed to dictate it, or edit it first.',
    fr: 'Lis le passage ci-dessous. Continue pour le dicter, ou modifie-le d abord.',
    ar: 'راجع المقطع ادناه. تابع لاملائه او عدّله اولاً.',
  );

  String get dictationChosenByAi => _pick(
    en: 'Chosen by AI from the detected text',
    fr: 'Choisi par l IA depuis le texte detecte',
    ar: 'اختاره الذكاء الاصطناعي من النص المكتشف',
  );

  String get dictationChosenFromText => _pick(
    en: 'Selected from the detected text',
    fr: 'Selectionne depuis le texte detecte',
    ar: 'مختار من النص المكتشف',
  );

  String get dictationProceed =>
      _pick(en: 'Proceed', fr: 'Continuer', ar: 'متابعة');

  String get dictationEdit =>
      _pick(en: 'Edit', fr: 'Modifier', ar: 'تعديل');

  String get dictationPreviewCancelled => _pick(
    en: 'Import cancelled. Nothing was loaded.',
    fr: 'Import annule. Rien n a ete charge.',
    ar: 'تم الغاء الاستيراد. لم يتم تحميل شيء.',
  );

  String get dictationCharacters =>
      _pick(en: 'characters', fr: 'caracteres', ar: 'حرفاً');

  String get dictationRecognitionFailed => _pick(
    en: 'Text recognition failed. Try again with a sharper, well-lit image.',
    fr: 'La reconnaissance du texte a echoue. Essaie avec une image plus nette.',
    ar: 'فشل التعرف على النص. حاول بصورة اوضح واضاءة افضل.',
  );

  String get dictationUnsupportedFile => _pick(
    en: 'This file type is not supported yet. Use an image or a plain text file.',
    fr: 'Ce type de fichier n est pas encore pris en charge. Utilise une image ou un fichier texte.',
    ar: 'هذا النوع من الملفات غير مدعوم حاليا. استخدم صورة أو ملفا نصيا عاديا.',
  );

  String get dictationOcrSupportNote => _pick(
    en: 'Photos go through our OCR service, which automatically picks the best free recognition engine for the image. Clear, high-contrast photos work best; if nothing is detected you can type or load a text file instead.',
    fr: 'Les photos passent par notre service OCR, qui choisit automatiquement le meilleur moteur de reconnaissance gratuit. Les images nettes et contrastées fonctionnent mieux ; si rien n est détecté, tu peux saisir ou charger un fichier texte.',
    ar: 'تمر الصور عبر خدمة OCR التي تختار تلقائياً أفضل محرك تعرف مجاني للصورة. تعمل الصور الواضحة وعالية التباين بشكل أفضل؛ وإذا لم يتم اكتشاف نص يمكنك الكتابة أو تحميل ملف نصي.',
  );

  String get dictationLoadBeforeRecording => _pick(
    en: 'Load a passage before recording.',
    fr: 'Charge un texte avant d enregistrer.',
    ar: 'حمّل نصاً قبل التسجيل.',
  );

  String get dictationListening => _pick(
       en: 'Listening for up to 60 seconds (will stop after 2s silence)...',
        fr: 'Écoute (jusqu\'à 60s, s\'arrêtera après 2s de silence)...',
        ar: 'جارٍ الاستماع حتى 60 ثانية (يتوقف بعد ثانيتين صمت)...',
      );

  String get dictationNoSpeech => _pick(
    en: 'No speech was captured. Try again in a quieter environment.',
    fr: 'Aucune voix capturee. Reessaie dans un endroit plus calme.',
    ar: 'لم يتم التقاط صوت. حاول مجدداً في مكان اكثر هدوءاً.',
  );

  String get dictationAnalysisReady => _pick(
    en: 'Analysis ready. Review the summary below.',
    fr: 'Analyse prete. Consulte le resume ci-dessous.',
    ar: 'التحليل جاهز. راجع الملخص في الاسفل.',
  );

  String get dictationSpeechFailed => _pick(
    en: 'Speech capture failed. Check microphone permissions and retry.',
    fr: 'La capture vocale a echoue. Verifie le micro puis reessaie.',
    ar: 'فشل تسجيل الصوت. تحقق من صلاحيات الميكروفون ثم حاول مجدداً.',
  );

  String get dictationCamera =>
      _pick(en: 'Use camera', fr: 'Camera', ar: 'استخدم الكاميرا');

  String get dictationGallery =>
      _pick(en: 'Use gallery', fr: 'Galerie', ar: 'استخدم المعرض');

  String get dictationFile =>
      _pick(en: 'Use file', fr: 'Fichier', ar: 'استخدم ملفا');

  String get dictationManualEntry =>
      _pick(en: 'Type text', fr: 'Saisir', ar: 'اكتب النص');

  String get dictationManualEntryTitle => _pick(
    en: 'Type or paste the passage',
    fr: 'Saisis ou colle le texte',
    ar: 'اكتب النص أو الصقه',
  );

  String get dictationManualEntryHint => _pick(
    en: 'Paste the expected passage here',
    fr: 'Colle ici le texte attendu',
    ar: 'الصق النص المتوقع هنا',
  );

  String get dictationManualEntryAction =>
      _pick(en: 'Load text', fr: 'Charger le texte', ar: 'حمّل النص');

  String get dictationRecord =>
      _pick(en: 'Record', fr: 'Enregistrer', ar: 'سجل');

  String get dictationRecording =>
      _pick(en: 'Recording...', fr: 'Enregistrement...', ar: 'جار التسجيل...');

  String get dictationStopRecording =>
      _pick(en: 'Stop', fr: 'Arrêter', ar: 'إيقاف');

  String get plannerCustomReminder =>
      _pick(en: 'Custom...', fr: 'Personnalis\u00e9...', ar: 'مخصص...');

  String get plannerCustomReminderPrompt =>
      _pick(en: 'Enter minutes before due date', fr: 'Entrez les minutes avant l\'\u00e9ch\u00e9ance', ar: 'أدخل الدقائق قبل الموعد');

  String get plannerMinutesLabel =>
      _pick(en: 'minutes', fr: 'minutes', ar: 'دقيقة');

  String get plannerHoursLabel =>
      _pick(en: 'hours', fr: 'heures', ar: 'ساعات');

  String get plannerDaysLabel =>
      _pick(en: 'days', fr: 'jours', ar: 'أيام');

  String get dictationExpectedPassage =>
      _pick(en: 'Expected passage', fr: 'Texte attendu', ar: 'النص المتوقع');

  String get plannerReminderLabel =>
      _pick(en: 'Remind me', fr: 'Rappelle-moi', ar: 'ذكرني');

  String reminderIntervalLabel(int? minutes) {
    if (minutes == null) {
      return _pick(en: 'None', fr: 'Aucun', ar: 'لا يوجد');
    }
    if (minutes == 60) {
      return _pick(en: '1 hour before', fr: '1 heure avant', ar: 'قبل ساعة');
    }
    if (minutes == 120) {
      return _pick(en: '2 hours before', fr: '2 heures avant', ar: 'قبل ساعتين');
    }
    if (minutes == 180) {
      return _pick(en: '3 hours before', fr: '3 heures avant', ar: 'قبل 3 ساعات');
    }
    if (minutes == 240) {
      return _pick(en: '4 hours before', fr: '4 heures avant', ar: 'قبل 4 ساعات');
    }
    if (minutes == 480) {
      return _pick(en: '8 hours before', fr: '8 heures avant', ar: 'قبل 8 ساعات');
    }
    if (minutes == 1440) {
      return _pick(en: '1 day before', fr: '1 jour avant', ar: 'قبل يوم');
    }
    if (minutes == 2880) {
      return _pick(en: '2 days before', fr: '2 jours avant', ar: 'قبل يومين');
    }
    if (minutes == 4320) {
      return _pick(en: '3 days before', fr: '3 jours avant', ar: 'قبل 3 أيام');
    }
    return '$minutes min';
  }

  String get dictationCapturedSpeech =>
      _pick(en: 'Captured speech', fr: 'Parole capturee', ar: 'الكلام الملتقط');

  String get dictationEmptyPassage => _pick(
    en: 'No passage loaded yet.',
    fr: 'Aucun texte charge pour le moment.',
    ar: 'لم يتم تحميل نص بعد.',
  );

  String get dictationEmptySpeech => _pick(
    en: 'No learner speech recorded yet.',
    fr: 'Aucune lecture eleve enregistree pour le moment.',
    ar: 'لم يتم تسجيل قراءة التلميذ بعد.',
  );

  String get dictationPerformanceSummary => _pick(
    en: 'Performance summary',
    fr: 'Resume de performance',
    ar: 'ملخص الاداء',
  );

  String get dictationAccuracy =>
      _pick(en: 'Accuracy', fr: 'Precision', ar: 'الدقة');

  String get dictationMatched =>
      _pick(en: 'Matched', fr: 'Corrects', ar: 'مطابقة');

  String get dictationMissed =>
      _pick(en: 'Missed', fr: 'Manques', ar: 'مفقودة');

  String get dictationExtra => _pick(en: 'Extra', fr: 'Ajoutes', ar: 'زائدة');

  String get dictationChangedWords =>
      _pick(en: 'Changed words', fr: 'Mots modifies', ar: 'كلمات متغيرة');

  String get dictationMissedWords =>
      _pick(en: 'Missed words', fr: 'Mots oublies', ar: 'كلمات ناقصة');

  String get dictationExtraWords =>
      _pick(en: 'Extra words', fr: 'Mots en plus', ar: 'كلمات زائدة');

  String get dictationResult =>
      _pick(en: 'Result', fr: 'Resultat', ar: 'النتيجة');

  String get dictationPerfectMatch => _pick(
    en: 'Strong read-through. The spoken passage matches cleanly.',
    fr: 'Lecture solide. Le texte lu correspond clairement au texte attendu.',
    ar: 'قراءة قوية. النص المنطوق يطابق النص المتوقع بشكل واضح.',
  );

  String get hubTypeYourText => _pick(
    en: 'Input Your Text',
    fr: 'Entrez votre texte',
    ar: 'أدخل نصك',
  );

  String get hubLearningHubBadge => _pick(
    en: 'LEARNING HUB',
    fr: 'HUB D\'APPRENTISSAGE',
    ar: 'مركز التعلم',
  );

  String get hubScanImageButton => _pick(
    en: 'Scan Image',
    fr: 'Scanner l\'image',
    ar: 'مسح صورة',
  );

  String get hubUploadFileButton => _pick(
    en: 'Upload File',
    fr: 'Télécharger le fichier',
    ar: 'تحميل ملف',
  );

  String get hubTypeTextButton => _pick(
    en: 'Type Text',
    fr: 'Saisir le texte',
    ar: 'كتابة نص',
  );

  String get hubEnterHint => _pick(
    en: 'Enter or paste your text here...',
    fr: 'Entrez ou collez votre texte ici...',
    ar: 'أدخل أو الصق نصك هنا...',
  );
  
  String get hubSpeakTextButton => _pick(
    en: 'Speak Text',
    fr: 'Parler le texte',
    ar: 'التحدث بنص',
  );

  String get hubSpeakingStatus => _pick(
    en: 'Listening... Speak your notes clearly.',
    fr: 'Ecoute... Enonce tes notes clairement.',
    ar: 'جاري الاستماع... تحدث بوضوح.',
  );

  String get hubSpeakSuccess => _pick(
    en: 'Speech transcribed successfully',
    fr: 'Parole transcrite avec succès',
    ar: 'تم نسخ الكلام بنجاح',
  );

  String get hubCancel => _pick(
    en: 'Cancel',
    fr: 'Annuler',
    ar: 'إلغاء',
  );

  String get hubDone => _pick(
    en: 'Done',
    fr: 'Terminé',
    ar: 'تم',
  );

  String hubProcessingProgress(String filename) => _pick(
    en: 'Processing file: $filename',
    fr: 'Traitement du fichier : $filename',
    ar: 'جاري معالجة الملف: $filename',
  );

  String get hubDetectionSuccess => _pick(
    en: 'Text detected successfully',
    fr: 'Texte détecté avec succès',
    ar: 'تم اكتشاف النص بنجاح',
  );

  String get hubImageSuccess => _pick(
    en: 'Image processed successfully',
    fr: 'Image traitée avec succès',
    ar: 'تمت معالجة الصورة بنجاح',
  );

  String hubImageError(String e) => _pick(
    en: 'Error processing image: $e',
    fr: 'Erreur de traitement d image : $e',
    ar: 'خطأ في معالجة الصورة: $e',
  );

  String get hubProcessing => _pick(
    en: 'Processing...',
    fr: 'Traitement...',
    ar: 'جاري المعالجة...',
  );

  String get hubProcessingPDF => _pick(
    en: 'Processing PDF with AI...',
    fr: 'Traitement du PDF par IA...',
    ar: 'جاري معالجة PDF بالذكاء الاصطناعي...',
  );

  String get hubUntitledTask => _pick(
    en: 'Untitled',
    fr: 'Sans titre',
    ar: 'بدون عنوان',
  );

  String get hubSelectSource => _pick(
    en: 'Select Image Source',
    fr: 'Sélectionner la source de l image',
    ar: 'اختر مصدر الصورة',
  );

  String get hubCamera => _pick(
    en: 'Camera',
    fr: 'Caméra',
    ar: 'الكاميرا',
  );

  String get hubGallery => _pick(
    en: 'Gallery',
    fr: 'Galerie',
    ar: 'المعرض',
  );

  String get hubSummarizeHint => _pick(
    en: 'Please enter some text to summarize',
    fr: 'Veuillez saisir un texte à résumer',
    ar: 'يرجى إدخال نص لتلخيصه',
  );

  String get hubGeneratedSummary => _pick(
    en: 'Generated Summary',
    fr: 'Résumé généré',
    ar: 'الملخص الناتج',
  );

  String get hubClose => _pick(
    en: 'Close',
    fr: 'Fermer',
    ar: 'إغلاق',
  );

  String get hubQuizHint => _pick(
    en: 'Please enter some text to generate quiz',
    fr: 'Veuillez saisir un texte pour générer un quiz',
    ar: 'يرجى إدخال نص لإنشاء اختبار',
  );

  String get hubTasksTitle => _pick(
    en: 'TASKS',
    fr: 'TÂCHES',
    ar: 'المهام',
  );

  String get hubStudyTasksTitle => _pick(
    en: 'Study Tasks',
    fr: 'Tâches d étude',
    ar: 'مهام الدراسة',
  );

  String hubMoreTasks(int count) => _pick(
    en: '+$count more tasks',
    fr: '+$count autres tâches',
    ar: '+$count مهام إضافية',
  );

  String get hubAllTasksDone => _pick(
    en: 'All tasks completed!',
    fr: 'Toutes les tâches sont terminées !',
    ar: 'تم إكمال جميع المهام!',
  );

  String hubPendingLabel(int count) => _pick(
    en: '$count PENDING',
    fr: '$count EN ATTENTE',
    ar: '$count قيد الانتظار',
  );

  String quizQuestionCounter(int current, int total) => _pick(
    en: 'Question $current of $total',
    fr: 'Question $current sur $total',
    ar: 'السؤال $current من $total',
  );

  String quizScoreLabel(int score, int total) => _pick(
    en: 'Score: $score/$total',
    fr: 'Score : $score/$total',
    ar: 'النتيجة: $score/$total',
  );

  String get quizCheckAnswer => _pick(
    en: 'Check Answer',
    fr: 'Vérifier la réponse',
    ar: 'تحقق من الإجابة',
  );

  String get quizFinish => _pick(
    en: 'Finish',
    fr: 'Terminer',
    ar: 'إنهاء',
  );

  String get quizNextQuestion => _pick(
    en: 'Next Question',
    fr: 'Question suivante',
    ar: 'السؤال التالي',
  );

  String get quizComplete => _pick(
    en: 'Quiz Complete!',
    fr: 'Quiz terminé !',
    ar: 'اكتمل الاختبار!',
  );

  String quizYourScore(int score, int total) => _pick(
    en: 'Your Score: $score out of $total',
    fr: 'Votre score : $score sur $total',
    ar: 'نتيجتك: $score من $total',
  );

  String get quizPerfectFeedback => _pick(
    en: 'Perfect! You got all questions correct! 🎉',
    fr: 'Parfait ! Vous avez répondu correctement à toutes les questions ! 🎉',
    ar: 'ممتاز! لقد أجبت على جميع الأسئلة بشكل صحيح! 🎉',
  );

  String get quizGreatFeedback => _pick(
    en: 'Great job! 🌟',
    fr: 'Beau travail ! 🌟',
    ar: 'عمل رائع! 🌟',
  );

  String get quizGoodFeedback => _pick(
    en: 'Good effort! 👍',
    fr: 'Bon effort ! 👍',
    ar: 'جهد جيد! 👍',
  );

  String get quizKeepPracticing => _pick(
    en: 'Keep practicing! 📚',
    fr: 'Continuez à vous entraîner ! 📚',
    ar: 'واصل التدريب! 📚',
  );

  String quizLevelUpMessage(int xp) => _pick(
    en: 'Awesome! You leveled up! (+$xp XP)',
    fr: 'Génial ! Vous avez monté de niveau ! (+$xp XP)',
    ar: 'رائع! لقد ارتفع مستواك! (+$xp XP)',
  );

  String quizCorrectXpMessage(int xp) => _pick(
    en: 'Correct! +$xp XP',
    fr: 'Correct ! +$xp XP',
    ar: 'صحيح! +$xp XP',
  );

  String get hubSummaryTitle => _pick(
    en: 'Summary',
    fr: 'Résumé',
    ar: 'ملخص',
  );

  String get hubSummarySubtitle => _pick(
    en: 'Get AI-powered summaries',
    fr: 'Obtenez des résumés par IA',
    ar: 'احصل على ملخصات بالذكاء الاصطناعي',
  );

  String get hubQuizTitle => _pick(
    en: 'Quiz',
    fr: 'Quiz',
    ar: 'اختبار',
  );

  String get hubQuizSubtitle => _pick(
    en: 'Test your knowledge',
    fr: 'Testez vos connaissances',
    ar: 'اختبر معرفتك',
  );

  String get hubDictationTitle => _pick(
    en: 'Dictation',
    fr: 'Dictée',
    ar: 'إملاء',
  );

  String get hubDictationSubtitle => _pick(
    en: 'Practice pronunciation',
    fr: 'Pratiquez la prononciation',
    ar: 'تدرب على النطق',
  );

  String get hubGenerateSummaryAction => _pick(
    en: 'Generate Summary',
    fr: 'Générer le résumé',
    ar: 'إنشاء ملخص',
  );

  String get hubGenerateQuizAction => _pick(
    en: 'Generate Quiz',
    fr: 'Générer le quiz',
    ar: 'إنشاء اختبار',
  );

  String get hubPracticeDictationAction => _pick(
    en: 'Practice Dictation',
    fr: 'Pratiquer la dictée',
    ar: 'ممارسة الإملاء',
  );

  String _pick({required String en, required String fr, required String ar}) {
    return switch (language) {
      AppLanguage.english => en,
      AppLanguage.french => fr,
      AppLanguage.arabic => ar,
    };
  }
}
