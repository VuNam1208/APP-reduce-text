import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Future<AiSummaryResponse> summarize({
    required String text,
    required double targetRatio,
    required String language,
  }) async {
    final endpoint = _endpoint('/api/summarize');
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
      return await _readSummaryResponse(response);
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

  Future<AiSummaryResponse> summarizeDocument({
    required String fileName,
    required Uint8List? bytes,
    required String? fallbackText,
    required double targetRatio,
    required String language,
    required bool enableOcr,
  }) async {
    final endpoint = _endpoint('/api/summarize-file');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final boundary = '----text-summary-${DateTime.now().microsecondsSinceEpoch}';

    try {
      final request = await client.postUrl(endpoint);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );

      _addMultipartField(request, boundary, 'targetRatio', '$targetRatio');
      _addMultipartField(request, boundary, 'language', language);
      _addMultipartField(request, boundary, 'enableOcr', '$enableOcr');

      final fallback = fallbackText?.trim();
      if (fallback != null && fallback.isNotEmpty) {
        _addMultipartField(request, boundary, 'fallbackText', fallback);
      }

      if (bytes != null) {
        _addMultipartFile(
          request,
          boundary,
          fieldName: 'file',
          fileName: fileName,
          bytes: bytes,
        );
      }

      request.add(utf8.encode('--$boundary--\r\n'));

      final response = await request.close().timeout(
            const Duration(seconds: 120),
          );
      return await _readSummaryResponse(response);
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

  Uri _endpoint(String path) {
    if (!isConfigured) {
      throw const AiSummarizerException('AI backend URL is not configured.');
    }

    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$normalized$path');
  }

  Future<AiSummaryResponse> _readSummaryResponse(
    HttpClientResponse response,
  ) async {
    final body = await response.transform(utf8.decoder).join();
    final data = _decodeJsonObject(body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiSummarizerException(
        data['error']?.toString() ??
            data['detail']?.toString() ??
            'AI backend request failed.',
      );
    }

    return AiSummaryResponse(
      summary: data['summary']?.toString() ?? '',
      originalWordCount: _readInt(data['originalWordCount']),
      summaryWordCount: _readInt(data['summaryWordCount']),
      extractedText: data['extractedText']?.toString(),
    );
  }

  Map<String, dynamic> _decodeJsonObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return const {};
    }

    return const {};
  }

  void _addMultipartField(
    HttpClientRequest request,
    String boundary,
    String name,
    String value,
  ) {
    request.add(
      utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="$name"\r\n\r\n'
        '$value\r\n',
      ),
    );
  }

  void _addMultipartFile(
    HttpClientRequest request,
    String boundary, {
    required String fieldName,
    required String fileName,
    required Uint8List bytes,
  }) {
    final safeFileName = fileName.replaceAll('"', '_');
    request.add(
      utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="$fieldName"; filename="$safeFileName"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n',
      ),
    );
    request.add(bytes);
    request.add(utf8.encode('\r\n'));
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
