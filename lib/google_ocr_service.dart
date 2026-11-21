import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:smart_student_ai/ai_service.dart';

class GoogleOCRService {
  Future<String> readText(
    String filePath,
  ) async {
    final extension = p.extension(filePath).toLowerCase();
    
    // Handle plain text files
    if (_plainTextExtensions.contains(extension)) {
      return _readPlainText(filePath);
    }
    
    // Check if file is supported image format
    if (extension.isNotEmpty && !_imageExtensions.contains(extension)) {
      throw UnsupportedError('Unsupported file type: $extension');
    }

    return _readImageText(filePath);
  }

  Future<String> _readPlainText(String filePath) async {
    try {
      final file = File(filePath);
      return await file.readAsString();
    } catch (e) {
      debugPrint('Error reading plain text file: $e');
      return '';
    }
  }

  Future<String> _readImageText(
    String filePath,
  ) async {
    debugPrint('Using AI Vision OCR via OpenRouter for high-accuracy results.');
    return await _aiVisionFallback(filePath);
  }

  Future<String> _aiVisionFallback(String filePath) async {
    try {
      debugPrint('Executing OpenRouter AI Vision for: $filePath');
      final file = File(filePath);
      return await AIService.extractTextFromImage(file);
    } catch (e) {
      debugPrint('AI Vision OCR failed: $e');
      return 'OCR Error: AI request failed. ${e.toString()}';
    }
  }

  static const Set<String> _imageExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.bmp',
    '.webp',
    '.heic',
  };

  static const Set<String> _plainTextExtensions = <String>{
    '.txt',
    '.md',
    '.csv',
    '.json',
  };
}
