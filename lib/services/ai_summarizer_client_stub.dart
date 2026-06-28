import 'dart:typed_data';

class AiSummaryResponse {
  const AiSummaryResponse({
    required this.summary,
    required this.originalWordCount,
    required this.summaryWordCount,
    this.extractedText,
  });

  final String summary;
  final int originalWordCount;
  final int summaryWordCount;
  final String? extractedText;
}

class AiSummarizerException implements Exception {
  const AiSummarizerException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiSummarizerClient {
  const AiSummarizerClient({
    this.baseUrl = const String.fromEnvironment('SUMMARY_API_URL'),
  });

  final String baseUrl;

  bool get isConfigured => false;

  Future<AiSummaryResponse> summarize({
    required String text,
    required double targetRatio,
    required String language,
  }) {
    throw const AiSummarizerException(
      'AI backend is only available on Android and iOS builds.',
    );
  }

  Future<AiSummaryResponse> summarizeDocument({
    required String fileName,
    required Uint8List? bytes,
    required String? fallbackText,
    required double targetRatio,
    required String language,
    required bool enableOcr,
  }) {
    throw const AiSummarizerException(
      'AI backend is only available on Android and iOS builds.',
    );
  }
}
