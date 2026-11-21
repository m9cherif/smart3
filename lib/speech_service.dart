import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:smart_student_ai/ai_service.dart';
import 'package:smart_student_ai/app_controller.dart';

class SpeechService {
  SpeechService._internal();
  
  static final SpeechService instance = SpeechService._internal();
  
  // Factory constructor for backward compatibility
  factory SpeechService() => instance;

  final AudioRecorder _recorder = AudioRecorder();
  bool _isAiRecording = false;

  Future<void> stop() async {
    if (_isAiRecording) {
      await _recorder.stop();
      _isAiRecording = false;
    }
  }

  Future<String> record({
    Duration duration = const Duration(seconds: 5),
    Locale? locale,
  }) async {
    // We now strictly use OpenRouter (Whisper) for STT as requested.
    debugPrint('Using AI Speech Recognition via OpenRouter...');
    return await _recordWithAiSpeech(duration: duration, locale: locale);
  }


  Future<String> _recordWithAiSpeech({
    required Duration duration,
    required Locale? locale,
  }) async {
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }

    if (!await _recorder.hasPermission()) {
      throw 'Microphone permission denied. Please grant permission in settings.';
    }

    final tempDir = await getTemporaryDirectory();
    final String path = p.join(tempDir.path, 'dictation_${DateTime.now().millisecondsSinceEpoch}.wav');

    const config = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      bitRate: 128000,
    );

    _isAiRecording = true;
    await _recorder.start(config, path: path);

    debugPrint('AI Recording started: $path');


    // Auto-stop after duration
    Timer(duration, () async {
      if (_isAiRecording) {
        await stop();
      }
    });

    // Wait for the recording to finish (either by stop() or timer)
    // We poll until _isAiRecording is false or use a more robust sync mechanism
    while (_isAiRecording) {
      await Future.delayed(const Duration(milliseconds: 200));
    }

    debugPrint('AI Recording finished. Transcribing...');
    
    // Determine AppLanguage from locale
    AppLanguage appLang = AppLanguage.english;
    if (locale?.languageCode == 'ar') {
      appLang = AppLanguage.arabic;
    } else if (locale?.languageCode == 'fr') {
      appLang = AppLanguage.french;
    }

    final transcription = await AIService.transcribeAudio(File(path), language: appLang);
    debugPrint('AI Transcription: $transcription');

    // Clean up
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting temp audio file: $e');
    }

    return transcription;
  }
}
