import 'package:flutter/services.dart';

class PickedDocumentFile {
  const PickedDocumentFile({
    required this.name,
    required this.bytes,
  });

  final String name;
  final Uint8List? bytes;
}

class DocumentReaderException implements Exception {
  const DocumentReaderException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TextDocumentReader {
  const TextDocumentReader();

  static const MethodChannel _channel =
      MethodChannel('document_summary/file_reader');

  Future<PickedDocumentFile?> pickDocumentFile() async {
    try {
      final response =
          await _channel.invokeMapMethod<String, dynamic>('pickTextFile');

      if (response == null) {
        return null;
      }

      return PickedDocumentFile(
        name: response['name'] as String? ?? 'document.txt',
        bytes: _bytesFrom(response['bytes']),
      );
    } on MissingPluginException {
      throw const DocumentReaderException(
        'File picking is only available on Android and iOS.',
      );
    } on PlatformException catch (error) {
      throw DocumentReaderException(
        error.message ?? 'Could not open the selected file.',
      );
    }
  }

  Future<bool> saveTextDocument({
    required String fileName,
    required String content,
  }) async {
    try {
      final saved = await _channel.invokeMethod<bool>(
        'saveTextFile',
        {
          'fileName': fileName,
          'content': content,
        },
      );

      return saved ?? false;
    } on MissingPluginException {
      throw const DocumentReaderException(
        'File download is only available on Android and iOS.',
      );
    } on PlatformException catch (error) {
      throw DocumentReaderException(
        error.message ?? 'Could not save the summary file.',
      );
    }
  }

  Future<bool> saveBinaryDocument({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    try {
      final saved = await _channel.invokeMethod<bool>(
        'saveBinaryFile',
        {
          'fileName': fileName,
          'bytes': bytes,
          'mimeType': mimeType,
        },
      );

      return saved ?? false;
    } on MissingPluginException {
      throw const DocumentReaderException(
        'File download is only available on Android and iOS.',
      );
    } on PlatformException catch (error) {
      throw DocumentReaderException(
        error.message ?? 'Could not save the summary file.',
      );
    }
  }

  Uint8List? _bytesFrom(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is Uint8List) {
      return value;
    }

    if (value is List<int>) {
      return Uint8List.fromList(value);
    }

    return null;
  }
}
