import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

class PickedTextDocument {
  const PickedTextDocument({
    required this.name,
    required this.content,
  });

  final String name;
  final String content;
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

  Future<PickedTextDocument?> pickTextDocument({
    bool enableOcr = true,
  }) async {
    try {
      final response =
          await _channel.invokeMapMethod<String, dynamic>('pickTextFile');

      if (response == null) {
        return null;
      }

      return PickedTextDocument(
        name: response['name'] as String? ?? 'Tai lieu',
        content: cleanExtractedText(await _extractDocumentText(
          response,
          enableOcr: enableOcr,
        )),
      );
    } on MissingPluginException {
      throw const DocumentReaderException(
        'Tinh nang chon file hien chi duoc cai tren Android va iOS. '
        'Hay dan noi dung vao o nhap neu dang chay tren web/desktop.',
      );
    } on PlatformException catch (error) {
      throw DocumentReaderException(
        error.message ?? 'Khong the doc file da chon.',
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
        'Tinh nang tai file hien chi duoc cai tren Android va iOS.',
      );
    } on PlatformException catch (error) {
      throw DocumentReaderException(
        error.message ?? 'Khong the luu file tom tat.',
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

  Future<String> _extractDocumentText(
    Map<String, dynamic> response, {
    required bool enableOcr,
  }) async {
    final name = response['name'] as String? ?? '';
    final extension = _extensionOf(name);
    final bytes = _bytesFrom(response['bytes']);

    if (extension == 'pdf') {
      if (bytes == null) {
        throw const DocumentReaderException('PDF file data is missing.');
      }

      return _extractPdfText(bytes, enableOcr: enableOcr);
    }

    if (extension == 'docx') {
      if (bytes == null) {
        throw const DocumentReaderException('DOCX file data is missing.');
      }

      return _extractDocxText(bytes);
    }

    if (_isImageExtension(extension)) {
      if (bytes == null) {
        throw const DocumentReaderException('Image file data is missing.');
      }

      if (!enableOcr) {
        throw const DocumentReaderException(
          'OCR is turned off. Enable OCR in Settings to read image files.',
        );
      }

      return _extractImageText(bytes);
    }

    final content = response['content'] as String?;
    if (content != null) {
      return content;
    }

    if (bytes != null) {
      return utf8.decode(bytes, allowMalformed: true);
    }

    return '';
  }

  Future<String> _extractPdfText(
    Uint8List bytes, {
    required bool enableOcr,
  }) async {
    final document = PdfDocument(inputBytes: bytes);

    try {
      final text = PdfTextExtractor(document).extractText().trim();

      if (text.isNotEmpty) {
        return text;
      }
    } finally {
      document.dispose();
    }

    if (!enableOcr) {
      throw const DocumentReaderException(
        'This PDF appears to be scanned. Enable OCR in Settings to read it.',
      );
    }

    return _extractScannedPdfText(bytes);
  }

  Future<String> _extractScannedPdfText(Uint8List bytes) async {
    final text = await _extractNativeOcrText(
      method: 'ocrScannedPdf',
      bytes: bytes,
    );

    if (text.isEmpty) {
      throw const DocumentReaderException(
        'OCR could not find readable text in this scanned PDF.',
      );
    }

    return text;
  }

  Future<String> _extractImageText(Uint8List bytes) async {
    final text = await _extractNativeOcrText(
      method: 'ocrImage',
      bytes: bytes,
    );

    if (text.isEmpty) {
      throw const DocumentReaderException(
        'OCR could not find readable text in this image.',
      );
    }

    return text;
  }

  Future<String> _extractNativeOcrText({
    required String method,
    required Uint8List bytes,
  }) async {
    try {
      final text = await _channel.invokeMethod<String>(
        method,
        {'bytes': bytes},
      );

      return (text ?? '').trim();
    } on MissingPluginException {
      throw const DocumentReaderException(
        'OCR is only available on Android and iOS.',
      );
    } on PlatformException catch (error) {
      throw DocumentReaderException(
        error.message ?? 'OCR could not read this scanned file.',
      );
    }
  }

  String _extractDocxText(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final parts = [
      'word/document.xml',
      ...archive.files
          .where((file) =>
              file.name.startsWith('word/header') &&
              file.name.endsWith('.xml'))
          .map((file) => file.name),
      ...archive.files
          .where((file) =>
              file.name.startsWith('word/footer') &&
              file.name.endsWith('.xml'))
          .map((file) => file.name),
    ];
    final paragraphs = <String>[];

    for (final partName in parts) {
      final part = archive.findFile(partName);
      final partBytes = part?.readBytes();

      if (partBytes == null) {
        continue;
      }

      paragraphs.addAll(_extractDocxXmlParagraphs(utf8.decode(partBytes)));
    }

    final text = paragraphs
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.isNotEmpty)
        .join('\n\n');

    if (text.isEmpty) {
      throw const DocumentReaderException(
        'This DOCX file does not contain readable text.',
      );
    }

    return text;
  }

  List<String> _extractDocxXmlParagraphs(String xmlContent) {
    final document = XmlDocument.parse(xmlContent);
    final paragraphs = <String>[];

    for (final paragraph in document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'p')) {
      final buffer = StringBuffer();

      for (final element in paragraph.descendants.whereType<XmlElement>()) {
        switch (element.name.local) {
          case 't':
            buffer.write(element.innerText);
          case 'tab':
            buffer.write('\t');
          case 'br':
            buffer.write('\n');
        }
      }

      paragraphs.add(buffer.toString());
    }

    return paragraphs;
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

  String _extensionOf(String fileName) {
    final lastDot = fileName.lastIndexOf('.');

    if (lastDot == -1 || lastDot == fileName.length - 1) {
      return '';
    }

    return fileName.substring(lastDot + 1).toLowerCase();
  }

  bool _isImageExtension(String extension) {
    return extension == 'jpg' || extension == 'jpeg' || extension == 'png';
  }

  static String cleanExtractedText(String text) {
    var cleaned = text
        .replaceAll('\u00A0', ' ')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'-\s*\n\s*'), '')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');

    cleaned = cleaned
        .split(RegExp(r'\n{2,}'))
        .map((paragraph) => paragraph.replaceAll(RegExp(r'\n+'), ' ').trim())
        .where((paragraph) => paragraph.isNotEmpty)
        .join('\n\n');

    cleaned = cleaned
        .replaceAllMapped(
          RegExp(r'([,;:])(?=\S)'),
          (match) => '${match.group(1)} ',
        )
        .replaceAllMapped(
          RegExp(r'([.!?])(?=[A-Za-z0-9À-ỹ])', unicode: true),
          (match) => '${match.group(1)} ',
        )
        .replaceAllMapped(
          RegExp(r'([a-zà-ỹ])([A-ZÀ-Ỹ])', unicode: true),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r'([A-Za-zÀ-ỹ])(\d)', unicode: true),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r'(\d)([A-Za-zÀ-ỹ])', unicode: true),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r'(\S)(\[)'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r'(\])(?=\S)'),
          (match) => '${match.group(1)} ',
        )
        .replaceAllMapped(
          RegExp(r'([a-z]{4,})(and|with|for|from|into|using)(\s+[A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}${match.group(3)}',
        )
        .replaceAllMapped(
          RegExp(r'([a-z]{4,})witha(\s+[A-Z])'),
          (match) => '${match.group(1)} with a${match.group(2)}',
        )
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .trim();

    return cleaned;
  }
}
