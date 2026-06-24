import 'dart:math';

class SummaryResult {
  const SummaryResult({
    required this.summary,
    required this.keywords,
    required this.originalWordCount,
    required this.summaryWordCount,
    required this.originalSentenceCount,
    required this.summarySentenceCount,
  });

  final String summary;
  final List<String> keywords;
  final int originalWordCount;
  final int summaryWordCount;
  final int originalSentenceCount;
  final int summarySentenceCount;

  double get compressionRatio {
    if (originalWordCount == 0) {
      return 0;
    }

    return summaryWordCount / originalWordCount;
  }
}

class TextSummarizer {
  const TextSummarizer();

  static final RegExp _wordPattern = RegExp(
    r"[A-Za-z0-9À-ỹ]+",
    unicode: true,
  );

  static const Set<String> _stopWords = {
    'a',
    'an',
    'and',
    'are',
    'as',
    'at',
    'be',
    'by',
    'for',
    'from',
    'has',
    'in',
    'is',
    'it',
    'of',
    'on',
    'or',
    'that',
    'the',
    'this',
    'to',
    'was',
    'were',
    'will',
    'with',
    'va',
    'voi',
    'cua',
    'cac',
    'nhung',
    'mot',
    'duoc',
    'trong',
    'cho',
    'khi',
    'thi',
    'la',
    'co',
    'khong',
    'tu',
    'den',
    've',
    'nhu',
    'nay',
    'do',
    'de',
    'ra',
    'vao',
    'tai',
    'sau',
    'truoc',
    'giua',
    'và',
    'với',
    'của',
    'các',
    'những',
    'một',
    'được',
    'thì',
    'là',
    'có',
    'không',
    'từ',
    'đến',
    'về',
    'như',
    'này',
    'đó',
    'để',
    'vào',
    'thể',
    'tại',
    'trước',
    'giữa',
  };

  static int countWords(String text) => _tokenize(text).length;

  SummaryResult summarize(
    String input, {
    double targetRatio = 0.1,
  }) {
    final cleanText = _normalizeWhitespace(input);
    final allWords = _tokenize(cleanText);
    final originalWordCount = allWords.length;
    final rawSentences = _splitSentences(cleanText);

    if (cleanText.isEmpty) {
      return const SummaryResult(
        summary: '',
        keywords: [],
        originalWordCount: 0,
        summaryWordCount: 0,
        originalSentenceCount: 0,
        summarySentenceCount: 0,
      );
    }

    if (originalWordCount <= 90 || rawSentences.length <= 2) {
      return SummaryResult(
        summary: cleanText,
        keywords: _topKeywords(_frequencies(allWords)),
        originalWordCount: originalWordCount,
        summaryWordCount: originalWordCount,
        originalSentenceCount: rawSentences.length,
        summarySentenceCount: rawSentences.length,
      );
    }

    final frequencies = _frequencies(allWords);
    final maxFrequency = frequencies.values.fold<int>(
      1,
      (previous, current) => max(previous, current),
    );
    final sentences = <_ScoredSentence>[];

    for (var index = 0; index < rawSentences.length; index++) {
      final text = rawSentences[index];
      final words = _tokenize(text);

      if (words.length < 4) {
        continue;
      }

      sentences.add(
        _ScoredSentence(
          text: text,
          index: index,
          wordCount: words.length,
          score: _scoreSentence(
            text: text,
            index: index,
            totalSentences: rawSentences.length,
            words: words,
            frequencies: frequencies,
            maxFrequency: maxFrequency,
          ),
        ),
      );
    }

    if (sentences.isEmpty) {
      return SummaryResult(
        summary: cleanText,
        keywords: _topKeywords(frequencies),
        originalWordCount: originalWordCount,
        summaryWordCount: originalWordCount,
        originalSentenceCount: rawSentences.length,
        summarySentenceCount: rawSentences.length,
      );
    }

    final targetWordCount = _targetWordCount(originalWordCount, targetRatio);
    final rankedSentences = [...sentences]
      ..sort((a, b) => b.score.compareTo(a.score));
    final selected = <_ScoredSentence>[];
    var selectedWords = 0;

    for (final sentence in rankedSentences) {
      if (selectedWords >= targetWordCount && selected.length >= 3) {
        break;
      }

      selected.add(sentence);
      selectedWords += sentence.wordCount;
    }

    selected.sort((a, b) => a.index.compareTo(b.index));
    final summary = selected.map((sentence) => sentence.text).join(' ');
    final summaryWordCount = countWords(summary);

    return SummaryResult(
      summary: summary,
      keywords: _topKeywords(frequencies),
      originalWordCount: originalWordCount,
      summaryWordCount: summaryWordCount,
      originalSentenceCount: rawSentences.length,
      summarySentenceCount: selected.length,
    );
  }

