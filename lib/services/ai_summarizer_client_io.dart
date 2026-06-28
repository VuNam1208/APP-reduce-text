import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AiSummaryResponse {
  const AiSummaryResponse({
    required this.summary,
    required this.originalWordCount,
    required this.summaryWordCount,
  });

  final String summary;
  final int originalWordCount;
  final int summaryWordCount;
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

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Future<AiSummaryResponse> summarize({
    required String text,
    required double targetRatio,
    required String language,
  }) async {
    final endpoint = _endpoint();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);

    try {
      final request = await client.postUrl(endpoint);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'text': text,
          'targetRatio': targetRatio,
          'language': language,
        }),
      );

      final response = await request.close().timeout(
            const Duration(seconds: 90),
          );
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiSummarizerException(
          data['error']?.toString() ?? 'AI backend request failed.',
        );
      }

      return AiSummaryResponse(
        summary: data['summary']?.toString() ?? '',
        originalWordCount: _readInt(data['originalWordCount']),
        summaryWordCount: _readInt(data['summaryWordCount']),
      );
    } on TimeoutException {
      throw const AiSummarizerException('AI backend request timed out.');
    } on AiSummarizerException {
      rethrow;
    } catch (_) {
      throw const AiSummarizerException('Could not connect to AI backend.');
    } finally {
      client.close(force: true);
    }
  }

  Uri _endpoint() {
    if (!isConfigured) {
      throw const AiSummarizerException('AI backend URL is not configured.');
    }

    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$normalized/api/summarize');
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
