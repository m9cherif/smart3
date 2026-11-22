import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:smart_student_ai/ai_service.dart';
import 'package:smart_student_ai/ocr_router_service.dart';

class GoogleOCRService {
  /// Reads text from an image or a plain-text file.
  ///
  /// Images go through the keyless OCR router on smart.chrif.net, which tries
  /// several free engines and returns the best result. If the router cannot be
  /// reached we fall back to the AI vision model so OCR keeps working offline
  /// from the router.
  Future<String> readText(
    String filePath, {
    String language = 'auto',
  }) async {
    final extension = p.extension(filePath).toLowerCase();

    // Handle plain text files
    if (_plainTextExtensions.contains(extension)) {
      return _readPlainText(filePath);
    }

    // Check if file is supported image format
    if (extension.isNotEmpty && !_imageExtensions.contains(extension)) {
      throw UnsupportedError('Unsupported file type: $extension');
    }

    return _readImageText(filePath, language: language);
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
    String filePath, {
    String language = 'auto',
  }) async {
    final routed = await OcrRouterService.instance.readImage(
      filePath,
      language: language,
    );
    if (routed != null && routed.hasText) {
      return routed.text;
    }

    debugPrint('OCR router unavailable — falling back to AI vision.');
    return _aiVisionFallback(filePath);
  }

  Future<String> _aiVisionFallback(String filePath) async {
    try {
      debugPrint('Executing AI vision OCR for: $filePath');
      final file = File(filePath);
      return await AIService.extractTextFromImage(file);
    } catch (e) {
      debugPrint('AI Vision OCR failed: $e');
      return 'OCR Error: could not read that image. ${e.toString()}';
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