  static String _normalizeWhitespace(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static List<String> _splitSentences(String text) {
    final sentences = <String>[];
    final buffer = StringBuffer();

    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      buffer.write(char);

      if (!_isSentenceBoundary(char)) {
        continue;
      }

      final nextChar = index + 1 < text.length ? text[index + 1] : '';
      final shouldSplit =
          char == '\n' || nextChar.isEmpty || RegExp(r'\s').hasMatch(nextChar);

      if (shouldSplit) {
        final sentence = buffer.toString().trim();
        if (sentence.isNotEmpty) {
          sentences.add(sentence);
        }
        buffer.clear();
      }
    }

    final rest = buffer.toString().trim();
    if (rest.isNotEmpty) {
      sentences.add(rest);
    }

    return sentences;
  }

  static bool _isSentenceBoundary(String char) {
    return char == '.' ||
        char == '!' ||
        char == '?' ||
        char == ';' ||
        char == '\n' ||
        char == '…';
  }

  static List<String> _tokenize(String text) {
    return _wordPattern
        .allMatches(text.toLowerCase())
        .map((match) => match.group(0)!)
        .where((word) => word.length > 1)
        .toList();
  }

  static Map<String, int> _frequencies(List<String> words) {
    final frequencies = <String, int>{};

    for (final word in words) {
      if (_stopWords.contains(word)) {
        continue;
      }

      frequencies[word] = (frequencies[word] ?? 0) + 1;
    }

    return frequencies;
  }

  static double _scoreSentence({
    required String text,
    required int index,
    required int totalSentences,
    required List<String> words,
    required Map<String, int> frequencies,
    required int maxFrequency,
  }) {
    var score = 0.0;

    for (final word in words) {
      score += (frequencies[word] ?? 0) / maxFrequency;
    }

    score = score / sqrt(words.length);

    if (index < max(3, totalSentences * 0.15).round()) {
      score += 0.35;
    }

    if (_containsCuePhrase(text)) {
      score += 0.45;
    }

    return score;
  }

  static bool _containsCuePhrase(String text) {
    final lowerText = text.toLowerCase();
    const cuePhrases = [
      'muc tieu',
      'mục tiêu',
      'ket qua',
      'kết quả',
      'phuong phap',
      'phương pháp',
      'ket luan',
      'kết luận',
      'nguyen nhan',
      'nguyên nhân',
      'giai phap',
      'giải pháp',
      'noi dung chinh',
      'nội dung chính',
      'tom lai',
      'tóm lại',
      'important',
      'result',
      'conclusion',
      'method',
      'objective',
    ];

    return cuePhrases.any(lowerText.contains);
  }

  static int _targetWordCount(int originalWordCount, double targetRatio) {
    final safeRatio = targetRatio.clamp(0.05, 0.4);
    final rawTarget = (originalWordCount * safeRatio).round();
    final minimum = originalWordCount < 180 ? originalWordCount : 80;

    if (rawTarget < minimum) {
      return minimum;
    }

    if (rawTarget > originalWordCount) {
      return originalWordCount;
    }

    return rawTarget;
  }

  static List<String> _topKeywords(Map<String, int> frequencies) {
    final entries = frequencies.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return entries.take(8).map((entry) => entry.key).toList();
  }
}

class _ScoredSentence {
  const _ScoredSentence({
    required this.text,
    required this.index,
    required this.wordCount,
    required this.score,
  });

  final String text;
  final int index;
  final int wordCount;
  final double score;
}
