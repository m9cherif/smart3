import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:flutter/foundation.dart';
import 'package:smart_student_ai/app_controller.dart';

class AIService {
  // Auto AI router (smart.chrif.net): asks for the best free model and
  // retries the next best one automatically. No key needed for keyless providers.
  static const String _routerBaseUrl = String.fromEnvironment(
    'SMART_ROUTER_URL',
    defaultValue: 'https://smart.chrif.net/v1/chat/completions',
  );

  // Direct Groq fallback, used only if the router itself is unreachable.
  static const String _apiKey = String.fromEnvironment('GROQ_API_KEY');
  static const String _baseUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static String _lastGeneratedSummary = '';
  static List<Map<String, dynamic>> _lastGeneratedQuiz = [];

  static Future<void> initialize() async {
    // OpenRouter API doesn't need model initialization like Gemini
  }

  /// POST a JSON body and return the decoded map, or null on any failure.
  static Future<Map<String, dynamic>?> _postJson(
    String url, {
    required Map<String, dynamic> body,
    Map<String, String>? extraHeaders,
    int timeoutSeconds = 90,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          ...?extraHeaders,
        },
        body: jsonEncode(body),
      ).timeout(Duration(seconds: timeoutSeconds));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      debugPrint(
        'AIService: POST $url failed with HTTP ${response.statusCode}: ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('AIService: POST $url exception: $e');
      return null;
    }
  }

  /// Chat completion through the auto router, with a direct Groq fallback.
  static Future<String> _chatCompletionText({
    required List<Map<String, dynamic>> messages,
    String groqModel = 'qwen/qwen3.8-27b',
    int maxTokens = 2000,
    double temperature = 0.7,
  }) async {
    final body = <String, dynamic>{
      'model': 'auto',
      'messages': messages,
      'max_tokens': maxTokens,
      'temperature': temperature,
    };

    // 1) The auto router: best free model first, automatic failover inside.
    final router = await _postJson(_routerBaseUrl, body: body);
    if (router != null) {
      final content =
          router['choices']?[0]?['message']?['content'] as String?;
      if (content != null && content.trim().isNotEmpty) {
        return content.trim();
      }
    }

    // 2) Fallback to Groq directly.
    if (_apiKey.isNotEmpty) {
      final groqBody = Map<String, dynamic>.from(body)..['model'] = groqModel;
      final groq = await _postJson(
        _baseUrl,
        body: groqBody,
        extraHeaders: {'Authorization': 'Bearer $_apiKey'},
      );
      if (groq != null) {
        final content =
            groq['choices']?[0]?['message']?['content'] as String?;
        if (content != null && content.trim().isNotEmpty) {
          return content.trim();
        }
      }
    }

    return 'Error: AI service unavailable.';
  }

  // Extract text from PDF using ConvertAPI
  static Future<String> extractTextFromPDF(File pdfFile) async {
    return _convertWithAPI(pdfFile, 'pdf');
  }

  // Extract text from DOCX/DOC using ConvertAPI
  static Future<String> extractTextFromDocx(File docxFile) async {
    return _convertWithAPI(docxFile, 'docx');
  }

  static Future<String> _convertWithAPI(File file, String format) async {
    try {
      if (!await file.exists()) {
        return '$format file not found.';
      }

      final isDoc = format == 'docx' || format == 'doc';
      final apiKey = const String.fromEnvironment('CONVERT_API_KEY');
      
      // Step 1: Upload file to PDF.co temporary storage
      final uploadRequest = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.pdf.co/v1/file/upload'),
      );
      uploadRequest.headers['x-api-key'] = apiKey;
      uploadRequest.files.add(await http.MultipartFile.fromPath('file', file.path));
      
      final uploadResponse = await uploadRequest.send();
      String uploadedFileUrl = '';
      
      if (uploadResponse.statusCode == 200) {
        final uploadData = await uploadResponse.stream.bytesToString();
        final uploadJson = jsonDecode(uploadData);
        uploadedFileUrl = uploadJson['url'];
      } else {
        final errorData = await uploadResponse.stream.bytesToString();
        return 'Error uploading to PDF.co: HTTP ${uploadResponse.statusCode}\n$errorData';
      }

      String sourceUrl = uploadedFileUrl;

      if (isDoc) {
        // Step 2: Convert Word to PDF (Word files must be PDFs before text extraction in PDF.co)
        final wordToPdfRequest = await http.post(
          Uri.parse('https://api.pdf.co/v1/pdf/convert/from/doc'),
          headers: {
            'x-api-key': apiKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'url': uploadedFileUrl,
            'inline': true,
          }),
        );
        
        if (wordToPdfRequest.statusCode == 200) {
          final json = jsonDecode(wordToPdfRequest.body);
          sourceUrl = json['url'];
        } else {
          return 'Error converting Word to PDF: HTTP ${wordToPdfRequest.statusCode}\n${wordToPdfRequest.body}';
        }
      }

      // Step 3: Convert PDF to Text
      final convertRequest = await http.post(
        Uri.parse('https://api.pdf.co/v1/pdf/convert/to/text'),
        headers: {
          'x-api-key': apiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'url': sourceUrl,
          'inline': true,
        }),
      );

      if (convertRequest.statusCode == 200) {
        final json = jsonDecode(convertRequest.body);

        if (json['body'] != null) {
          return json['body'].toString().trim();
        } else if (json['url'] != null) {
          final textUrl = json['url'];
          final textResponse = await http.get(Uri.parse(textUrl));
          return textResponse.statusCode == 200 
              ? textResponse.body.trim() 
              : 'Error downloading text output from PDF.co.';
        }
        return 'Error: No text content returned from PDF.co';
      } else {
        return 'Error converting to Text: HTTP ${convertRequest.statusCode}\n${convertRequest.body}';
      }
    } catch (e) {
      return 'Error extracting text: ${e.toString()}';
    }
  }

  // Extract text from text file
  static Future<String> extractTextFromTextFile(File textFile) async {
    try {
      if (await textFile.exists()) {
        final content = await textFile.readAsString();
        return content.isNotEmpty ? content : 'Empty text file.';
      } else {
        return 'Text file not found.';
      }
    } catch (e) {
      return 'Error reading text file: ${e.toString()}';
    }
  }

  // Process any document (PDF, Docx, Text) with AI to get a summary
  static Future<String> processDocumentSummary(
    File file, {
    AppLanguage language = AppLanguage.english,
  }) async {
    try {
      final extractedText = await extractTextFromFile(file);
      if (extractedText.isEmpty || extractedText.startsWith('Error')) {
        return 'No readable text could be extracted from this document ($extractedText).';
      }
      return await generateSummary(extractedText, language: language);
    } catch (e) {
      return 'Error processing document summary: ${e.toString()}';
    }
  }

  // Process any document (PDF, Docx, Text) with AI to get a quiz
  static Future<List<Map<String, dynamic>>> processDocumentQuiz(
    File file, {
    AppLanguage language = AppLanguage.english,
  }) async {
    try {
      final extractedText = await extractTextFromFile(file);
      if (extractedText.isEmpty || extractedText.startsWith('Error')) {
        return [];
      }
      return await generateQuiz(extractedText, language: language);
    } catch (e) {
      return [];
    }
  }

  // Extract text from any file (PDF, Docx, or text)
  static Future<String> extractTextFromFile(File file) async {
    final path = file.path.toLowerCase();
    if (path.endsWith('.pdf')) {
      return await extractTextFromPDF(file);
    } else if (path.endsWith('.docx') || path.endsWith('.doc')) {
      return await extractTextFromDocx(file);
    } else {
      return await extractTextFromTextFile(file);
    }
  }

  // Vision-based OCR using AI (Groq)
  static Future<String> extractTextFromImage(File imageFile) async {
    try {
      if (!await imageFile.exists()) {
        return 'Image file not found.';
      }

      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      final extension = p
          .extension(imageFile.path)
          .toLowerCase()
          .replaceFirst('.', '');
      final mimeType = extension == 'jpg' || extension == 'jpeg'
          ? 'image/jpeg'
          : 'image/$extension';

      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'meta-llama/llama-4-scout-17b-16e-instruct', // Groq Vision model
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text':
                      'Please perform OCR on this image. Extract ALL readable text exactly as it appears. If the text is in Arabic, preserve the Arabic characters. Return ONLY the extracted text with no commentary.',
                },
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:$mimeType;base64,$base64Image'},
                },
              ],
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final content = responseData['choices'][0]['message']['content'];
        return content?.trim() ?? 'No text extracted from image.';
      } else {
        return 'AI OCR Error: HTTP ${response.statusCode} - ${response.body}';
      }
    } catch (e) {
      return 'AI OCR Exception: ${e.toString()}';
    }
  }

  // Audio-based transcription using AI (Groq Whisper)
  static Future<String> transcribeAudio(
    File audioFile, {
    AppLanguage language = AppLanguage.english,
  }) async {
    try {
      if (!await audioFile.exists()) {
        return 'Audio file not found.';
      }

      // Use Groq Whisper (whisper-large-v3)
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions'),
      );

      request.headers.addAll({
        'Authorization': 'Bearer $_apiKey',
      });

      request.files.add(
        await http.MultipartFile.fromPath('file', audioFile.path),
      );

      request.fields['model'] = 'whisper-large-v3';
      request.fields['temperature'] = '0.0';

      if (language == AppLanguage.arabic) {
        request.fields['prompt'] = 'السلام عليكم. هذا تسجيل صوتي باللغة العربية الفصحى. يرجى كتابة النص بالرسم العربي فقط وتجنب أي أحرف لاتينية.';
        request.fields['language'] = 'ar';
      } else {
        request.fields['language'] = language == AppLanguage.french
            ? 'fr'
            : 'en';
      }

      final response = await http.Response.fromStream(await request.send());

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final transcription = responseData['text'];
        return transcription?.trim() ?? 'No transcription generated.';
      } else {
        debugPrint(
          'Whisper STT failed (${response.statusCode}). Trying text extraction fallback.',
        );
        return 'Transcription failed. Please try again or use manual entry.';
      }
    } catch (e) {
      return 'Audio AI Exception: ${e.toString()}';
    }
  }
  static Future<String> generateSummary(
    String text, {
    AppLanguage language = AppLanguage.english,
  }) async {
    try {
      if (text.length <= 15000) {
        return await _generateSummaryForChunk(text, language: language);
      }

      // Handle very long text with chunked summarization
      final chunks = _splitIntoChunks(text, 12000);
      // Run chunk summarization in parallel for better performance
      final chunkSummaries = await Future.wait(
        chunks.take(10).map((chunk) => _generateSummaryForChunk(chunk, language: language))
      );
      
      final successfulSummaries = chunkSummaries.where((s) => !s.startsWith('Error')).toList();
      
      if (successfulSummaries.isEmpty) return 'Unable to generate summary.';
      
      final combinedSummaries = successfulSummaries.join('\n\n');
      final result = await _generateSummaryForChunk(combinedSummaries, isFinal: true, language: language);
      _lastGeneratedSummary = result;
      return result;
    } catch (e) {
      return 'Error generating summary: ${e.toString()}';
    }
  }

  static Future<String> _generateSummaryForChunk(
    String chunk, {
    bool isFinal = false,
    AppLanguage language = AppLanguage.english,
  }) async {
    final languageName = language == AppLanguage.arabic
        ? 'Arabic'
        : language == AppLanguage.french
        ? 'French'
        : 'English';

    try {
      final response = await _chatCompletionText(
        messages: [
          {
            'role': 'system',
            'content':
                'You are an AI that summarizes text. Return ONLY the final summary in $languageName. Do not include any introductory phrases or conversational filler.',
          },
          {
            'role': 'user',
            'content': isFinal
                ? 'The following are summaries of different parts of a document in $languageName. Please combine them into one final, cohesive, and comprehensive summary in $languageName:\n\n$chunk'
                : 'Please provide a comprehensive summary of the following text in $languageName:\n\n$chunk',
          },
        ],
        groqModel: 'qwen/qwen3.8-27b',
        maxTokens: 2000,
        temperature: 0.7,
      );

      if (!response.startsWith('Error:')) {
        return response.trim();
      }
      return 'Error: AI service unavailable.';
    } catch (e) {
      return 'Error: $e';
    }
  }

  static List<String> _splitIntoChunks(String text, int chunkSize) {
    final List<String> chunks = [];
    for (int i = 0; i < text.length; i += chunkSize) {
      final end = (i + chunkSize < text.length) ? i + chunkSize : text.length;
      chunks.add(text.substring(i, end));
    }
    return chunks;
  }

  static Future<List<Map<String, dynamic>>> generateQuiz(
    String text, {
    AppLanguage language = AppLanguage.english,
  }) async {
    try {
      String quizInputText = text;
      if (text.length > 15000) {
        // For very long text, we take a balanced sample from start, middle, and end 
        // to ensure the quiz covers the whole document
        final partSize = 4500;
        final start = text.substring(0, partSize);
        final middle = text.substring(text.length ~/ 2 - partSize ~/ 2, text.length ~/ 2 + partSize ~/ 2);
        final end = text.substring(text.length - partSize);
        quizInputText = '$start\n\n[...]\n\n$middle\n\n[...]\n\n$end';
      }

      final responseText = await _chatCompletionText(
        messages: [
          {
            'role': 'system',
            'content':
                'You are a quiz generator. You must return ONLY a JSON array of 5 multiple-choice questions. Do not include markdown code blocks, explanations, or any other text.',
          },
          {
            'role': 'user',
            'content':
                'Based on the following text, create a quiz with 5 multiple-choice questions in the same language as the text provided. Each question should test important concepts from the text, have 4 options (A, B, C, D), and include the correct answer at the end.\n\nReturn the response as a JSON array of questions with this format:\n[\n  {\n    "question": "The question text here",\n    "options": ["Option A", "Option B", "Option C", "Option D"],\n    "correct_answer": 0\n  }\n]\n\nIMPORTANT: Return ONLY the JSON array. Each question must be an object with exactly "question", "options", and "correct_answer" fields. Use 0 for A, 1 for B, 2 for C, and 3 for D as the correct_answer index.\n\nText for quiz:\n$quizInputText',
          },
        ],
        groqModel: 'qwen/qwen3.8-27b',
        maxTokens: 2000,
        temperature: 0.5, // Lower temperature for more consistent JSON
      );

      if (responseText.startsWith('Error:')) {
        debugPrint('AIService: Quiz API failed: $responseText');
        return _parseQuizManually('');
      }

      final content = responseText;

      try {
        final jsonStart = content.indexOf('[');
        final jsonEnd = content.lastIndexOf(']');
        if (jsonStart != -1 && jsonEnd != -1 && jsonEnd > jsonStart) {
          final jsonStr = content.substring(jsonStart, jsonEnd + 1);

          final List<dynamic> quizDataList = jsonDecode(jsonStr) as List<dynamic>;
          final List<Map<String, dynamic>> validQuizData = quizDataList
              .where((item) {
                if (item is! Map<String, dynamic>) return false;
                return item.containsKey('question') &&
                    item.containsKey('options') &&
                    item.containsKey('correct_answer') &&
                    item['options'] is List &&
                    item['correct_answer'] is int &&
                    (item['options'] as List).length == 4;
              })
              .map((item) => item as Map<String, dynamic>)
              .toList();

          if (validQuizData.isEmpty) {
            return _parseQuizManually(content);
          }

          _lastGeneratedQuiz = validQuizData.take(5).toList();
          return _lastGeneratedQuiz;
        } else {
          return _parseQuizManually(content);
        }
      } catch (e) {
        return _parseQuizManually(content);
      }
    } catch (e) {
      return _parseQuizManually('');
    }
  }

  static List<Map<String, dynamic>> _parseQuizManually(String quizText) {
    final List<Map<String, dynamic>> quiz = [];
    final lines = quizText.split('\n');

    String currentQuestion = '';
    List<String> currentOptions = [];
    int? correctAnswer;

    for (final line in lines) {
      if (line.startsWith('Question')) {
        if (currentQuestion.isNotEmpty) {
          quiz.add({
            'question': currentQuestion.trim(),
            'options': List<String>.from(currentOptions),
            'correct_answer': correctAnswer ?? 0,
          });
        }
        currentQuestion = line.replaceFirst('Question ', '').trim();
        currentOptions = [];
        correctAnswer = null;
      } else if (line.startsWith('Correct Answer')) {
        final answerStr = line.replaceFirst('Correct Answer: ', '').trim();
        correctAnswer = answerStr == 'A'
            ? 0
            : answerStr == 'B'
            ? 1
            : answerStr == 'C'
            ? 2
            : 3;
      } else if (line.startsWith(RegExp(r'^[A-D]\)'))) {
        currentOptions.add(line.substring(3).trim());
      }
    }

    // Add the last question if exists
    if (currentQuestion.isNotEmpty) {
      quiz.add({
        'question': currentQuestion.trim(),
        'options': List<String>.from(currentOptions),
        'correct_answer': correctAnswer ?? 0,
      });
    }

    _lastGeneratedQuiz = quiz.take(5).toList();
    return _lastGeneratedQuiz;
  }

  static List<Map<String, dynamic>> get lastGeneratedQuiz => _lastGeneratedQuiz;
  static String get lastGeneratedSummary => _lastGeneratedSummary;

  /* ------------------------------------------------------------------ */
  /* Dictation passage selection                                        */
  /* ------------------------------------------------------------------ */

  /// Asks the AI to choose the best dictatable excerpt from freshly detected
  /// text (OCR or document import).
  ///
  /// The passage is copied verbatim — the model is instructed not to rewrite,
  /// translate or paraphrase. When the text is short it is used as-is, and a
  /// deterministic heuristic is used if the AI call fails.
  static Future<DictationPassage> chooseDictationPassage(
    String text, {
    String language = 'en',
    int targetChars = 650,
  }) async {
    final cleaned = _tidySourceText(text);
    if (cleaned.isEmpty) {
      return DictationPassage.empty();
    }

    // Short extracts are already a good dictation exercise.
    if (cleaned.length <= 900) {
      return DictationPassage(
        title: _passageTitle(cleaned),
        passage: cleaned,
        chosenByAi: false,
        note: 'The whole detected text is short enough to dictate as-is.',
      );
    }

    final langName = switch (language) {
      'ar' => 'Arabic',
      'fr' => 'French',
      _ => 'English',
    };
    final minChars = (targetChars * 0.65).round();
    final maxChars = (targetChars * 1.5).round();

    const system = 'You prepare dictation exercises for students. '
        'You copy text exactly and never rewrite, translate, summarise or paraphrase it. '
        'You output strict JSON and nothing else.';

    final prompt = '''
From the SOURCE TEXT below, choose the single best continuous passage for a
dictation exercise in $langName.

Rules:
- Copy the passage verbatim from the source: same spelling, accents, punctuation and wording.
- It must be a continuous excerpt (no gaps, no ellipses, no added words).
- It must read as a self-contained, meaningful piece.
- Prefer clear prose sentences. Skip tables, page numbers, headers/footers, URLs,
  formulas, references, footnotes and repeated nav text.
- Aim for roughly $targetChars characters (between $minChars and $maxChars).
- Never add commentary or translations.

Return JSON only, exactly this shape:
{"title":"short 3-6 word label","passage":"the excerpt copied verbatim"}

SOURCE TEXT:
$cleaned
''';

    DictationPassage? result;

    try {
      final raw = await _chatCompletionText(
        messages: [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': prompt},
        ],
        maxTokens: 1800,
        temperature: 0.1,
      );

      final parsed = _extractJsonObject(raw);
      final passage = (parsed?['passage'] ?? '').toString().trim();
      final title = (parsed?['title'] ?? '').toString().trim();
      if (passage.length >= 80 && _looksLikeRealText(passage)) {
        result = DictationPassage(
          title: title.isEmpty ? _passageTitle(passage) : title,
          passage: passage,
          chosenByAi: true,
          note: 'AI selected this passage from the detected text.',
        );
      }
    } catch (e) {
      debugPrint('AIService: passage selection failed: $e');
    }

    result ??= DictationPassage(
      title: _passageTitle(cleaned),
      passage: _heuristicPassage(cleaned, targetChars: targetChars),
      chosenByAi: false,
      note: 'Selected from the detected text.',
    );

    return result;
  }

  /// Normalises OCR output before it is shown or sent to a model.
  static String _tidySourceText(String text) {
    var out = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    out = out.replaceAll(RegExp(r'[ \t]+'), ' ');
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return out.trim();
  }

  static bool _looksLikeRealText(String text) {
    final letters = RegExp(r'[\p{L}\p{N}]', unicode: true).allMatches(text).length;
    if (letters < 60) return false;
    final ratio = letters / text.length;
    return ratio > 0.55;
  }

  static String _passageTitle(String text) {
    final firstLine = text
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    final words = firstLine.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(6);
    final title = words.join(' ');
    if (title.isEmpty) return 'Dictation passage';
    return title.length > 48 ? '${title.substring(0, 45)}…' : title;
  }

  /// Deterministic fallback: picks a run of full sentences close to the target
  /// length, preferring paragraphs made of prose.
  static String _heuristicPassage(String text, {int targetChars = 650}) {
    final paragraphs = text
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    final candidates = paragraphs.isNotEmpty ? paragraphs : [text];

    // Score paragraphs: prose-like, reasonable length, no link/number noise.
    double score(String p) {
      final letters =
          RegExp(r'[\p{L}]', unicode: true).allMatches(p).length.toDouble();
      final digits =
          RegExp(r'[0-9]').allMatches(p).length.toDouble();
      final punctuation =
          RegExp(r'[.,!?;:…؟،]').allMatches(p).length.toDouble();
      var s = letters + punctuation * 6 - digits * 4;
      if (p.length < 120) s -= 80;
      if (p.length > 1600) s -= 120;
      return s;
    }

    candidates.sort((a, b) => score(b).compareTo(score(a)));
    var chosen = candidates.first;

    if (chosen.length > targetChars * 1.35) {
      // Trim on a sentence boundary near the target length.
      final sentences = chosen.split(RegExp(r'(?<=[.!?؟])\s+'));
      final buffer = StringBuffer();
      for (final sentence in sentences) {
        if (buffer.length + sentence.length > targetChars && buffer.isNotEmpty) {
          break;
        }
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(sentence);
      }
      if (buffer.isNotEmpty) chosen = buffer.toString();
    }

    return chosen.trim();
  }

  /// Pulls the first JSON object out of a model response (tolerates fences).
  static Map<String, dynamic>? _extractJsonObject(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      text = text.replaceFirst(RegExp(r'```\s*$'), '');
    }
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Fall through.
    }
    return null;
  }
}

/// The passage chosen for a dictation session.
@immutable
class DictationPassage {
  const DictationPassage({
    required this.title,
    required this.passage,
    required this.chosenByAi,
    this.note,
  });

  factory DictationPassage.empty() => const DictationPassage(
        title: '',
        passage: '',
        chosenByAi: false,
      );

  final String title;
  final String passage;
  final bool chosenByAi;
  final String? note;

  bool get isEmpty => passage.trim().isEmpty;
  int get characterCount => passage.trim().length;
}
