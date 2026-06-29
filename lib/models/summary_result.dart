class SummaryResult {
  const SummaryResult({
    required this.summary,
    required this.originalWordCount,
    required this.summaryWordCount,
  });

  final String summary;
  final int originalWordCount;
  final int summaryWordCount;

  double get compressionRatio {
    if (originalWordCount == 0) {
      return 0;
    }

    return summaryWordCount / originalWordCount;
  }
}
