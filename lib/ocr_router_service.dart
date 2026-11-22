import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// A text extraction returned by the keyless OCR router.
@immutable
class OcrRouterResult {
  const OcrRouterResult({
    required this.text,
    required this.provider,
    required this.score,
    required this.elapsedMs,
  });

  final String text;
  final String provider;
  final double score;
  final int elapsedMs;

  bool get hasText => text.trim().isNotEmpty;
}

/// Client for the smart.chrif.net `/ocr` router.
///
/// The router tries several free OCR engines (OCR.space, Tesseract, ...),
/// scores each result and returns the best one. The app never needs an OCR
/// key. When the router is unreachable the caller falls back to AI vision.
class OcrRouterService {
  OcrRouterService._();

  static final OcrRouterService instance = OcrRouterService._();

  static const String baseUrl = String.fromEnvironment(
    'OCR_BASE_URL',
    defaultValue: 'https://smart.chrif.net/ocr',
  );

  /// Keep uploads small: better latency, less chance of a provider rejection.
  static const int _maxUploadBytes = 4 * 1024 * 1024;
  static const int _maxSide = 2200;

  /// Extracts text from an image. Returns `null` when the router cannot help,
  /// so callers can try their own offline / AI fallback.
  Future<OcrRouterResult?> readImage(
    String filePath, {
    String language = 'auto',
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('OcrRouter: file not found: $filePath');
        return null;
      }

      var bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;

      var mime = _mimeFor(filePath);
      if (bytes.length > _maxUploadBytes) {
        final shrunk = await compute(_shrinkForUpload, bytes);
        if (shrunk != null) {
          bytes = shrunk;
          mime = 'image/jpeg';
        }
      }

      final started = DateTime.now();
      final response = await http
          .post(
            Uri.parse(baseUrl),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'image_base64': base64Encode(bytes),
              'mime': mime,
              'language': language,
            }),
          )
          .timeout(const Duration(seconds: 75));

      final elapsed = DateTime.now().difference(started).inMilliseconds;

      if (response.statusCode != 200) {
        debugPrint(
          'OcrRouter: HTTP ${response.statusCode} '
          '${response.body.length > 220 ? response.body.substring(0, 220) : response.body}',
        );
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        debugPrint('OcrRouter: router reported no result');
        return null;
      }

      final text = (decoded['text'] ?? '').toString().trim();
      if (text.isEmpty) return null;

      final result = OcrRouterResult(
        text: text,
        provider: (decoded['provider'] ?? 'router').toString(),
        score: (decoded['score'] as num?)?.toDouble() ?? 0,
        elapsedMs: (decoded['elapsed_ms'] as num?)?.toInt() ?? elapsed,
      );
      debugPrint(
        'OcrRouter: ${result.provider} won '
        '(score ${result.score}, ${result.elapsedMs} ms, ${text.length} chars)',
      );
      return result;
    } catch (e) {
      debugPrint('OcrRouter: request failed: $e');
      return null;
    }
  }

  String _mimeFor(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.bmp':
        return 'image/bmp';
      case '.gif':
        return 'image/gif';
      case '.heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
}

/// Runs on a background isolate: downscales and re-encodes an oversized photo
/// so the upload stays under the router limit.
Uint8List? _shrinkForUpload(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    var image = decoded;
    if (image.width > OcrRouterService._maxSide ||
        image.height > OcrRouterService._maxSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: OcrRouterService._maxSide)
          : img.copyResize(image, height: OcrRouterService._maxSide);
    }

    var quality = 88;
    var out = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    while (out.length > OcrRouterService._maxUploadBytes && quality > 50) {
      quality -= 8;
      out = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    }
    return out;
  } catch (_) {
    return null;
  }
}