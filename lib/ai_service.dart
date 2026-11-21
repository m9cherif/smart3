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
    final router = await _postJson(_routerBaseUrl, body);
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
}
