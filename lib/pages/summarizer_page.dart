import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/summary_result.dart';
import '../services/ai_summarizer_client.dart';
import '../services/text_document_reader.dart';

enum SummaryLanguage {
  auto('Auto', 'Auto EN/VI'),
  english('English', 'English'),
  vietnamese('Vietnamese', 'Vietnamese');

  const SummaryLanguage(this.shortLabel, this.label);

  final String shortLabel;
  final String label;
}

enum ExportPreference {
  both('Both', 'TXT/PDF'),
  text('TXT', 'TXT only'),
  pdf('PDF', 'PDF only');

  const ExportPreference(this.shortLabel, this.label);

  final String shortLabel;
  final String label;
}

class SummarizerPage extends StatefulWidget {
  const SummarizerPage({super.key});

  @override
  State<SummarizerPage> createState() => _SummarizerPageState();
}

class _SummarizerPageState extends State<SummarizerPage> {
  final TextEditingController _inputController = TextEditingController();
  final AiSummarizerClient _aiSummarizer = const AiSummarizerClient();
  final TextDocumentReader _documentReader = const TextDocumentReader();

  SummaryResult? _summaryResult;
  PickedDocumentFile? _selectedDocumentFile;
  String? _documentName;
  double _targetRatio = 0.1;
  SummaryLanguage _summaryLanguage = SummaryLanguage.auto;
  ExportPreference _exportPreference = ExportPreference.both;
  bool _isPickingFile = false;
  bool _isSavingFile = false;
  bool _isSavingPdf = false;
  bool _isSummarizing = false;
  bool _isOcrEnabled = true;
  bool _isTextInputVisible = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _pickTextFile() async {
    if (!_ensureBackendConfigured()) {
      return;
    }

    PickedDocumentFile? document;
    setState(() {
      _isPickingFile = true;
    });

    try {
      document = await _documentReader.pickDocumentFile();
    } on DocumentReaderException catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPickingFile = false;
        });
      }
    }

    final pickedDocument = document;
    if (!mounted || pickedDocument == null) {
      return;
    }

    setState(() {
      _selectedDocumentFile = pickedDocument;
      _documentName = pickedDocument.name;
      _inputController.clear();
      _summaryResult = null;
      _isTextInputVisible = false;
    });
    _showMessage('File selected. Tap Summarize to process it.');
  }

  Future<void> _summarizePickedDocumentWithBackend(
    PickedDocumentFile document,
  ) async {
    if (document.bytes == null) {
      _showMessage('Could not read the selected file bytes.');
      return;
    }

    setState(() {
      _documentName = document.name;
      _summaryResult = null;
      _isSummarizing = true;
    });

    try {
      final aiResult = await _aiSummarizer.summarizeDocument(
        fileName: document.name,
        bytes: document.bytes,
        fallbackText: null,
        targetRatio: _targetRatio,
        language: _summaryLanguage.name,
        enableOcr: _isOcrEnabled,
      );

      if (!mounted) {
        return;
      }

      final extractedText = aiResult.extractedText?.trim() ?? '';
      setState(() {
        _inputController.text = extractedText;
        _selectedDocumentFile = null;
        _isTextInputVisible = false;
        _summaryResult = SummaryResult(
          summary: aiResult.summary,
          originalWordCount: aiResult.originalWordCount,
          summaryWordCount: aiResult.summaryWordCount,
        );
      });
    } on AiSummarizerException catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSummarizing = false;
        });
      }
    }
  }

  Future<void> _summarize() async {
    final input = _inputController.text.trim();
    final selectedDocument = _selectedDocumentFile;

    if (input.isEmpty && selectedDocument == null) {
      _showMessage('Enter text or choose a file first.');
      return;
    }

    if (_isSummarizing) {
      return;
    }

    if (!_ensureBackendConfigured()) {
      return;
    }

    if (input.isEmpty && selectedDocument != null) {
      await _summarizePickedDocumentWithBackend(selectedDocument);
      return;
    }

    setState(() {
      _isSummarizing = true;
    });

    try {
      final aiResult = await _aiSummarizer.summarize(
        text: input,
        targetRatio: _targetRatio,
        language: _summaryLanguage.name,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _summaryResult = SummaryResult(
          summary: aiResult.summary,
          originalWordCount: aiResult.originalWordCount,
          summaryWordCount: aiResult.summaryWordCount,
        );
      });
    } on AiSummarizerException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() {
          _isSummarizing = false;
        });
      }
    }
  }

  bool _ensureBackendConfigured() {
    if (_aiSummarizer.isConfigured) {
      return true;
    }

    _showMessage(
      'Backend URL is not configured. Build the app with SUMMARY_API_URL.',
    );
    return false;
  }

  void _clearInput() {
    setState(() {
      _inputController.clear();
      _summaryResult = null;
      _documentName = null;
      _selectedDocumentFile = null;
      _isTextInputVisible = false;
    });
  }

  void _showTextInput() {
    setState(() {
      _summaryResult = null;
      _selectedDocumentFile = null;
      _documentName = null;
      _isTextInputVisible = true;
    });
  }

  void _editSourceText() {
    setState(() {
      _summaryResult = null;
      _selectedDocumentFile = null;
      _isTextInputVisible = true;
    });
  }

  void _handleSourceTextChanged() {
    setState(() {
      _summaryResult = null;
      _isTextInputVisible = true;
      if (_inputController.text.trim().isNotEmpty) {
        _selectedDocumentFile = null;
        _documentName = null;
      }
    });
  }

  void _setSummaryLength(double value) {
    setState(() {
      _targetRatio = value;
      _summaryResult = null;
    });
  }

  void _setSummaryLanguage(SummaryLanguage value) {
    setState(() {
      _summaryLanguage = value;
      _summaryResult = null;
    });
  }

  void _setOcrEnabled(bool value) {
    setState(() {
      _isOcrEnabled = value;
    });

    _showMessage(value ? 'OCR enabled.' : 'OCR disabled.');
  }

  void _setExportPreference(ExportPreference value) {
    setState(() {
      _exportPreference = value;
    });
  }

  void _resetSummaryLength() {
    setState(() {
      _targetRatio = 0.1;
      _summaryResult = null;
    });

    _showMessage('Summary length reset to 10%.');
  }

  void _openSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF6F8FC),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void updateSheet(VoidCallback action) {
              action();
              setSheetState(() {});
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: _SettingsBar(
                    language: _summaryLanguage,
                    targetRatio: _targetRatio,
                    isOcrEnabled: _isOcrEnabled,
                    exportPreference: _exportPreference,
                    onLanguageChanged: (value) {
                      updateSheet(() => _setSummaryLanguage(value));
                    },
                    onTargetRatioChanged: (value) {
                      updateSheet(() => _setSummaryLength(value));
                    },
                    onOcrChanged: (value) {
                      updateSheet(() => _setOcrEnabled(value));
                    },
                    onExportPreferenceChanged: (value) {
                      updateSheet(() => _setExportPreference(value));
                    },
                    onResetLength: () {
                      updateSheet(_resetSummaryLength);
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _copySummary() async {
    final summary = _summaryResult?.summary;

    if (summary == null || summary.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: summary));
    _showMessage('Summary copied.');
  }

  Future<void> _downloadSummary() async {
    final summary = _summaryResult?.summary;

    if (summary == null || summary.isEmpty) {
      return;
    }

    setState(() {
      _isSavingFile = true;
    });

    try {
      final saved = await _documentReader.saveTextDocument(
        fileName: _summaryFileName(),
        content: summary,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        saved ? 'Summary file saved.' : 'File download was canceled.',
      );
    } on DocumentReaderException catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingFile = false;
        });
      }
    }
  }

  Future<void> _downloadSummaryPdf() async {
    final result = _summaryResult;

    if (result == null || result.summary.isEmpty) {
      return;
    }

    setState(() {
      _isSavingPdf = true;
    });

    try {
      final pdfBytes = await _buildSummaryPdf(result);
      final saved = await _documentReader.saveBinaryDocument(
        fileName: _summaryPdfFileName(),
        bytes: pdfBytes,
        mimeType: 'application/pdf',
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        saved ? 'Summary PDF saved.' : 'PDF download was canceled.',
      );
    } on DocumentReaderException catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('Could not save PDF: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingPdf = false;
        });
      }
    }
  }

  String _summaryFileName() {
    final sourceName = _documentName?.trim();
    final baseName = sourceName == null || sourceName.isEmpty
        ? 'summary'
        : sourceName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final safeName = baseName
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();

    return '${safeName.isEmpty ? 'summary' : safeName}_summary.txt';
  }

  String _summaryPdfFileName() {
    final textFileName = _summaryFileName();
    return textFileName.replaceFirst(RegExp(r'\.txt$'), '.pdf');
  }

  Future<Uint8List> _buildSummaryPdf(SummaryResult result) async {
    final regularFontData = await rootBundle.load(
      'assets/fonts/Roboto-Regular.ttf',
    );
    final regularFontBytes = regularFontData.buffer.asUint8List(
      regularFontData.offsetInBytes,
      regularFontData.lengthInBytes,
    );

    final document = PdfDocument();
    document.pageSettings.margins.all = 32;

    final page = document.pages.add();
    final bounds = page.getClientSize();
    final bodyFont = PdfTrueTypeFont(regularFontBytes, 12);
    final textBrush = PdfSolidBrush(PdfColor(38, 38, 38));

    PdfTextElement(
      text: result.summary,
      font: bodyFont,
      brush: textBrush,
      format: PdfStringFormat(lineSpacing: 4),
    ).draw(
      page: page,
      bounds: Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
    );

    final bytes = Uint8List.fromList(document.saveSync());
    document.dispose();

    return bytes;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inputWordCount = _summaryResult?.originalWordCount ??
        (_isTextInputVisible ? _countWords(_inputController.text) : 0);
    final targetWordCount = (inputWordCount * _targetRatio).round();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 920;
            final horizontalPadding = constraints.maxWidth > 720 ? 32.0 : 16.0;

            if (!isWide) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  children: [
                    _Header(onOpenSettings: _openSettingsSheet),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _PhoneWorkspace(
                        controller: _inputController,
                        documentName: _documentName,
                        wordCount: inputWordCount,
                        targetRatio: _targetRatio,
                        result: _summaryResult,
                        exportPreference: _exportPreference,
                        isPickingFile: _isPickingFile,
                        isSavingFile: _isSavingFile,
                        isSavingPdf: _isSavingPdf,
                        isSummarizing: _isSummarizing,
                        isTextInputVisible: _isTextInputVisible,
                        onPickFile: _pickTextFile,
                        onEnterText: _showTextInput,
                        onClear: _clearInput,
                        onSummarize: _summarize,
                        onCopy: _copySummary,
                        onDownload: _downloadSummary,
                        onDownloadPdf: _downloadSummaryPdf,
                        onEditText: _editSourceText,
                        onTextChanged: _handleSourceTextChanged,
                      ),
                    ),
                  ],
                ),
              );
            }

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                18,
                horizontalPadding,
                28,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1060),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(
                        onOpenSettings: _openSettingsSheet,
                      ),
                      const SizedBox(height: 18),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 7,
                              child: _InputSection(
                                controller: _inputController,
                                documentName: _documentName,
                                wordCount: inputWordCount,
                                isPickingFile: _isPickingFile,
                                isTextInputVisible: _isTextInputVisible,
                                onPickFile: _pickTextFile,
                                onEnterText: _showTextInput,
                                onClear: _clearInput,
                                onTextChanged: _handleSourceTextChanged,
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              flex: 4,
                              child: _SummaryControls(
                                targetRatio: _targetRatio,
                                targetWordCount: targetWordCount,
                                isSummarizing: _isSummarizing,
                                onRatioChanged: _setSummaryLength,
                                onSummarize: _summarize,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _InputSection(
                          controller: _inputController,
                          documentName: _documentName,
                          wordCount: inputWordCount,
                          isPickingFile: _isPickingFile,
                          isTextInputVisible: _isTextInputVisible,
                          onPickFile: _pickTextFile,
                          onEnterText: _showTextInput,
                          onClear: _clearInput,
                          onTextChanged: _handleSourceTextChanged,
                        ),
                        const SizedBox(height: 16),
                        _SummaryControls(
                          targetRatio: _targetRatio,
                          targetWordCount: targetWordCount,
                          isSummarizing: _isSummarizing,
                          onRatioChanged: _setSummaryLength,
                          onSummarize: _summarize,
                        ),
                      ],
                      const SizedBox(height: 16),
                      _SummaryOutput(
                        result: _summaryResult,
                        onCopy: _copySummary,
                        onDownload: _downloadSummary,
                        onDownloadPdf: _downloadSummaryPdf,
                        exportPreference: _exportPreference,
                        isSavingFile: _isSavingFile,
                        isSavingPdf: _isSavingPdf,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  int _countWords(String text) {
    return text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .length;
  }

}

class _Header extends StatelessWidget {
  const _Header({
    required this.onOpenSettings,
  });

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1E8F2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            offset: const Offset(0, 12),
            blurRadius: 28,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Text Summarizer',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF111827),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Tooltip(
            message: 'Open settings',
            child: IconButton.filledTonal(
              key: const Key('settingsToggleButton'),
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneWorkspace extends StatelessWidget {
  const _PhoneWorkspace({
    required this.controller,
    required this.documentName,
    required this.wordCount,
    required this.targetRatio,
    required this.result,
    required this.exportPreference,
    required this.isPickingFile,
    required this.isSavingFile,
    required this.isSavingPdf,
    required this.isSummarizing,
    required this.isTextInputVisible,
    required this.onPickFile,
    required this.onEnterText,
    required this.onClear,
    required this.onSummarize,
    required this.onCopy,
    required this.onDownload,
    required this.onDownloadPdf,
    required this.onEditText,
    required this.onTextChanged,
  });

  final TextEditingController controller;
  final String? documentName;
  final int wordCount;
  final double targetRatio;
  final SummaryResult? result;
  final ExportPreference exportPreference;
  final bool isPickingFile;
  final bool isSavingFile;
  final bool isSavingPdf;
  final bool isSummarizing;
  final bool isTextInputVisible;
  final VoidCallback onPickFile;
  final VoidCallback onEnterText;
  final VoidCallback onClear;
  final VoidCallback onSummarize;
  final VoidCallback onCopy;
  final VoidCallback onDownload;
  final VoidCallback onDownloadPdf;
  final VoidCallback onEditText;
  final VoidCallback onTextChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = this.result;
    final hasDocument = documentName != null && documentName!.trim().isNotEmpty;
    final percent = (targetRatio * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    result == null
                        ? Icons.article_outlined
                        : Icons.summarize_outlined,
                    color: const Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result == null ? 'Source document' : 'Summary',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: const Color(0xFF111827),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        result == null
                            ? (hasDocument
                                ? documentName!
                                : isTextInputVisible
                                    ? 'Paste text to summarize'
                                    : 'Choose a file or enter text')
                            : '${result.summaryWordCount} words, target $percent% of original',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF697586),
                        ),
                      ),
                    ],
                  ),
                ),
                _CountBadge(
                  value: result == null
                      ? wordCount.toString()
                      : result.originalWordCount.toString(),
                  label: result == null ? 'words' : 'source',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: result == null
                  ? isTextInputVisible
                      ? TextField(
                          key: const Key('sourceInput'),
                          controller: controller,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          textInputAction: TextInputAction.newline,
                          decoration: const InputDecoration(
                            alignLabelWithHint: true,
                            labelText: 'Document content',
                            hintText: 'Paste English/Vietnamese text...',
                          ),
                          onChanged: (_) => onTextChanged(),
                        )
                      : _SourcePlaceholder(
                          hasDocument: hasDocument,
                          documentName: documentName,
                        )
                  : Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBFCFE),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE4EAF3)),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          result.summary,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF1F2937),
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            if (result == null) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: isPickingFile ? null : onPickFile,
                    icon: isPickingFile
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file),
                    label: Text(isPickingFile ? 'Opening file' : 'Choose file'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('enterTextButton'),
                    onPressed: isTextInputVisible ? null : onEnterText,
                    icon: const Icon(Icons.edit_note_outlined),
                    label: const Text('Enter text'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.text.isEmpty &&
                            !hasDocument &&
                            !isTextInputVisible
                        ? null
                        : onClear,
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('summarizeButton'),
                onPressed: isSummarizing ? null : onSummarize,
                icon: isSummarizing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  isSummarizing ? 'Summarizing' : 'Summarize ($percent%)',
                ),
              ),
            ] else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onEditText,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit text'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                  ),
                  if (exportPreference != ExportPreference.pdf)
                    FilledButton.tonalIcon(
                      key: const Key('downloadSummaryButton'),
                      onPressed: isSavingFile ? null : onDownload,
                      icon: isSavingFile
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.file_download_outlined),
                      label: Text(isSavingFile ? 'Saving' : 'Download .txt'),
                    ),
                  if (exportPreference != ExportPreference.text)
                    FilledButton.icon(
                      key: const Key('downloadSummaryPdfButton'),
                      onPressed: isSavingPdf ? null : onDownloadPdf,
                      icon: isSavingPdf
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(isSavingPdf ? 'Saving' : 'Download PDF'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourcePlaceholder extends StatelessWidget {
  const _SourcePlaceholder({
    required this.hasDocument,
    required this.documentName,
  });

  final bool hasDocument;
  final String? documentName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4EAF3)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasDocument ? Icons.insert_drive_file_outlined : Icons.input,
              size: 36,
              color: const Color(0xFF4F66A3),
            ),
            const SizedBox(height: 10),
            Text(
              hasDocument ? documentName ?? 'Selected file' : 'No source yet',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: const Color(0xFF111827),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasDocument
                  ? 'Tap Summarize to process this file.'
                  : 'Choose a file or tap Enter text.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF697586),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsBar extends StatelessWidget {
  const _SettingsBar({
    required this.language,
    required this.targetRatio,
    required this.isOcrEnabled,
    required this.exportPreference,
    required this.onLanguageChanged,
    required this.onTargetRatioChanged,
    required this.onOcrChanged,
    required this.onExportPreferenceChanged,
    required this.onResetLength,
  });

  final SummaryLanguage language;
  final double targetRatio;
  final bool isOcrEnabled;
  final ExportPreference exportPreference;
  final ValueChanged<SummaryLanguage> onLanguageChanged;
  final ValueChanged<double> onTargetRatioChanged;
  final ValueChanged<bool> onOcrChanged;
  final ValueChanged<ExportPreference> onExportPreferenceChanged;
  final VoidCallback onResetLength;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (targetRatio * 100).round();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1E8F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Settings',
            style: theme.textTheme.titleSmall?.copyWith(
              color: const Color(0xFF111827),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          _SettingsItem(
            icon: Icons.translate,
            label: 'Language',
            value: language.label,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<SummaryLanguage>(
                key: const Key('languageDropdown'),
                value: language,
                isExpanded: true,
                borderRadius: BorderRadius.circular(8),
                icon: const Icon(Icons.keyboard_arrow_down),
                items: SummaryLanguage.values
                    .map(
                      (value) => DropdownMenuItem<SummaryLanguage>(
                        value: value,
                        child: Text(value.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    onLanguageChanged(value);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          _SettingsItem(
            icon: Icons.compress,
            label: 'Length of original',
            value: '$percent%',
            child: Slider(
              value: targetRatio,
              min: 0,
              max: 1,
              divisions: 100,
              label: '$percent%',
              onChanged: onTargetRatioChanged,
            ),
          ),
          const SizedBox(height: 8),
          _SettingsItem(
            icon: Icons.document_scanner_outlined,
            label: 'OCR',
            value: isOcrEnabled ? 'On' : 'Off',
            child: Switch.adaptive(
              value: isOcrEnabled,
              onChanged: onOcrChanged,
            ),
          ),
          const SizedBox(height: 8),
          _SettingsItem(
            icon: Icons.ios_share_outlined,
            label: 'Export',
            value: exportPreference.label,
            child: SegmentedButton<ExportPreference>(
              showSelectedIcon: false,
              segments: ExportPreference.values
                  .map(
                    (value) => ButtonSegment<ExportPreference>(
                      value: value,
                      label: Text(value.shortLabel),
                    ),
                  )
                  .toList(),
              selected: {exportPreference},
              onSelectionChanged: (selection) {
                onExportPreferenceChanged(selection.first);
              },
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: percent == 10 ? null : onResetLength,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Reset length'),
          ),
        ],
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.child,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4EAF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF64748B)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF697586),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF111827),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _InputSection extends StatelessWidget {
  const _InputSection({
    required this.controller,
    required this.documentName,
    required this.wordCount,
    required this.isPickingFile,
    required this.isTextInputVisible,
    required this.onPickFile,
    required this.onEnterText,
    required this.onClear,
    required this.onTextChanged,
  });

  final TextEditingController controller;
  final String? documentName;
  final int wordCount;
  final bool isPickingFile;
  final bool isTextInputVisible;
  final VoidCallback onPickFile;
  final VoidCallback onEnterText;
  final VoidCallback onClear;
  final VoidCallback onTextChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDocument = documentName != null && documentName!.trim().isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.article_outlined,
                    color: Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Source document',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: const Color(0xFF111827),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasDocument
                            ? documentName!
                            : isTextInputVisible
                                ? 'Paste text to summarize'
                                : 'Choose a file or enter text',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF697586),
                        ),
                      ),
                    ],
                  ),
                ),
                _CountBadge(
                  value: wordCount.toString(),
                  label: 'words',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isTextInputVisible)
              TextField(
                key: const Key('sourceInput'),
                controller: controller,
                minLines: 11,
                maxLines: 18,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  alignLabelWithHint: true,
                  labelText: 'Document content',
                  hintText:
                      'Paste English/Vietnamese text or open TXT, PDF, DOCX, JPG, PNG...',
                ),
                onChanged: (_) => onTextChanged(),
              )
            else
              SizedBox(
                height: 190,
                child: _SourcePlaceholder(
                  hasDocument: hasDocument,
                  documentName: documentName,
                ),
              ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: isPickingFile ? null : onPickFile,
                  icon: isPickingFile
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file),
                  label: Text(isPickingFile ? 'Opening file' : 'Choose file'),
                ),
                OutlinedButton.icon(
                  key: const Key('enterTextButton'),
                  onPressed: isTextInputVisible ? null : onEnterText,
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('Enter text'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.text.isEmpty &&
                          !hasDocument &&
                          !isTextInputVisible
                      ? null
                      : onClear,
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear text'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Supported: plain text, native PDF text, scanned PDF OCR, DOCX, JPG, and PNG.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF697586),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryControls extends StatelessWidget {
  const _SummaryControls({
    required this.targetRatio,
    required this.targetWordCount,
    required this.isSummarizing,
    required this.onRatioChanged,
    required this.onSummarize,
  });

  final double targetRatio;
  final int targetWordCount;
  final bool isSummarizing;
  final ValueChanged<double> onRatioChanged;
  final VoidCallback onSummarize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (targetRatio * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFFAF7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.tune,
                    color: Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Summary settings',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: const Color(0xFF111827),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Choose the summary length as a percentage of the original text.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF697586),
                        ),
                      ),
                    ],
                  ),
                ),
                _CountBadge(value: '$percent%', label: 'of original'),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE4EAF3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.short_text,
                        size: 20,
                        color: Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          targetRatio == 0
                              ? 'Target: shortest possible summary'
                              : targetWordCount > 0
                                  ? 'Target: about $targetWordCount words from the original'
                                  : 'Enter text to estimate target length',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Slider(
                    value: targetRatio,
                    min: 0,
                    max: 1,
                    divisions: 100,
                    label: '$percent%',
                    onChanged: onRatioChanged,
                  ),
                  const Row(
                    children: [
                      Text('0%'),
                      Spacer(),
                      Text('100% of original'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('summarizeButton'),
              onPressed: isSummarizing ? null : onSummarize,
              icon: isSummarizing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(isSummarizing ? 'Summarizing' : 'Summarize'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryOutput extends StatelessWidget {
  const _SummaryOutput({
    required this.result,
    required this.onCopy,
    required this.onDownload,
    required this.onDownloadPdf,
    required this.exportPreference,
    required this.isSavingFile,
    required this.isSavingPdf,
  });

  final SummaryResult? result;
  final VoidCallback onCopy;
  final VoidCallback onDownload;
  final VoidCallback onDownloadPdf;
  final ExportPreference exportPreference;
  final bool isSavingFile;
  final bool isSavingPdf;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: result == null
            ? const _EmptySummary()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.summarize_outlined,
                          color: Color(0xFFB45309),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Summary',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: const Color(0xFF111827),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Ready to copy or download.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF697586),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const _StatusPill(label: 'Ready'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetricChip(
                        icon: Icons.notes,
                        label: 'Original',
                        value: '${result.originalWordCount} words',
                      ),
                      _MetricChip(
                        icon: Icons.compress,
                        label: 'Output',
                        value: '${result.summaryWordCount} words',
                      ),
                      _MetricChip(
                        icon: Icons.percent,
                        label: 'Summary length',
                        value:
                            '${(result.compressionRatio * 100).round()}% of original',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onCopy,
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy'),
                      ),
                      if (exportPreference != ExportPreference.pdf)
                        FilledButton.tonalIcon(
                          key: const Key('downloadSummaryButton'),
                          onPressed: isSavingFile ? null : onDownload,
                          icon: isSavingFile
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.file_download_outlined),
                          label: Text(
                            isSavingFile ? 'Saving' : 'Download .txt',
                          ),
                        ),
                      if (exportPreference != ExportPreference.text)
                        FilledButton.icon(
                          key: const Key('downloadSummaryPdfButton'),
                          onPressed: isSavingPdf ? null : onDownloadPdf,
                          icon: isSavingPdf
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.picture_as_pdf_outlined),
                          label: Text(
                            isSavingPdf ? 'Saving' : 'Download PDF',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBFCFE),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE4EAF3)),
                    ),
                    child: SelectableText(
                      result.summary,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF1F2937),
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _EmptySummary extends StatelessWidget {
  const _EmptySummary();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4EAF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Color(0xFF2563EB),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Summary',
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFF111827),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your summary will appear here after you tap Summarize.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF697586),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFAF7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFE8DC)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF0F766E),
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4EAF3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF111827),
                  fontWeight: FontWeight.w800,
                ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF697586),
                ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4EAF3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF2563EB)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF697586),
                    ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF111827),
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
