import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/text_document_reader.dart';
import '../services/text_summarizer.dart';

class SummarizerPage extends StatefulWidget {
  const SummarizerPage({super.key});

  @override
  State<SummarizerPage> createState() => _SummarizerPageState();
}

class _SummarizerPageState extends State<SummarizerPage> {
  final TextEditingController _inputController = TextEditingController();
  final TextSummarizer _summarizer = const TextSummarizer();
  final TextDocumentReader _documentReader = const TextDocumentReader();

  SummaryResult? _summaryResult;
  String? _documentName;
  double _targetRatio = 0.1;
  bool _isPickingFile = false;
  bool _isSavingFile = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _pickTextFile() async {
    setState(() {
      _isPickingFile = true;
    });

    try {
      final document = await _documentReader.pickTextDocument();

      if (!mounted || document == null) {
        return;
      }

      setState(() {
        _documentName = document.name;
        _inputController.text = document.content;
        _summaryResult = null;
      });

      if (document.content.trim().isEmpty) {
        _showMessage('File nay khong co noi dung van ban de tom tat.');
      } else {
        _summarize();
      }
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
  }

  void _summarize() {
    final input = _inputController.text.trim();

    if (input.isEmpty) {
      _showMessage('Hay nhap hoac chon file van ban truoc.');
      return;
    }

    setState(() {
      _summaryResult = _summarizer.summarize(
        input,
        targetRatio: _targetRatio,
      );
    });
  }

  void _clearInput() {
    setState(() {
      _inputController.clear();
      _summaryResult = null;
      _documentName = null;
    });
  }

  Future<void> _copySummary() async {
    final summary = _summaryResult?.summary;

    if (summary == null || summary.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: summary));
    _showMessage('Da sao chep ban tom tat.');
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inputWordCount = TextSummarizer.countWords(_inputController.text);
    final targetWordCount = (inputWordCount * _targetRatio).round();
    final estimatedInputPages = _estimatePages(inputWordCount);
    final estimatedSummaryPages = _estimatePages(targetWordCount);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Text Summarizer'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth > 720 ? 32.0 : 16.0;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                16,
                horizontalPadding,
                24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(
                        inputPages: estimatedInputPages,
                        summaryPages: estimatedSummaryPages,
                      ),
                      const SizedBox(height: 16),
                      _InputSection(
                        controller: _inputController,
                        documentName: _documentName,
                        wordCount: inputWordCount,
                        isPickingFile: _isPickingFile,
                        onPickFile: _pickTextFile,
                        onClear: _clearInput,
                        onTextChanged: () {
                          setState(() {
                            _summaryResult = null;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      _SummaryControls(
                        targetRatio: _targetRatio,
                        targetWordCount: targetWordCount,
                        onRatioChanged: (value) {
                          setState(() {
                            _targetRatio = value;
                            _summaryResult = null;
                          });
                        },
                        onSummarize: _summarize,
                      ),
                      const SizedBox(height: 16),
                      _SummaryOutput(
                        result: _summaryResult,
                        onCopy: _copySummary,
                        onDownload: _downloadSummary,
                        isSavingFile: _isSavingFile,
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

  double _estimatePages(int wordCount) {
    if (wordCount == 0) {
      return 0;
    }

    return wordCount / 500;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.inputPages,
    required this.summaryPages,
  });

  final double inputPages;
  final double summaryPages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF12355B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Text Summarizer',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Paste English or Vietnamese text, or open a TXT, PDF, DOCX, JPG, or PNG file, then turn long content into a clear summary of the main ideas.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.86),
              height: 1.4,
            ),
          ),
          if (inputPages > 0) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.description_outlined,
                  label: 'Gốc: ${_formatPages(inputPages)} trang',
                ),
                _InfoChip(
                  icon: Icons.compress,
                  label: 'Tóm tắt: ${_formatPages(summaryPages)} trang',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatPages(double pages) {
    if (pages == 0) {
      return '0';
    }

    if (pages < 1) {
      return '<1';
    }

    return pages.toStringAsFixed(pages >= 10 ? 0 : 1);
  }
}

class _InputSection extends StatelessWidget {
  const _InputSection({
    required this.controller,
    required this.documentName,
    required this.wordCount,
    required this.isPickingFile,
    required this.onPickFile,
    required this.onClear,
    required this.onTextChanged,
  });

  final TextEditingController controller;
  final String? documentName;
  final int wordCount;
  final bool isPickingFile;
  final VoidCallback onPickFile;
  final VoidCallback onClear;
  final VoidCallback onTextChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.article_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    documentName ?? 'Nguồn dữ liệu',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Text('$wordCount từ'),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('sourceInput'),
              controller: controller,
              minLines: 9,
              maxLines: 18,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                labelText: 'Dán nội dung hoặc chọn file TXT/PDF/DOCX/ảnh',
                hintText: 'Dán nội dung tiếng Việt/English hoặc mở file TXT, PDF, DOCX, JPG, PNG...',
              ),
              onChanged: (_) => onTextChanged(),
            ),
            const SizedBox(height: 12),
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
                  label: Text(isPickingFile ? 'Đang mở file' : 'Chọn file'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.text.isEmpty ? null : onClear,
                  icon: const Icon(Icons.clear),
                  label: const Text('Xóa nội dung'),
                ),
              ],
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
    required this.onRatioChanged,
    required this.onSummarize,
  });

  final double targetRatio;
  final int targetWordCount;
  final ValueChanged<double> onRatioChanged;
  final VoidCallback onSummarize;

  @override
  Widget build(BuildContext context) {
    final percent = (targetRatio * 100).round();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.tune),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Độ dài tóm tắt',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Text('$percent%'),
              ],
            ),
            Slider(
              value: targetRatio,
              min: 0.05,
              max: 0.3,
              divisions: 5,
              label: '$percent%',
              onChanged: onRatioChanged,
            ),
            Text(
              targetWordCount > 0
                  ? 'Mục tiêu khoảng $targetWordCount từ.'
                  : 'Nhập nội dung để xem độ dài mục tiêu.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('summarizeButton'),
              onPressed: onSummarize,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Tóm tắt'),
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
    required this.isSavingFile,
  });

  final SummaryResult? result;
  final VoidCallback onCopy;
  final VoidCallback onDownload;
  final bool isSavingFile;

  @override
  Widget build(BuildContext context) {
    final result = this.result;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: result == null
            ? const _EmptySummary()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.summarize_outlined),
                          const SizedBox(width: 8),
                          Text(
                            'Bản tóm tắt',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          TextButton.icon(
                            onPressed: onCopy,
                            icon: const Icon(Icons.copy, size: 18),
                            label: const Text('Sao chép'),
                          ),
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
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetricChip(
                        label: 'Gốc ${result.originalWordCount} từ',
                      ),
                      _MetricChip(
                        label: 'Tóm tắt ${result.summaryWordCount} từ',
                      ),
                      _MetricChip(
                        label:
                            'Còn ${(result.compressionRatio * 100).round()}%',
                      ),
                    ],
                  ),
                  if (result.keywords.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Từ khóa: ${result.keywords.join(', ')}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 14),
                  SelectableText(
                    result.summary,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.45,
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
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.summarize_outlined),
            SizedBox(width: 8),
            Text(
              'Bản tóm tắt',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        SizedBox(height: 10),
        Text('Kết quả sẽ xuất hiện ở đây sau khi bạn bấm Tóm tắt.'),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label),
    );
  }
}
